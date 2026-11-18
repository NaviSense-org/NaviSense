import 'dart:async';
import 'dart:developer';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/features/camera/camera_service.dart';

/// Permission state surfaced by [CameraControllerNotifier] when denied.
final class CameraPermissionDeniedException implements Exception {
  /// Creates a [CameraPermissionDeniedException].
  const CameraPermissionDeniedException({required this.permanentlyDenied});

  /// Whether Android stopped showing the system permission prompt.
  final bool permanentlyDenied;
}

/// Manages the lifecycle-aware back [CameraController] (NV21, medium preset).
final cameraControllerProvider =
    AsyncNotifierProvider<CameraControllerNotifier, CameraController?>(
  CameraControllerNotifier.new,
);

/// Initializes the back camera with `ResolutionPreset.medium` (`enableAudio: false`,
/// `ImageFormatGroup.nv21`) and disposes/re-initializes across lifecycle transitions.
final class CameraControllerNotifier extends AsyncNotifier<CameraController?>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _observerRegistered = false;
  bool _spokeRationaleThisSession = false;

  @override
  Future<CameraController?> build() async {
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    ref.onDispose(() {
      if (_observerRegistered) {
        WidgetsBinding.instance.removeObserver(this);
        _observerRegistered = false;
      }
      unawaited(_disposeCurrentController());
    });

    return _initializeCamera();
  }

  Future<CameraController?> _initializeCamera() async {
    final service = ref.read(cameraServiceProvider);
    final nativeBridge = ref.read(cameraNativeBridgeProvider);

    try {
      if (!_spokeRationaleThisSession) {
        _spokeRationaleThisSession = true;
        await service.speakPermissionRationale();
      }

      final memInfo = await nativeBridge.getDeviceMemoryClass();
      if (!ref.mounted) return null;

      final cameras = await availableCameras();
      if (!ref.mounted || cameras.isEmpty) return null;

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // WHY: Always use ResolutionPreset.medium (~720x480) on Android Go / <4GB
      // devices to stay well below the 150 MB total PSS budget.
      final preset = memInfo.isLowMemoryDevice
          ? ResolutionPreset.medium
          : ResolutionPreset.medium;

      final controller = CameraController(
        backCamera,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await controller.initialize();
      if (!ref.mounted) {
        await controller.dispose();
        return null;
      }

      _controller = controller;
      return controller;
    } on CameraException catch (e) {
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'cameraPermission') {
        throw CameraPermissionDeniedException(
          permanentlyDenied: e.code == 'CameraAccessDeniedWithoutPrompt',
        );
      }
      throw CameraFailure(e.description ?? 'Failed to initialize camera');
    }
  }

  /// Re-attempts camera initialization (for example after returning from Settings).
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_initializeCamera);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_disposeCurrentController());
      if (ref.mounted) {
        this.state = const AsyncData(null);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && ref.mounted) {
        unawaited(retry());
      }
    }
  }

  Future<void> _disposeCurrentController() async {
    final active = _controller;
    _controller = null;
    if (active == null) return;
    try {
      if (active.value.isInitialized && active.value.isStreamingImages) {
        await active.stopImageStream();
      }
    } catch (e, st) {
      log(
        'Error stopping image stream on dispose',
        name: 'navisense.camera',
        error: e,
        stackTrace: st,
      );
    }
    try {
      await active.dispose();
    } catch (e, st) {
      log(
        'Error disposing camera controller',
        name: 'navisense.camera',
        error: e,
        stackTrace: st,
      );
    }
  }
}
