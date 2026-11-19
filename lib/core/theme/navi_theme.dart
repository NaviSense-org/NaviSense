import 'package:flutter/material.dart';
import 'package:navisense/core/theme/navi_colors.dart';

/// Dark-only high-contrast TalkBack-first theme (`3-ui-context.md` §3.1).
///
/// Enforces >= 18sp body typography, >= 22sp caption typography, and >= 72dp
/// minimum touch targets for discrete controls.
abstract final class NaviTheme {
  /// Builds NaviSense's sole dark [ThemeData].
  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      surface: NaviColors.navyDeep,
      primary: NaviColors.goldAntique,
      onPrimary: NaviColors.navyDeep,
      secondary: NaviColors.emerald,
      onSecondary: NaviColors.navyDeep,
      onSurface: NaviColors.cream,
      error: NaviColors.errorRed,
      onError: NaviColors.navyDeep,
    );

    const textTheme = TextTheme(
      headlineSmall: TextStyle(
        color: NaviColors.cream,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      titleLarge: TextStyle(
        color: NaviColors.cream,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        color: NaviColors.cream,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      bodyLarge: TextStyle(
        color: NaviColors.cream,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      bodyMedium: TextStyle(
        color: NaviColors.cream,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        color: NaviColors.cream,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NaviColors.navyDeep,
      appBarTheme: const AppBarTheme(
        backgroundColor: NaviColors.navyDeep,
        foregroundColor: NaviColors.cream,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: NaviColors.cream,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: textTheme,
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(72, 72),
          foregroundColor: NaviColors.cream,
          backgroundColor: NaviColors.navyDeep,
          side: const BorderSide(color: NaviColors.goldAntique, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(72, 72),
          foregroundColor: NaviColors.cream,
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? NaviColors.navyDeep
              : NaviColors.cream,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? NaviColors.emerald
              : NaviColors.navyDeep,
        ),
        trackOutlineColor: WidgetStateProperty.all<Color>(
          NaviColors.goldAntique,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: NaviColors.goldAntique,
        inactiveTrackColor: Color(0xFF2B356E),
        thumbColor: NaviColors.cream,
        overlayColor: Color(0x33B18A41),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: NaviColors.navyDeep,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: NaviColors.goldAntique, width: 2),
        ),
      ),
    );
  }
}
