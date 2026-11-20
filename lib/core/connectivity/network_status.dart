import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/connectivity/connectivity_probe.dart';
import 'package:navisense/core/utils/navi_log.dart';

/// Live network reachability as experienced by the user.
enum NetworkStatus {
  /// An interface is up and Firebase AI Logic's host resolves.
  online,

  /// No interface, or an interface without working internet.
  offline,

  /// Not determined yet (startup, or the platform plugin is unavailable).
  unknown,
}

/// Abstracts `connectivity_plus` so the notifier is unit-testable.
abstract interface class ConnectivitySource {
  /// Emits whenever the set of active network interfaces changes.
  Stream<List<ConnectivityResult>> get changes;

  /// Current set of active network interfaces.
  Future<List<ConnectivityResult>> current();
}

/// Production [ConnectivitySource] backed by `connectivity_plus`.
final class PlusConnectivitySource implements ConnectivitySource {
  /// Creates a [PlusConnectivitySource].
  PlusConnectivitySource([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<List<ConnectivityResult>> get changes =>
      _connectivity.onConnectivityChanged;

  @override
  Future<List<ConnectivityResult>> current() =>
      _connectivity.checkConnectivity();
}

/// Provides the [ConnectivitySource] (overridable in tests).
final connectivitySourceProvider = Provider<ConnectivitySource>(
  (ref) => PlusConnectivitySource(),
);

/// Streams [NetworkStatus] changes so the UI and orchestrator react the moment
/// the link drops or returns, instead of discovering it on the next tap.
final networkStatusProvider =
    NotifierProvider<NetworkStatusNotifier, NetworkStatus>(
  NetworkStatusNotifier.new,
);

/// Combines interface changes (`connectivity_plus`) with a DNS reachability
/// check, because "connected to Wi-Fi" does not mean "has internet".
final class NetworkStatusNotifier extends Notifier<NetworkStatus> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  int _generation = 0;

  @override
  NetworkStatus build() {
    final source = ref.watch(connectivitySourceProvider);
    try {
      _sub = source.changes.listen(
        (results) => unawaited(_evaluate(results)),
        onError: (Object e) =>
            log('Connectivity stream error', name: 'navisense.net', error: e),
      );
    } on MissingPluginException {
      return NetworkStatus.unknown;
    }
    ref.onDispose(() => _sub?.cancel());

    unawaited(
      source.current().then(_evaluate).catchError((Object e) {
        log('Connectivity check failed', name: 'navisense.net', error: e);
      }),
    );
    return NetworkStatus.unknown;
  }

  Future<void> _evaluate(List<ConnectivityResult> results) async {
    final generation = ++_generation;
    final probe = ref.read(connectivityProbeProvider);
    // WHY: Any interface change invalidates the cached reachability result
    // the orchestrator relies on.
    probe.resetCache();

    final hasInterface =
        results.any((r) => r != ConnectivityResult.none) && results.isNotEmpty;
    final next = hasInterface
        ? (await probe.isOffline(forceRefresh: true)
            ? NetworkStatus.offline
            : NetworkStatus.online)
        : NetworkStatus.offline;

    if (!ref.mounted || generation != _generation) return;
    if (state != next) {
      log('network status=${next.name} interfaces=$results',
          name: 'navisense.net');
      state = next;
    }
  }
}
