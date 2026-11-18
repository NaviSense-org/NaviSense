import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/voice/wav_cache.dart';
import 'package:navisense/features/voice/wav_codec.dart';

final class _FakeClock implements Clock {
  int _nowMs = 1700000000000;

  void advance(int deltaMs) => _nowMs += deltaMs;

  @override
  int nowMs() => _nowMs;

  @override
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(_nowMs);
}

void main() {
  late Directory tempDir;
  late _FakeClock clock;
  late WavCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('navisense_wav_cache_');
    clock = _FakeClock();
    cache = WavCache(
      clock: clock,
      directoryProvider: () async => tempDir,
      maxBytes: 20 * 1024 * 1024,
      maxFiles: 200,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('WavCache', () {
    test('produces identical key for normalized whitespace/case/punctuation',
        () {
      final k1 = WavCache.cacheKey(
        'Caution: Chair very close ahead.',
        voiceName: 'Kore',
        model: 'gemini-3.1-flash-tts-preview',
      );
      final k2 = WavCache.cacheKey(
        '  caution:   chair VERY  close ahead!! ',
        voiceName: 'Kore',
        model: 'gemini-3.1-flash-tts-preview',
      );
      final k3 = WavCache.cacheKey(
        'Caution: Chair very close ahead.',
        voiceName: 'Aoede',
        model: 'gemini-3.1-flash-tts-preview',
      );

      expect(k1, k2);
      expect(k1, isNot(k3));
    });

    test('stores atomically and hits on lookup', () async {
      final key = WavCache.cacheKey(
        'Door on your left.',
        voiceName: 'Kore',
        model: 'gemini-3.1-flash-tts-preview',
      );
      final wav = pcmToWav(Uint8List(1024));

      expect(await cache.lookup(key), isNull);

      final stored = await cache.store(key, wav);
      expect(await stored.exists(), isTrue);
      expect(stored.path.endsWith('$key.wav'), isTrue);

      final hit = await cache.lookup(key);
      expect(hit, isNotNull);
      expect(await hit!.readAsBytes(), wav);
    });

    test('evicts oldest entries first when exceeding 20 MB cap', () async {
      final chunk = pcmToWav(Uint8List(7 * 1024 * 1024)); // ~7 MB each
      final k1 = WavCache.cacheKey(
        'one',
        voiceName: 'Kore',
        model: 'gemini-3.1-flash-tts-preview',
      );
      final k2 = WavCache.cacheKey(
        'two',
        voiceName: 'Kore',
        model: 'gemini-3.1-flash-tts-preview',
      );
      final k3 = WavCache.cacheKey(
        'three',
        voiceName: 'Kore',
        model: 'gemini-3.1-flash-tts-preview',
      );

      await cache.store(k1, chunk);
      clock.advance(5000);
      await cache.store(k2, chunk);
      clock.advance(5000);
      await cache.store(k3, chunk); // 21 MB total -> k1 evicted

      expect(await cache.lookup(k1), isNull);
      expect(await cache.lookup(k2), isNotNull);
      expect(await cache.lookup(k3), isNotNull);
    });

    test('interrupted write / stale .tmp file leaves no partial .wav',
        () async {
      final staleTmp = File('${tempDir.path}/interrupted.wav.tmp');
      await staleTmp.writeAsBytes(Uint8List(512));

      final key = WavCache.cacheKey(
        'valid entry',
        voiceName: 'Kore',
        model: 'gemini-3.1-flash-tts-preview',
      );
      await cache.store(key, pcmToWav(Uint8List(512)));

      expect(await staleTmp.exists(), isFalse);
      expect(await File('${tempDir.path}/interrupted.wav').exists(), isFalse);
      expect(await cache.lookup(key), isNotNull);
    });
  });
}
