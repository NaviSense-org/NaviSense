import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navisense/features/voice/wav_codec.dart';

void main() {
  group('pcmToWav', () {
    test('writes exact 44-byte RIFF/WAVE header for 48000 PCM bytes', () {
      final pcm = Uint8List(48000);
      final wav = pcmToWav(pcm);

      expect(wav.length, 48044);
      // ChunkID "RIFF"
      expect(wav.sublist(0, 4), <int>[0x52, 0x49, 0x46, 0x46]);
      // ChunkSize = LE(48036) = A4 BB 00 00
      expect(wav.sublist(4, 8), <int>[0xA4, 0xBB, 0x00, 0x00]);
      // Format "WAVE"
      expect(wav.sublist(8, 12), <int>[0x57, 0x41, 0x56, 0x45]);
      // Subchunk1ID "fmt "
      expect(wav.sublist(12, 16), <int>[0x66, 0x6D, 0x74, 0x20]);
      // Subchunk1Size = 16, AudioFormat = 1
      expect(wav.sublist(16, 20), <int>[0x10, 0x00, 0x00, 0x00]);
      expect(wav.sublist(20, 22), <int>[0x01, 0x00]);
      // NumChannels = 1
      expect(wav.sublist(22, 24), <int>[0x01, 0x00]);
      // SampleRate = LE(24000) = C0 5D 00 00
      expect(wav.sublist(24, 28), <int>[0xC0, 0x5D, 0x00, 0x00]);
      // ByteRate = LE(48000) = 80 BB 00 00
      expect(wav.sublist(28, 32), <int>[0x80, 0xBB, 0x00, 0x00]);
      // BlockAlign = 2, BitsPerSample = 16
      expect(wav.sublist(32, 34), <int>[0x02, 0x00]);
      expect(wav.sublist(34, 36), <int>[0x10, 0x00]);
      // Subchunk2ID "data"
      expect(wav.sublist(36, 40), <int>[0x64, 0x61, 0x74, 0x61]);
      // Subchunk2Size = LE(48000) = 80 BB 00 00
      expect(wav.sublist(40, 44), <int>[0x80, 0xBB, 0x00, 0x00]);
    });

    test('drops dangling odd PCM byte (48001 -> 48000 data bytes)', () {
      final pcm = Uint8List(48001);
      final wav = pcmToWav(pcm);

      expect(wav.length, 48044);
      expect(wav.sublist(4, 8), <int>[0xA4, 0xBB, 0x00, 0x00]);
      expect(wav.sublist(40, 44), <int>[0x80, 0xBB, 0x00, 0x00]);
    });
  });
}
