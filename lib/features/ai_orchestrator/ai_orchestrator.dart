import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher, TextDirection;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/connectivity/connectivity_probe.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/ai_orchestrator/cloud_reasoning_service.dart';
import 'package:navisense/features/ai_orchestrator/deterministic_spatial_formatter.dart';
import 'package:navisense/features/ai_orchestrator/models/guidance_result.dart';
import 'package:navisense/features/ai_orchestrator/nano_bridge.dart';
import 'package:navisense/features/camera/camera_controller_provider.dart';
import 'package:navisense/features/camera/camera_service.dart';
import 'package:navisense/features/mlkit_perception/mlkit_perception_service.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';
import 'package:navisense/features/mlkit_perception/perception_provider.dart';
import 'package:navisense/features/telemetry/telemetry_notifier.dart';
import 'package:navisense/features/voice/cloud_tts_service.dart';
import 'package:navisense/features/voice/voice_player.dart';
import 'package:path_provider/path_provider.dart';

/// Error carrying the settled [GuidanceResult] (including text) when every
/// voice playback path fails so the UI can display the text and trigger SOS.
final class GuidanceVoiceFailedException implements Exception {
  /// Creates a [GuidanceVoiceFailedException].
  const GuidanceVoiceFailedException(this.result);

  /// Guidance result whose spoken output could not be played via audio/TTS.
  final GuidanceResult result;

  /// Human-readable guidance text for display/accessibility announcement.
  String get text => result.text;
}

/// Abstracts snapshot capture + Stage 0 freshness resolution for unit tests.
abstract interface class OrchestratorPerceptionGateway {
  /// Captures a compressed `<= 768px` JPEG snapshot.
  Future<Uint8List> captureSnapshot();

  /// Returns a fresh (`<= 2s`) [SpatialSceneSummary], running Stage 0 on [jpeg]
  /// if the cached stream summary is missing or stale.
  Future<SpatialSceneSummary> resolveFreshSummary(Uint8List jpeg);
}

/// Production [OrchestratorPerceptionGateway] wired to `CameraService` and
/// `MlKitPerceptionService`.
final class DefaultOrchestratorPerceptionGateway
    implements OrchestratorPerceptionGateway {
  /// Creates a [DefaultOrchestratorPerceptionGateway].
  const DefaultOrchestratorPerceptionGateway(this._ref);

  final Ref _ref;

  @override
  Future<Uint8List> captureSnapshot() async {
    final controller = _ref.read(cameraControllerProvider).value;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraFailure('Camera is not ready yet');
    }
    return _ref
        .read(cameraServiceProvider)
        .captureSnapshot(FlutterCameraStreamHandle(controller));
  }

  @override
  Future<SpatialSceneSummary> resolveFreshSummary(Uint8List jpeg) async {
    final perceptionNotifier = _ref.read(perceptionProvider.notifier);
    final latest = _ref.read(perceptionProvider);
    if (latest != null && !perceptionNotifier.isStale) {
      return latest;
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/navisense_stage0_${_ref.read(clockProvider).nowMs()}.jpg',
    );
    try {
      await tempFile.writeAsBytes(jpeg, flush: true);
      final inputImage = MlKitPerceptionService.inputFromFilePath(
        tempFile.path,
      );
      final frameSize = MlKitPerceptionService.readJpegDimensions(jpeg);
      final fresh = await _ref
          .read(mlKitPerceptionServiceProvider)
          .perceive(inputImage, frameSize: frameSize);
      perceptionNotifier.update(fresh);
      return fresh;
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } on FileSystemException {
          // Best-effort transient file cleanup.
        }
      }
    }
  }
}

/// Provides [OrchestratorPerceptionGateway] (overridable in routing tests).
final orchestratorPerceptionGatewayProvider =
    Provider<OrchestratorPerceptionGateway>(
  (ref) => DefaultOrchestratorPerceptionGateway(ref),
);

/// Injectable last-resort TalkBack announcement hook (`SemanticsService`).
final semanticsAnnouncerProvider = Provider<void Function(String message)>(
  (ref) => _defaultSemanticsAnnounce,
);

void _defaultSemanticsAnnounce(String message) {
  final view = PlatformDispatcher.instance.implicitView;
  if (view == null) return;
  // WHY: Last-resort TalkBack fallback when both AudioPlayer and FlutterTts fail.
  unawaited(
    SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
  );
}

/// Provides the central 3-tier [AiOrchestrator].
final aiOrchestratorProvider =
    AsyncNotifierProvider<AiOrchestrator, GuidanceResult?>(AiOrchestrator.new);

/// Coordinates Stage 0 perception, Tier 1 Gemini Nano 4, Tier 2 Cloud Prompt
/// Templates + Cloud TTS, and Tier 3 deterministic edge fallback (`§2.7`).
final class AiOrchestrator extends AsyncNotifier<GuidanceResult?> {
  int _requestId = 0;

