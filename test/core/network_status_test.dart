import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navisense/core/connectivity/connectivity_probe.dart';
import 'package:navisense/core/connectivity/network_status.dart';

final class _ControlledSource implements ConnectivitySource {
  _ControlledSource(this.initial);

  final List<ConnectivityResult> initial;
  // ignore: close_sinks — closed via addTearDown in the tests that emit.
  final StreamController<List<ConnectivityResult>> controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get changes => controller.stream;

  @override
  Future<List<ConnectivityResult>> current() async => initial;
}

void main() {
  late bool dnsWorks;

  ProviderContainer makeContainer(_ControlledSource source) {
    final container = ProviderContainer(
      overrides: [
        connectivitySourceProvider.overrideWithValue(source),
        connectivityProbeProvider.overrideWithValue(
          ConnectivityProbe(
            lookup: (_) async => dnsWorks
                ? <InternetAddress>[InternetAddress.loopbackIPv4]
                : throw const SocketException('no route'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() => dnsWorks = true);

  test('no interface -> offline immediately', () async {
    final container = makeContainer(
      _ControlledSource(<ConnectivityResult>[ConnectivityResult.none]),
    );
    expect(container.read(networkStatusProvider), NetworkStatus.unknown);
    await settle();
    expect(container.read(networkStatusProvider), NetworkStatus.offline);
  });

  test('wifi with working DNS -> online', () async {
    final container = makeContainer(
      _ControlledSource(<ConnectivityResult>[ConnectivityResult.wifi]),
    );
    container.read(networkStatusProvider);
    await settle();
    await settle();
    expect(container.read(networkStatusProvider), NetworkStatus.online);
  });

  test('wifi without internet (captive/dead hotspot) -> offline after retry',
      () async {
    dnsWorks = false;
    final container = makeContainer(
      _ControlledSource(<ConnectivityResult>[ConnectivityResult.wifi]),
    );
    container.read(networkStatusProvider);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(container.read(networkStatusProvider), NetworkStatus.offline);
    expect(
      container.read(networkStatusProvider.notifier).noInterface,
      isFalse,
    );
  });

  test(
      'regression: online phone whose first DNS check fails recovers on its '
      'own (never stuck offline)', () async {
    final saved = NetworkStatusNotifier.recheckInterval;
    NetworkStatusNotifier.recheckInterval = const Duration(milliseconds: 50);
    addTearDown(() => NetworkStatusNotifier.recheckInterval = saved);

    dnsWorks = false;
    final container = makeContainer(
      _ControlledSource(<ConnectivityResult>[ConnectivityResult.mobile]),
    );
    container.read(networkStatusProvider);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(container.read(networkStatusProvider), NetworkStatus.offline);

    dnsWorks = true;
    // One recheck cycle (interval + possible 500 ms retry) is enough.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(container.read(networkStatusProvider), NetworkStatus.online);
  });

  test('markReachable flips offline -> online after a cloud success', () async {
    dnsWorks = false;
    final container = makeContainer(
      _ControlledSource(<ConnectivityResult>[ConnectivityResult.wifi]),
    );
    container.read(networkStatusProvider);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(container.read(networkStatusProvider), NetworkStatus.offline);

    container.read(networkStatusProvider.notifier).markReachable();
    expect(container.read(networkStatusProvider), NetworkStatus.online);
  });

  test('stream transitions online -> offline -> online', () async {
    final source =
        _ControlledSource(<ConnectivityResult>[ConnectivityResult.mobile]);
    addTearDown(source.controller.close);
    final container = makeContainer(source);
    final seen = <NetworkStatus>[];
    container.listen<NetworkStatus>(
      networkStatusProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    await settle();
    await settle();

    source.controller.add(<ConnectivityResult>[ConnectivityResult.none]);
    await settle();
    await settle();

    source.controller.add(<ConnectivityResult>[ConnectivityResult.wifi]);
    await settle();
    await settle();

    expect(seen, <NetworkStatus>[
      NetworkStatus.unknown,
      NetworkStatus.online,
      NetworkStatus.offline,
      NetworkStatus.online,
    ]);
  });
}
