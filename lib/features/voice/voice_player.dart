import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/features/voice/local_tts_service.dart';

/// Abstracts `AudioPlayer` for deterministic unit testing.
abstract interface class VoiceAudioBackend {
  /// Stream emitting whenever an active audio source finishes playing.
  Stream<void> get onPlayerComplete;

  /// Plays [source] in `PlayerMode.mediaPlayer`.
  Future<void> play(Source source);

  /// Stops active playback.
  Future<void> stop();

  /// Releases native audio player resources.
  Future<void> dispose();
}

/// Production [VoiceAudioBackend] using a single `AudioPlayer` instance.
final class AudioplayersBackend implements VoiceAudioBackend {
  /// Creates an [AudioplayersBackend].
  AudioplayersBackend({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Future<void> play(Source source) =>
      _player.play(source, mode: PlayerMode.mediaPlayer);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Provides the single app-wide [VoicePlayer] coordinating WAV and local TTS.
final voicePlayerProvider = Provider<VoicePlayer>((ref) {
  final player = VoicePlayer(localTts: ref.watch(localTtsServiceProvider));
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});

/// Plays WAV files (`DeviceFileSource`), WAV buffers (`BytesSource`), or local
/// TTS (`LocalTtsService`), guaranteeing only one voice output plays at a time.
final class VoicePlayer {
  /// Creates a [VoicePlayer].
  VoicePlayer({required LocalTtsService localTts, VoiceAudioBackend? backend})
      : _localTts = localTts,
        _backend = backend ?? AudioplayersBackend();

  final LocalTtsService _localTts;
  final VoiceAudioBackend _backend;

  Completer<void>? _activePlayback;
  StreamSubscription<void>? _completeSub;

  /// Plays a cached WAV [file] from disk via [DeviceFileSource] and waits
  /// until playback completes or [stop] interrupts it.
  Future<void> playFile(File file) =>
      _playSource(DeviceFileSource(file.path, mimeType: 'audio/wav'));

  /// Plays in-memory WAV [bytes] via [BytesSource] and waits until completion
  /// or [stop].
  Future<void> playBytes(Uint8List bytes) =>
      _playSource(BytesSource(bytes, mimeType: 'audio/wav'));

  /// Arbitrates with `AudioPlayer`, then speaks [text] via [LocalTtsService].
  Future<void> speakLocal(String text) async {
    await _stopAudioOnly();
    await _localTts.speak(text);
  }

  /// Stops whichever voice output (WAV player or local TTS) is active.
  Future<void> stop() async {
    await _stopAudioOnly();
    await _localTts.stop();
  }

  /// Releases both the underlying `AudioPlayer` and local TTS.
  Future<void> dispose() async {
    await stop();
    try {
      await _backend.dispose();
    } on MissingPluginException {
      // Ignore in tests without platform channels.
    } catch (e, st) {
      log(
        'AudioPlayer dispose failed',
        name: 'navisense.voice',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _playSource(Source source) async {
    await stop();
    final completer = Completer<void>();
    _activePlayback = completer;

    _completeSub = _backend.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await _backend.play(source);
      await completer.future;
    } on PlatformException catch (e) {
      throw VoiceFailure(e.message ?? 'Audio playback failed');
    } on MissingPluginException {
      throw const VoiceFailure('Audio playback plugin unavailable');
    } finally {
      await _completeSub?.cancel();
      _completeSub = null;
      if (identical(_activePlayback, completer)) {
        _activePlayback = null;
      }
    }
  }

  Future<void> _stopAudioOnly() async {
    final sub = _completeSub;
    _completeSub = null;
    await sub?.cancel();

    final pending = _activePlayback;
    _activePlayback = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }

    try {
      await _backend.stop();
    } on PlatformException catch (e, st) {
      log(
        'AudioPlayer stop failed',
        name: 'navisense.voice',
        error: e,
        stackTrace: st,
      );
    } on MissingPluginException {
      // Ignore in tests without platform channels.
    }
  }
}
