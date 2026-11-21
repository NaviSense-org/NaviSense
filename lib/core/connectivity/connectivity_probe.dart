import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/utils/clock.dart';

/// DNS lookup signature injected into [ConnectivityProbe] for testing.
typedef DnsLookup = Future<List<InternetAddress>> Function(String host);

/// Provides [ConnectivityProbe] for sub-300 ms offline detection.
final connectivityProbeProvider = Provider<ConnectivityProbe>(
  (ref) => ConnectivityProbe(clock: ref.watch(clockProvider)),
);

/// Fast, cached DNS reachability probe (`2-architecture.md` §2.6).
///
/// Checks `firebasevertexai.googleapis.com` with a 1.2 s timeout and caches
/// the result for 5 s so offline devices fall through to Tier 3 immediately.
final class ConnectivityProbe {
  /// Creates a [ConnectivityProbe].
  ConnectivityProbe({
    Clock? clock,
    DnsLookup? lookup,
    this.probeHost = defaultProbeHost,
    // WHY: 300 ms was routinely exceeded by a cold DNS lookup on mobile data
    // or a phone hotspot, marking real online users offline. Airplane Mode
    // still fails instantly (no interface), so this costs offline users
    // nothing.
    this.timeout = const Duration(milliseconds: 1200),
    this.cacheTtl = const Duration(seconds: 5),
  })  : _clock = clock ?? const SystemClock(),
        _lookup = lookup ?? InternetAddress.lookup;

  /// Host resolved to verify Firebase AI Logic cloud reachability.
  static const String defaultProbeHost = 'firebasevertexai.googleapis.com';

  /// Target host for DNS lookups.
  final String probeHost;

  /// Hard timeout per DNS probe.
  final Duration timeout;

  /// Cache duration for recent connectivity probes (5 s per §2.6).
  final Duration cacheTtl;

  final Clock _clock;
  final DnsLookup _lookup;

  int? _lastCheckedMs;
  bool? _lastOffline;

  /// Returns `true` when the device cannot resolve [probeHost] within [timeout].
  Future<bool> isOffline({bool forceRefresh = false}) async {
    final nowMs = _clock.nowMs();
    final cachedMs = _lastCheckedMs;
    final cachedOffline = _lastOffline;
    if (!forceRefresh &&
        cachedMs != null &&
        cachedOffline != null &&
        nowMs - cachedMs < cacheTtl.inMilliseconds) {
      return cachedOffline;
    }

    var offline = true;
    try {
      final addresses = await _lookup(probeHost).timeout(timeout);
      offline = addresses.isEmpty;
    } on TimeoutException {
      offline = true;
    } on SocketException {
      offline = true;
    } on OSError {
      offline = true;
    }

    _lastCheckedMs = nowMs;
    _lastOffline = offline;
    return offline;
  }

  /// One uncached reachability check with a caller-chosen [timeout]; updates
  /// the cache on completion so the next [isOffline] call is instant.
  Future<bool> isReachable({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    var reachable = false;
    try {
      final addresses = await _lookup(probeHost).timeout(timeout);
      reachable = addresses.isNotEmpty;
    } on TimeoutException {
      reachable = false;
    } on SocketException {
      reachable = false;
    } on OSError {
      reachable = false;
    }
    _lastCheckedMs = _clock.nowMs();
    _lastOffline = !reachable;
    return reachable;
  }

  /// Clears the cached reachability value.
  void resetCache() {
    _lastCheckedMs = null;
    _lastOffline = null;
  }
}
