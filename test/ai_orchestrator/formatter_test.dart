import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navisense/core/connectivity/connectivity_probe.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/ai_orchestrator/deterministic_spatial_formatter.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';
import 'package:navisense/features/voice/local_tts_service.dart';

final class _FakeClock implements Clock {
  int _nowMs = 0;

  void advance(int ms) => _nowMs += ms;

  @override
  int nowMs() => _nowMs;

  @override
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(_nowMs);
}

final class _MockTtsEngine extends Mock implements TtsEngine {}

void main() {
  const formatter = DeterministicSpatialFormatter();
  final ts = DateTime.utc(2026, 11, 18);

  group('DeterministicSpatialFormatter', () {
    test('matches §2.6 golden example verbatim', () {
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
        capturedAt: ts,
        processingMs: 35,
      );

      expect(
        formatter.format(summary),
        'Caution: Chair very close ahead in center. '
        'Door on your left. Sign reads EXIT.',
      );
    });

    test('matches empty summary golden string', () {
      expect(
        formatter.format(SpatialSceneSummary.empty(ts)),
        'Path looks clear. No objects detected.',
      );
    });

    test('matches FAR RIGHT golden string', () {
      final summary = SpatialSceneSummary(
        entities: const <SpatialEntity>[
          SpatialEntity(
            kind: EntityKind.object,
            label: 'Table',
            direction: Direction.right,
            distance: Distance.far,
            confidence: 0.82,
          ),
        ],
        texts: const <String>[],
        capturedAt: ts,
        processingMs: 25,
      );

      expect(formatter.format(summary), 'Table further to the right.');
    });

    test('caps 6 entities at <= 4 sentences and is deterministic over 100 runs',
        () {
      final summary = SpatialSceneSummary(
        entities: const <SpatialEntity>[
          SpatialEntity(
            kind: EntityKind.obstacle,
            label: 'cone',
            direction: Direction.left,
            distance: Distance.veryClose,
            confidence: 0.95,
          ),
          SpatialEntity(
            kind: EntityKind.obstacle,
            label: 'bike',
            direction: Direction.right,
            distance: Distance.veryClose,
            confidence: 0.91,
          ),
          SpatialEntity(
            kind: EntityKind.object,
            label: 'door',
            direction: Direction.center,
            distance: Distance.ahead,
            confidence: 0.88,
          ),
          SpatialEntity(
            kind: EntityKind.object,
            label: 'bench',
            direction: Direction.left,
            distance: Distance.ahead,
            confidence: 0.84,
          ),
          SpatialEntity(
            kind: EntityKind.object,
            label: 'tree',
            direction: Direction.center,
            distance: Distance.far,
            confidence: 0.78,
          ),
          SpatialEntity(
            kind: EntityKind.object,
            label: 'car',
            direction: Direction.right,
            distance: Distance.far,
            confidence: 0.72,
          ),
        ],
        texts: const <String>['STOP', 'AHEAD'],
        capturedAt: ts,
        processingMs: 40,
      );

      final first = formatter.format(summary);
      final sentences =
          first.split('.').where((String s) => s.trim().isNotEmpty).toList();
      expect(sentences.length, lessThanOrEqualTo(4));

      for (var i = 0; i < 100; i++) {
        expect(formatter.format(summary), first);
      }
    });

    test('textOnly emits only signs or No text found', () {
      final withTexts = SpatialSceneSummary(
        entities: const <SpatialEntity>[
          SpatialEntity(
            kind: EntityKind.obstacle,
            label: 'Chair',
            direction: Direction.center,
            distance: Distance.veryClose,
            confidence: 0.9,
          ),
        ],
        texts: const <String>['EXIT', 'STAIRS', 'EXTRA'],
        capturedAt: ts,
        processingMs: 20,
      );

      expect(
        formatter.format(withTexts, textOnly: true),
        'Sign reads EXIT. Sign reads STAIRS.',
      );
      expect(
        formatter.format(SpatialSceneSummary.empty(ts), textOnly: true),
        'No text found.',
      );
    });
  });

  group('LocalTtsService', () {
    late _MockTtsEngine engine;

    setUp(() {
      engine = _MockTtsEngine();
      when(() => engine.awaitSpeakCompletion(true)).thenAnswer((_) async {});
      when(() => engine.setSpeechRate(any())).thenAnswer((_) async {});
      when(() => engine.setPitch(1.0)).thenAnswer((_) async {});
      when(() => engine.setVolume(1.0)).thenAnswer((_) async {});
      when(() => engine.setLanguage('en-US')).thenAnswer((_) async {});
      when(() => engine.getEngines())
          .thenAnswer((_) async => <String>['com.google.android.tts']);
      when(() => engine.isLanguageInstalled('en-US'))
          .thenAnswer((_) async => true);
      when(() => engine.speak(any())).thenAnswer((_) async => true);
      when(() => engine.stop()).thenAnswer((_) async {});
    });

    test('initializes per §2.7 and speaks cleanly', () async {
      final tts = LocalTtsService(engine: engine);
      await tts.speak('Caution: Chair very close.');

      expect(tts.isAvailable, isTrue);
      expect(tts.isOfflineVoiceInstalled, isTrue);
      verify(() => engine.awaitSpeakCompletion(true)).called(1);
      verify(() => engine.setSpeechRate(0.45)).called(1);
      verify(() => engine.setPitch(1.0)).called(1);
      verify(() => engine.setVolume(1.0)).called(1);
      verify(() => engine.setLanguage('en-US')).called(1);
      verify(() => engine.speak('Caution: Chair very close.')).called(1);
    });

    test('throws VoiceFailure when no TTS engine is installed', () async {
      when(() => engine.getEngines()).thenAnswer((_) async => <String>[]);
      final tts = LocalTtsService(engine: engine);

      await expectLater(
        tts.speak('Hello'),
        throwsA(isA<VoiceFailure>()),
      );
    });

    test('clamps speech rate to [0.30, 0.70]', () async {
      final tts = LocalTtsService(engine: engine);
      await tts.ensureInitialized();
      await tts.setRate(0.95);
      expect(tts.rate, 0.70);
      verify(() => engine.setSpeechRate(0.70)).called(1);
    });
  });

  group('ConnectivityProbe', () {
    test('caches lookup result for 5s and times out to offline', () async {
      final clock = _FakeClock();
      var calls = 0;

      final probe = ConnectivityProbe(
        clock: clock,
        timeout: const Duration(milliseconds: 25),
        lookup: (String _) async {
          calls++;
          if (calls == 1) {
            return <InternetAddress>[InternetAddress.loopbackIPv4];
          }
          await Future<void>.delayed(const Duration(milliseconds: 60));
          return <InternetAddress>[];
        },
      );

      expect(await probe.isOffline(), isFalse);
      expect(calls, 1);

      clock.advance(4000);
      expect(await probe.isOffline(), isFalse);
      expect(calls, 1);

      clock.advance(1000);
      expect(await probe.isOffline(), isTrue);
      expect(calls, 2);
    });
  });
}
