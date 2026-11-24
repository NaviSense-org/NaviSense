import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/core/utils/navi_log.dart';

/// Device memory metrics returned by native Android `getDeviceMemoryClass`.
final class DeviceMemoryInfo {
  /// Creates [DeviceMemoryInfo].
  const DeviceMemoryInfo({
    required this.memoryClassMb,
    required this.totalMemBytes,
  });

  /// Per-app Dalvik/ART heap limit in MB.
  final int memoryClassMb;

  /// Total physical RAM in bytes.
  final int totalMemBytes;

  /// Whether this device has under 4 GB RAM (for example 3 GB Redmi A3).
  bool get isLowMemoryDevice =>
      totalMemBytes > 0 && totalMemBytes < 4 * 1024 * 1024 * 1024;
}

/// Abstracts native channel operations used by the camera pipeline.
abstract interface class CameraNativeBridge {
  /// Compresses and downscales [path] natively on Android without Dart decoding.
  Future<Uint8List> compressJpeg({
    required String path,
    int maxEdge = 768,
    int quality = 70,
  });

  /// Queries Android `ActivityManager` memory class and total RAM.
  Future<DeviceMemoryInfo> getDeviceMemoryClass();

  /// Opens Android application settings so the user can grant camera access.
  Future<void> openAppSettings();

  /// Whether the Android `CAMERA` runtime permission is already granted.
  Future<bool> hasCameraPermission();
}

/// Production [CameraNativeBridge] backed by `navisense/gemini_nano`.
final class MethodChannelCameraNativeBridge implements CameraNativeBridge {
  /// Creates a [MethodChannelCameraNativeBridge].
  const MethodChannelCameraNativeBridge({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'navisense/gemini_nano',
  );

  final MethodChannel _channel;

  @override
  Future<Uint8List> compressJpeg({
    required String path,
    int maxEdge = 768,
    int quality = 70,
  }) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'compressJpeg',
        <String, Object?>{
          'path': path,
          'maxEdge': maxEdge,
          'quality': quality,
        },
      );
      if (bytes == null || bytes.isEmpty) {
        throw const CameraFailure('Native JPEG compression returned no bytes');
      }
      return bytes;
    } on PlatformException catch (e) {
      throw CameraFailure(e.message ?? 'Native JPEG compression failed');
    }
  }

  @override
  Future<DeviceMemoryInfo> getDeviceMemoryClass() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'getDeviceMemoryClass',
      );
      if (raw == null) {
        return const DeviceMemoryInfo(memoryClassMb: 256, totalMemBytes: 0);
      }
      final memoryClassMb = raw['memoryClassMb'];
      final totalMemBytes = raw['totalMemBytes'];
      return DeviceMemoryInfo(
        memoryClassMb: memoryClassMb is int ? memoryClassMb : 256,
        totalMemBytes: totalMemBytes is int ? totalMemBytes : 0,
      );
    } on PlatformException catch (e, st) {
      log(
        'getDeviceMemoryClass failed; assuming low-RAM safety defaults',
        name: 'navisense.camera',
        error: e,
        stackTrace: st,
      );
      return const DeviceMemoryInfo(memoryClassMb: 256, totalMemBytes: 0);
    }
  }

  @override
  Future<bool> hasCameraPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasCameraPermission') ?? false;
    } on PlatformException catch (e, st) {
      log(
        'hasCameraPermission failed; assuming not granted',
        name: 'navisense.camera',
        error: e,
        stackTrace: st,
      );
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on PlatformException catch (e, st) {
      log(
        'openAppSettings failed',
        name: 'navisense.camera',
        error: e,
        stackTrace: st,
      );
    }
  }
}

/// Pure frame-throttling gate ensuring at most one frame every [intervalMs]
/// and dropping frames while a previous perception pass is in flight.
final class FrameThrottler {
  /// Creates a [FrameThrottler] using [clock].
  FrameThrottler({required Clock clock, this.intervalMs = 700})
      : _clock = clock;

