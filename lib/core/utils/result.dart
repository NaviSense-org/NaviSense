/// Functional outcome wrapper returned by non-throwing domain operations.
sealed class Result<T> {
  /// Base constructor for [Result].
  const Result();

  /// Creates a successful result carrying [value].
  const factory Result.success(T value) = Success<T>;

  /// Creates a failure result carrying a human-readable [message].
  const factory Result.error(String message) = Failure<T>;

  /// Whether this result holds a success [value].
  bool get isSuccess => this is Success<T>;

  /// Returns the wrapped value when [isSuccess] is `true`.
  T get value => switch (this) {
        Success<T>(:final value) => value,
        Failure<T>(:final message) =>
          throw StateError('Called Result.value on Failure: $message'),
      };

  /// Returns the failure message when [isSuccess] is `false`.
  String get message => switch (this) {
        Success<T>() => '',
        Failure<T>(:final message) => message,
      };
}

/// Successful [Result] holding [value].
final class Success<T> extends Result<T> {
  /// Creates a [Success] outcome.
  const Success(this.value);

  @override
  final T value;
}

/// Failed [Result] holding a calm diagnostic [message].
final class Failure<T> extends Result<T> {
  /// Creates a [Failure] outcome.
  const Failure(this.message);

  @override
  final String message;
}
