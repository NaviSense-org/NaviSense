import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/features/telemetry/telemetry_notifier.dart';

/// Color-coded Judge Telemetry Pill surfacing real-time hybrid routing
/// (`3-ui-context.md` §3.7).
///
/// Exempt from the 72dp rule while display-only (`announceInferenceTier == false`);
/// padded to >= 72dp height when Judge/announce mode makes it focusable.
final class TelemetryPill extends ConsumerWidget {
  /// Creates a [TelemetryPill].
  const TelemetryPill({
    super.key,
    required this.judgeMode,
    required this.announceInferenceTier,
  });

  /// Shows the secondary `infer ... • stage0 ...` line when `true`.
  final bool judgeMode;

  /// Allows TalkBack focus on the pill when `true`.
  final bool announceInferenceTier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(telemetryProvider);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final focusable = announceInferenceTier || judgeMode;
    final minHeight = focusable ? 72.0 : 40.0;

    return ExcludeSemantics(
      excluding: !focusable,
      child: Semantics(
        container: true,
        label: telemetry.semanticsLabel,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: AnimatedContainer(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: telemetry.backgroundColor,
                borderRadius: BorderRadius.circular(24),
                border: telemetry.borderColor != null
                    ? Border.all(color: telemetry.borderColor!, width: 2)
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 4,
                children: <Widget>[
                  _PillPrimaryRow(telemetry: telemetry),
                  if (judgeMode && telemetry.detailLine != null)
                    _PillDetailLine(
                      text: telemetry.detailLine!,
                      color: telemetry.foregroundColor,
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

final class _PillPrimaryRow extends StatelessWidget {
  const _PillPrimaryRow({required this.telemetry});

  final TelemetryState telemetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: <Widget>[
        Icon(telemetry.icon, color: telemetry.foregroundColor, size: 22),
        Flexible(
          child: Text(
            telemetry.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: telemetry.foregroundColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

final class _PillDetailLine extends StatelessWidget {
  const _PillDetailLine({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}
