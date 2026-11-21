import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/connectivity/connectivity_probe.dart';
import 'package:navisense/core/connectivity/network_status.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/features/ai_orchestrator/ai_orchestrator.dart';
import 'package:navisense/features/ai_orchestrator/cloud_reasoning_service.dart';
import 'package:navisense/features/ai_orchestrator/models/guidance_result.dart';
import 'package:navisense/features/ai_orchestrator/nano_bridge.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';
import 'package:navisense/features/telemetry/telemetry_notifier.dart';
import 'package:navisense/features/voice/cloud_tts_service.dart';
import 'package:navisense/features/voice/local_tts_service.dart';
import 'package:navisense/features/voice/voice_player.dart';
import 'package:navisense/features/voice/wav_cache.dart';
import 'package:navisense/features/voice/wav_codec.dart';

import '../helpers/fake_connectivity.dart';

final class _MockGateway extends Mock
    implements OrchestratorPerceptionGateway {}

final class _MockNanoBridge extends Mock implements NanoBridgeClient {}

final class _MockTemplateClient extends Mock
    implements TemplateReasoningClient {}

final class _MockCloudTtsClient extends Mock implements CloudTtsClient {}

final class _MockTtsEngine extends Mock implements TtsEngine {}

final class _MockAudioBackend extends Mock implements VoiceAudioBackend {}

final class _StaticConnectivitySource implements ConnectivitySource {
  const _StaticConnectivitySource(this.results);

  final List<ConnectivityResult> results;

  @override
  Stream<List<ConnectivityResult>> get changes => const Stream.empty();