  @override
  FutureOr<GuidanceResult?> build() => null;

  /// Describes the current scene through the 3-tier hybrid pipeline.
  Future<void> describe() => _runPipeline(textOnly: false);

  /// Runs the 3-tier hybrid pipeline prioritizing visible signage/text.
  Future<void> readText() => _runPipeline(textOnly: true);

  /// Replays the most recent [GuidanceResult] via cache or local TTS.
  Future<void> repeat() async {
    final last = state.value;
    if (last == null) {
      await _speakOrAnnounce('No previous guidance yet.');
      return;
    }

    final myId = ++_requestId;
    final voicePlayer = ref.read(voicePlayerProvider);
    await voicePlayer.stop();
    if (_isStale(myId)) return;

    await _speakTier3OrReplay(last, myId);
  }

  /// Stops active voice output and cancels any in-flight reasoning result.
  Future<void> stop() async {
    _requestId++;
    await ref.read(voicePlayerProvider).stop();
  }

  Future<void> _runPipeline({required bool textOnly}) async {
    final myId = ++_requestId;
    final voicePlayer = ref.read(voicePlayerProvider);
    final clock = ref.read(clockProvider);
    final telemetry = ref.read(telemetryProvider.notifier);

    await voicePlayer.stop();
    if (_isStale(myId)) return;

    state = const AsyncLoading();

    final gateway = ref.read(orchestratorPerceptionGatewayProvider);
    final Uint8List jpeg;
    try {
      jpeg = await gateway.captureSnapshot();
    } on NaviFailure catch (e, st) {
      if (_isStale(myId)) return;
      const fallbackResult = GuidanceResult(
        text: 'Camera unavailable. Please try again.',
        tier: Tier3Edge(),
        stage0Ms: 0,
        inferenceMs: 0,
      );
      telemetry.updateFromResult(fallbackResult);
      await _deliverLocalVoice(fallbackResult, myId, errorStack: st);
      return;
    }
    if (_isStale(myId)) return;

    SpatialSceneSummary summary;
    try {
      summary = await gateway.resolveFreshSummary(jpeg);
    } catch (e, st) {
      // WHY: §4.7.3 — Perception failure is non-fatal; continue with empty summary.
      log(
        'Stage 0 perception failed; continuing with empty summary',
        name: 'navisense.orchestrator',
        error: e,
        stackTrace: st,
      );
      summary = SpatialSceneSummary.empty(clock.now());
    }
    if (_isStale(myId)) return;

    // 1. Try Tier 1 (Gemini Nano 4 via OnDeviceExtension) when AVAILABLE.
    final nanoBridge = ref.read(nanoBridgeProvider);
    var nanoStatus = ref.read(nanoStatusProvider).value;
    nanoStatus ??= await nanoBridge.getStatus();
    if (_isStale(myId)) return;

    if (nanoStatus == NanoStatus.available) {
      try {
        final summaryInput = textOnly
            ? 'Read all visible text verbatim. ${summary.toPromptString()}'
            : summary.toPromptString();
        final nanoRes = await nanoBridge.generate(
          jpeg: jpeg,
          summary: summaryInput,
        );
        if (_isStale(myId)) return;

        final inCloud = nanoRes.inferenceSource == NanoInferenceSource.inCloud;
        if (inCloud) {
          // WHY: §2.4 — re-check Nano status if AICore evicted model mid-session.
          unawaited(ref.read(nanoStatusProvider.notifier).refresh());
        }

        final result = GuidanceResult(
          text: nanoRes.text,
          tier: Tier1Nano(inCloudFallback: inCloud),
          stage0Ms: summary.processingMs,
          inferenceMs: nanoRes.latencyMs,
          hasVeryCloseObstacle: summary.hasVeryCloseObstacle,
        );
        telemetry.updateFromResult(result);
        await _deliverLocalVoice(result, myId);
        return;
      } on NaviFailure catch (e, st) {
        log(
          'Tier 1 Nano failed; failing over',
          name: 'navisense.orchestrator',
          error: e,
          stackTrace: st,
        );
      }
      if (_isStale(myId)) return;
    }

    // 2. Try Tier 2 (Cloud Server Prompt Templates + Cloud TTS) when online.
    final offline = await ref.read(connectivityProbeProvider).isOffline();
    if (_isStale(myId)) return;

    if (!offline) {
      try {
        final cloudRes = await ref
            .read(cloudReasoningServiceProvider)
            .reason(jpeg: jpeg, summary: summary, textOnly: textOnly);
        if (_isStale(myId)) return;

        await _deliverCloudVoice(
          cloudRes: cloudRes,
          summary: summary,
          myId: myId,
        );
        return;
      } on NaviFailure catch (e, st) {
        log(
          'Tier 2 cloud reasoning failed; failing over to Tier 3',
          name: 'navisense.orchestrator',
          error: e,
          stackTrace: st,
        );
      }
      if (_isStale(myId)) return;
    }

    // 3. Tier 3: Deterministic Edge Fallback (never goes silent).
    final tier3Text = ref
        .read(deterministicSpatialFormatterProvider)
        .format(summary, textOnly: textOnly);
    final cachedFile =
        await ref.read(cloudTtsServiceProvider).lookupCached(tier3Text);
    if (_isStale(myId)) return;

    final tier3Result = GuidanceResult(
      text: tier3Text,
      tier: const Tier3Edge(),
      stage0Ms: summary.processingMs,
      inferenceMs: 0,
      cacheHit: cachedFile != null,
      hasVeryCloseObstacle: summary.hasVeryCloseObstacle,
    );
    telemetry.updateFromResult(tier3Result);

    if (cachedFile != null) {
      state = AsyncData<GuidanceResult?>(tier3Result);
      try {
        await voicePlayer.playFile(cachedFile);
        return;
      } on NaviFailure catch (e, st) {
        log(
          'Tier 3 cached WAV playback failed; falling back to local TTS',
          name: 'navisense.orchestrator',
          error: e,
          stackTrace: st,
        );
      }
      if (_isStale(myId)) return;
    }

    await _deliverLocalVoice(tier3Result, myId);
  }

