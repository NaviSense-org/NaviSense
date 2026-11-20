import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/navi_log.dart';
import 'package:navisense/features/voice/wav_cache.dart';
import 'package:navisense/features/voice/wav_codec.dart';

/// Output of [CloudTtsService.synthesize].
final class CloudTtsResult {
  /// Creates a [CloudTtsResult].
  const CloudTtsResult({required this.file, required this.cacheHit});

  /// Cached `.wav` file ready for streaming playback via `DeviceFileSource`.
  final File file;

  /// Whether [file] was already present in [WavCache].
  final bool cacheHit;
}

/// Raw inline audio part returned by [CloudTtsClient.synthesizePcm].
final class RawTtsAudio {
  /// Creates a [RawTtsAudio].
  const RawTtsAudio({required this.bytes, required this.mimeType});

  /// Linear PCM payload bytes.
  final Uint8List bytes;

  /// Mime type reported by Gemini TTS (for example `'audio/L16;rate=24000'`).
  final String mimeType;
}

/// Abstracts `gemini-3.1-flash-tts-preview` audio generation for unit testing.
abstract interface class CloudTtsClient {
  /// Synthesizes spoken audio for [text] using [voiceName] on [model].
  Future<RawTtsAudio> synthesizePcm({
    required String text,
    required String voiceName,
    required String model,
  });
}

/// Production [CloudTtsClient] backed by Firebase AI Logic.
final class FirebaseCloudTtsClient implements CloudTtsClient {
  /// Creates a [FirebaseCloudTtsClient].
  FirebaseCloudTtsClient({FirebaseAI? firebaseAi}) : _firebaseAi = firebaseAi;

  final FirebaseAI? _firebaseAi;

  @override
  Future<RawTtsAudio> synthesizePcm({
    required String text,
    required String voiceName,
    required String model,
  }) async {
    final ai = _firebaseAi ?? FirebaseAI.googleAI();
    final ttsModel = ai.generativeModel(
      model: model,
      generationConfig: GenerationConfig(
        responseModalities: <ResponseModalities>[ResponseModalities.audio],
        speechConfig: SpeechConfig(voiceName: voiceName),
      ),
    );
    final response = await ttsModel.generateContent(<Content>[
      Content.text('Say calmly and clearly: $text'),
    ]);
    final parts = response.inlineDataParts;
    if (parts.isEmpty) {
      throw const VoiceFailure('Cloud TTS returned empty inlineDataParts');
    }
    final first = parts.first;
    return RawTtsAudio(bytes: first.bytes, mimeType: first.mimeType);
  }
}

/// Provides [CloudTtsClient].
final cloudTtsClientProvider = Provider<CloudTtsClient>(
  (ref) => FirebaseCloudTtsClient(),
);

/// Provides [CloudTtsService].
final cloudTtsServiceProvider = Provider<CloudTtsService>((ref) {
  final rc = ref.watch(remoteConfigServiceProvider);
  return CloudTtsService(
    cache: ref.watch(wavCacheProvider),
    client: ref.watch(cloudTtsClientProvider),
    voiceNameReader: () => rc.ttsVoiceName,
    timeoutReader: () => rc.cloudTimeout,
    enabledReader: () => rc.enableCloudTts,
  );
});

/// Synthesizes high-fidelity speech via `gemini-3.1-flash-tts-preview` and
/// persists WAV files into [WavCache].
final class CloudTtsService {
  /// Creates a [CloudTtsService].
  CloudTtsService({
    required WavCache cache,
    required CloudTtsClient client,
    String Function()? voiceNameReader,
    Duration Function()? timeoutReader,
    bool Function()? enabledReader,
  })  : _cache = cache,
        _client = client,
        _voiceNameReader = voiceNameReader ?? (() => defaultVoiceName),
        _timeoutReader = timeoutReader ??
            (() => const Duration(
                  milliseconds: RemoteConfigService.defaultCloudTimeoutMs,
                )),
        _enabledReader = enabledReader ?? (() => true);

  /// Cloud TTS Gemini model ID (`2-architecture.md` §2.5).
  static const String ttsModel = 'gemini-3.1-flash-tts-preview';

  /// Default voice name (`2-architecture.md` §2.5).
  static const String defaultVoiceName = 'Kore';

  final WavCache _cache;
  final CloudTtsClient _client;
  final String Function() _voiceNameReader;
  final Duration Function() _timeoutReader;
  final bool Function() _enabledReader;

  /// Looks up cached WAV for [text] without hitting the network.
  Future<File?> lookupCached(String text) {
    final voiceName = _voiceNameReader();
    final key = WavCache.cacheKey(text, voiceName: voiceName, model: ttsModel);
    return _cache.lookup(key);
  }

  /// Returns a cached `.wav` file for [text], or synthesizes one via Cloud TTS
  /// within the configured `cloud_timeout_ms` budget and stores it atomically in [WavCache].
  ///
  /// Throws [VoiceFailure] / [TimeoutFailure] / [NetworkFailure] / [FirebaseAiFailure]
  /// so `AiOrchestrator` fails over cleanly to `LocalTtsService`.
  Future<CloudTtsResult> synthesize(String text) async {
    final voiceName = _voiceNameReader();
    final key = WavCache.cacheKey(text, voiceName: voiceName, model: ttsModel);

    final cached = await _cache.lookup(key);
    if (cached != null) {
      log('cache=hit key=$key', name: 'navisense.voice');
      return CloudTtsResult(file: cached, cacheHit: true);
    }

    if (!_enabledReader()) {
      throw const VoiceFailure('Cloud TTS disabled by Remote Config');
    }

    final timeout = _timeoutReader();
    try {
      final raw = await _client
          .synthesizePcm(text: text, voiceName: voiceName, model: ttsModel)
          .timeout(timeout);

      log(
        'cache=miss mimeType=${raw.mimeType} bytes=${raw.bytes.lengthInBytes}',
        name: 'navisense.voice',
      );

      if (raw.bytes.isEmpty) {
        throw const VoiceFailure('Cloud TTS returned 0 audio bytes');
      }

      final sampleRate = _parsePcmSampleRate(raw.mimeType);
      final wavBytes = pcmToWav(raw.bytes, sampleRate: sampleRate);
      final stored = await _cache.store(key, wavBytes);
      return CloudTtsResult(file: stored, cacheHit: false);
    } on TimeoutException {
      throw TimeoutFailure('cloud TTS > ${timeout.inMilliseconds}ms');
    } on SocketException catch (e) {
      throw NetworkFailure(e.message);
    } on HttpException catch (e) {
      throw NetworkFailure(e.message);
    } on FirebaseException catch (e) {
      throw FirebaseAiFailure(
        e.message ?? 'Firebase error during Cloud TTS',
        code: e.code,
      );
    } on FirebaseAIException catch (e) {
      throw FirebaseAiFailure(e.message);
    } catch (e) {
      if (e is NaviFailure) rethrow;
      throw VoiceFailure('Cloud TTS synthesis failed: $e');
    }
  }

  static int _parsePcmSampleRate(String mimeType) {
    final lower = mimeType.toLowerCase();
    final isCompatible =
        lower.startsWith('audio/l16') || lower.startsWith('audio/pcm');
    if (!isCompatible) {
      throw VoiceFailure('Unsupported Cloud TTS mimeType: $mimeType');
    }
    final match = RegExp(r'rate=(\d+)').firstMatch(lower);
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      if (parsed != null && parsed >= 8000 && parsed <= 96000) {
        return parsed;
      }
    }
    return 24000;
  }
}
