import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abstracts system haptic actuators for deterministic unit & widget tests.
abstract interface class HapticsDriver {
  /// Plays a light tactile impact.
  Future<void> lightImpact();

  /// Plays a medium tactile impact.
  Future<void> mediumImpact();

  /// Plays a heavy tactile impact.
  Future<void> heavyImpact();

  /// Plays a soft selection tick (processing heartbeat).
  Future<void> selectionClick();

  /// Plays a sustained vibration buzz (`VERY_CLOSE` obstacle alert).
  Future<void> vibrate();
}

/// Production [HapticsDriver] delegating to Flutter's [HapticFeedback].
final class PlatformHapticsDriver implements HapticsDriver {
  /// Creates a [PlatformHapticsDriver].
  const PlatformHapticsDriver();

  @override
  Future<void> lightImpact() => HapticFeedback.lightImpact();

  @override
  Future<void> mediumImpact() => HapticFeedback.mediumImpact();

  @override
  Future<void> heavyImpact() => HapticFeedback.heavyImpact();

  @override
  Future<void> selectionClick() => HapticFeedback.selectionClick();

  @override
  Future<void> vibrate() => HapticFeedback.vibrate();
}

/// Provides the app-wide [TierHaptics] controller.
final tierHapticsProvider = Provider<TierHaptics>(
  (ref) => const TierHaptics(),
);

/// Distinct pulse-count haptic patterns (`3-ui-context.md` §3.5).
///
/// Pulse counts discriminate tiers reliably even on weak Android Go actuators.
final class TierHaptics {
  /// Creates a [TierHaptics] helper.
  const TierHaptics({HapticsDriver driver = const PlatformHapticsDriver()})
      : _driver = driver;

  final HapticsDriver _driver;

  /// 1 x light impact acknowledging a tap.
  Future<void> tap() => _driver.lightImpact();

  /// Tier 1 (ON_DEVICE Gemini Nano 4): 2 x medium, 80 ms gap ("da-dum").
  Future<void> tier1() async {
    await _driver.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _driver.mediumImpact();
  }

  /// Tier 2 (IN_CLOUD Gemini Flash): 1 x heavy ("dum").
  Future<void> tier2() => _driver.heavyImpact();

  /// Tier 3 (ML Kit Edge Fallback): 3 x light, 60 ms gaps ("tik-tik-tik").
  Future<void> tier3() async {
    for (var i = 0; i < 3; i++) {
      await _driver.lightImpact();
      if (i < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
  }

  /// Soft processing heartbeat played every 800 ms while analyzing.
  Future<void> heartbeat() => _driver.selectionClick();

  /// Additional urgent vibration before speech when a `VERY_CLOSE` obstacle is ahead.
  Future<void> veryCloseObstacle() => _driver.vibrate();

  /// Total failure SOS sequence: 3 short, 3 heavy, 3 short.
  Future<void> sos() async {
    for (var i = 0; i < 3; i++) {
      await _driver.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    for (var i = 0; i < 3; i++) {
      await _driver.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
    for (var i = 0; i < 3; i++) {
      await _driver.lightImpact();
      if (i < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  }
}
