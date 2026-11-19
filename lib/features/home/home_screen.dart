import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/core/utils/haptics.dart';
import 'package:navisense/features/ai_orchestrator/ai_orchestrator.dart';
import 'package:navisense/features/ai_orchestrator/models/guidance_result.dart';
import 'package:navisense/features/camera/camera_controller_provider.dart';
import 'package:navisense/features/camera/camera_service.dart';
import 'package:navisense/features/home/settings_screen.dart';
import 'package:navisense/features/home/widgets/bottom_controls.dart';
import 'package:navisense/features/home/widgets/gesture_surface.dart';
import 'package:navisense/features/home/widgets/nano_download_banner.dart';
import 'package:navisense/features/mlkit_perception/mlkit_perception_service.dart';
import 'package:navisense/features/mlkit_perception/perception_provider.dart';
import 'package:navisense/features/telemetry/widgets/telemetry_pill.dart';
import 'package:navisense/features/voice/local_tts_service.dart';

/// Primary blind-first spatial guidance screen (`3-ui-context.md` §3.2–§3.8).
final class HomeScreen extends ConsumerStatefulWidget {
  /// Creates the [HomeScreen].
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _heartbeatTimer;
  CameraController? _streamingController;
  bool _announcedCameraReady = false;
  bool _checkedVoiceData = false;
  bool _ranOnboarding = false;
  bool _missingOfflineVoice = false;

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final orchestratorAsync = ref.watch(aiOrchestratorProvider);

    _listenCameraStream();
    _listenOrchestratorSideEffects(settings);
    _scheduleStartupChecks(settings);

    final captionText = _resolveCaptionText(orchestratorAsync);
    final isVoiceUnavailableError = orchestratorAsync.hasError &&
        orchestratorAsync.error is GuidanceVoiceFailedException;