  @override
  Future<List<ConnectivityResult>> current() async => results;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(UrlSource('https://example.com'));
  });

  late Directory tempDir;
  late _MockGateway gateway;
  late _MockNanoBridge nanoBridge;
  late _MockTemplateClient templateClient;
  late _MockCloudTtsClient cloudTtsClient;
  late _MockTtsEngine ttsEngine;
  late _MockAudioBackend audioBackend;
  late StreamController<void> audioCompleteController;
  late bool isOffline;
  late List<String> announcements;
  late int dnsLookups;

  final jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]);
  final pcm = Uint8List(2048);
  final summary = SpatialSceneSummary(
    entities: const <SpatialEntity>[
      SpatialEntity(
        kind: EntityKind.obstacle,
        label: 'Chair',
        direction: Direction.center,
        distance: Distance.veryClose,
        confidence: 0.88,
      ),
      SpatialEntity(
        kind: EntityKind.object,
        label: 'Door',
        direction: Direction.left,
        distance: Distance.ahead,
        confidence: 0.79,
      ),
    ],
    texts: const <String>['EXIT'],
    capturedAt: DateTime.utc(2026, 11, 18),
    processingMs: 36,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('navisense_orch_test_');
    gateway = _MockGateway();
    nanoBridge = _MockNanoBridge();
    templateClient = _MockTemplateClient();
    cloudTtsClient = _MockCloudTtsClient();
    ttsEngine = _MockTtsEngine();
    audioBackend = _MockAudioBackend();
    audioCompleteController = StreamController<void>.broadcast();
    isOffline = false;
    announcements = <String>[];
    dnsLookups = 0;

    when(
      () => gateway.captureSnapshot(
        maxEdge: any(named: 'maxEdge'),
        quality: any(named: 'quality'),
      ),
    ).thenAnswer((_) async => jpeg);
    when(() => gateway.resolveFreshSummary(any())).thenAnswer(
      (_) async => summary,
    );
    when(() => nanoBridge.downloadProgress).thenAnswer(
      (_) => const Stream<NanoDownloadProgress>.empty(),
    );
    when(() => nanoBridge.getStatus()).thenAnswer(
      (_) async => NanoStatus.unavailable,
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

    when(() => audioBackend.onPlayerComplete).thenAnswer(
      (_) => audioCompleteController.stream,
    );
    when(() => audioBackend.stop()).thenAnswer((_) async {});
    when(() => audioBackend.dispose()).thenAnswer((_) async {});
    when(() => audioBackend.play(any())).thenAnswer((_) async {
      scheduleMicrotask(() {
        if (!audioCompleteController.isClosed) {
          audioCompleteController.add(null);
        }
      });
    });

    when(
      () => cloudTtsClient.synthesizePcm(
        text: any(named: 'text'),
        voiceName: any(named: 'voiceName'),
        model: any(named: 'model'),
      ),
    ).thenAnswer(
      (_) async => RawTtsAudio(bytes: pcm, mimeType: 'audio/L16;rate=24000'),
    );
  });

  tearDown(() async {
    await audioCompleteController.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ProviderContainer makeContainer({
    Duration cloudTimeout = const Duration(milliseconds: 1500),
    ConnectivitySource connectivitySource = const FakeConnectivitySource(),
  }) {
    final wavCache = WavCache(directoryProvider: () async => tempDir);
    final localTts = LocalTtsService(engine: ttsEngine);
    final voicePlayer = VoicePlayer(
      localTts: localTts,
      backend: audioBackend,
    );
    final connectivity = ConnectivityProbe(
      lookup: (String _) async {
        dnsLookups++;
        if (isOffline) {
          throw const SocketException('Airplane Mode');
        }
        return <InternetAddress>[InternetAddress.loopbackIPv4];
      },
    );
    final rcService = RemoteConfigService();
    final cloudReasoning = CloudReasoningService(
      client: templateClient,
      templateIdReader: () => 'navisense_nav_prompt_v1',
      timeoutReader: () => cloudTimeout,
    );
    final cloudTts = CloudTtsService(
      cache: wavCache,
      client: cloudTtsClient,
      timeoutReader: () => cloudTimeout,
    );

    final container = ProviderContainer(
      overrides: [
        remoteConfigServiceProvider.overrideWithValue(rcService),
        orchestratorPerceptionGatewayProvider.overrideWithValue(gateway),
        nanoBridgeProvider.overrideWithValue(nanoBridge),
        connectivityProbeProvider.overrideWithValue(connectivity),
        connectivitySourceProvider.overrideWithValue(connectivitySource),
        cloudReasoningServiceProvider.overrideWithValue(cloudReasoning),
        wavCacheProvider.overrideWithValue(wavCache),
        cloudTtsServiceProvider.overrideWithValue(cloudTts),
        localTtsServiceProvider.overrideWithValue(localTts),
        voicePlayerProvider.overrideWithValue(voicePlayer),
        semanticsAnnouncerProvider.overrideWithValue(announcements.add),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AiOrchestrator 8 routing transitions (§2.7)', () {
    test('1. Nano AVAILABLE + success -> Tier1, local TTS called once',
        () async {
      when(() => nanoBridge.getStatus()).thenAnswer(
        (_) async => NanoStatus.available,
      );
      when(
        () => nanoBridge.generate(
          jpeg: any(named: 'jpeg'),
          summary: any(named: 'summary'),
        ),
      ).thenAnswer(
        (_) async => const NanoResult(
          text: 'Chair very close ahead. Door on left.',
          inferenceSource: NanoInferenceSource.onDevice,
          latencyMs: 520,
        ),
      );

      final container = makeContainer();
      await container.read(nanoStatusProvider.future);
      await container.read(aiOrchestratorProvider.notifier).describe();

      final result = container.read(aiOrchestratorProvider).value!;
      expect(result.tier, const Tier1Nano(inCloudFallback: false));
      expect(
        container.read(telemetryProvider).label,
        'ON_DEVICE • Gemini Nano 4 • 0ms • \$0',
      );
      verify(() => ttsEngine.speak(result.text)).called(1);
    });

    test('2. Nano error + online -> Tier2', () async {
      when(() => nanoBridge.getStatus()).thenAnswer(
        (_) async => NanoStatus.available,
      );
      when(
        () => nanoBridge.generate(
          jpeg: any(named: 'jpeg'),
          summary: any(named: 'summary'),
        ),
      ).thenThrow(const NanoFailure('AICore busy', code: 'NANO_FAILED'));
      when(
        () => templateClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) async => 'Chair ahead.');

      final container = makeContainer();
      await container.read(nanoStatusProvider.future);
      await container.read(aiOrchestratorProvider.notifier).describe();

      final result = container.read(aiOrchestratorProvider).value!;
      expect(result.tier, const Tier2Cloud(localVoice: false));
      verify(() => audioBackend.play(any(that: isA<DeviceFileSource>())))
          .called(
        1,
      );
    });

    test('3. Nano error + offline -> Tier3', () async {
      isOffline = true;
      when(() => nanoBridge.getStatus()).thenAnswer(
        (_) async => NanoStatus.available,
      );
      when(
        () => nanoBridge.generate(
          jpeg: any(named: 'jpeg'),
          summary: any(named: 'summary'),
        ),
      ).thenThrow(const NanoFailure('Timeout', code: 'NANO_TIMEOUT'));

      final container = makeContainer();
      await container.read(nanoStatusProvider.future);
      await container.read(aiOrchestratorProvider.notifier).describe();

      final result = container.read(aiOrchestratorProvider).value!;
      expect(result.tier, const Tier3Edge());
      expect(
        result.text,
        'Caution: Chair very close ahead in center. Door on your left. Sign reads EXIT.',
      );
      verify(() => ttsEngine.speak(result.text)).called(1);
    });

    test(
        '3b. Stage 0 failure + offline never claims "Path looks clear" '
        '(safety)', () async {
      isOffline = true;
      when(() => gateway.resolveFreshSummary(any())).thenThrow(
        const TimeoutFailure('ML Kit perception > 1000ms'),
      );

      final container = makeContainer();
      await container.read(aiOrchestratorProvider.notifier).describe();

      final result = container.read(aiOrchestratorProvider).value!;
      expect(result.tier, const Tier3Edge());
      expect(result.text, AiOrchestrator.perceptionFailedMessage);
      expect(result.text, isNot(contains('clear')));
      verify(() => ttsEngine.speak(AiOrchestrator.perceptionFailedMessage))
          .called(1);
    });

    test(
        '3c. Live connectivity stream offline -> Tier3 without DNS probe or '
        'cloud call', () async {
      final container = makeContainer(
        connectivitySource: const _StaticConnectivitySource(
          <ConnectivityResult>[ConnectivityResult.none],
        ),
      );
      container.read(networkStatusProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(networkStatusProvider), NetworkStatus.offline);
      dnsLookups = 0;

      await container.read(aiOrchestratorProvider.notifier).describe();

      final result = container.read(aiOrchestratorProvider).value!;
      expect(result.tier, const Tier3Edge());
      expect(dnsLookups, 0);
      verifyNever(
        () => templateClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      );
    });

    test('4. Nano unavailable + online + success -> Tier2, playFile called',
        () async {
      when(
        () => templateClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) async => 'Chair directly ahead.');

      final container = makeContainer();
      await container.read(aiOrchestratorProvider.notifier).describe();

      final result = container.read(aiOrchestratorProvider).value!;
      expect(result.tier, const Tier2Cloud(localVoice: false));
      verify(() => audioBackend.play(any(that: isA<DeviceFileSource>())))
          .called(
        1,
      );
    });

    test('5. Cloud TimeoutFailure -> Tier3 within <= 1600ms total', () async {
      when(
        () => templateClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return 'Too late';
      });

      final sw = Stopwatch()..start();
      final container = makeContainer(
        cloudTimeout: const Duration(milliseconds: 40),
      );
      await container.read(aiOrchestratorProvider.notifier).describe();
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThanOrEqualTo(1600));
      expect(
        container.read(aiOrchestratorProvider).value!.tier,
        const Tier3Edge(),
      );
    });

    test(
        '6. Cloud TTS failure -> local TTS speaks cloud text, Tier2Cloud(localVoice: true)',
        () async {
      when(
        () => templateClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) async => 'Chair very close.');
      when(
        () => cloudTtsClient.synthesizePcm(
          text: any(named: 'text'),
          voiceName: any(named: 'voiceName'),
          model: any(named: 'model'),
        ),
      ).thenThrow(const VoiceFailure('TTS timeout'));

      final container = makeContainer();
      await container.read(aiOrchestratorProvider.notifier).describe();

      final result = container.read(aiOrchestratorProvider).value!;
      expect(result.tier, const Tier2Cloud(localVoice: true));
      expect(
        container.read(telemetryProvider).label,
        'IN_CLOUD • Gemini Flash • local voice',
      );
      verify(() => ttsEngine.speak('Chair very close.')).called(1);
    });

    test(
        '6b. Slow cloud TTS -> cloud text spoken by local voice after the '
        'wait budget, not after the full TTS timeout', () async {
      when(
        () => templateClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) async => 'Chair directly ahead.');
      final slowTts = Completer<RawTtsAudio>();
      when(
        () => cloudTtsClient.synthesizePcm(
          text: any(named: 'text'),
          voiceName: any(named: 'voiceName'),
          model: any(named: 'model'),
        ),
      ).thenAnswer((_) => slowTts.future);

      final container = makeContainer(
        cloudTimeout: const Duration(seconds: 30),
      );
      final sw = Stopwatch()..start();
      await container.read(aiOrchestratorProvider.notifier).describe();
      sw.stop();

      final result = container.read(aiOrchestratorProvider).value!;
      expect(result.tier, const Tier2Cloud(localVoice: true));
      expect(result.text, 'Chair directly ahead.');
      verify(() => ttsEngine.speak('Chair directly ahead.')).called(1);
      expect(
        sw.elapsed,
        lessThan(
          AiOrchestrator.cloudVoiceWaitBudget +
              const Duration(milliseconds: 1500),
        ),
      );
      slowTts
          .complete(RawTtsAudio(bytes: pcm, mimeType: 'audio/L16;rate=24000'));
    });

    test('7. Tier3 cache hit -> playFile called, no flutter_tts speak',
        () async {
      isOffline = true;
      const tier3Sentence =
          'Caution: Chair very close ahead in center. Door on your left. Sign reads EXIT.';
      final key = WavCache.cacheKey(
        tier3Sentence,
        voiceName: CloudTtsService.defaultVoiceName,
        model: CloudTtsService.ttsModel,
      );
      final cache = WavCache(directoryProvider: () async => tempDir);
      await cache.store(key, pcmToWav(pcm));

      final container = makeContainer();
      await container.read(aiOrchestratorProvider.notifier).describe();

      final result = container.read(aiOrchestratorProvider).value!;
      expect(result.tier, const Tier3Edge());
      expect(result.cacheHit, isTrue);
      verify(() => audioBackend.play(any(that: isA<DeviceFileSource>())))
          .called(
        1,
      );
      verifyNever(() => ttsEngine.speak(any()));
    });

    test('8. All voice fails -> announce called, AsyncError with text',
        () async {
      isOffline = true;
      when(() => ttsEngine.getEngines()).thenAnswer((_) async => <String>[]);

      final container = makeContainer();
      await container.read(aiOrchestratorProvider.notifier).describe();

      final state = container.read(aiOrchestratorProvider);
      expect(state.hasError, isTrue);
      final error = state.error! as GuidanceVoiceFailedException;
      expect(
        error.text,
        'Caution: Chair very close ahead in center. Door on your left. Sign reads EXIT.',
      );
      expect(announcements, <String>[error.text]);
    });
  });

  group('AiOrchestrator stale-result guard', () {
    test('two rapid describe() calls emit and speak only the second result',
        () async {
      final firstGate = Completer<String?>();
      var calls = 0;

      when(
        () => templateClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) {
        calls++;
        if (calls == 1) return firstGate.future;
        return Future<String?>.value('Second fresh guidance.');
      });

      final container = makeContainer();
      final notifier = container.read(aiOrchestratorProvider.notifier);

      final firstRun = notifier.describe();
      await pumpEventQueue();
      final secondRun = notifier.describe();
      await secondRun;

      firstGate.complete('Stale first guidance.');
      await firstRun;

      expect(
        container.read(aiOrchestratorProvider).value!.text,
        'Second fresh guidance.',
      );
      verifyNever(
        () => cloudTtsClient.synthesizePcm(
          text: 'Stale first guidance.',
          voiceName: any(named: 'voiceName'),
          model: any(named: 'model'),
        ),
      );
      verify(
        () => cloudTtsClient.synthesizePcm(
          text: 'Second fresh guidance.',
          voiceName: any(named: 'voiceName'),
          model: any(named: 'model'),
        ),
      ).called(1);
    });
  });
}
