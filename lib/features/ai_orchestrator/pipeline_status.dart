import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/errors/navi_failure.dart';

/// Live, human-readable progress and problems for the current guidance request.
@immutable
final class PipelineStatus {
  /// Creates a [PipelineStatus].
  const PipelineStatus({this.stage, this.issues = const <String>[]});

  /// What the pipeline is doing right now (for example "Taking photo…"), or
  /// `null` when idle.
  final String? stage;

  /// Problems hit during the latest request, in order (for example a cloud
  /// error before falling back to offline detection). Empty when all went well.
  final List<String> issues;

  /// Whether the latest request ran into any problem.
  bool get hasIssues => issues.isNotEmpty;
}

/// Provides the [PipelineStatus] of the most recent guidance request.
final pipelineStatusProvider =
    NotifierProvider<PipelineStatusNotifier, PipelineStatus>(
  PipelineStatusNotifier.new,
);

/// Updated by the orchestrator as a request moves through its tiers.
final class PipelineStatusNotifier extends Notifier<PipelineStatus> {
  @override
  PipelineStatus build() => const PipelineStatus();

  /// Starts a fresh request: clears old issues and shows [stage].
  void begin(String stage) => state = PipelineStatus(stage: stage);

  /// Updates the in-progress [stage] label.
  void stage(String stage) =>
      state = PipelineStatus(stage: stage, issues: state.issues);

  /// Records a problem; [area] is a short label such as "Camera".
  void issue(String area, Object error) {
    state = PipelineStatus(
      stage: state.stage,
      issues: <String>[...state.issues, '$area: ${describeError(error)}'],
    );
  }

  /// Marks the request finished, keeping any recorded issues visible.
  void finish() {
    if (state.stage == null) return;
    state = PipelineStatus(issues: state.issues);
  }

  /// Clears stage and issues (for example when a request is cancelled).
  void clear() {
    if (state.stage == null && state.issues.isEmpty) return;
    state = const PipelineStatus();
  }

  /// Turns [error] into a short message suitable for on-screen diagnostics.
  static String describeError(Object error) {
    final text = switch (error) {
      FirebaseAiFailure(:final code?, :final message) => '$message ($code)',
      NanoFailure(:final code, :final message) => '$message ($code)',
      NaviFailure(:final message) => message,
      _ => error.toString(),
    };
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length > 160 ? '${oneLine.substring(0, 157)}…' : oneLine;
  }
}
