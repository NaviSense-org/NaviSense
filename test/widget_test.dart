import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navisense/app.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/theme/navi_colors.dart';
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

void main() {
  testWidgets('NaviSenseApp renders high-contrast TalkBack-first HomeScreen', (
    WidgetTester tester,
  ) async {
    final nanoBridge = _MockNanoBridge();
    final ttsEngine = _MockTtsEngine();
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(RemoteConfigService()),
          cameraControllerProvider.overrideWithBuild((_, __) async => null),
          nanoBridgeProvider.overrideWithValue(nanoBridge),
          localTtsServiceProvider.overrideWithValue(
            LocalTtsService(engine: ttsEngine),
          ),
          settingsStorageProvider.overrideWithValue(_InMemorySettingsStorage()),
        ],
        child: const NaviSenseApp(),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, NaviColors.navyDeep);
    expect(find.text('READY • Tap anywhere'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
