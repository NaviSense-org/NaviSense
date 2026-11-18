import 'package:flutter/foundation.dart';

/// Relative horizontal direction of a detected entity in the camera frame.
enum Direction { left, center, right }

/// Estimated proximity bucket derived from normalized bounding-box area.
enum Distance { veryClose, ahead, far }

/// Safety classification for a detected entity.
enum EntityKind { obstacle, object }

/// Immutable spatial entity produced by Stage 0 ML Kit perception.
@immutable
final class SpatialEntity {
  /// Creates a [SpatialEntity].
  const SpatialEntity({
    required this.kind,
    required this.label,
    required this.direction,
    required this.distance,
    required this.confidence,
  });

  /// Whether this entity is an immediate [EntityKind.obstacle] or [EntityKind.object].
  final EntityKind kind;

  /// Human-readable label after Stage 0 label fusion (`"object"` if unlabeled).
  final String label;

  /// Horizontal region (`LEFT`, `CENTER`, or `RIGHT`).
  final Direction direction;

  /// Proximity bucket (`VERY CLOSE`, `AHEAD`, or `FAR`).
  final Distance distance;

  /// Classification confidence in `[0.0, 1.0]`.
  final double confidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpatialEntity &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          label == other.label &&
          direction == other.direction &&
          distance == other.distance &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(kind, label, direction, distance, confidence);
}

/// Deterministic Stage 0 scene snapshot consumed by all three AI tiers.
@immutable
final class SpatialSceneSummary {
  /// Creates a [SpatialSceneSummary].
  const SpatialSceneSummary({
    required this.entities,
    required this.texts,
    required this.capturedAt,
    required this.processingMs,
  });

  /// Empty scene summary fallback when perception fails or detects nothing.
  factory SpatialSceneSummary.empty(
    DateTime capturedAt, {
    int processingMs = 0,
  }) =>
      SpatialSceneSummary(
        entities: const <SpatialEntity>[],
        texts: const <String>[],
        capturedAt: capturedAt,
        processingMs: processingMs,
      );

  /// Detected entities sorted obstacles-first, then distance, then confidence.
  final List<SpatialEntity> entities;

  /// Top OCR text snippets (filtered, whitespace-collapsed, <= 40 chars).
  final List<String> texts;

  /// Timestamp when the source frame was captured.
  final DateTime capturedAt;

  /// Stage 0 sequential execution duration in milliseconds.
  final int processingMs;

  /// Maximum age before a cached stream summary is considered stale.
  static const Duration staleThreshold = Duration(seconds: 2);

  /// Whether any detected entity is a `VERY CLOSE` obstacle.
  bool get hasVeryCloseObstacle => entities.any(
        (SpatialEntity e) =>
            e.kind == EntityKind.obstacle && e.distance == Distance.veryClose,
      );

  /// Returns `true` when this summary is older than 2 seconds relative to [now].
  bool isStaleAt(DateTime now) => now.difference(capturedAt) > staleThreshold;

  /// Canonical deterministic prompt/cache serialization per `2-architecture.md` §2.3.
  String toPromptString() => <String>[
        ...entities.map(
          (SpatialEntity e) =>
              '[${e.kind == EntityKind.obstacle ? 'Obstacle' : 'Object'}: '
              '${e.label}, ${e.direction.name.toUpperCase()}, '
              '${switch (e.distance) {
            Distance.veryClose => 'VERY CLOSE',
            Distance.ahead => 'AHEAD',
            Distance.far => 'FAR',
          }} '
              '(${(e.confidence * 100).round()}%)]',
        ),
        ...texts.map((String t) => '[Text: "$t"]'),
      ].join(', ');
}
