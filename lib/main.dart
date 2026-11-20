import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/app.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/security/app_check_bootstrap.dart';
import 'package:navisense/core/utils/navi_log.dart';

/// Entry point for the NaviSense Android spatial-guidance application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeFirebase();
  runApp(const ProviderScope(child: _AppBootstrapHost()));
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    await AppCheckBootstrap.activate();
  } catch (e, st) {
    // WHY: Missing google-services.json in CI/clones or offline cold starts
    // must not block first frame or Tier 3 deterministic edge fallback.
    log(
      'Firebase initialization skipped/failed; continuing in edge-safe mode',
      name: 'navisense.bootstrap',
      error: e,
      stackTrace: st,
    );
  }
}

final class _AppBootstrapHost extends ConsumerWidget {
  const _AppBootstrapHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initializes non-blocking Remote Config governance after first frame builds.
    ref.watch(promptTemplateProvider);
    return const NaviSenseApp();
  }
}
