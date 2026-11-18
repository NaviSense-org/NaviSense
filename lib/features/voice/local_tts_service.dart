import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:navisense/core/errors/navi_failure.dart';

/// Typed seam over `FlutterTts` enabling unit tests without platform channels.
abstract interface class TtsEngine {
  /// Configures whether [speak] awaits utterance completion.
  Future<void> awaitSpeakCompletion(bool awaitCompletion);

  /// Sets speech rate in `[0.0, 1.0]`.
  Future<void> setSpeechRate(double rate);

  /// Sets vocal pitch (default `1.0`).
  Future<void> setPitch(double pitch);

  /// Sets audio volume in `[0.0, 1.0]`.
  Future<void> setVolume(double volume);

  /// Selects BCP-47 language tag (for example `'en-US'`).
  Future<void> setLanguage(String language);

  /// Lists installed Android TTS engine package identifiers.
  Future<List<String>> getEngines();

  /// Checks whether offline voice data for [language] is installed.
  Future<bool> isLanguageInstalled(String language);

  /// Speaks [text]; returns `true` when accepted by the engine.
  Future<bool> speak(String text);

  /// Stops any active utterance.
  Future<void> stop();
}

/// Production [TtsEngine] backed by a single [FlutterTts] instance.
final class FlutterTtsEngine implements TtsEngine {
  /// Creates a [FlutterTtsEngine].
  FlutterTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> awaitSpeakCompletion(bool awaitCompletion) async {
    await _tts.awaitSpeakCompletion(awaitCompletion);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _tts.setVolume(volume);
  }

  @override
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
  }

  @override
  Future<List<String>> getEngines() async {
    final Object? raw = await _tts.getEngines;
    if (raw is List<Object?>) {
      return raw.whereType<Object>().map((Object e) => '$e').toList();
    }
    return const <String>[];
  }

  @override
  Future<bool> isLanguageInstalled(String language) async {
    final Object? raw = await _tts.isLanguageInstalled(language);
    if (raw is bool) return raw;
    if (raw is int) return raw == 1;
    return false;
  }

  @override
  Future<bool> speak(String text) async {
    final Object? raw = await _tts.speak(text);
    if (raw is int) return raw == 1;
    if (raw is bool) return raw;
    return true;
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

/// Provides the single app-wide [LocalTtsService].
final localTtsServiceProvider = Provider<LocalTtsService>((ref) {
  final service = LocalTtsService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// Manages on-device `flutter_tts` initialization, rate updates, and playback.
final class LocalTtsService {
  /// Creates a [LocalTtsService] wrapping a single [TtsEngine].
  LocalTtsService({TtsEngine? engine, double initialRate = defaultRate})
      : _engine = engine ?? FlutterTtsEngine(),
        _rate = initialRate.clamp(minRate, maxRate);

  /// Default speech rate (`2-architecture.md` §2.7).
  static const double defaultRate = 0.45;

  /// Minimum user-configurable speech rate (`3-ui-context.md` §3.9).
  static const double minRate = 0.30;

  /// Maximum user-configurable speech rate (`3-ui-context.md` §3.9).
  static const double maxRate = 0.70;

  final TtsEngine _engine;
  double _rate;
  bool _initialized = false;
  bool _isAvailable = false;
  bool _isOfflineVoiceInstalled = false;

  /// Whether at least one TTS engine was detected on the device.
  bool get isAvailable => _isAvailable;

  /// Whether `'en-US'` offline voice data is installed on the device.
  bool get isOfflineVoiceInstalled => _isOfflineVoiceInstalled;

  /// Current configured speech rate in `[0.30, 0.70]`.
  double get rate => _rate;

  /// Initializes the underlying TTS engine once and detects installed voices.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      await _engine.awaitSpeakCompletion(true);
      await _engine.setSpeechRate(_rate);
      await _engine.setPitch(1.0);
      await _engine.setVolume(1.0);
      await _engine.setLanguage('en-US');

      final engines = await _engine.getEngines();
      _isAvailable = engines.isNotEmpty;
      _isOfflineVoiceInstalled =
          _isAvailable && await _engine.isLanguageInstalled('en-US');
      _initialized = true;
    } on PlatformException catch (e, st) {
      _initialized = true;
      _isAvailable = false;
      log(
        'Local TTS initialization failed',
        name: 'navisense.voice',
        error: e,
        stackTrace: st,
      );
    } on MissingPluginException {
      _initialized = true;
      _isAvailable = false;
    }
  }

  /// Speaks [text] through the local TTS engine.
  ///
  /// Throws [VoiceFailure] when no TTS engine is available or speech fails so
  /// the orchestrator can trigger the SOS TalkBack announcement fallback.
  Future<void> speak(String text) async {
    await ensureInitialized();
    if (!_isAvailable) {
      throw const VoiceFailure('No on-device TTS engine available');
    }
    try {
      final ok = await _engine.speak(text);
      if (!ok) {
        throw const VoiceFailure('Local TTS engine rejected utterance');
      }
    } on PlatformException catch (e) {
      throw VoiceFailure(e.message ?? 'Local TTS speak failed');
    }
  }

  /// Stops active local TTS playback immediately.
  Future<void> stop() async {
    try {
      await _engine.stop();
    } on PlatformException catch (e, st) {
      log(
        'Local TTS stop failed',
        name: 'navisense.voice',
        error: e,
        stackTrace: st,
      );
    } on MissingPluginException {
      // Ignore in widget tests without platform channels.
    }
  }

  /// Updates the speech rate (clamped to `[0.30, 0.70]`).
  Future<void> setRate(double rate) async {
    _rate = rate.clamp(minRate, maxRate);
    if (!_initialized) return;
    try {
      await _engine.setSpeechRate(_rate);
    } on PlatformException catch (e, st) {
      log(
        'Local TTS setRate failed',
        name: 'navisense.voice',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Releases playback when the provider scope disposes.
  Future<void> dispose() => stop();
}
