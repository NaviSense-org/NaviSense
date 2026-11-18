import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/features/ai_orchestrator/models/guidance_result.dart';

/// Visual & semantic state backing the Judge Telemetry Pill (`3-ui-context.md` §3.7).
@immutable
final class TelemetryState {
  /// Creates a [TelemetryState].
  const TelemetryState({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.semanticsLabel,
    this.borderColor,
    this.detailLine,
  });

  /// Initial idle state before the first query.
  factory TelemetryState.idle() => const TelemetryState(
        label: 'READY • Tap anywhere',
        backgroundColor: Colors.transparent,
        foregroundColor: NaviColors.cream,
        borderColor: NaviColors.goldAntique,
        icon: Icons.touch_app,
        semanticsLabel: 'Ready. Tap anywhere to describe your surroundings.',
      );

  /// Derives exact §3.7 pill state from a completed [GuidanceResult].
  factory TelemetryState.fromResult(GuidanceResult result) {
    final detail = _buildDetailLine(result);
    return switch (result.tier) {
      Tier1Nano(inCloudFallback: false) => TelemetryState(
          label: 'ON_DEVICE • Gemini Nano 4 • 0ms • \$0',
          backgroundColor: NaviColors.emerald,
          foregroundColor: NaviColors.navyDeep,
          icon: Icons.memory,
          semanticsLabel: 'Inference source: on device, Gemini Nano 4, '
              'zero network latency, zero cost',
          detailLine: detail,
        ),
      Tier1Nano(inCloudFallback: true) ||
      Tier2Cloud(localVoice: true) =>
        TelemetryState(
          label: 'IN_CLOUD • Gemini Flash • local voice',
          backgroundColor: NaviColors.royalBlue,
          foregroundColor: NaviColors.navyDeep,
          icon: Icons.cloud_off_outlined,
          semanticsLabel:
              'Inference source: in cloud, Gemini Flash, local voice',
          detailLine: detail,
        ),
      Tier2Cloud(localVoice: false) => TelemetryState(
          label: 'IN_CLOUD • Gemini Flash TTS',
          backgroundColor: NaviColors.royalBlue,
          foregroundColor: NaviColors.navyDeep,
          icon: Icons.cloud,
          semanticsLabel:
              'Inference source: in cloud, Gemini Flash text to speech',
          detailLine: detail,
        ),
      Tier3Edge() => TelemetryState(
          label: 'ON_DEVICE • ML Kit Edge Fallback • 0ms • \$0',
          backgroundColor: NaviColors.goldAntique,
          foregroundColor: NaviColors.navyDeep,
          icon: Icons.offline_bolt,
          semanticsLabel: 'Inference source: on device, ML Kit edge fallback, '
              'zero network latency, zero cost',
          detailLine: detail,
        ),
    };
  }

  /// Exact primary pill label (`3-ui-context.md` §3.7).
  final String label;

  /// Pill fill color.
  final Color backgroundColor;

  /// Pill text and icon color (AAA/AA verified against [backgroundColor]).
  final Color foregroundColor;

  /// Optional pill outline color (used in idle state).
  final Color? borderColor;

  /// Leading icon paired with [label] so color never carries meaning alone.
  final IconData icon;

  /// TalkBack announcement label when Judge mode makes the pill focusable.
  final String semanticsLabel;

  /// Secondary 12sp telemetry line shown when Settings -> Judge mode is ON.
  final String? detailLine;

  static String _buildDetailLine(GuidanceResult result) {
    final parts = <String>[
      'infer ${result.inferenceMs}ms',
      'stage0 ${result.stage0Ms}ms',
    ];
    final templateId = result.templateId;
    if (templateId != null && templateId.isNotEmpty) {
      final shortTag = switch (templateId) {
        'navisense_nav_prompt_v1' => 'template v1',
        'navisense_nav_prompt_v2' => 'template v2',
        _ => 'template $templateId',
      };
      parts.add(shortTag);
    }
    if (result.cacheHit) {
      parts.add('cache hit');
    }
    return parts.join(' • ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelemetryState &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          backgroundColor == other.backgroundColor &&
          foregroundColor == other.foregroundColor &&
          borderColor == other.borderColor &&
          icon == other.icon &&
          semanticsLabel == other.semanticsLabel &&
          detailLine == other.detailLine;

  @override
  int get hashCode => Object.hash(
        label,
        backgroundColor,
        foregroundColor,
        borderColor,
        icon,
        semanticsLabel,
        detailLine,
      );
}

/// Holds the current [TelemetryState] displayed by `TelemetryPill`.
final telemetryProvider = NotifierProvider<TelemetryNotifier, TelemetryState>(
  TelemetryNotifier.new,
);

/// Updates [TelemetryState] whenever `AiOrchestrator` settles on a tier.
final class TelemetryNotifier extends Notifier<TelemetryState> {
  @override
  TelemetryState build() => TelemetryState.idle();

  /// Updates the pill to reflect [result].
  void updateFromResult(GuidanceResult result) {
    state = TelemetryState.fromResult(result);
  }

  /// Resets the pill back to the idle state.
  void reset() {
    state = TelemetryState.idle();
  }
}