    return Scaffold(
      backgroundColor: NaviColors.navyDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: GestureSurface(
              isAnalyzing: orchestratorAsync.isLoading,
              onDescribe: () => unawaited(
                ref.read(aiOrchestratorProvider.notifier).describe(),
              ),
              onReadText: () => unawaited(
                ref.read(aiOrchestratorProvider.notifier).readText(),
              ),
              onRepeat: () => unawaited(
                ref.read(aiOrchestratorProvider.notifier).repeat(),
              ),
              onStop: () => unawaited(
                ref.read(aiOrchestratorProvider.notifier).stop(),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const NanoDownloadBanner(),
                  const SizedBox(height: 8),
                  Center(
                    child: TelemetryPill(
                      judgeMode: settings.judgeMode,
                      announceInferenceTier: settings.announceInferenceTier,
                    ),
                  ),
                  if (_missingOfflineVoice) ...<Widget>[
                    const SizedBox(height: 8),
                    const _OfflineVoiceMissingBanner(),
                  ],
                  const Spacer(),
                  if (captionText != null) ...<Widget>[
                    _GuidanceCaption(
                      text: captionText,
                      liveRegion: isVoiceUnavailableError,
                    ),
                    const SizedBox(height: 16),
                  ],
                  BottomControls(
                    onRepeat: () => unawaited(
                      ref.read(aiOrchestratorProvider.notifier).repeat(),
                    ),
                    onReadText: () => unawaited(
                      ref.read(aiOrchestratorProvider.notifier).readText(),
                    ),
                    onOpenSettings: () => _openSettings(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _listenCameraStream() {
    ref.listen<AsyncValue<CameraController?>>(cameraControllerProvider, (
      AsyncValue<CameraController?>? prev,
      AsyncValue<CameraController?> next,
    ) {
      final controller = next.value;
      if (controller == null || !controller.value.isInitialized) {
        _streamingController = null;
        return;
      }
      if (!identical(_streamingController, controller)) {
        _streamingController = controller;
        final cameraService = ref.read(cameraServiceProvider);
        final mlKit = ref.read(mlKitPerceptionServiceProvider);
        final handle = FlutterCameraStreamHandle(controller);
        unawaited(
          cameraService.startStream(handle, (CameraImage image) async {
            final input = MlKitPerceptionService.inputFromNv21CameraImage(
              cameraImage: image,
              sensorOrientation: controller.description.sensorOrientation,
              deviceOrientation: controller.value.deviceOrientation,
            );
            final summary = await mlKit.perceive(
              input.image,
              frameSize: input.frameSize,
            );
            if (!mounted) return;
            ref.read(perceptionProvider.notifier).update(summary);
          }),
        );
        if (!_announcedCameraReady) {
          _announcedCameraReady = true;
          _announce('Camera ready');
        }
      }
    });
  }

  void _listenOrchestratorSideEffects(SettingsState settings) {
    ref.listen<AsyncValue<GuidanceResult?>>(aiOrchestratorProvider, (
      AsyncValue<GuidanceResult?>? prev,
      AsyncValue<GuidanceResult?> next,
    ) {
      if (next.isLoading) {
        if (settings.hapticsEnabled) {
          unawaited(ref.read(tierHapticsProvider).tap());
        }
        _startHeartbeat(settings);
        return;
      }

      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;

      if (next.hasError) {
        if (settings.hapticsEnabled) {
          unawaited(ref.read(tierHapticsProvider).sos());
        }
        return;
      }

      final result = next.value;
      if (result != null && settings.hapticsEnabled) {
        unawaited(_playTierHaptics(result));
      }
    });
  }

  void _startHeartbeat(SettingsState settings) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (mounted && settings.hapticsEnabled) {
        unawaited(ref.read(tierHapticsProvider).heartbeat());
      }
    });
  }

  Future<void> _playTierHaptics(GuidanceResult result) async {
    final haptics = ref.read(tierHapticsProvider);
    if (result.hasVeryCloseObstacle) {
      await haptics.veryCloseObstacle();
    }
    switch (result.tier) {
      case Tier1Nano(inCloudFallback: false):
        await haptics.tier1();
      case Tier1Nano(inCloudFallback: true):
      case Tier2Cloud():
        await haptics.tier2();
      case Tier3Edge():
        await haptics.tier3();
    }
  }

  void _scheduleStartupChecks(SettingsState settings) {
    if (!_checkedVoiceData) {
      _checkedVoiceData = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final tts = ref.read(localTtsServiceProvider);
        await tts.ensureInitialized();
        if (!mounted) return;
        if (tts.isAvailable && !tts.isOfflineVoiceInstalled) {
          setState(() => _missingOfflineVoice = true);
        }
      });
    }

    if (!_ranOnboarding && !settings.onboardingCompleted) {
      _ranOnboarding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(settingsProvider.notifier).markOnboardingCompleted();
        if (!mounted) return;
        await ref.read(localTtsServiceProvider).speak(
              'Hold your phone at chest height, camera facing forward. '
              'Tap anywhere to hear what is ahead. Hold to read text.',
            );
      });
    }
  }

  String? _resolveCaptionText(AsyncValue<GuidanceResult?> orchestratorAsync) {
    if (orchestratorAsync.hasError &&
        orchestratorAsync.error is GuidanceVoiceFailedException) {
      return (orchestratorAsync.error! as GuidanceVoiceFailedException).text;
    }
    return orchestratorAsync.value?.text;
  }

  void _openSettings(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
      ),
    );
  }

  void _announce(String message) {
    final view = View.maybeOf(context);
    if (view == null) return;
    // WHY: State change announcements per §3.4 Rule 6.
    unawaited(
      SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
    );
  }
}

final class _GuidanceCaption extends StatelessWidget {
  const _GuidanceCaption({required this.text, required this.liveRegion});

  final String text;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        liveRegion: liveRegion,
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NaviColors.navyDeep.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NaviColors.cream,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _OfflineVoiceMissingBanner extends StatelessWidget {
  const _OfflineVoiceMissingBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: NaviColors.navyDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NaviColors.errorRed, width: 2),
        ),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Install offline voice data in Settings → Text-to-speech',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NaviColors.cream,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
