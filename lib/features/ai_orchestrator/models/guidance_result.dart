import 'package:flutter/foundation.dart';

/// Sealed tier classification describing where guidance was reasoned and voiced.
sealed class GuidanceTier {
  /// Base constructor for [GuidanceTier].
  const GuidanceTier();
}

/// Tier 1: Gemini Nano 4 via `OnDeviceExtension` (`PREFER_ON_DEVICE`).
@immutable
final class Tier1Nano extends GuidanceTier {
  /// Creates a [Tier1Nano] tier descriptor.
  ///
  /// [inCloudFallback] is `true` when AICore evicted Nano mid-session and
  /// `firebase-ai` answered via `InferenceSource.IN_CLOUD`.
  const Tier1Nano({this.inCloudFallback = false});

  /// Whether the hybrid bridge reported `IN_CLOUD` despite Nano status check.
  final bool inCloudFallback;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tier1Nano &&
          runtimeType == other.runtimeType &&
          inCloudFallback == other.inCloudFallback;

  @override
  int get hashCode => inCloudFallback.hashCode;
}

/// Tier 2: Cloud Server Prompt Template reasoning + Cloud TTS (or local fallback).
@immutable
final class Tier2Cloud extends GuidanceTier {
  /// Creates a [Tier2Cloud] tier descriptor.
  const Tier2Cloud({this.localVoice = false});

  /// `true` when cloud reasoning succeeded but Cloud TTS failed/disabled and
  /// `LocalTtsService` spoke the cloud text instead.
  final bool localVoice;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tier2Cloud &&
          runtimeType == other.runtimeType &&
          localVoice == other.localVoice;

  @override
  int get hashCode => localVoice.hashCode;
}

/// Tier 3: Deterministic ML Kit `SpatialSceneSummary` edge fallback.
@immutable
final class Tier3Edge extends GuidanceTier {
  /// Creates a [Tier3Edge] tier descriptor.
  const Tier3Edge();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tier3Edge && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Output of Tier 2 cloud Server Prompt Template reasoning.
@immutable
final class CloudReasoningResult {
  /// Creates a [CloudReasoningResult].
  const CloudReasoningResult({
    required this.text,
    required this.templateId,
    required this.latencyMs,
  });

  /// Spoken guidance text returned by the server prompt template.
  final String text;

  /// Remote Config-selected template identifier used for this call.
  final String templateId;

  /// Measured cloud reasoning latency in milliseconds.
  final int latencyMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudReasoningResult &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          templateId == other.templateId &&
          latencyMs == other.latencyMs;

  @override
  int get hashCode => Object.hash(text, templateId, latencyMs);
}

/// End-to-end guidance response emitted by `AiOrchestrator`.
@immutable
final class GuidanceResult {
  /// Creates a [GuidanceResult].
  const GuidanceResult({
    required this.text,
    required this.tier,
    required this.stage0Ms,
    required this.inferenceMs,
    this.templateId,
    this.cacheHit = false,
    this.hasVeryCloseObstacle = false,
  });

  /// Final spoken guidance string shown in the caption and spoken aloud.
  final String text;

  /// Tier that produced this response.
  final GuidanceTier tier;

  /// Stage 0 ML Kit perception latency in milliseconds.
  final int stage0Ms;

  /// Reasoning inference latency in milliseconds (`0` for Tier 3).
  final int inferenceMs;

  /// Active Remote Config Server Prompt Template ID (for Tier 2).
  final String? templateId;

  /// Whether WAV audio was served from the SHA-256 disk cache.
  final bool cacheHit;

  /// Whether a `VERY_CLOSE` obstacle triggered an urgency haptic pulse.
  final bool hasVeryCloseObstacle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuidanceResult &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          tier == other.tier &&
          stage0Ms == other.stage0Ms &&
          inferenceMs == other.inferenceMs &&
          templateId == other.templateId &&
          cacheHit == other.cacheHit &&
          hasVeryCloseObstacle == other.hasVeryCloseObstacle;

  @override
  int get hashCode => Object.hash(
        text,
        tier,
        stage0Ms,
        inferenceMs,
        templateId,
        cacheHit,
        hasVeryCloseObstacle,
      );
}
