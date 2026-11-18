import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable clock abstraction enabling deterministic fake-clock tests.
abstract interface class Clock {
  /// Returns the current epoch timestamp in milliseconds.
  int nowMs();

  /// Returns the current wall-clock [DateTime].
  DateTime now();
}

/// System clock backed by [DateTime.now].
final class SystemClock implements Clock {
  /// Creates a [SystemClock].
  const SystemClock();

  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  DateTime now() => DateTime.now();
}

/// Provides the app-wide [Clock] instance.
final clockProvider = Provider<Clock>((ref) => const SystemClock());
