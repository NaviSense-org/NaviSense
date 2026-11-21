import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:navisense/core/connectivity/network_status.dart';

/// Test [ConnectivitySource] with no platform channel and no events, so
/// widget tests don't hit `connectivity_plus` or start the DNS probe; the
/// status simply stays [NetworkStatus.unknown].
final class FakeConnectivitySource implements ConnectivitySource {
  /// Creates a [FakeConnectivitySource].
  const FakeConnectivitySource();

  @override
  Stream<List<ConnectivityResult>> get changes => const Stream.empty();

  @override
  Future<List<ConnectivityResult>> current() =>
      Completer<List<ConnectivityResult>>().future;
}
