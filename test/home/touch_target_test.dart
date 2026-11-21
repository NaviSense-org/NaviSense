import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../helpers/fake_connectivity.dart';
import 'package:navisense/app.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/connectivity/network_status.dart';
import 'package:navisense/features/ai_orchestrator/nano_bridge.dart';
import 'package:navisense/features/camera/camera_controller_provider.dart';
import 'package:navisense/features/home/settings_screen.dart';
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

void _assertAllTapTargetsAtLeast72Dp(WidgetTester tester) {
  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  expect(root, isNotNull);

  final violations = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.hasAction(SemanticsAction.tap)) {
      final rect = _globalBounds(node);
      if (rect.width < 72.0 - 0.01 || rect.height < 72.0 - 0.01) {
        violations.add(
          'Node(${data.label}) rect=${rect.width.toStringAsFixed(1)}x'
          '${rect.height.toStringAsFixed(1)} < 72x72',
        );
      }
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(root!);
  expect(violations, isEmpty);
}

Rect _globalBounds(SemanticsNode node) {
  var rect = node.rect;
  SemanticsNode? current = node.parent;
  while (current != null) {
    rect = MatrixUtils.transformRect(
      current.transform ?? Matrix4.identity(),
      rect,
    );
    current = current.parent;
  }
  return rect;
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
      (_) async => NanoStatus.downloadable,
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

  List<dynamic> buildOverrides() {
    return [
      remoteConfigServiceProvider.overrideWithValue(RemoteConfigService()),
      connectivitySourceProvider.overrideWithValue(
        const FakeConnectivitySource(),
      ),
      cameraControllerProvider.overrideWithBuild((_, __) async => null),
      nanoBridgeProvider.overrideWithValue(nanoBridge),
      localTtsServiceProvider.overrideWithValue(
        LocalTtsService(engine: ttsEngine),
      ),
      settingsStorageProvider.overrideWithValue(storage),
    ];
  }

  testWidgets(
      'HomeScreen + NanoDownloadBanner satisfy 72dp targets, tap guidelines, '
      'and text contrast', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: buildOverrides().cast(),
        child: const NaviSenseApp(),
      ),
    );
    await tester.pumpAndSettle();

    _assertAllTapTargetsAtLeast72Dp(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    handle.dispose();
  });

  testWidgets('SettingsScreen rows meet >= 72dp height and contrast guidelines',
      (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: buildOverrides().cast(),
        child: const NaviSenseApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Speech rate: 0.45'), findsOneWidget);
    expect(find.text('Clear audio cache'), findsOneWidget);
    expect(find.text('Licenses'), findsOneWidget);

    _assertAllTapTargetsAtLeast72Dp(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    handle.dispose();
  });

  testWidgets(
      'HomeScreen and SettingsScreen do not overflow at 200% text scale',
      (WidgetTester tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: buildOverrides().cast(),
        child: const NaviSenseApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('READY • Tap anywhere'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Speech rate: 0.45'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Licenses'), 100);
    expect(find.text('Licenses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