  /// Minimum interval in milliseconds between accepted frames.
  final int intervalMs;

  final Clock _clock;
  int? _lastProcessedMs;
  bool _busy = false;

  /// Whether a frame perception pass is currently executing.
  bool get isBusy => _busy;

  /// Attempts to acquire the throttle slot for an incoming frame.
  ///
  /// Returns `true` only if no frame is currently busy and at least
  /// [intervalMs] ms have elapsed since the previous accepted frame.
  bool tryAcquire() {
    final now = _clock.nowMs();
    final last = _lastProcessedMs;
    if (_busy || (last != null && now - last < intervalMs)) {
      return false;
    }
    _busy = true;
    _lastProcessedMs = now;
    return true;
  }

  /// Releases the busy flag after asynchronous frame processing completes.
  void release() {
    _busy = false;
  }

  /// Resets throttle state (for example after stream restart).
  void reset() {
    _busy = false;
    _lastProcessedMs = null;
  }
}

/// Abstracts the active camera controller surface for testability.
abstract interface class CameraStreamHandle {
  /// Whether the camera controller is initialized.
  bool get isInitialized;

  /// Whether an image stream is currently active.
  bool get isStreamingImages;

  /// Starts streaming NV21 frames.
  Future<void> startImageStream(void Function(CameraImage image) onAvailable);

  /// Stops streaming NV21 frames.
  Future<void> stopImageStream();

  /// Captures a still JPEG picture to a temporary file path.
  Future<String> takePicturePath();
}

/// [CameraStreamHandle] wrapping a real Flutter [CameraController].
final class FlutterCameraStreamHandle implements CameraStreamHandle {
  /// Creates a [FlutterCameraStreamHandle] around [controller].
  const FlutterCameraStreamHandle(this.controller);

  /// Underlying Flutter camera controller.
  final CameraController controller;

  @override
  bool get isInitialized => controller.value.isInitialized;

  @override
  bool get isStreamingImages => controller.value.isStreamingImages;

  @override
  Future<void> startImageStream(void Function(CameraImage image) onAvailable) =>
      controller.startImageStream(onAvailable);

  @override
  Future<void> stopImageStream() => controller.stopImageStream();

  @override
  Future<String> takePicturePath() async {
    final file = await controller.takePicture();
    return file.path;
  }
}

/// Provides [CameraNativeBridge].
final cameraNativeBridgeProvider = Provider<CameraNativeBridge>(
  (ref) => const MethodChannelCameraNativeBridge(),
);

/// Provides [CameraService].
final cameraServiceProvider = Provider<CameraService>(
  (ref) => CameraService(
    clock: ref.watch(clockProvider),
    nativeBridge: ref.watch(cameraNativeBridgeProvider),
  ),
);

/// Manages throttled NV21 streaming, safe snapshot capture, native JPEG
/// downscaling, and spoken camera permission rationale.
final class CameraService {
  /// Creates a [CameraService].
  CameraService({
    required Clock clock,
    required CameraNativeBridge nativeBridge,
    int throttleIntervalMs = 700,
    Duration captureTimeout = const Duration(milliseconds: 2000),
    Future<void> Function(String path)? deleteFile,
  })  : _throttler = FrameThrottler(
          clock: clock,
          intervalMs: throttleIntervalMs,
        ),
        _nativeBridge = nativeBridge,
        _captureTimeout = captureTimeout,
        _deleteFile = deleteFile ?? _defaultDeleteFile;

  final FrameThrottler _throttler;
  final CameraNativeBridge _nativeBridge;
  final Duration _captureTimeout;
  final Future<void> Function(String path) _deleteFile;

  Future<void> Function(CameraImage image)? _activeOnFrame;

  /// Exposes the throttler for unit verification.
  FrameThrottler get throttler => _throttler;

