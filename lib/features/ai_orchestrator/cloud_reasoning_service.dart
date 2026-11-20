import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/ai_orchestrator/models/guidance_result.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';

/// Abstracts `TemplateGenerativeModel.generateContent` for unit testing.
abstract interface class TemplateReasoningClient {
  /// Executes Server Prompt Template [templateId] with [inputs] and returns
  /// generated text (or `null` when blocked/empty).
  Future<String?> generateContent(
    String templateId, {
    required Map<String, Object?> inputs,
  });
}

/// Production [TemplateReasoningClient] backed by Firebase AI Logic.
///
/// `FirebaseAI.googleAI()` automatically attaches the active `FirebaseAppCheck`
/// token registered on the default `FirebaseApp`.
final class FirebaseTemplateReasoningClient implements TemplateReasoningClient {
  /// Creates a [FirebaseTemplateReasoningClient].
  FirebaseTemplateReasoningClient({FirebaseAI? firebaseAi})
      : _firebaseAi = firebaseAi;

  final FirebaseAI? _firebaseAi;

  @override
  Future<String?> generateContent(
    String templateId, {
    required Map<String, Object?> inputs,
  }) async {
    final ai = _firebaseAi ?? FirebaseAI.googleAI();
    // ignore: experimental_member_use
    final model = ai.templateGenerativeModel();
    // ignore: experimental_member_use
    final response = await model.generateContent(templateId, inputs: inputs);
    return response.text;
  }
}

/// Direct Firebase AI Logic Gemini client used by default for Tier 2.
///
/// WHY: Server Prompt Templates hard-code their model inside the Firebase
/// console (the shipped ones referenced the non-existent `gemini-3-flash`), so
/// a bad template silently broke every cloud request. This client keeps the
/// v1/v2 guidance styles in code, takes the model ID from Remote Config
/// (`cloud_model`), and disables extended thinking so short spoken answers
/// come back fast and are never starved by thought tokens.
final class FirebaseGeminiReasoningClient implements TemplateReasoningClient {
  /// Creates a [FirebaseGeminiReasoningClient].
  FirebaseGeminiReasoningClient({
    required String Function() modelReader,
    FirebaseAI? firebaseAi,
  })  : _modelReader = modelReader,
        _firebaseAi = firebaseAi;

  final String Function() _modelReader;
  final FirebaseAI? _firebaseAi;

  /// Builds the system instruction for a whitelisted guidance style.
  static String systemInstructionFor(String templateId, String locale) {
    final style = templateId == RemoteConfigService.v2PromptTemplate
        ? 'Use clock-face directions (12 o\'clock is straight ahead, 9 is left, '
            '3 is right) and step counts (one step is about 0.7 m).'
        : 'Give direction as left, ahead, or right and distance as very close, '
            'a few steps, or far.';
    return 'You are NaviSense, a calm spatial guide for a blind pedestrian. '
        'Look at the photo from their chest-height camera. Reply in at most '
        'two short spoken sentences. State the closest obstacle or hazard '
        'first. $style Read safety-relevant signs verbatim. Only claim the '
        'path is clear if you can actually see open walkable ground ahead. '
        'Never describe colors or aesthetics unless safety-relevant. Never '
        'speculate. Language: $locale.';
  }

  @override
  Future<String?> generateContent(
    String templateId, {
    required Map<String, Object?> inputs,
  }) async {
    final ai = _firebaseAi ?? FirebaseAI.googleAI();
    final locale = (inputs['locale'] as String?) ?? 'en';
    final model = ai.generativeModel(
      model: _modelReader(),
      systemInstruction: Content.system(
        systemInstructionFor(templateId, locale),
      ),
      generationConfig: GenerationConfig(
        maxOutputTokens: 160,
        thinkingConfig: ThinkingConfig.withThinkingLevel(
          ThinkingLevel.minimal,
        ),
      ),
    );

    final parts = <Part>[
      TextPart('On-device perception hints: ${inputs['scene'] ?? ''}'),
    ];
    final image = inputs['image'];
    if (image is String) {
      final comma = image.indexOf(',');
      final b64 = comma >= 0 ? image.substring(comma + 1) : image;
      parts.add(InlineDataPart('image/jpeg', base64Decode(b64)));
    }
    final response = await model.generateContent(<Content>[
      Content.multi(parts),
    ]);
    return response.text;
  }
}

