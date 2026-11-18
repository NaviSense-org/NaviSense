import 'package:flutter/material.dart';
import 'package:navisense/core/theme/navi_colors.dart';

/// Entry point for the NaviSense Android spatial-guidance application.
void main() {
  runApp(const NaviSenseApp());
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

final class _BootstrapScaffold extends StatelessWidget {
  const _BootstrapScaffold();

  @override
  Widget build(BuildContext context) {
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
