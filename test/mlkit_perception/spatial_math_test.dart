import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';
import 'package:navisense/features/mlkit_perception/spatial_math.dart';

void main() {
  const frame = Size(1000, 1000);

  group('directionFor boundary tests', () {
    Rect boxWithCenterX(double centerX) =>
        Rect.fromCenter(center: Offset(centerX, 500), width: 100, height: 100);

    test('xCenterRatio 0.329 -> LEFT', () {
      expect(directionFor(boxWithCenterX(329), frame), Direction.left);
    });

    test('xCenterRatio 0.33 -> CENTER', () {
      expect(directionFor(boxWithCenterX(330), frame), Direction.center);
    });

    test('xCenterRatio 0.67 -> CENTER', () {
      expect(directionFor(boxWithCenterX(670), frame), Direction.center);
    });

    test('xCenterRatio 0.671 -> RIGHT', () {
      expect(directionFor(boxWithCenterX(671), frame), Direction.right);
    });
  });

  group('distanceFor boundary tests', () {
    Rect boxWithAreaRatio(double ratio) =>
        Rect.fromLTWH(0, 0, 1000 * ratio, 1000);

    test('areaRatio 0.25 -> VERY_CLOSE', () {
      expect(distanceFor(boxWithAreaRatio(0.25), frame), Distance.veryClose);
    });

    test('areaRatio 0.2499 -> AHEAD', () {
      expect(distanceFor(boxWithAreaRatio(0.2499), frame), Distance.ahead);
    });

    test('areaRatio 0.06 -> AHEAD', () {
      expect(distanceFor(boxWithAreaRatio(0.06), frame), Distance.ahead);
    });

    test('areaRatio 0.0599 -> FAR', () {
      expect(distanceFor(boxWithAreaRatio(0.0599), frame), Distance.far);
    });
  });

  group('isObstacle classification', () {
    test('VERY_CLOSE is obstacle regardless of direction', () {
      expect(isObstacle(Direction.left, Distance.veryClose), isTrue);
      expect(isObstacle(Direction.center, Distance.veryClose), isTrue);
      expect(isObstacle(Direction.right, Distance.veryClose), isTrue);
    });

    test('CENTER + AHEAD is obstacle, side AHEAD and FAR are objects', () {
      expect(isObstacle(Direction.center, Distance.ahead), isTrue);
      expect(isObstacle(Direction.left, Distance.ahead), isFalse);
      expect(isObstacle(Direction.right, Distance.ahead), isFalse);
      expect(isObstacle(Direction.center, Distance.far), isFalse);
    });
  });
}
