import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/security/app_check_bootstrap.dart';

class _MockFirebaseRemoteConfig extends Mock implements FirebaseRemoteConfig {}

class _MockFirebaseAppCheck extends Mock implements FirebaseAppCheck {}

class _FakeRemoteConfigSettings extends Fake implements RemoteConfigSettings {}

class _FakeAndroidAppCheckProvider extends Fake
    implements AndroidAppCheckProvider {}

class _FakeAppleAppCheckProvider extends Fake
    implements AppleAppCheckProvider {}

class _FakeWindowsAppCheckProvider extends Fake
    implements WindowsAppCheckProvider {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeRemoteConfigSettings());
    registerFallbackValue(_FakeAndroidAppCheckProvider());
    registerFallbackValue(_FakeAppleAppCheckProvider());
    registerFallbackValue(_FakeWindowsAppCheckProvider());
  });

  group('RemoteConfigService.sanitizeTemplateId', () {
    test('falls back to v1 for unknown, empty, or null values', () {
      expect(
        RemoteConfigService.sanitizeTemplateId(null),
        RemoteConfigService.defaultPromptTemplate,
      );
      expect(
        RemoteConfigService.sanitizeTemplateId(''),
        RemoteConfigService.defaultPromptTemplate,
      );
      expect(
        RemoteConfigService.sanitizeTemplateId('navisense_nav_prompt_v99'),
        RemoteConfigService.defaultPromptTemplate,
      );
    });

    test('accepts whitelisted v1 and v2 template IDs', () {
      expect(
        RemoteConfigService.sanitizeTemplateId('navisense_nav_prompt_v1'),
        'navisense_nav_prompt_v1',
      );
      expect(
        RemoteConfigService.sanitizeTemplateId('navisense_nav_prompt_v2'),
        'navisense_nav_prompt_v2',
      );
    });
  });

  group('RemoteConfigService', () {
    late _MockFirebaseRemoteConfig mockRc;
    late StreamController<RemoteConfigUpdate> updateController;
    late List<String> announcements;

    setUp(() {
      mockRc = _MockFirebaseRemoteConfig();
      updateController = StreamController<RemoteConfigUpdate>.broadcast();
      announcements = <String>[];

      when(() => mockRc.getString(RemoteConfigService.keyActivePromptTemplate))
          .thenReturn(RemoteConfigService.defaultPromptTemplate);
      when(() => mockRc.getInt(RemoteConfigService.keyCloudTimeoutMs))
          .thenReturn(1500);
      when(() => mockRc.getString(RemoteConfigService.keyTtsVoiceName))
          .thenReturn('Kore');
      when(() => mockRc.getBool(RemoteConfigService.keyEnableCloudTts))
          .thenReturn(true);
      when(() => mockRc.setConfigSettings(any())).thenAnswer((_) async {});
      when(() => mockRc.setDefaults(any())).thenAnswer((_) async {});
      when(() => mockRc.fetchAndActivate()).thenAnswer((_) async => false);
      when(() => mockRc.activate()).thenAnswer((_) async => true);
      when(() => mockRc.onConfigUpdated)
          .thenAnswer((_) => updateController.stream);
    });

    tearDown(() async {
      await updateController.close();
    });

    test('returns defaults when FirebaseRemoteConfig is null (uninitialized)',
        () {
      final service = RemoteConfigService();

      expect(
        service.activePromptTemplate,
        RemoteConfigService.defaultPromptTemplate,
      );
      expect(
        service.cloudTimeout,
        const Duration(
          milliseconds: RemoteConfigService.defaultCloudTimeoutMs,
        ),
      );
      expect(service.ttsVoiceName, 'Kore');
      expect(service.enableCloudTts, isTrue);
    });

    test('sanitizes activePromptTemplate and validates typed getters', () {
      when(() => mockRc.getString(RemoteConfigService.keyActivePromptTemplate))
          .thenReturn('malicious_template');
      when(() => mockRc.getInt(RemoteConfigService.keyCloudTimeoutMs))
          .thenReturn(0);
      when(() => mockRc.getString(RemoteConfigService.keyTtsVoiceName))
          .thenReturn('   ');
      when(() => mockRc.getBool(RemoteConfigService.keyEnableCloudTts))
          .thenReturn(false);

      final service = RemoteConfigService(remoteConfig: mockRc);

      expect(
        service.activePromptTemplate,
        RemoteConfigService.defaultPromptTemplate,
      );
      expect(
        service.cloudTimeout,
        const Duration(
          milliseconds: RemoteConfigService.defaultCloudTimeoutMs,
        ),
      );
      expect(service.ttsVoiceName, 'Kore');
      expect(service.enableCloudTts, isFalse);

      when(() => mockRc.getString(RemoteConfigService.keyActivePromptTemplate))
          .thenReturn('navisense_nav_prompt_v2');
      when(() => mockRc.getInt(RemoteConfigService.keyCloudTimeoutMs))
          .thenReturn(2200);
      when(() => mockRc.getString(RemoteConfigService.keyTtsVoiceName))
          .thenReturn('Aoede');

      expect(service.activePromptTemplate, 'navisense_nav_prompt_v2');
      expect(service.cloudTimeout, const Duration(milliseconds: 2200));
      expect(service.ttsVoiceName, 'Aoede');
    });

    test('initialize succeeds silently even if fetchAndActivate fails offline',
        () async {
      when(() => mockRc.fetchAndActivate())
          .thenAnswer((_) async => throw Exception('offline'));

      final service = RemoteConfigService(remoteConfig: mockRc);
      await service.initialize();
      await pumpEventQueue();

      verify(() => mockRc.setConfigSettings(any())).called(1);
      verify(() => mockRc.setDefaults(any())).called(1);
      verify(() => mockRc.fetchAndActivate()).called(1);
    });

    test(
        'promptTemplateProvider updates on active_prompt_template update and '
        'ignores unrelated update keys', () async {
      final service = RemoteConfigService(
        remoteConfig: mockRc,
        announce: announcements.add,
      );
      final container = ProviderContainer(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(promptTemplateProvider),
        RemoteConfigService.defaultPromptTemplate,
      );
      await pumpEventQueue();

      // Empty update event does not activate or mutate state.
      updateController.add(RemoteConfigUpdate(<String>{}));
      await pumpEventQueue();
      verifyNever(() => mockRc.activate());
      expect(
        container.read(promptTemplateProvider),
        RemoteConfigService.defaultPromptTemplate,
      );

      // Update event without active_prompt_template activates but keeps template.
      when(() => mockRc.getString(RemoteConfigService.keyActivePromptTemplate))
          .thenReturn('navisense_nav_prompt_v2');
      updateController.add(
        RemoteConfigUpdate(<String>{RemoteConfigService.keyTtsVoiceName}),
      );
      await pumpEventQueue();
      verify(() => mockRc.activate()).called(1);
      expect(
        container.read(promptTemplateProvider),
        RemoteConfigService.defaultPromptTemplate,
      );
      expect(announcements, isEmpty);

      // Update event containing active_prompt_template updates state & announces.
      updateController.add(
        RemoteConfigUpdate(<String>{
          RemoteConfigService.keyActivePromptTemplate,
        }),
      );
      await pumpEventQueue();
      expect(
        container.read(promptTemplateProvider),
        RemoteConfigService.v2PromptTemplate,
      );
      expect(announcements, <String>['Guidance style updated']);
    });

    test('promptTemplateProvider.set enforces whitelist', () async {
      final service = RemoteConfigService(remoteConfig: mockRc);
      final container = ProviderContainer(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      container.read(promptTemplateProvider);
      await pumpEventQueue();

      container
          .read(promptTemplateProvider.notifier)
          .set('navisense_nav_prompt_v2');
      expect(container.read(promptTemplateProvider), 'navisense_nav_prompt_v2');

      container.read(promptTemplateProvider.notifier).set('invalid_template');
      expect(container.read(promptTemplateProvider), 'navisense_nav_prompt_v1');
    });

    test('stream errors keep last activated template without crashing',
        () async {
      final service = RemoteConfigService(
        remoteConfig: mockRc,
        announce: announcements.add,
      );
      final container = ProviderContainer(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(promptTemplateProvider),
        RemoteConfigService.defaultPromptTemplate,
      );
      await pumpEventQueue();

      updateController.addError(Exception('network dropped'));
      await pumpEventQueue();

      expect(
        container.read(promptTemplateProvider),
        RemoteConfigService.defaultPromptTemplate,
      );
    });
  });

  group('AppCheckBootstrap', () {
    late _MockFirebaseAppCheck mockAppCheck;

    setUp(() {
      mockAppCheck = _MockFirebaseAppCheck();
      when(
        () => mockAppCheck.activate(
          providerAndroid: any(named: 'providerAndroid'),
          providerApple: any(named: 'providerApple'),
          providerWindows: any(named: 'providerWindows'),
          providerWeb: any(named: 'providerWeb'),
        ),
      ).thenAnswer((_) async {});
      when(() => mockAppCheck.setTokenAutoRefreshEnabled(any()))
          .thenAnswer((_) async {});
    });

    test('uses AndroidDebugProvider with safelisted token in debug mode',
        () async {
      await AppCheckBootstrap.activate(
        appCheck: mockAppCheck,
        isDebugModeOverride: true,
        debugTokenOverride: '11111111-2222-3333-4444-555555555555',
      );

      final captured = verify(
        () => mockAppCheck.activate(
          providerAndroid: captureAny(named: 'providerAndroid'),
          providerApple: any(named: 'providerApple'),
          providerWindows: any(named: 'providerWindows'),
          providerWeb: any(named: 'providerWeb'),
        ),
      ).captured;

      final provider = captured.single as AndroidDebugProvider;
      expect(provider.debugToken, '11111111-2222-3333-4444-555555555555');
      verify(() => mockAppCheck.setTokenAutoRefreshEnabled(true)).called(1);
    });

    test('treats placeholder debug token as null in debug mode', () async {
      await AppCheckBootstrap.activate(
        appCheck: mockAppCheck,
        isDebugModeOverride: true,
        debugTokenOverride: '<paste-your-safelisted-debug-token>',
      );

      final captured = verify(
        () => mockAppCheck.activate(
          providerAndroid: captureAny(named: 'providerAndroid'),
          providerApple: any(named: 'providerApple'),
          providerWindows: any(named: 'providerWindows'),
          providerWeb: any(named: 'providerWeb'),
        ),
      ).captured;

      final provider = captured.single as AndroidDebugProvider;
      expect(provider.debugToken, isNull);
    });

    test('uses AndroidPlayIntegrityProvider in release mode', () async {
      await AppCheckBootstrap.activate(
        appCheck: mockAppCheck,
        isDebugModeOverride: false,
        debugTokenOverride: 'ignored',
      );

      final captured = verify(
        () => mockAppCheck.activate(
          providerAndroid: captureAny(named: 'providerAndroid'),
          providerApple: any(named: 'providerApple'),
          providerWindows: any(named: 'providerWindows'),
          providerWeb: any(named: 'providerWeb'),
        ),
      ).captured;

      expect(captured.single, isA<AndroidPlayIntegrityProvider>());
      verify(() => mockAppCheck.setTokenAutoRefreshEnabled(true)).called(1);
    });

    test('never throws when App Check activation fails offline', () async {
      when(
        () => mockAppCheck.activate(
          providerAndroid: any(named: 'providerAndroid'),
          providerApple: any(named: 'providerApple'),
          providerWindows: any(named: 'providerWindows'),
          providerWeb: any(named: 'providerWeb'),
        ),
      ).thenThrow(Exception('offline'));

      await expectLater(
        AppCheckBootstrap.activate(
          appCheck: mockAppCheck,
          isDebugModeOverride: true,
          debugTokenOverride: 'token',
        ),
        completes,
      );
    });
  });
}
