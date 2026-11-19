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
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        color: NaviColors.cream,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        color: NaviColors.cream,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      bodyLarge: TextStyle(
        color: NaviColors.cream,
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      bodyMedium: TextStyle(
        color: NaviColors.cream,
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        color: NaviColors.cream,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
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
        toolbarHeight: 72,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: NaviColors.cream,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      textTheme: textTheme,
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(72, 72),
          foregroundColor: NaviColors.cream,
          backgroundColor: NaviColors.navySurface,
          side: const BorderSide(color: NaviColors.goldAntique, width: 1.5),
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
        trackHeight: 6,
        activeTrackColor: NaviColors.goldAntique,
        inactiveTrackColor: Color(0xFF2B356E),
        thumbColor: NaviColors.cream,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12),
        overlayColor: Color(0x33B18A41),
        valueIndicatorColor: NaviColors.goldAntique,
        valueIndicatorTextStyle: TextStyle(
          color: NaviColors.navyDeep,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: NaviColors.navySurface,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: NaviColors.goldAntique, width: 1.5),
        ),
      ),
    );
  }
}
