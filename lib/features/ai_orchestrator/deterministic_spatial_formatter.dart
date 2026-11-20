import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';

/// Provides [DeterministicSpatialFormatter].
final deterministicSpatialFormatterProvider =
    Provider<DeterministicSpatialFormatter>(
  (ref) => const DeterministicSpatialFormatter(),
);

/// Pure, deterministic Tier 3 scene-to-speech formatter (`2-architecture.md` §2.6).
///
/// Guarantees a spoken response within 4 sentences even in Airplane Mode on
/// low-RAM Android Go hardware.
final class DeterministicSpatialFormatter {
  /// Creates a [DeterministicSpatialFormatter].
  const DeterministicSpatialFormatter();

  /// Spoken when offline Stage 0 detects nothing.
  static const String emptySceneMessage =
      'Offline mode: I did not recognize any objects, but I cannot confirm '
      'the path is clear. Move carefully.';

  /// Formats [summary] according to §2.6 rules.
  ///
  /// When [textOnly] is `true`, emits up to 2 `"Sign reads <TEXT>."` sentences
  /// or `"No text found."`.
  String format(SpatialSceneSummary summary, {bool textOnly = false}) {
    if (textOnly) {
      if (summary.texts.isEmpty) return 'No text found.';
      return summary.texts
          .take(2)
          .map((String text) => 'Sign reads $text.')
          .join(' ');
    }

    final sentences = <String>[];
    final remaining = <SpatialEntity>[];

    // Rule 1: Obstacles with VERY_CLOSE first.
    for (final entity in summary.entities) {
      if (entity.kind == EntityKind.obstacle &&
          entity.distance == Distance.veryClose) {
        if (sentences.length < 4) {
          final label = _capitalize(entity.label);
          final dirPhrase = switch (entity.direction) {
            Direction.center => 'ahead in center',
            Direction.left => 'on your left',
            Direction.right => 'on your right',
          };
          sentences.add('Caution: $label very close $dirPhrase.');
        }
      } else {
        remaining.add(entity);
      }
    }

    // Rule 2: Remaining entities (max 2 total besides #1), staying <= 4 total.
    var remainingAdded = 0;
    for (final entity in remaining) {
      if (remainingAdded >= 2 || sentences.length >= 4) break;
      final label = _capitalize(entity.label);
      final sentence = switch (entity.distance) {
        Distance.veryClose => switch (entity.direction) {
            Direction.center => '$label very close ahead in center.',
            Direction.left => '$label very close on your left.',
            Direction.right => '$label very close on your right.',
          },
        Distance.ahead => switch (entity.direction) {
            Direction.center => '$label ahead.',
            Direction.left => '$label on your left.',
            Direction.right => '$label on your right.',
          },
        Distance.far => switch (entity.direction) {
            Direction.center => '$label further ahead.',
            Direction.left => '$label further to the left.',
            Direction.right => '$label further to the right.',
          },
      };
      sentences.add(sentence);
      remainingAdded++;
    }

    // Rule 3: Texts (max 2), staying <= 4 total.
    var textsAdded = 0;
    for (final text in summary.texts) {
      if (textsAdded >= 2 || sentences.length >= 4) break;
      sentences.add('Sign reads $text.');
      textsAdded++;
    }

    // Rule 4: Empty summary.
    if (sentences.isEmpty) {
      // WHY: ML Kit finding nothing is not evidence the path is clear (it
      // misses most real obstacles); never tell a blind user it is safe.
      return emptySceneMessage;
    }

    return sentences.join(' ');
  }

  static String _capitalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Object';
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }
}
