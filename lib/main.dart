import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/security/app_check_bootstrap.dart';
import 'package:navisense/core/theme/navi_colors.dart';

/// Entry point for the NaviSense Android spatial-guidance application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeFirebase();
  runApp(const ProviderScope(child: NaviSenseApp()));
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

/// Root widget configuring NaviSense's high-contrast dark theme.
final class NaviSenseApp extends StatelessWidget {
  /// Creates the root NaviSense application widget.
  const NaviSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NaviSense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: NaviColors.navyDeep,
        colorScheme: const ColorScheme.dark(
          surface: NaviColors.navyDeep,
          primary: NaviColors.goldAntique,
          onPrimary: NaviColors.navyDeep,
          onSurface: NaviColors.cream,
          error: NaviColors.errorRed,
        ),
        useMaterial3: true,
      ),
      home: const _BootstrapScaffold(),
    );
  }
}

final class _BootstrapScaffold extends ConsumerWidget {
  const _BootstrapScaffold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Starts non-blocking Remote Config governance after the first frame builds.
    ref.watch(promptTemplateProvider);

    return Scaffold(
      backgroundColor: NaviColors.navyDeep,
      body: Center(
        child: Semantics(
          container: true,
          header: true,
          label: 'NaviSense. Hybrid AI spatial guide ready.',
          child: const ExcludeSemantics(
            child: Text(
              'NaviSense',
              style: TextStyle(
                color: NaviColors.cream,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
