import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:navisense/core/utils/navi_log.dart';

/// Bootstraps Firebase App Check for Android-only builds.
///
/// Uses [AndroidDebugProvider] with `--dart-define-from-file=secrets.json`
/// in debug builds and [AndroidPlayIntegrityProvider] in release builds.
abstract final class AppCheckBootstrap {
  /// Dart define key supplying the safelisted debug token from `secrets.json`.
  static const String debugTokenEnvKey = 'APP_CHECK_DEBUG_TOKEN';

  /// Dart define that forces the debug provider in a *release* build.
  ///
  /// WHY: Play Integrity rejects sideloaded APKs (e.g. a judge installing from
  /// GitHub Releases), which would lock them out of every cloud tier. The
  /// hackathon accepts App Check debug tokens, so the CI "internal" APK sets
  /// this together with [debugTokenEnvKey]. Never set it for Play builds.
  static const String forceDebugProviderEnvKey =
      'APP_CHECK_FORCE_DEBUG_PROVIDER';

  static const String _placeholderPrefix = '<';

  /// Activates App Check and enables automatic token refresh.
  ///
  /// Errors are logged and never rethrown so offline / Airplane Mode launches
  /// continue gracefully onto Tier 3 edge fallback.
  static Future<void> activate({
    FirebaseAppCheck? appCheck,
    bool? isDebugModeOverride,
    String? debugTokenOverride,
  }) async {
    final instance = appCheck ?? FirebaseAppCheck.instance;
    final isDebug = isDebugModeOverride ??
        (kDebugMode || const bool.fromEnvironment(forceDebugProviderEnvKey));
    final rawToken =
        debugTokenOverride ?? const String.fromEnvironment(debugTokenEnvKey);
    final debugToken =
        rawToken.trim().startsWith(_placeholderPrefix) ? '' : rawToken.trim();

    if (isDebug && debugToken.isEmpty) {
      log(
        'APP_CHECK_DEBUG_TOKEN is not set. Run with '
        '--dart-define-from-file=secrets.json (see README.md "For Judges" / '
        '"Zero-Secret Configuration"). Falling back to SDK-generated debug '
        'token logged in logcat.',
        name: 'navisense.app_check',
      );
    }

    try {
      await instance.activate(
        providerAndroid: isDebug
            ? AndroidDebugProvider(
                debugToken: debugToken.isEmpty ? null : debugToken,
              )
            : const AndroidPlayIntegrityProvider(),
      );
      await instance.setTokenAutoRefreshEnabled(true);
      log(
        'App Check activated (mode=${isDebug ? 'debug' : 'play_integrity'})',
        name: 'navisense.app_check',
      );
    } catch (e, st) {
      // WHY: Offline/Airplane Mode cold starts or missing Play Services must
      // not crash startup; Tier 3 remains functional without cloud tokens.
      log(
        'App Check activation failed; continuing without cloud attestation',
        name: 'navisense.app_check',
        error: e,
        stackTrace: st,
      );
    }
  }
}
