import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher, TextDirection;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/connectivity/connectivity_probe.dart';
import 'package:navisense/core/connectivity/network_status.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/core/utils/navi_log.dart';
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
  /// Captures a compressed JPEG snapshot whose longest edge is `<= maxEdge`.
  Future<Uint8List> captureSnapshot({int maxEdge = 768, int quality = 70});

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
  Future<Uint8List> captureSnapshot({
    int maxEdge = 768,
    int quality = 70,
  }) async {
    final controller = _ref.read(cameraControllerProvider).value;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraFailure('Camera is not ready yet');
    }
    return _ref.read(cameraServiceProvider).captureSnapshot(
          FlutterCameraStreamHandle(controller),
          maxEdge: maxEdge,
          quality: quality,
        );
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
  /// Spoken in Tier 3 when Stage 0 perception itself failed (never claims the
  /// path is clear when nothing was actually analyzed).
  static const String perceptionFailedMessage =
      'I could not analyze the scene. Please hold steady and tap again.';

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
    final startedMs = clock.nowMs();

    final gateway = ref.read(orchestratorPerceptionGatewayProvider);
    final Uint8List jpeg;
    try {
      // WHY: Upload size dominates on real mobile networks. Scene description
      // only needs a 512 px frame (~2.3x fewer pixels, ~30-40 KB); reading
      // text keeps 768 px so small signage stays legible.
      jpeg = textOnly
          ? await gateway.captureSnapshot(maxEdge: 768, quality: 75)
          : await gateway.captureSnapshot(maxEdge: 512, quality: 65);
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
    final captureMs = clock.nowMs() - startedMs;

    // WHY: Stage 0, the Nano status check, and the connectivity probe are
    // independent, so they start together instead of queueing (~1 s saved per
    // tap). Only Stage 0 is CPU/RAM-heavy, and MlKitPerceptionService
    // serializes its own passes, so this never runs two ML Kit jobs at once
    // on 3 GB devices.
    final summaryFuture = _resolveSummary(gateway, jpeg);
    final nanoStatusFuture = _currentNanoStatus();
    final offlineFuture = _probeOffline();

    // 1. Try Tier 1 (Gemini Nano 4 via OnDeviceExtension) when AVAILABLE.
    final nanoStatus = await nanoStatusFuture;
    if (_isStale(myId)) return;

    if (nanoStatus == NanoStatus.available) {
      final stage0 = await summaryFuture;
      if (_isStale(myId)) return;
      final summary = stage0.summary;
      try {
        final summaryInput = textOnly
            ? 'Read all visible text verbatim. ${summary.toPromptString()}'
            : summary.toPromptString();
        final nanoRes = await ref.read(nanoBridgeProvider).generate(
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
        _logTiming(
          inCloud ? 'tier1_cloud' : 'tier1_nano',
          startedMs: startedMs,
          captureMs: captureMs,
          inferenceMs: nanoRes.latencyMs,
        );
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

    // 2. Try Tier 2 (Cloud Gemini + Cloud TTS) when online.
    final offline = await offlineFuture;
    if (_isStale(myId)) return;

    if (!offline) {
      // WHY: Gemini sees the photo itself; Stage 0 is only a hint, so the
      // cloud call must not queue behind a slow ML Kit pass.
      final hint = await _cloudHint(summaryFuture);
      if (_isStale(myId)) return;
      // WHY: Never leave a blind user in silence on a slow link: if the
      // cloud hasn't answered soon, say so once (haptic heartbeat continues).
      final slowNotice = Timer(slowNoticeDelay, () {
        if (_isStale(myId)) return;
        unawaited(
          ref
              .read(voicePlayerProvider)
              .speakLocal(slowNoticeMessage)
              .catchError((Object _) {}),
        );
      });
      try {
        final cloudRes = await ref
            .read(cloudReasoningServiceProvider)
            .reason(jpeg: jpeg, summary: hint, textOnly: textOnly);
        slowNotice.cancel();
        if (_isStale(myId)) return;

        _logTiming(
          'tier2_cloud',
          startedMs: startedMs,
          captureMs: captureMs,
          inferenceMs: cloudRes.latencyMs,
        );
        await _deliverCloudVoice(
          cloudRes: cloudRes,
          summary: hint,
          myId: myId,
        );
        return;
      } on NaviFailure catch (e, st) {
        slowNotice.cancel();
        log(
          'Tier 2 cloud reasoning failed; failing over to Tier 3',
          name: 'navisense.orchestrator',
          error: e,
          stackTrace: st,
        );
      }
      if (_isStale(myId)) return;
    }

    final stage0 = await summaryFuture;
    if (_isStale(myId)) return;
    final summary = stage0.summary;
    final perceptionFailed = stage0.failed;
    _logTiming('tier3_edge', startedMs: startedMs, captureMs: captureMs);

    // 3. Tier 3: Deterministic Edge Fallback (never goes silent).
    // WHY: An empty summary caused by a perception *failure* must never be
    // spoken as "Path looks clear" to a blind user.
    final tier3Text = perceptionFailed
        ? perceptionFailedMessage
        : ref
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

  /// How long Tier 2 waits for Gemini TTS audio before speaking the cloud text
  /// with the local voice (synthesis keeps running to warm the WAV cache).
  static const Duration cloudVoiceWaitBudget = Duration(milliseconds: 1500);

  /// Delay before the "still working" notice on a slow cloud request.
  static const Duration slowNoticeDelay = Duration(milliseconds: 3500);

  /// Spoken once when the cloud is slow to answer.
  static const String slowNoticeMessage =
      'Still working. The connection is slow.';

  /// Reasoning latency above which the link is treated as slow and cloud TTS
  /// is skipped for uncached phrases.
  static const int slowNetworkThresholdMs = 3500;

  /// How long the cloud call waits for an in-flight Stage 0 pass to use as a
  /// hint before falling back to the latest stream summary.
  static const Duration cloudHintGrace = Duration(milliseconds: 150);

  Future<({SpatialSceneSummary summary, bool failed})> _resolveSummary(
    OrchestratorPerceptionGateway gateway,
    Uint8List jpeg,
  ) async {
    try {
      return (summary: await gateway.resolveFreshSummary(jpeg), failed: false);
    } catch (e, st) {
      // WHY: §4.7.3 — Perception failure is non-fatal; continue with empty summary.
      log(
        'Stage 0 perception failed; continuing with empty summary',
        name: 'navisense.orchestrator',
        error: e,
        stackTrace: st,
      );
      return (
        summary: SpatialSceneSummary.empty(ref.read(clockProvider).now()),
        failed: true,
      );
    }
  }

  Future<SpatialSceneSummary> _cloudHint(
    Future<({SpatialSceneSummary summary, bool failed})> summaryFuture,
  ) async {
    SpatialSceneSummary fallback() =>
        ref.read(perceptionProvider) ??
        SpatialSceneSummary.empty(ref.read(clockProvider).now());
    try {
      final stage0 = await summaryFuture.timeout(cloudHintGrace);
      return stage0.failed ? fallback() : stage0.summary;
    } on TimeoutException {
      return fallback();
    }
  }

  Future<NanoStatus> _currentNanoStatus() async {
    final cached = ref.read(nanoStatusProvider).value;
    if (cached != null) return cached;
    try {
      return await ref.read(nanoBridgeProvider).getStatus();
    } catch (_) {
      return NanoStatus.unavailable;
    }
  }

  Future<bool> _probeOffline() async {
    // WHY: The live connectivity stream already knows when the link is down;
    // skip the DNS probe and go straight to on-device guidance.
    if (ref.read(networkStatusProvider) == NetworkStatus.offline) return true;
    try {
      return await ref.read(connectivityProbeProvider).isOffline();
    } catch (_) {
      // Unknown connectivity: attempt the cloud; its own timeout bounds it.
      return false;
    }
  }

  void _logTiming(
    String tier, {
    required int startedMs,
    required int captureMs,
    int? inferenceMs,
  }) {
    final totalMs = ref.read(clockProvider).nowMs() - startedMs;
    log(
      'timing tier=$tier totalMs=$totalMs captureMs=$captureMs'
      '${inferenceMs == null ? '' : ' inferenceMs=$inferenceMs'}',
      name: 'navisense.orchestrator',
    );
  }

  Future<void> _deliverCloudVoice({
    required CloudReasoningResult cloudRes,
    required SpatialSceneSummary summary,
    required int myId,
  }) async {
    final telemetry = ref.read(telemetryProvider.notifier);
    final voicePlayer = ref.read(voicePlayerProvider);

    // WHY: On a slow link, a second round trip for Gemini TTS both delays
    // speech and competes for bandwidth with the user's next request. If the
    // reasoning call itself was slow, skip cloud voice entirely (unless the
    // phrase is already cached) and speak immediately.
    final ttsService = ref.read(cloudTtsServiceProvider);
    if (cloudRes.latencyMs > slowNetworkThresholdMs) {
      final cached = await ttsService.lookupCached(cloudRes.text);
      if (_isStale(myId)) return;
      if (cached == null) {
        log(
          'Slow network (reasoning ${cloudRes.latencyMs}ms); skipping cloud '
          'voice',
          name: 'navisense.orchestrator',
        );
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
        return;
      }
    }

    // WHY: Gemini TTS is a second full round trip (observed > 6 s on mobile
    // data). Wait only briefly; otherwise speak now with the local voice and
    // let synthesis finish in the background so a repeat plays cached audio.
    final ttsFuture = ttsService.synthesize(cloudRes.text);
    try {
      final ttsRes = await ttsFuture.timeout(cloudVoiceWaitBudget);
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
    } on TimeoutException {
      unawaited(
        ttsFuture.then(
          (_) => log('Cloud voice cached for repeat', name: 'navisense.voice'),
          onError: (Object e) => log(
            'Background cloud voice synthesis failed',
            name: 'navisense.voice',
            error: e,
          ),
        ),
      );
      log(
        'Cloud voice slower than ${cloudVoiceWaitBudget.inMilliseconds}ms; '
        'speaking cloud text via local voice now',
        name: 'navisense.orchestrator',
      );
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