/// Provides the injectable [TemplateReasoningClient] for Tier 2.
///
/// Uses [FirebaseGeminiReasoningClient] unless Remote Config
/// `use_server_templates` is `true`.
final templateReasoningClientProvider = Provider<TemplateReasoningClient>(
  (ref) {
    final rc = ref.watch(remoteConfigServiceProvider);
    final direct = FirebaseGeminiReasoningClient(
      modelReader: () => rc.cloudModel,
    );
    final templates = FirebaseTemplateReasoningClient();
    return _SwitchingReasoningClient(
      useTemplates: () => rc.useServerTemplates,
      templates: templates,
      direct: direct,
    );
  },
);

/// Chooses templates vs direct Gemini per request so a Remote Config change
/// takes effect without restarting the app.
final class _SwitchingReasoningClient implements TemplateReasoningClient {
  const _SwitchingReasoningClient({
    required bool Function() useTemplates,
    required TemplateReasoningClient templates,
    required TemplateReasoningClient direct,
  })  : _useTemplates = useTemplates,
        _templates = templates,
        _direct = direct;

  final bool Function() _useTemplates;
  final TemplateReasoningClient _templates;
  final TemplateReasoningClient _direct;

  @override
  Future<String?> generateContent(
    String templateId, {
    required Map<String, Object?> inputs,
  }) =>
      (_useTemplates() ? _templates : _direct)
          .generateContent(templateId, inputs: inputs);
}

/// Provides [CloudReasoningService] reading live template ID and timeout from
/// Remote Config providers.
final cloudReasoningServiceProvider = Provider<CloudReasoningService>((ref) {
  return CloudReasoningService(
    client: ref.watch(templateReasoningClientProvider),
    templateIdReader: () => ref.read(promptTemplateProvider),
    timeoutReader: () => ref.read(remoteConfigServiceProvider).cloudTimeout,
    clock: ref.watch(clockProvider),
  );
});

/// Tier 2 Cloud Reasoning service executing Firebase Server Prompt Templates
/// (`navisense_nav_prompt_v1` / `v2`) within the Remote Config `cloud_timeout_ms` budget.
final class CloudReasoningService {
  /// Creates a [CloudReasoningService].
  CloudReasoningService({
    required TemplateReasoningClient client,
    required String Function() templateIdReader,
    Duration Function()? timeoutReader,
    Clock? clock,
  })  : _client = client,
        _templateIdReader = templateIdReader,
        _timeoutReader = timeoutReader ??
            (() => const Duration(
                  milliseconds: RemoteConfigService.defaultCloudTimeoutMs,
                )),
        _clock = clock ?? const SystemClock();

  final TemplateReasoningClient _client;
  final String Function() _templateIdReader;
  final Duration Function() _timeoutReader;
  final Clock _clock;

  /// Generates calm spatial guidance from compressed [jpeg] and Stage 0 [summary].
  ///
  /// Throws only [NaviFailure] subtypes ([TimeoutFailure], [NetworkFailure],
  /// or [FirebaseAiFailure]).
  Future<CloudReasoningResult> reason({
    required Uint8List jpeg,
    required SpatialSceneSummary summary,
    String locale = 'en',
    bool textOnly = false,
  }) async {
    final templateId = RemoteConfigService.sanitizeTemplateId(
      _templateIdReader(),
    );
    final timeout = _timeoutReader();
    final startedMs = _clock.nowMs();

    final scenePrompt = textOnly
        ? 'Task: Read all visible text verbatim. ${summary.toPromptString()}'
        : summary.toPromptString();

    final inputs = <String, Object?>{
      'scene': scenePrompt,
      'image': 'data:image/jpeg;base64,${base64Encode(jpeg)}',
      'locale': locale,
    };

    try {
      final rawText = await _client
          .generateContent(templateId, inputs: inputs)
          .timeout(timeout);
      final trimmed = rawText?.trim() ?? '';
      if (trimmed.isEmpty) {
        throw const FirebaseAiFailure(
          'Cloud reasoning returned empty or blocked response',
          code: 'empty',
        );
      }
      final latencyMs = (_clock.nowMs() - startedMs).clamp(0, 60000);
      return CloudReasoningResult(
        text: trimmed,
        templateId: templateId,
        latencyMs: latencyMs,
      );
    } on TimeoutException {
      throw TimeoutFailure('cloud reasoning > ${timeout.inMilliseconds}ms');
    } on SocketException catch (e) {
      throw NetworkFailure(e.message);
    } on HttpException catch (e) {
      throw NetworkFailure(e.message);
    } on FirebaseException catch (e) {
      throw FirebaseAiFailure(
        e.message ?? 'Firebase error during cloud reasoning',
        code: e.code,
      );
    } on FirebaseAIException catch (e) {
      throw FirebaseAiFailure(e.message);
    } catch (e) {
      if (e is NaviFailure) rethrow;
      throw FirebaseAiFailure('Unexpected cloud reasoning failure: $e');
    }
  }
}
