import 'dart:ui';

import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';

/// Computes horizontal [Direction] from a bounding box's X-center ratio.
///
/// Thresholds per `2-architecture.md` §2.3:
/// `< 0.33` -> [Direction.left], `> 0.67` -> [Direction.right], else [Direction.center].
Direction directionFor(Rect box, Size frame) {
  if (frame.width <= 0) return Direction.center;
  final xCenterRatio = (box.left + box.width / 2) / frame.width;
  if (xCenterRatio < 0.33) return Direction.left;
  if (xCenterRatio > 0.67) return Direction.right;
  return Direction.center;
}

/// Computes [Distance] bucket from normalized bounding-box area ratio.
///
/// Thresholds per `2-architecture.md` §2.3:
/// `>= 0.25` -> [Distance.veryClose], `>= 0.06` -> [Distance.ahead], else [Distance.far].
Distance distanceFor(Rect box, Size frame) {
  final frameArea = frame.width * frame.height;
  if (frameArea <= 0) return Distance.far;
  final boxArea = box.width.clamp(0.0, double.infinity) *
      box.height.clamp(0.0, double.infinity);
  final areaRatio = boxArea / frameArea;
  if (areaRatio >= 0.25) return Distance.veryClose;
  if (areaRatio >= 0.06) return Distance.ahead;
  return Distance.far;
}

/// Classifies whether an entity is an immediate [EntityKind.obstacle].
bool isObstacle(Direction direction, Distance distance) =>
    distance == Distance.veryClose ||
    (direction == Direction.center && distance == Distance.ahead);
