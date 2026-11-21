import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
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
  Timer? _recheck;
  int _generation = 0;
  bool _hasInterface = true;
  List<ConnectivityResult> _lastResults = const <ConnectivityResult>[];

  /// How often reachability is re-checked while an interface is up but the
  /// internet looked unreachable (captive portal, slow first DNS, dead
  /// hotspot), so a transient failure never leaves the app stuck offline.
  @visibleForTesting
  static Duration recheckInterval = const Duration(seconds: 5);

  /// `true` only when the OS reports no network interface at all. This is the
  /// one definitive offline signal the orchestrator may trust to skip the
  /// cloud without probing.
  bool get noInterface => !_hasInterface;

  @override
  NetworkStatus build() {
    final source = ref.watch(connectivitySourceProvider);
    ref.onDispose(() {
      _sub?.cancel();
      _recheck?.cancel();
    });
    try {
      _sub = source.changes.listen(
        (results) => unawaited(_evaluate(results)),
        onError: (Object e) =>
            log('Connectivity stream error', name: 'navisense.net', error: e),
      );
    } on MissingPluginException {
      return NetworkStatus.unknown;
    }

    unawaited(
      source.current().then(_evaluate).catchError((Object e) {
        log('Connectivity check failed', name: 'navisense.net', error: e);
      }),
    );
    return NetworkStatus.unknown;
  }

  /// Records that a cloud request just succeeded (proof of connectivity).
  void markReachable() {
    if (!ref.mounted || !_hasInterface) return;
    _recheck?.cancel();
    _set(NetworkStatus.online, reason: 'cloud request succeeded');
  }

  Future<void> _evaluate(List<ConnectivityResult> results) async {
    final generation = ++_generation;
    _recheck?.cancel();
    _lastResults = results;
    final probe = ref.read(connectivityProbeProvider);
    // WHY: Any interface change invalidates the cached reachability result
    // the orchestrator relies on.
    probe.resetCache();

    _hasInterface =
        results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);
    if (!_hasInterface) {
      _set(NetworkStatus.offline, reason: 'no interface $results');
      return;
    }

    // WHY: One slow lookup is not proof of being offline; retry once before
    // telling a user they've lost the network.
    var reachable = await probe.isReachable();
    if (!reachable && ref.mounted && generation == _generation) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!ref.mounted || generation != _generation) return;
      reachable = await probe.isReachable();
    }
    if (!ref.mounted || generation != _generation) return;

    _set(
      reachable ? NetworkStatus.online : NetworkStatus.offline,
      reason: 'interfaces=$results reachable=$reachable',
    );
    if (!reachable) {
      _recheck = Timer(recheckInterval, () {
        if (ref.mounted) unawaited(_evaluate(_lastResults));
      });
    }
  }

  void _set(NetworkStatus next, {required String reason}) {
    if (state == next) return;
    log('network status=${next.name} ($reason)', name: 'navisense.net');
    state = next;
  }
}
