import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/mlkit_perception/mlkit_perception_service.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';

final class _MockPerceptionDetectors extends Mock
    implements PerceptionDetectors {}

final class _FakeClock implements Clock {
  int _ms = 1000;

  void advance(int deltaMs) => _ms += deltaMs;

  @override
  int nowMs() => _ms;

  @override
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(_ms, isUtc: true);
}

void main() {
  setUpAll(() {
    registerFallbackValue(InputImage.fromFilePath('/tmp/dummy.jpg'));
  });

  group('SpatialSceneSummary.toPromptString', () {
    test('matches §2.3 golden format exactly', () {
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
        processingMs: 38,
      );

      expect(
        summary.toPromptString(),
        '[Obstacle: Chair, CENTER, VERY CLOSE (88%)], '
        '[Object: Door, LEFT, AHEAD (79%)], '
        '[Text: "EXIT"]',
      );
      expect(summary.hasVeryCloseObstacle, isTrue);
    });

    test('staleness checks > 2 seconds', () {
      final base = DateTime.utc(2026, 11, 18, 12, 0, 0);
      final summary = SpatialSceneSummary.empty(base);
      expect(summary.isStaleAt(base.add(const Duration(seconds: 2))), isFalse);
      expect(
        summary.isStaleAt(base.add(const Duration(milliseconds: 2001))),
        isTrue,
      );
    });
  });

  group('MlKitPerceptionService', () {
    late _MockPerceptionDetectors detectors;
    late _FakeClock clock;
    late MlKitPerceptionService service;

    setUp(() {
      detectors = _MockPerceptionDetectors();
      clock = _FakeClock();
      service = MlKitPerceptionService(detectors: detectors, clock: clock);
    });

    test(
        'fuses coarse labels, filters < 0.65 labels, sorts, caps at 5, and filters OCR',
        () async {
      // 1000 x 1000 frame.
      when(() => detectors.detectObjects(any())).thenAnswer((_) async {
        clock.advance(15);
        return <DetectedObject>[
          // Coarse label -> gets ImageLabeler 'Chair' (0.88).
          DetectedObject(
            boundingBox: const Rect.fromLTWH(250, 250, 500, 500),
            labels: <Label>[
              Label(confidence: 0.75, index: 1, text: 'Home good'),
            ],
            trackingId: 1,
          ),
          // Unlabeled -> gets next unused ImageLabel 'Door' (0.79).
          DetectedObject(
            boundingBox: const Rect.fromLTWH(50, 400, 200, 400),
            labels: <Label>[],
            trackingId: 2,
          ),
          // Below 0.65 label ignored -> becomes 'object'.
          DetectedObject(
            boundingBox: const Rect.fromLTWH(800, 400, 150, 150),
            labels: <Label>[
              Label(confidence: 0.64, index: 2, text: 'WeakGuess'),
            ],
            trackingId: 3,
          ),
          // Three more FAR objects to test 5-entity cap.
          for (var i = 0; i < 3; i++)
            DetectedObject(
              boundingBox: Rect.fromLTWH(750 + i * 10.0, 100, 100, 100),
              labels: <Label>[
                Label(
                  confidence: 0.9 - i * 0.05,
                  index: 10 + i,
                  text: 'Pole$i',
                ),
              ],
              trackingId: 10 + i,
            ),
        ];
      });

      when(() => detectors.labelImage(any())).thenAnswer((_) async {
        clock.advance(12);
        return <ImageLabel>[
          ImageLabel(confidence: 0.88, label: 'Chair', index: 1),
          ImageLabel(confidence: 0.79, label: 'Door', index: 2),
          ImageLabel(confidence: 0.64, label: 'IgnoredLowConf', index: 3),
        ];
      });

      when(() => detectors.recognizeText(any())).thenAnswer((_) async {
        clock.advance(10);
        return RecognizedText(
          text: 'combined',
          blocks: <TextBlock>[
            // Too small (< 0.005 of 1_000_000 = 5000).
            TextBlock(
              text: 'tiny',
              lines: const <TextLine>[],
              boundingBox: const Rect.fromLTWH(0, 0, 50, 50), // 2500
              recognizedLanguages: const <String>[],
              cornerPoints: const <Point<int>>[],
            ),
            TextBlock(
              text: '  EXIT\nONLY  ',
              lines: const <TextLine>[],
              boundingBox: const Rect.fromLTWH(10, 10, 200, 100), // 20000
              recognizedLanguages: const <String>[],
              cornerPoints: const <Point<int>>[],
            ),
            TextBlock(
              text: 'A' * 55,
              lines: const <TextLine>[],
              boundingBox: const Rect.fromLTWH(10, 200, 100, 100), // 10000
              recognizedLanguages: const <String>[],
              cornerPoints: const <Point<int>>[],
            ),
            TextBlock(
              text: 'STAIRS',
              lines: const <TextLine>[],
              boundingBox: const Rect.fromLTWH(10, 350, 100, 150), // 15000
              recognizedLanguages: const <String>[],
              cornerPoints: const <Point<int>>[],
            ),
            TextBlock(
              text: 'FOURTH',
              lines: const <TextLine>[],
              boundingBox: const Rect.fromLTWH(10, 550, 100, 60), // 6000
              recognizedLanguages: const <String>[],
              cornerPoints: const <Point<int>>[],
            ),
          ],
        );
      });

      final summary = await service.perceive(
        InputImage.fromFilePath('/tmp/test.jpg'),
        frameSize: const Size(1000, 1000),
      );

      expect(summary.processingMs, 37);
      expect(summary.entities.length, 5);
      expect(summary.entities.first.kind, EntityKind.obstacle);
      expect(summary.entities.first.label, 'Chair');
      expect(summary.entities[1].label, 'Door');

      // Labels below 0.65 never appear anywhere in entities or prompt output.
      final prompt = summary.toPromptString();
      expect(prompt.contains('WeakGuess'), isFalse);
      expect(prompt.contains('IgnoredLowConf'), isFalse);

      // OCR top 3 by area, whitespace collapsed, <= 40 chars.
      expect(summary.texts.length, 3);
      expect(summary.texts[0], 'EXIT ONLY');
      expect(summary.texts[1], 'STAIRS');
      expect(summary.texts[2], 'A' * 40);
    });

    test('throws TimeoutFailure when sequential pipeline exceeds 1000ms',
        () async {
      final slowService = MlKitPerceptionService(
        detectors: detectors,
        clock: clock,
        timeout: const Duration(milliseconds: 20),
      );

      when(() => detectors.detectObjects(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return <DetectedObject>[];
      });

      await expectLater(
        slowService.perceive(
          InputImage.fromFilePath('/tmp/test.jpg'),
          frameSize: const Size(640, 480),
        ),
        throwsA(isA<TimeoutFailure>()),
      );
    });

    test('serializes passes: never two ML Kit runs in flight (low-RAM safety)',
        () async {
      var inFlight = 0;
      var maxInFlight = 0;
      when(() => detectors.detectObjects(any())).thenAnswer((_) async {
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        inFlight--;
        return <DetectedObject>[];
      });
      when(() => detectors.labelImage(any()))
          .thenAnswer((_) async => <ImageLabel>[]);
      when(() => detectors.recognizeText(any())).thenAnswer(
        (_) async => RecognizedText(text: '', blocks: <TextBlock>[]),
      );

      final image = InputImage.fromFilePath('/tmp/test.jpg');
      final first = service.perceive(image, frameSize: const Size(640, 480));
      expect(service.isBusy, isTrue);
      final second = service.perceive(image, frameSize: const Size(640, 480));
      await Future.wait(<Future<SpatialSceneSummary>>[first, second]);

      expect(maxInFlight, 1);
      expect(service.isBusy, isFalse);
    });
  });
}
