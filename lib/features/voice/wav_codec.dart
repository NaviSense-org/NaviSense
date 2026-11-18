import 'dart:typed_data';

/// Wraps raw linear PCM bytes in a 44-byte little-endian RIFF/WAVE header.
///
/// Defaults match `gemini-3.1-flash-tts-preview` output (`24000` Hz, mono,
/// signed 16-bit LE PCM). Any dangling odd trailing byte is dropped per
/// `2-architecture.md` §2.5.
Uint8List pcmToWav(
  Uint8List pcm, {
  int sampleRate = 24000,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final dataLen = pcm.lengthInBytes - (pcm.lengthInBytes % 2);
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;

  final header = ByteData(44)
    ..setUint32(0, 0x52494646, Endian.big) // "RIFF"
    ..setUint32(4, 36 + dataLen, Endian.little)
    ..setUint32(8, 0x57415645, Endian.big) // "WAVE"
    ..setUint32(12, 0x666d7420, Endian.big) // "fmt "
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // AudioFormat = 1 (PCM)
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, byteRate, Endian.little)
    ..setUint16(32, blockAlign, Endian.little)
    ..setUint16(34, bitsPerSample, Endian.little)
    ..setUint32(36, 0x64617461, Endian.big) // "data"
    ..setUint32(40, dataLen, Endian.little);

  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(Uint8List.sublistView(pcm, 0, dataLen)))
      .takeBytes();
}
