/// Sealed domain failure hierarchy for NaviSense services.
///
/// Services map raw SDK/platform exceptions into [NaviFailure] subtypes at
/// their boundary so the orchestrator can route across tiers deterministically.
sealed class NaviFailure implements Exception {
  /// Creates a failure with a diagnostic [message].
  const NaviFailure(this.message);

  /// Human-readable diagnostic message describing what failed.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Connectivity or socket failure (for example `SocketException` or offline).
final class NetworkFailure extends NaviFailure {
  /// Creates a [NetworkFailure].
  const NetworkFailure(super.message);
}

/// Cross-boundary await exceeded its mandatory latency budget.
final class TimeoutFailure extends NaviFailure {
  /// Creates a [TimeoutFailure].
  const TimeoutFailure(super.message);
}

/// Failure returned by Firebase AI Logic or Firebase SDKs.
final class FirebaseAiFailure extends NaviFailure {
  /// Creates a [FirebaseAiFailure] with an optional Firebase error [code].
  const FirebaseAiFailure(super.message, {this.code});

  /// Firebase exception or status code, if provided.
  final String? code;

  @override
  String toString() =>
      code == null ? '$runtimeType: $message' : '$runtimeType($code): $message';
}

/// Failure emitted by the native Android Gemini Nano bridge (`PlatformException`).
final class NanoFailure extends NaviFailure {
  /// Creates a [NanoFailure] with a structured bridge [code].
  const NanoFailure(super.message, {required this.code});

  /// Bridge error code: `NANO_UNAVAILABLE`, `NANO_TIMEOUT`, or `NANO_FAILED`.
  final String code;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// Failure during Google ML Kit Stage 0 perception.
final class PerceptionFailure extends NaviFailure {
  /// Creates a [PerceptionFailure].
  const PerceptionFailure(super.message);
}

/// Failure during cloud TTS, WAV caching, or local TTS playback.
final class VoiceFailure extends NaviFailure {
  /// Creates a [VoiceFailure].
  const VoiceFailure(super.message);
}

/// Failure initializing or capturing from the Android camera.
final class CameraFailure extends NaviFailure {
  /// Creates a [CameraFailure].
  const CameraFailure(super.message);
}
