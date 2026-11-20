import 'dart:async';
import 'dart:ui' show PlatformDispatcher, TextDirection;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/utils/navi_log.dart';

/// Optional [FirebaseRemoteConfig] provider; returns `null` when Firebase is
/// uninitialized (for example in isolated tests).
final firebaseRemoteConfigProvider = Provider<FirebaseRemoteConfig?>((ref) {
  if (Firebase.apps.isEmpty) return null;
  return FirebaseRemoteConfig.instance;
});

/// Provides [RemoteConfigService] wrapping Firebase Remote Config governance.
final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  return RemoteConfigService(
    remoteConfig: ref.watch(firebaseRemoteConfigProvider),
  );
});

/// Reactive notifier holding the validated active Tier 2 prompt template ID.
final promptTemplateProvider = NotifierProvider<PromptTemplateNotifier, String>(
  PromptTemplateNotifier.new,
);

/// Manages Remote Config defaults, non-blocking fetch, real-time updates, and
/// client-side prompt template whitelisting.
final class RemoteConfigService {
  /// Creates a [RemoteConfigService] with an optional [remoteConfig] instance.
  RemoteConfigService({
    FirebaseRemoteConfig? remoteConfig,
    bool isDebugMode = kDebugMode,
    void Function(String message)? announce,
  })  : _remoteConfig = remoteConfig,
        _isDebugMode = isDebugMode,
        _announce = announce ?? _defaultAnnounce;

  /// Remote Config key for the Tier 2 Server Prompt Template ID.
  static const String keyActivePromptTemplate = 'active_prompt_template';

  /// Remote Config key for the per-stage cloud timeout in milliseconds.
  static const String keyCloudTimeoutMs = 'cloud_timeout_ms';

  /// Remote Config key for the Cloud TTS voice name.
  static const String keyTtsVoiceName = 'tts_voice_name';

  /// Remote Config key acting as a kill-switch for Cloud TTS.
  static const String keyEnableCloudTts = 'enable_cloud_tts';

  /// Remote Config key for the Tier 2 Gemini model ID.
  static const String keyCloudModel = 'cloud_model';

  /// Remote Config key: route Tier 2 through console Server Prompt Templates
  /// instead of the direct Gemini client.
  static const String keyUseServerTemplates = 'use_server_templates';

  /// Default Tier 2 Gemini model.
  ///
  /// WHY: `gemini-3.5-flash-lite` is the current stable low-latency multimodal
  /// model in Firebase AI Logic; two-sentence spatial guidance does not need
  /// full Flash. Override with Remote Config `cloud_model`.
  static const String defaultCloudModel = 'gemini-3.5-flash-lite';

  /// Server Prompt Templates are opt-in; their model is pinned in the console.
  static const bool defaultUseServerTemplates = false;

  /// Default v1 Server Prompt Template ID.
  static const String defaultPromptTemplate = 'navisense_nav_prompt_v1';

  /// Clock-face v2 Server Prompt Template ID for live hot-swap governance.
  static const String v2PromptTemplate = 'navisense_nav_prompt_v2';

  /// Default cloud stage timeout in milliseconds.
  ///
  /// WHY: A multimodal Gemini Flash call (768 px JPEG + prompt) through the
  /// Firebase AI Logic proxy is typically 1.5–4 s end to end, and a limited-use
  /// App Check token exchange runs first; slow 3G/4G links need headroom.
  /// The old 1500 ms budget made Tier 2 time out on most taps and silently
  /// degrade every request to the Tier 3 ML Kit formatter.
  static const int defaultCloudTimeoutMs = 9000;

  /// Default Cloud TTS voice name.
  static const String defaultTtsVoiceName = 'Kore';

  /// Default Cloud TTS toggle.
  static const bool defaultEnableCloudTts = true;

  /// Client-side allowlist of approved Server Prompt Template IDs.
  static const Set<String> allowedPromptTemplates = <String>{
    defaultPromptTemplate,
    v2PromptTemplate,
  };

  final FirebaseRemoteConfig? _remoteConfig;
  final bool _isDebugMode;
  final void Function(String message) _announce;

  /// Validates [raw] against [allowedPromptTemplates].
  ///
  /// Unknown or empty values fall back to [defaultPromptTemplate] and log a
  /// warning so arbitrary template names from misconfigured consoles fail safe.
  static String sanitizeTemplateId(String? raw) {
    if (raw != null && allowedPromptTemplates.contains(raw)) {
      return raw;
    }
    if (raw != null && raw.isNotEmpty) {
      log(
        'Unknown active_prompt_template "$raw"; falling back to '
        '$defaultPromptTemplate',
        name: 'navisense.rc',
      );
    }
    return defaultPromptTemplate;
  }

  /// Currently active, whitelisted Server Prompt Template ID.
  String get activePromptTemplate {
    final rc = _remoteConfig;
    if (rc == null) return defaultPromptTemplate;
    return sanitizeTemplateId(rc.getString(keyActivePromptTemplate));
  }

