import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/features/ai_orchestrator/nano_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(NanoBridge.methodChannelName);
  const downloadChannel = EventChannel(NanoBridge.downloadChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late NanoBridge bridge;

  setUp(() {
    bridge = NanoBridge(
      methodChannel: methodChannel,
      downloadChannel: downloadChannel,
      generateTimeout: const Duration(milliseconds: 50),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(downloadChannel, null);
  });

  group('NanoBridge.getStatus', () {
    test('maps all native status strings accurately', () async {
      for (final entry in <String, NanoStatus>{
        'AVAILABLE': NanoStatus.available,
        'DOWNLOADABLE': NanoStatus.downloadable,
        'DOWNLOADING': NanoStatus.downloading,
        'UNAVAILABLE': NanoStatus.unavailable,
        'SOMETHING_ELSE': NanoStatus.unavailable,
      }.entries) {
        messenger.setMockMethodCallHandler(
          methodChannel,
          (MethodCall call) async => entry.key,
        );
        expect(await bridge.getStatus(), entry.value);
      }
    });

    test('returns unavailable when platform throws', () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall call) =>
            throw PlatformException(code: 'ERR', message: 'no'),
      );
      expect(await bridge.getStatus(), NanoStatus.unavailable);
    });
  });

  group('NanoBridge.generate', () {
    final jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]);

    test('parses ON_DEVICE and IN_CLOUD results', () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall call) async => <String, Object?>{
          'text': 'Chair very close ahead.',
          'inferenceSource': 'ON_DEVICE',
          'latencyMs': 410,
        },
      );

      final onDevice = await bridge.generate(jpeg: jpeg, summary: 'Chair');
      expect(onDevice.text, 'Chair very close ahead.');
      expect(onDevice.inferenceSource, NanoInferenceSource.onDevice);
      expect(onDevice.latencyMs, 410);

      messenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall call) async => <String, Object?>{
          'text': 'Door on your left.',
          'inferenceSource': 'IN_CLOUD',
          'latencyMs': 920,
        },
      );

      final inCloud = await bridge.generate(jpeg: jpeg, summary: 'Door');
      expect(inCloud.inferenceSource, NanoInferenceSource.inCloud);
    });

    test(
        'maps NANO_TIMEOUT PlatformException to NanoFailure(code: NANO_TIMEOUT)',
        () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall call) => throw PlatformException(
          code: 'NANO_TIMEOUT',
          message: 'Exceeded 4000ms',
        ),
      );

      await expectLater(
        bridge.generate(jpeg: jpeg, summary: 'Chair'),
        throwsA(
          isA<NanoFailure>().having(
            (NanoFailure f) => f.code,
            'code',
            'NANO_TIMEOUT',
          ),
        ),
      );
    });

    test('maps malformed map payload to NanoFailure(code: NANO_FAILED)',
        () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall call) async => <String, Object?>{
          'text': 123,
          'inferenceSource': 'ON_DEVICE',
        },
      );

      await expectLater(
        bridge.generate(jpeg: jpeg, summary: 'Chair'),
        throwsA(
          isA<NanoFailure>().having(
            (NanoFailure f) => f.code,
            'code',
            'NANO_FAILED',
          ),
        ),
      );
    });

    test('maps Dart-side timeout to TimeoutFailure', () async {
      messenger.setMockMethodCallHandler(methodChannel,
          (MethodCall call) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return <String, Object?>{
          'text': 'Too late',
          'inferenceSource': 'ON_DEVICE',
          'latencyMs': 120,
        };
      });

      await expectLater(
        bridge.generate(jpeg: jpeg, summary: 'Chair'),
        throwsA(isA<TimeoutFailure>()),
      );
    });
  });

  group('NanoBridge.downloadProgress', () {
    test('emits typed NanoDownloadProgress events from EventChannel', () async {
      messenger.setMockStreamHandler(
        downloadChannel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events.success(<String, Object?>{
              'state': 'DOWNLOADING',
              'bytesDownloaded': 500,
              'totalBytes': 1000,
            });
            events.success(<String, Object?>{
              'state': 'COMPLETED',
              'bytesDownloaded': 1000,
              'totalBytes': 1000,
            });
            events.endOfStream();
          },
        ),
      );

      final items = await bridge.downloadProgress.toList();
      expect(items, const <NanoDownloadProgress>[
        NanoDownloadProgress(
          state: 'DOWNLOADING',
          bytesDownloaded: 500,
          totalBytes: 1000,
        ),
        NanoDownloadProgress(
          state: 'COMPLETED',
          bytesDownloaded: 1000,
          totalBytes: 1000,
        ),
      ]);
      expect(items.first.percent, 50);
      expect(items.last.isCompleted, isTrue);
    });
  });
}
