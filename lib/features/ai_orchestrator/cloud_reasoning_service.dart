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

/// Provides optional injectable [TemplateReasoningClient].
final templateReasoningClientProvider = Provider<TemplateReasoningClient>(
  (ref) => FirebaseTemplateReasoningClient(),
);

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
