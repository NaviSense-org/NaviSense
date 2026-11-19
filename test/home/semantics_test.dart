import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navisense/app.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/features/ai_orchestrator/ai_orchestrator.dart';
import 'package:navisense/features/ai_orchestrator/models/guidance_result.dart';
import 'package:navisense/features/ai_orchestrator/nano_bridge.dart';
import 'package:navisense/features/camera/camera_controller_provider.dart';
import 'package:navisense/features/home/settings_screen.dart';
import 'package:navisense/features/home/widgets/gesture_surface.dart';
import 'package:navisense/features/telemetry/telemetry_notifier.dart';
import 'package:navisense/features/telemetry/widgets/telemetry_pill.dart';
import 'package:navisense/features/voice/local_tts_service.dart';

final class _MockNanoBridge extends Mock implements NanoBridgeClient {}

final class _MockTtsEngine extends Mock implements TtsEngine {}

final class _InMemorySettingsStorage implements SettingsStorage {
  SettingsState? saved = const SettingsState(onboardingCompleted: true);

  @override
  Future<SettingsState?> load() async => saved;

  @override
  Future<void> save(SettingsState state) async {
    saved = state;
  }
}

void main() {
  late _MockNanoBridge nanoBridge;
  late _MockTtsEngine ttsEngine;
  late _InMemorySettingsStorage storage;

  setUp(() {
    nanoBridge = _MockNanoBridge();
    ttsEngine = _MockTtsEngine();
    storage = _InMemorySettingsStorage();

    when(() => nanoBridge.getStatus()).thenAnswer(
      (_) async => NanoStatus.unavailable,
    );
    when(() => nanoBridge.downloadProgress).thenAnswer(
      (_) => const Stream<NanoDownloadProgress>.empty(),
    );
    when(() => ttsEngine.awaitSpeakCompletion(true)).thenAnswer((_) async {});
    when(() => ttsEngine.setSpeechRate(any())).thenAnswer((_) async {});
    when(() => ttsEngine.setPitch(1.0)).thenAnswer((_) async {});
    when(() => ttsEngine.setVolume(1.0)).thenAnswer((_) async {});
    when(() => ttsEngine.setLanguage('en-US')).thenAnswer((_) async {});
    when(() => ttsEngine.getEngines()).thenAnswer(
      (_) async => <String>['com.google.android.tts'],
    );
    when(() => ttsEngine.isLanguageInstalled('en-US')).thenAnswer(
      (_) async => true,
    );
    when(() => ttsEngine.speak(any())).thenAnswer((_) async => true);
    when(() => ttsEngine.stop()).thenAnswer((_) async {});
  });

  testWidgets(
      'GestureSurface fills screen rect and exposes TalkBack label & custom actions',
      (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(RemoteConfigService()),
          cameraControllerProvider.overrideWithBuild((_, __) async => null),
          nanoBridgeProvider.overrideWithValue(nanoBridge),
          localTtsServiceProvider.overrideWithValue(
            LocalTtsService(engine: ttsEngine),
          ),
          settingsStorageProvider.overrideWithValue(storage),
        ],
        child: const NaviSenseApp(),
      ),
    );
    await tester.pumpAndSettle();

    final screenRect = tester.getRect(find.byType(Scaffold));
    final surfaceRect = tester.getRect(find.byType(GestureSurface));
    expect(surfaceRect, screenRect);

    final surfaceFinder = find.bySemanticsLabel(
      'NaviSense camera. Double tap to describe your surroundings.',
    );
    expect(surfaceFinder, findsOneWidget);

    final node = tester.getSemantics(surfaceFinder);
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.longPress), isTrue);
    expect(
      data.customSemanticsActionIds,
      containsAll(<int>[
        CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'Repeat last guidance'),
        ),
        CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'Stop speaking'),
        ),
      ]),
    );

    handle.dispose();
  });

  testWidgets('TelemetryPill renders exact label and color per tier', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: TelemetryPill(judgeMode: true, announceInferenceTier: true),
          ),
        ),
      ),
    );

    expect(find.text('READY • Tap anywhere'), findsOneWidget);

    // Tier 1 Emerald
    container.read(telemetryProvider.notifier).updateFromResult(
          const GuidanceResult(
            text: 'Chair ahead.',
            tier: Tier1Nano(inCloudFallback: false),
            stage0Ms: 38,
            inferenceMs: 640,
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('ON_DEVICE • Gemini Nano 4 • 0ms • \$0'), findsOneWidget);
    final t1Box = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect((t1Box.decoration! as BoxDecoration).color, NaviColors.emerald);

    // Tier 2 Royal Blue
    container.read(telemetryProvider.notifier).updateFromResult(
          const GuidanceResult(
            text: 'Chair at 12 o clock.',
            tier: Tier2Cloud(localVoice: false),
            stage0Ms: 38,
            inferenceMs: 700,
            templateId: 'navisense_nav_prompt_v2',
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('IN_CLOUD • Gemini Flash TTS'), findsOneWidget);
    expect(
      find.text('infer 700ms • stage0 38ms • template v2'),
      findsOneWidget,
    );
    final t2Box = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect((t2Box.decoration! as BoxDecoration).color, NaviColors.royalBlue);

    // Tier 3 Antique Gold
    container.read(telemetryProvider.notifier).updateFromResult(
          const GuidanceResult(
            text: 'Caution: Chair very close ahead in center.',
            tier: Tier3Edge(),
            stage0Ms: 40,
            inferenceMs: 0,
          ),
        );
    await tester.pumpAndSettle();

    expect(
      find.text('ON_DEVICE • ML Kit Edge Fallback • 0ms • \$0'),
      findsOneWidget,
    );
    final t3Box = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect((t3Box.decoration! as BoxDecoration).color, NaviColors.goldAntique);
  });

  testWidgets(
      'Camera permission denied exposes accessible 72dp recovery buttons to TalkBack',
      (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(RemoteConfigService()),
          cameraControllerProvider.overrideWithBuild(
            (_, __) async => throw const CameraPermissionDeniedException(
              permanentlyDenied: true,
            ),
          ),
          nanoBridgeProvider.overrideWithValue(nanoBridge),
          localTtsServiceProvider.overrideWithValue(
            LocalTtsService(engine: ttsEngine),
          ),
          settingsStorageProvider.overrideWithValue(storage),
        ],
        child: const NaviSenseApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Camera access needed'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Open settings to allow camera'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Try again'), findsOneWidget);

    expect(
      tester
          .getSize(
            find.widgetWithText(
              OutlinedButton,
              'Open settings to allow camera',
            ),
          )
          .height,
      greaterThanOrEqualTo(72),
    );
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Try again')).height,
      greaterThanOrEqualTo(72),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    handle.dispose();
  });

  testWidgets(
      'HomeScreen shows visual Analyzing indicator while loading without duplicating TalkBack semantics',
      (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    final loadingCompleter = Completer<GuidanceResult?>();
    addTearDown(() {
      if (!loadingCompleter.isCompleted) {
        loadingCompleter.complete(null);
      }
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(RemoteConfigService()),
          cameraControllerProvider.overrideWithBuild((_, __) async => null),
          nanoBridgeProvider.overrideWithValue(nanoBridge),
          localTtsServiceProvider.overrideWithValue(
            LocalTtsService(engine: ttsEngine),
          ),
          settingsStorageProvider.overrideWithValue(storage),
          aiOrchestratorProvider.overrideWithBuild(
            (_, __) => loadingCompleter.future,
          ),
        ],
        child: const NaviSenseApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Analyzing…'), findsOneWidget);
    expect(find.bySemanticsLabel('Analyzing…'), findsNothing);

    final surfaceNode = tester.getSemantics(
      find.bySemanticsLabel(
        'NaviSense camera. Double tap to describe your surroundings.',
      ),
    );
    expect(surfaceNode.getSemanticsData().value, 'Analyzing…');

    loadingCompleter.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Analyzing…'), findsNothing);

    handle.dispose();
  });
}
