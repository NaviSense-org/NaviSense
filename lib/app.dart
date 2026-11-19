import 'package:flutter/material.dart';
import 'package:navisense/core/theme/navi_theme.dart';
import 'package:navisense/features/home/home_screen.dart';

/// Root widget configuring NaviSense's dark-only high-contrast theme and home
/// spatial-guidance interface.
final class NaviSenseApp extends StatelessWidget {
  /// Creates the root [NaviSenseApp].
  const NaviSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NaviSense',
      debugShowCheckedModeBanner: false,
      theme: NaviTheme.dark(),
      darkTheme: NaviTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