  Future<void> _deliverCloudVoice({
    required CloudReasoningResult cloudRes,
    required SpatialSceneSummary summary,
    required int myId,
  }) async {
    final telemetry = ref.read(telemetryProvider.notifier);
    final voicePlayer = ref.read(voicePlayerProvider);

    try {
      final ttsRes =
          await ref.read(cloudTtsServiceProvider).synthesize(cloudRes.text);
      if (_isStale(myId)) return;

      final result = GuidanceResult(
        text: cloudRes.text,
        tier: const Tier2Cloud(localVoice: false),
        stage0Ms: summary.processingMs,
        inferenceMs: cloudRes.latencyMs,
        templateId: cloudRes.templateId,
        cacheHit: ttsRes.cacheHit,
        hasVeryCloseObstacle: summary.hasVeryCloseObstacle,
      );
      telemetry.updateFromResult(result);
      state = AsyncData<GuidanceResult?>(result);

      await voicePlayer.playFile(ttsRes.file);
      return;
    } on NaviFailure catch (e, st) {
      log(
        'Cloud TTS/WAV playback failed; speaking cloud text via local voice',
        name: 'navisense.orchestrator',
        error: e,
        stackTrace: st,
      );
    }
    if (_isStale(myId)) return;

    final localVoiceResult = GuidanceResult(
      text: cloudRes.text,
      tier: const Tier2Cloud(localVoice: true),
      stage0Ms: summary.processingMs,
      inferenceMs: cloudRes.latencyMs,
      templateId: cloudRes.templateId,
      hasVeryCloseObstacle: summary.hasVeryCloseObstacle,
    );
    telemetry.updateFromResult(localVoiceResult);
    await _deliverLocalVoice(localVoiceResult, myId);
  }

  Future<void> _speakTier3OrReplay(GuidanceResult result, int myId) async {
    final cachedFile =
        await ref.read(cloudTtsServiceProvider).lookupCached(result.text);
    if (_isStale(myId)) return;

    if (cachedFile != null) {
      try {
        await ref.read(voicePlayerProvider).playFile(cachedFile);
        return;
      } on NaviFailure {
        // Fall through to local TTS.
      }
      if (_isStale(myId)) return;
    }

    await _deliverLocalVoice(result, myId);
  }

  Future<void> _deliverLocalVoice(
    GuidanceResult result,
    int myId, {
    StackTrace? errorStack,
  }) async {
    if (_isStale(myId)) return;
    state = AsyncData<GuidanceResult?>(result);
    try {
      await ref.read(voicePlayerProvider).speakLocal(result.text);
    } on NaviFailure catch (e, st) {
      if (_isStale(myId)) return;
      log(
        'All voice playback paths failed; falling back to TalkBack announce',
        name: 'navisense.orchestrator',
        error: e,
        stackTrace: st,
      );
      ref.read(semanticsAnnouncerProvider)(result.text);
      state = AsyncError<GuidanceResult?>(
        GuidanceVoiceFailedException(result),
        errorStack ?? st,
      );
    }
  }

  Future<void> _speakOrAnnounce(String message) async {
    try {
      await ref.read(voicePlayerProvider).speakLocal(message);
    } on NaviFailure {
      ref.read(semanticsAnnouncerProvider)(message);
    }
  }

  bool _isStale(int myId) => !ref.mounted || myId != _requestId;
}
