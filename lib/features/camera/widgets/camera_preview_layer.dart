import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/features/camera/camera_controller_provider.dart';

/// Full-bleed aspect-correct camera preview excluded from TalkBack
/// semantics so screen readers never announce "image".
final class CameraPreviewLayer extends ConsumerWidget {
  /// Creates a [CameraPreviewLayer].
  const CameraPreviewLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraAsync = ref.watch(cameraControllerProvider);
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    return ExcludeSemantics(
      child: ColoredBox(
        color: NaviColors.navyDeep,
        child: cameraAsync.when(
          data: (CameraController? controller) {
            if (controller == null || !controller.value.isInitialized) {
              return const SizedBox.expand();
            }
            // WHY: Show the raw camera feed untinted; overlays carry their own
            // backgrounds for legibility.
            return _CoverCameraPreview(
              controller: controller,
              isPortrait: isPortrait,
            );
          },
          loading: () => const SizedBox.expand(),
          error: (Object error, StackTrace _) => const SizedBox.expand(),
        ),
      ),
    );
  }
}

final class _CoverCameraPreview extends StatelessWidget {
  const _CoverCameraPreview({
    required this.controller,
    required this.isPortrait,
  });

  final CameraController controller;
  final bool isPortrait;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null ||
        previewSize.width <= 0 ||
        previewSize.height <= 0) {
      return CameraPreview(controller);
    }

    final width = isPortrait ? previewSize.height : previewSize.width;
    final height = isPortrait ? previewSize.width : previewSize.height;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

/// Accessible full-screen camera permission recovery overlay
/// (`3-ui-context.md` §3.8).
///
/// Kept outside [ExcludeSemantics] so TalkBack users always reach actionable
/// 72dp+ controls without dead ends.
final class CameraPermissionRecoveryOverlay extends StatelessWidget {
  /// Creates a [CameraPermissionRecoveryOverlay].
  const CameraPermissionRecoveryOverlay({
    super.key,
    required this.onOpenSettings,
    required this.onRetry,
  });

  /// Opens system Android app settings so the user can grant camera access.
  final VoidCallback onOpenSettings;

  /// Retries camera initialization after returning from settings.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: NaviColors.navyDeep,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Semantics(
              container: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: NaviColors.navySurface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: NaviColors.hairline,
                        width: 1.5,
                      ),
                    ),
                    child: const SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(
                        Icons.videocam_off_rounded,
                        color: NaviColors.goldAntique,
                        size: 36,
                      ),
                    ),
                  ),
                  const Text(
                    'Camera access needed',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NaviColors.cream,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Text(
                    'Allow camera access so NaviSense can describe what is '
                    'ahead.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NaviColors.creamMuted,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 72),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onPressed: onOpenSettings,
                      child: const Text(
                        'Open settings to allow camera',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 72),
                        foregroundColor: NaviColors.goldAntique,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onPressed: onRetry,
                      child: const Text(
                        'Try again',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
