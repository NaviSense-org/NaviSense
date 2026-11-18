import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/features/ai_orchestrator/models/guidance_result.dart';
import 'package:navisense/features/telemetry/telemetry_notifier.dart';

void main() {
  group('TelemetryNotifier pill labels (§3.7 golden)', () {
    test('starts in idle state with exact READY label', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final pill = container.read(telemetryProvider);
      expect(pill.label, 'READY • Tap anywhere');
      expect(pill.backgroundColor, Colors.transparent);
      expect(pill.foregroundColor, NaviColors.cream);
      expect(pill.borderColor, NaviColors.goldAntique);
    });

    test('Tier 1 ON_DEVICE emits exact label and emerald styling', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(telemetryProvider.notifier).updateFromResult(
            const GuidanceResult(
              text: 'Chair ahead.',
              tier: Tier1Nano(inCloudFallback: false),
              stage0Ms: 38,
              inferenceMs: 640,
            ),
          );

      final pill = container.read(telemetryProvider);
      expect(pill.label, 'ON_DEVICE • Gemini Nano 4 • 0ms • \$0');
      expect(pill.backgroundColor, NaviColors.emerald);
      expect(pill.foregroundColor, NaviColors.navyDeep);
      expect(pill.icon, Icons.memory);
      expect(pill.detailLine, 'infer 640ms • stage0 38ms');
    });

    test('Tier 2 Cloud TTS emits exact label and royal blue styling', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(telemetryProvider.notifier).updateFromResult(
            const GuidanceResult(
              text: 'Chair at 12 o clock.',
              tier: Tier2Cloud(localVoice: false),
              stage0Ms: 40,
              inferenceMs: 820,
              templateId: 'navisense_nav_prompt_v2',
              cacheHit: true,
            ),
          );

      final pill = container.read(telemetryProvider);
      expect(pill.label, 'IN_CLOUD • Gemini Flash TTS');
      expect(pill.backgroundColor, NaviColors.royalBlue);
      expect(pill.foregroundColor, NaviColors.navyDeep);
      expect(pill.icon, Icons.cloud);
      expect(
        pill.detailLine,
        'infer 820ms • stage0 40ms • template v2 • cache hit',
      );
    });

    test(
        'Tier 2 TTS failure and Tier 1 IN_CLOUD fallback emit exact local voice label',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(telemetryProvider.notifier).updateFromResult(
            const GuidanceResult(
              text: 'Door on your left.',
              tier: Tier2Cloud(localVoice: true),
              stage0Ms: 35,
              inferenceMs: 700,
              templateId: 'navisense_nav_prompt_v1',
            ),
          );

      final pillCloud = container.read(telemetryProvider);
      expect(pillCloud.label, 'IN_CLOUD • Gemini Flash • local voice');
      expect(pillCloud.backgroundColor, NaviColors.royalBlue);
      expect(pillCloud.foregroundColor, NaviColors.navyDeep);
      expect(pillCloud.icon, Icons.cloud_off_outlined);

      container.read(telemetryProvider.notifier).updateFromResult(
            const GuidanceResult(
              text: 'Door on your left.',
              tier: Tier1Nano(inCloudFallback: true),
              stage0Ms: 35,
              inferenceMs: 710,
            ),
          );

      expect(
        container.read(telemetryProvider).label,
        'IN_CLOUD • Gemini Flash • local voice',
      );
    });

    test('Tier 3 Edge Fallback emits exact label and antique gold styling', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(telemetryProvider.notifier).updateFromResult(
            const GuidanceResult(
              text: 'Caution: Chair very close ahead in center.',
              tier: Tier3Edge(),
              stage0Ms: 42,
              inferenceMs: 0,
            ),
          );

      final pill = container.read(telemetryProvider);
      expect(pill.label, 'ON_DEVICE • ML Kit Edge Fallback • 0ms • \$0');
      expect(pill.backgroundColor, NaviColors.goldAntique);
      expect(pill.foregroundColor, NaviColors.navyDeep);
      expect(pill.icon, Icons.offline_bolt);
    });
  });
}
