import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/features/camera/camera_controller_provider.dart';
import 'package:navisense/features/camera/camera_service.dart';

/// Full-bleed dimmed camera preview layer excluded from TalkBack semantics so
/// screen readers never announce "image".
final class CameraPreviewLayer extends ConsumerWidget {
  /// Creates a [CameraPreviewLayer].
  const CameraPreviewLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraAsync = ref.watch(cameraControllerProvider);

    return ExcludeSemantics(
      child: ColoredBox(
        color: NaviColors.navyDeep,
        child: cameraAsync.when(
          data: (CameraController? controller) {
            if (controller == null || !controller.value.isInitialized) {
              return const SizedBox.expand();
            }
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CameraPreview(controller),
                ColoredBox(
                  color: NaviColors.navyDeep.withValues(alpha: 0.65),
                ),
              ],
            );
          },
          loading: () => const SizedBox.expand(),
          error: (Object error, StackTrace _) {
            if (error is CameraPermissionDeniedException) {
              return _PermissionRecoveryOverlay(
                onOpenSettings: () =>
                    ref.read(cameraServiceProvider).openAppSettings(),
                onRetry: () =>
                    ref.read(cameraControllerProvider.notifier).retry(),
              );
            }
            return const SizedBox.expand();
          },
        ),
      ),
    );
  }
}

final class _PermissionRecoveryOverlay extends StatelessWidget {
  const _PermissionRecoveryOverlay({
    required this.onOpenSettings,
    required this.onRetry,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: <Widget>[
              const Text(
                'Camera access is needed to describe your surroundings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NaviColors.cream,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(220, 72),
                  foregroundColor: NaviColors.cream,
                  side: const BorderSide(
                    color: NaviColors.goldAntique,
                    width: 2,
                  ),
                ),
                onPressed: onOpenSettings,
                child: const Text(
                  'Open settings to allow camera',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(220, 72),
                  foregroundColor: NaviColors.goldAntique,
                ),
                onPressed: onRetry,
                child: const Text(
                  'Try again',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