  /// Timeout applied individually to Tier 2 reasoning and Tier 2 TTS calls.
  Duration get cloudTimeout {
    final rc = _remoteConfig;
    if (rc == null) {
      return const Duration(milliseconds: defaultCloudTimeoutMs);
    }
    final ms = rc.getInt(keyCloudTimeoutMs);
    return Duration(milliseconds: ms > 0 ? ms : defaultCloudTimeoutMs);
  }

  /// Cloud TTS voice name (for example `'Kore'`).
  String get ttsVoiceName {
    final rc = _remoteConfig;
    if (rc == null) return defaultTtsVoiceName;
    final name = rc.getString(keyTtsVoiceName).trim();
    return name.isEmpty ? defaultTtsVoiceName : name;
  }

  /// Whether Cloud TTS synthesis is enabled.
  bool get enableCloudTts {
    final rc = _remoteConfig;
    if (rc == null) return defaultEnableCloudTts;
    return rc.getBool(keyEnableCloudTts);
  }

  /// Tier 2 Gemini model ID (for example `'gemini-3.5-flash'`).
  String get cloudModel {
    final rc = _remoteConfig;
    if (rc == null) return defaultCloudModel;
    final name = rc.getString(keyCloudModel).trim();
    return name.isEmpty ? defaultCloudModel : name;
  }

  /// Whether Tier 2 should use console Server Prompt Templates.
  bool get useServerTemplates {
    final rc = _remoteConfig;
    if (rc == null) return defaultUseServerTemplates;
    return rc.getBool(keyUseServerTemplates);
  }

  /// Applies settings and in-app defaults, then triggers a background fetch.
  ///
  /// Never blocks startup or throws when the device is offline.
  Future<void> initialize() async {
    final rc = _remoteConfig;
    if (rc == null) return;

    try {
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 5),
          minimumFetchInterval:
              _isDebugMode ? Duration.zero : const Duration(minutes: 5),
        ),
      );
      await rc.setDefaults(const <String, Object>{
        keyActivePromptTemplate: defaultPromptTemplate,
        keyCloudTimeoutMs: defaultCloudTimeoutMs,
        keyTtsVoiceName: defaultTtsVoiceName,
        keyEnableCloudTts: defaultEnableCloudTts,
        keyCloudModel: defaultCloudModel,
        keyUseServerTemplates: defaultUseServerTemplates,
      });
      // WHY: Non-blocking startup per §2.9; offline launches keep defaults.
      unawaited(
        rc.fetchAndActivate().then(
          (_) {
            log(
              'navisense.rc template=$activePromptTemplate',
              name: 'navisense.rc',
            );
          },
          onError: (Object e, StackTrace st) {
            log(
              'Remote Config background fetch skipped/failed; keeping defaults',
              name: 'navisense.rc',
              error: e,
              stackTrace: st,
            );
          },
        ),
      );
    } catch (e, st) {
      log(
        'Remote Config initialization failed; keeping defaults',
        name: 'navisense.rc',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Subscribes to real-time Remote Config updates and invokes [onTemplateChanged]
  /// whenever [keyActivePromptTemplate] updates.
  StreamSubscription<RemoteConfigUpdate>? listenForUpdates(
    void Function(String templateId) onTemplateChanged,
  ) {
    final rc = _remoteConfig;
    if (rc == null) return null;

    return rc.onConfigUpdated.listen(
      (RemoteConfigUpdate event) async {
        if (event.updatedKeys.isEmpty) return;
        try {
          await rc.activate();
        } catch (e, st) {
          log(
            'Failed to activate Remote Config update',
            name: 'navisense.rc',
            error: e,
            stackTrace: st,
          );
          return;
        }
        if (event.updatedKeys.contains(keyActivePromptTemplate)) {
          final template = activePromptTemplate;
          log('navisense.rc template=$template', name: 'navisense.rc');
          onTemplateChanged(template);
          _announce('Guidance style updated');
        }
      },
      onError: (Object e, StackTrace st) {
        // WHY: Keep last activated values when offline or stream disconnects.
        log(
          'Remote Config update stream error; keeping last activated values',
          name: 'navisense.rc',
          error: e,
          stackTrace: st,
        );
      },
    );
  }

  static void _defaultAnnounce(String message) {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return;
    // WHY: Fire-and-forget accessibility announcement on live template switch.
    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        message,
        TextDirection.ltr,
      ),
    );
  }
}

/// Holds the active Tier 2 prompt template ID and subscribes to live updates.
final class PromptTemplateNotifier extends Notifier<String> {
  @override
  String build() {
    final service = ref.watch(remoteConfigServiceProvider);
    final sub = service.listenForUpdates((String templateId) {
      if (ref.mounted) {
        state = templateId;
      }
    });
    if (sub != null) {
      ref.onDispose(sub.cancel);
    }

    // WHY: Initialize Remote Config asynchronously so the first frame is never blocked.
    unawaited(
      service.initialize().then((_) {
        if (!ref.mounted) return;
        final current = service.activePromptTemplate;
        if (state != current) {
          state = current;
        }
      }),
    );

    return service.activePromptTemplate;
  }

  /// Updates the active template ID after whitelist validation.
  void set(String templateId) {
    state = RemoteConfigService.sanitizeTemplateId(templateId);
  }
}
