import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/camera/camera_service.dart';

final class _FakeClock implements Clock {
  int _nowMs = 0;

  void setNowMs(int ms) => _nowMs = ms;

  @override
  int nowMs() => _nowMs;

  @override
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(_nowMs);
}

final class _MockCameraNativeBridge extends Mock
    implements CameraNativeBridge {}

final class _MockCameraStreamHandle extends Mock
    implements CameraStreamHandle {}

void main() {
  group('FrameThrottler', () {
    test('processes exactly t=0 and t=700 across 10 frames at 100ms intervals',
        () {
      final clock = _FakeClock();
      final throttler = FrameThrottler(clock: clock, intervalMs: 700);
      final processedAt = <int>[];

      for (var i = 0; i < 10; i++) {
        final ts = i * 100;
        clock.setNowMs(ts);
        if (throttler.tryAcquire()) {
          processedAt.add(ts);
          throttler.release();
        }
      }

      expect(processedAt, <int>[0, 700]);
    });

    test('drops frames arriving while busy even past throttle interval', () {
      final clock = _FakeClock();
      final throttler = FrameThrottler(clock: clock, intervalMs: 700);

      clock.setNowMs(0);
      expect(throttler.tryAcquire(), isTrue);
      expect(throttler.isBusy, isTrue);

      // Even after 1000 ms, frame is dropped because previous frame is still busy.
      clock.setNowMs(1000);
      expect(throttler.tryAcquire(), isFalse);

      throttler.release();
      expect(throttler.tryAcquire(), isTrue);
    });
  });

  group('CameraService.captureSnapshot', () {
    late _FakeClock clock;
    late _MockCameraNativeBridge nativeBridge;
    late _MockCameraStreamHandle handle;
    late List<String> deletedPaths;
    late bool streaming;

    setUp(() {
      clock = _FakeClock();
      nativeBridge = _MockCameraNativeBridge();
      handle = _MockCameraStreamHandle();
      deletedPaths = <String>[];
      streaming = false;

      when(() => handle.isInitialized).thenReturn(true);
      when(() => handle.isStreamingImages).thenAnswer((_) => streaming);
      when(() => handle.stopImageStream()).thenAnswer((_) async {
        streaming = false;
      });
      when(() => handle.startImageStream(any())).thenAnswer((_) async {
        streaming = true;
      });
      when(() => handle.takePicturePath())
          .thenAnswer((_) async => '/tmp/snap_001.jpg');
      when(
        () => nativeBridge.compressJpeg(
          path: '/tmp/snap_001.jpg',
          maxEdge: 768,
          quality: 70,
        ),
      ).thenAnswer((_) async => Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]));
    });

    test(
        'pauses stream, compresses natively, deletes temp file, and restarts stream',
        () async {
      final service = CameraService(
        clock: clock,
        nativeBridge: nativeBridge,
        deleteFile: (String path) async => deletedPaths.add(path),
      );

      await service.startStream(handle, (_) async {});
      final jpeg = await service.captureSnapshot(handle);

      expect(jpeg, Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]));
      expect(deletedPaths, <String>['/tmp/snap_001.jpg']);
      expect(streaming, isTrue);
      verifyInOrder(<Future<void> Function()>[
        () => handle.startImageStream(any()),
        () => handle.stopImageStream(),
        () => handle.takePicturePath(),
        () => nativeBridge.compressJpeg(
              path: '/tmp/snap_001.jpg',
              maxEdge: 768,
              quality: 70,
            ),
        () => handle.startImageStream(any()),
      ]);
    });

    test('deletes temp file in finally even when native compression throws',
        () async {
      when(
        () => nativeBridge.compressJpeg(
          path: any(named: 'path'),
          maxEdge: any(named: 'maxEdge'),
          quality: any(named: 'quality'),
        ),
      ).thenThrow(const CameraFailure('decode error'));

      final service = CameraService(
        clock: clock,
        nativeBridge: nativeBridge,
        deleteFile: (String path) async => deletedPaths.add(path),
      );

      await expectLater(
        service.captureSnapshot(handle),
        throwsA(isA<CameraFailure>()),
      );
      expect(deletedPaths, <String>['/tmp/snap_001.jpg']);
    });

    test('maps takePicture timeout to TimeoutFailure', () async {
      final service = CameraService(
        clock: clock,
        nativeBridge: nativeBridge,
        captureTimeout: const Duration(milliseconds: 20),
        deleteFile: (String path) async => deletedPaths.add(path),
      );

      when(() => handle.takePicturePath()).thenAnswer(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return '/tmp/slow.jpg';
        },
      );

      await expectLater(
        service.captureSnapshot(handle),
        throwsA(isA<TimeoutFailure>()),
      );
    });
  });
}
