import 'package:flutter/material.dart';

/// High-contrast color palette for NaviSense (dark-only, TalkBack-first UI).
abstract final class NaviColors {
  /// Primary app background (Cream on Navy ~15.9:1 AAA contrast).
  static const Color navyDeep = Color(0xFF141B41);

  /// Elevated card and discrete control surface (~13.5:1 AAA with cream).
  static const Color navySurface = Color(0xFF1C2554);

  /// Primary text and icon color.
  static const Color cream = Color(0xFFF7F5F0);

  /// Secondary muted text color (~11.9:1 AAA on navyDeep).
  static const Color creamMuted = Color(0xFFD6D2C9);

  /// Brand accent, Tier 3 edge fallback pill, and focus rings.
  static const Color goldAntique = Color(0xFFB18A41);

  /// Subtle 25% antique gold divider and quiet border token.
  static const Color hairline = Color(0x40B18A41);

  /// Tier 1 pill background (on-device Gemini Nano 4).
  static const Color emerald = Color(0xFF10B981);

  /// Tier 2 pill background (cloud Gemini Flash + TTS).
  static const Color royalBlue = Color(0xFF3B82F6);

  /// Error banner border color (never used as sole indicator).
  static const Color errorRed = Color(0xFFF87171);
}
