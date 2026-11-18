import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/mlkit_perception/mlkit_perception_service.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';

/// Provides the single app-lifetime [MlKitPerceptionService] and closes its
/// three ML Kit detectors cleanly when disposed.
final mlKitPerceptionServiceProvider = Provider<MlKitPerceptionService>((ref) {
  final service = MlKitPerceptionService(clock: ref.watch(clockProvider));
  ref.onDispose(() => unawaited(service.close()));
  return service;
});

/// Holds the latest Stage 0 [SpatialSceneSummary] (never any `CameraImage` or
/// `InputImage` buffer) plus a staleness helper (`> 2s`).
final perceptionProvider =
    NotifierProvider<PerceptionNotifier, SpatialSceneSummary?>(
  PerceptionNotifier.new,
);

/// Manages the latest in-memory [SpatialSceneSummary].
final class PerceptionNotifier extends Notifier<SpatialSceneSummary?> {
  @override
  SpatialSceneSummary? build() => null;

  /// Updates the latest summary from Stage 0 perception.
  void update(SpatialSceneSummary summary) {
    state = summary;
  }

  /// Clears the cached summary (for example when camera stops).
  void clear() {
    state = null;
  }

  /// Whether there is no summary or the latest summary is older than 2 s.
  bool get isStale {
    final current = state;
    if (current == null) return true;
    return current.isStaleAt(ref.read(clockProvider).now());
  }
}
