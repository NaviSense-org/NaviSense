import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/core/utils/navi_log.dart';
import 'package:path_provider/path_provider.dart';

/// Provides [WavCache] configured with LRU eviction (20 MB / 200 files).
final wavCacheProvider = Provider<WavCache>(
  (ref) => WavCache(clock: ref.watch(clockProvider)),
);

/// Content-addressed SHA-256 WAV disk cache (`2-architecture.md` §2.5).
///
/// Keys normalize text (lowercase, trim, collapse whitespace, strip trailing
/// punctuation) so Tier 2 syntheses and identical Tier 3 deterministic phrases
/// hit the same cached high-fidelity WAV file offline.
final class WavCache {
  /// Creates a [WavCache].
  WavCache({
    Clock? clock,
    Future<Directory> Function()? directoryProvider,
    this.maxBytes = defaultMaxBytes,
    this.maxFiles = defaultMaxFiles,
  })  : _clock = clock ?? const SystemClock(),
        _directoryProvider = directoryProvider ?? _defaultDirectoryProvider;

  /// Maximum total cache size on disk (20 MB per §2.5).
  static const int defaultMaxBytes = 20 * 1024 * 1024;

  /// Maximum number of cached `.wav` files (200 per §2.5).
  static const int defaultMaxFiles = 200;

  /// Subdirectory under app documents storing cached WAV files.
  static const String cacheFolderName = 'navisense_audio';

  /// Maximum byte budget for this cache instance.
  final int maxBytes;

  /// Maximum file count for this cache instance.
  final int maxFiles;

  final Clock _clock;
  final Future<Directory> Function() _directoryProvider;

  static Future<Directory> _defaultDirectoryProvider() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$cacheFolderName');
  }

  /// Normalizes [text] for deterministic cache key generation.
  static String normalizeText(String text) {
    final collapsed = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.replaceAll(RegExp(r'[.!?,;:]+$'), '').trim();
  }

  /// Computes SHA-256 hex cache key for `(voiceName, model, text)`.
  static String cacheKey(
    String text, {
    required String voiceName,
    required String model,
  }) {
    final payload = '$voiceName|$model|${normalizeText(text)}';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// Looks up a cached `.wav` file for [key], updating its `lastModified`
  /// timestamp on hit. Returns `null` on miss.
  Future<File?> lookup(String key) async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) return null;

    final file = File('${dir.path}/$key.wav');
    if (!await file.exists()) return null;

    try {
      final length = await file.length();
      if (length <= 44) return null;
      await file.setLastModified(_clock.now());
      return file;
    } on FileSystemException catch (e, st) {
      log(
        'WAV cache lookup failed for $key',
        name: 'navisense.voice',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Atomically writes [wavBytes] to `<key>.wav` via `<key>.wav.tmp` -> rename,
  /// then enforces LRU size/count caps.
  Future<File> store(String key, Uint8List wavBytes) async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final tmpFile = File('${dir.path}/$key.wav.tmp');
    final targetFile = File('${dir.path}/$key.wav');

    try {
      await tmpFile.writeAsBytes(wavBytes, flush: true);
      final renamed = await tmpFile.rename(targetFile.path);
      try {
        await renamed.setLastModified(_clock.now());
      } on FileSystemException {
        // Ignore if filesystem forbids mtime updates.
      }
      await evict();
      return renamed;
    } catch (_) {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } on FileSystemException {
          // Best-effort temp cleanup.
        }
      }
      rethrow;
    }
  }

  /// Evicts oldest `.wav` files (LRU by `lastModified`) until total size is
  /// `<= maxBytes` and file count is `<= maxFiles`. Also sweeps stale `.tmp`.
  Future<void> evict() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) return;

    final entries = <_CacheEntry>[];
    var totalBytes = 0;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.wav.tmp')) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Ignore stale tmp cleanup error.
        }
        continue;
      }
      if (!entity.path.endsWith('.wav')) continue;
      try {
        final stat = await entity.stat();
        entries.add(
          _CacheEntry(file: entity, size: stat.size, modified: stat.modified),
        );
        totalBytes += stat.size;
      } on FileSystemException {
        // Skip disappearing file.
      }
    }

    if (totalBytes <= maxBytes && entries.length <= maxFiles) return;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    var remainingCount = entries.length;

    for (final entry in entries) {
      if (totalBytes <= maxBytes && remainingCount <= maxFiles) break;
      try {
        await entry.file.delete();
        totalBytes -= entry.size;
        remainingCount--;
      } on FileSystemException catch (e, st) {
        log(
          'Failed to evict ${entry.file.path}',
          name: 'navisense.voice',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  /// Deletes all cached audio files (for Settings "Clear audio cache").
  Future<void> clear() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Continue clearing remaining files.
        }
      }
    }
  }
}

final class _CacheEntry {
  const _CacheEntry({
    required this.file,
    required this.size,
    required this.modified,
  });

  final File file;
  final int size;
  final DateTime modified;
}
