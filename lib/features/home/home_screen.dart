import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/connectivity/network_status.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/core/utils/haptics.dart';
import 'package:navisense/core/utils/navi_log.dart';
import 'package:navisense/features/ai_orchestrator/ai_orchestrator.dart';
import 'package:navisense/features/ai_orchestrator/models/guidance_result.dart';
import 'package:navisense/features/camera/camera_controller_provider.dart';
import 'package:navisense/features/camera/camera_service.dart';
import 'package:navisense/features/camera/widgets/camera_preview_layer.dart';
import 'package:navisense/features/home/settings_screen.dart';
import 'package:navisense/features/home/widgets/bottom_controls.dart';
import 'package:navisense/features/home/widgets/gesture_surface.dart';
import 'package:navisense/features/home/widgets/nano_download_banner.dart';
import 'package:navisense/features/mlkit_perception/mlkit_perception_service.dart';
import 'package:navisense/features/mlkit_perception/perception_provider.dart';
import 'package:navisense/features/telemetry/widgets/telemetry_pill.dart';
import 'package:navisense/features/voice/local_tts_service.dart';
import 'package:navisense/features/voice/voice_player.dart';

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
    final cameraAsync = ref.watch(cameraControllerProvider);

    _listenCameraStream();
    _listenNetworkChanges();
    _listenOrchestratorSideEffects(settings);
    final isOffline = ref.watch(networkStatusProvider) == NetworkStatus.offline;
    _scheduleStartupChecks(settings);

    if (cameraAsync.hasError &&
        cameraAsync.error is CameraPermissionDeniedException) {
      return Scaffold(
        backgroundColor: NaviColors.navyDeep,
        body: CameraPermissionRecoveryOverlay(
          onOpenSettings: () => unawaited(
            ref.read(cameraServiceProvider).openAppSettings(),
          ),
          onRetry: () => ref.read(cameraControllerProvider.notifier).retry(),
        ),
      );
    }

    final captionText = _resolveCaptionText(orchestratorAsync);
    final isVoiceUnavailableError = orchestratorAsync.hasError &&
        orchestratorAsync.error is GuidanceVoiceFailedException;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

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
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final reservedBottom = (textScale > 1.5 ? 140.0 : 108.0) +
                      (captionText != null
                          ? (textScale > 1.5 ? 160.0 : 180.0)
                          : 0.0);
                  final maxTopHeight = math.max(
                    120.0,
                    constraints.maxHeight - reservedBottom,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxTopHeight),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const NanoDownloadBanner(),
                              Center(
                                child: TelemetryPill(
                                  judgeMode: settings.judgeMode,
                                  announceInferenceTier:
                                      settings.announceInferenceTier,
                                ),
                              ),
                              if (isOffline) ...<Widget>[
                                const SizedBox(height: 12),
                                const _NetworkOfflineBanner(),
                              ],
                              if (_missingOfflineVoice) ...<Widget>[
                                const SizedBox(height: 12),
                                const _OfflineVoiceMissingBanner(),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _AnalyzingIndicator(
                            visible: orchestratorAsync.isLoading,
                            disableAnimations: disableAnimations,
                          ),
                        ),
                      ),
                      if (captionText != null) ...<Widget>[
                        _GuidanceCaption(
                          text: captionText,
                          liveRegion: isVoiceUnavailableError,
                          maxLines: textScale > 1.5 ? 2 : 4,
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
                  );
                },
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
            // WHY: Skip (don't queue) background frames while an on-tap
            // snapshot pass holds the single ML Kit slot.
            if (mlKit.isBusy) return;
            final input = MlKitPerceptionService.inputFromNv21CameraImage(
              cameraImage: image,
              sensorOrientation: controller.description.sensorOrientation,
              deviceOrientation: controller.value.deviceOrientation,
            );
            try {
              final summary = await mlKit.perceive(
                input.image,
                frameSize: input.frameSize,
              );
              if (!mounted) return;
              ref.read(perceptionProvider.notifier).update(summary);
            } on NaviFailure catch (e) {
              // WHY: A slow/failed background frame is expected (cold ML Kit
              // model load, low-end CPU); drop it instead of surfacing an
              // unhandled async exception every 700 ms.
              log('Stream frame dropped', name: 'navisense.mlkit', error: e);
            }
          }),
        );
        if (!_announcedCameraReady) {
          _announcedCameraReady = true;
          _announce('Camera ready');
        }
      }
    });
  }

  /// Offline notice spoken when the connection drops.
  static const String offlineNotice =
      "You're offline. I'll keep guiding you with on-device detection, "
      'with less detail.';

  /// Notice spoken when the connection returns.
  static const String onlineNotice =
      'Back online. Full scene descriptions are available again.';

  void _listenNetworkChanges() {
    ref.listen<NetworkStatus>(networkStatusProvider, (
      NetworkStatus? prev,
      NetworkStatus next,
    ) {
      if (prev == next) return;
      if (next == NetworkStatus.offline) {
        unawaited(_announceWhenIdle(offlineNotice));
      } else if (next == NetworkStatus.online &&
          prev == NetworkStatus.offline) {
        unawaited(_announceWhenIdle(onlineNotice));
      }
    });
  }

  /// Speaks [message] as soon as no guidance is being produced or spoken.
  ///
  /// WHY: A connectivity notice must never cut off a hazard warning, but it
  /// should still arrive promptly (bounded wait of ~10 s).
  Future<void> _announceWhenIdle(String message) async {
    for (var i = 0; i < 20; i++) {
      if (!mounted) return;
      final busy = ref.read(aiOrchestratorProvider).isLoading ||
          ref.read(voicePlayerProvider).isBusy;
      if (!busy) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;
    try {
      await ref.read(voicePlayerProvider).speakLocal(message);
    } on NaviFailure {
      _announce(message);
    }
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

    if (!_ranOnboarding) {
      _ranOnboarding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final settingsNotifier = ref.read(settingsProvider.notifier);
        await settingsNotifier.hydrated;
        if (!mounted || ref.read(settingsProvider).onboardingCompleted) return;
        await settingsNotifier.markOnboardingCompleted();
        // WHY: Wait for the camera permission rationale/prompt to finish so
        // the two utterances don't race; flutter_tts rejects a second
        // `speak` while one is in flight (returns 0 -> VoiceFailure).
        try {
          await ref
              .read(cameraControllerProvider.future)
              .timeout(const Duration(seconds: 20));
        } catch (_) {
          // Permission denied / timeout: still give the hint below.
        }
        if (!mounted) return;
        try {
          await ref.read(localTtsServiceProvider).speak(
                'Hold your phone at chest height, camera facing forward. '
                'Tap anywhere to hear what is ahead. Hold to read text.',
              );
        } on NaviFailure catch (e) {
          log('Onboarding hint not spoken', name: 'navisense.home', error: e);
        }
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

final class _AnalyzingIndicator extends StatelessWidget {
  const _AnalyzingIndicator({
    required this.visible,
    required this.disableAnimations,
  });

  final bool visible;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    // WHY: GestureSurface already exposes value 'Analyzing…' to TalkBack, so
    // the visual pill is excluded from semantics to prevent double announcements.
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: visible
              ? DecoratedBox(
                  key: const ValueKey<String>('analyzing-pill'),
                  decoration: BoxDecoration(
                    color: NaviColors.navySurface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: NaviColors.goldAntique,
                      width: 1.5,
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 12,
                      children: <Widget>[
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: NaviColors.goldAntique,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            'Analyzing…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: NaviColors.cream,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

final class _GuidanceCaption extends StatelessWidget {
  const _GuidanceCaption({
    required this.text,
    required this.liveRegion,
    required this.maxLines,
  });

  final String text;
  final bool liveRegion;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        liveRegion: liveRegion,
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NaviColors.navySurface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NaviColors.hairline, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: maxLines,
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

final class _NetworkOfflineBanner extends StatelessWidget {
  const _NetworkOfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Offline. On-device guidance only.',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: NaviColors.navySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NaviColors.goldAntique, width: 1.5),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            spacing: 12,
            children: <Widget>[
              Icon(
                Icons.cloud_off_rounded,
                color: NaviColors.goldAntique,
                size: 24,
              ),
              Expanded(
                child: Text(
                  'Offline · on-device guidance only',
                  style: TextStyle(
                    color: NaviColors.cream,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
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
          color: NaviColors.navySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NaviColors.errorRed, width: 1.5),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            spacing: 12,
            children: <Widget>[
              Icon(
                Icons.record_voice_over_rounded,
                color: NaviColors.errorRed,
                size: 24,
              ),
              Expanded(
                child: Text(
                  'Install offline voice data in Settings → Text-to-speech',
                  style: TextStyle(
                    color: NaviColors.cream,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