  /// Starts the NV21 image stream and routes accepted frames to [onFrame].
  ///
  /// Never retains [CameraImage] beyond the synchronous callback boundary.
  Future<void> startStream(
    CameraStreamHandle handle,
    Future<void> Function(CameraImage image) onFrame,
  ) async {
    if (!handle.isInitialized || handle.isStreamingImages) return;
    _activeOnFrame = onFrame;
    _throttler.reset();
    try {
      await handle.startImageStream((CameraImage image) {
        if (!_throttler.tryAcquire()) {
          return;
        }
        // WHY: Caller must synchronously copy plane bytes; we never retain `image`.
        unawaited(
          onFrame(image).whenComplete(_throttler.release),
        );
      });
    } on CameraException catch (e) {
      throw CameraFailure(e.description ?? 'Failed to start camera stream');
    }
  }

  /// Stops the active image stream if running.
  Future<void> stopStream(CameraStreamHandle handle) async {
    if (!handle.isInitialized || !handle.isStreamingImages) return;
    try {
      await handle.stopImageStream();
    } on CameraException catch (e) {
      throw CameraFailure(e.description ?? 'Failed to stop camera stream');
    } finally {
      _throttler.reset();
    }
  }

  /// Captures a snapshot safely by pausing the NV21 stream first (preventing
  /// low-end HAL OOMs), downscaling natively in Kotlin, and deleting the temp
  /// file in `finally`.
  Future<Uint8List> captureSnapshot(
    CameraStreamHandle handle, {
    int maxEdge = 768,
    int quality = 70,
  }) async {
    if (!handle.isInitialized) {
      throw const CameraFailure('Camera is not initialized');
    }

    final wasStreaming = handle.isStreamingImages;
    if (wasStreaming) {
      // WHY: Some camera HALs never complete stopImageStream; bound it so a
      // tap can't hang silently.
      try {
        await stopStream(handle).timeout(_captureTimeout);
      } on TimeoutException {
        throw const TimeoutFailure('camera stream stop > 2000ms');
      }
    }

    String? capturedPath;
    try {
      capturedPath = await handle.takePicturePath().timeout(_captureTimeout);
      return await _nativeBridge
          .compressJpeg(
            path: capturedPath,
            maxEdge: maxEdge,
            quality: quality,
          )
          .timeout(_captureTimeout);
    } on TimeoutException {
      throw const TimeoutFailure('camera capture/compress > 2000ms');
    } on CameraException catch (e) {
      throw CameraFailure(e.description ?? 'Snapshot capture failed');
    } finally {
      if (capturedPath != null) {
        try {
          await _deleteFile(capturedPath);
        } catch (e, st) {
          log(
            'Failed to delete temporary snapshot file $capturedPath',
            name: 'navisense.camera',
            error: e,
            stackTrace: st,
          );
        }
      }
      final savedOnFrame = _activeOnFrame;
      if (wasStreaming && savedOnFrame != null && handle.isInitialized) {
        try {
          await startStream(handle, savedOnFrame).timeout(_captureTimeout);
        } catch (e, st) {
          log(
            'Failed to restart camera stream after snapshot',
            name: 'navisense.camera',
            error: e,
            stackTrace: st,
          );
        }
      }
    }
  }

  /// Speaks the onboarding camera permission rationale before prompting the OS.
  ///
  /// Uses [FlutterTts] directly in Unit 3; refactored onto `LocalTtsService`
  /// once Unit 5 lands.
  Future<void> speakPermissionRationale({FlutterTts? tts}) async {
    final engine = tts ?? FlutterTts();
    try {
      await engine.awaitSpeakCompletion(true);
      await engine.setLanguage('en-US');
      await engine.setSpeechRate(0.45);
      await engine.speak(
        'Welcome to NaviSense. I describe what is in front of your camera. '
        'I need camera access.',
      );
    } catch (e, st) {
      log(
        'Spoken permission rationale skipped/failed',
        name: 'navisense.camera',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Opens Android app settings when camera permission is permanently denied.
  Future<void> openAppSettings() => _nativeBridge.openAppSettings();

  static Future<void> _defaultDeleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
