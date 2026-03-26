/// device_providers unit tests.
///
/// Covers:
///   - ConnectionNotifier: state machine, backoff progression, timer debounce
///   - deviceInfoProvider, storageStatsProvider, storageDevicesProvider,
///     systemStatsStreamProvider: provider wiring (data flows through to reader)
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aihomecloud/models/models.dart';
import 'package:aihomecloud/providers/device_providers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

const _baseStorage = StorageStats(totalGB: 100, usedGB: 40);

SystemStats _makeStats({double cpu = 10}) => SystemStats(
      cpuPercent: cpu,
      ramPercent: 20,
      tempCelsius: 45,
      uptime: const Duration(hours: 1),
      networkUpMbps: 0,
      networkDownMbps: 0,
      storage: _baseStorage,
    );

// ---------------------------------------------------------------------------
// ConnectionNotifier — state machine
// ---------------------------------------------------------------------------

void main() {
  group('ConnectionNotifier initial state', () {
    test('starts connected', () {
      final n = ConnectionNotifier();
      addTearDown(n.dispose);
      expect(n.state, ConnectionStatus.connected);
    });

    test('initial attempt is 0 → backoff is 2 s', () {
      final n = ConnectionNotifier();
      addTearDown(n.dispose);
      expect(n.currentBackoffSeconds, 2);
    });
  });

  // ── markConnected ──────────────────────────────────────────────────────────

  group('ConnectionNotifier.markConnected', () {
    test('sets state to connected', () {
      final n = ConnectionNotifier()..markReconnectStart();
      addTearDown(n.dispose);
      n.markConnected();
      expect(n.state, ConnectionStatus.connected);
    });

    test('resets attempt to 0 so backoff returns to 2 s', () {
      fakeAsync((fake) {
        final n = ConnectionNotifier();
        addTearDown(n.dispose);

        // Fire the timer once so attempt increments to 1.
        n.markReconnectStart();
        fake.elapse(const Duration(seconds: 11));
        expect(n.currentBackoffSeconds, 4); // attempt == 1

        n.markConnected();
        expect(n.currentBackoffSeconds, 2); // reset to attempt 0
      });
    });
  });

  // ── markReconnectStart ─────────────────────────────────────────────────────

  group('ConnectionNotifier.markReconnectStart', () {
    test('immediately sets state to reconnecting', () {
      final n = ConnectionNotifier();
      addTearDown(n.dispose);
      n.markReconnectStart();
      expect(n.state, ConnectionStatus.reconnecting);
    });

    test('transitions to disconnected after 10-second debounce', () {
      fakeAsync((fake) {
        final n = ConnectionNotifier();
        addTearDown(n.dispose);
        n.markReconnectStart();
        expect(n.state, ConnectionStatus.reconnecting);

        fake.elapse(const Duration(seconds: 9));
        expect(n.state, ConnectionStatus.reconnecting); // still waiting

        fake.elapse(const Duration(seconds: 2));
        expect(n.state, ConnectionStatus.disconnected);
      });
    });

    test('increments attempt when timer fires (first time → attempt 1)', () {
      fakeAsync((fake) {
        final n = ConnectionNotifier();
        addTearDown(n.dispose);
        n.markReconnectStart();
        fake.elapse(const Duration(seconds: 11));
        expect(n.currentBackoffSeconds, 4); // reconnectBackoff[1]
      });
    });

    test('calling markReconnectStart again cancels the previous timer', () {
      fakeAsync((fake) {
        final n = ConnectionNotifier();
        addTearDown(n.dispose);

        n.markReconnectStart();
        fake.elapse(const Duration(seconds: 5)); // timer not yet fired

        // Second call cancels first timer and starts a fresh 10-second window.
        n.markReconnectStart();
        fake.elapse(const Duration(seconds: 8)); // still in reconnecting
        expect(n.state, ConnectionStatus.reconnecting);

        fake.elapse(const Duration(seconds: 3)); // now fires
        expect(n.state, ConnectionStatus.disconnected);
      });
    });
  });

  // ── backoff progression ────────────────────────────────────────────────────

  group('ConnectionNotifier backoff', () {
    test('progresses through full backoff list [2,4,8,16,30]', () {
      fakeAsync((fake) {
        final n = ConnectionNotifier();
        addTearDown(n.dispose);

        final expected = [2, 4, 8, 16, 30];
        expect(n.currentBackoffSeconds, expected[0]);

        for (var i = 1; i < expected.length; i++) {
          n.markReconnectStart();
          fake.elapse(const Duration(seconds: 11));
          expect(n.currentBackoffSeconds, expected[i],
              reason: 'attempt $i should give ${expected[i]} s');
        }
      });
    });

    test('clamps at last backoff value after exhausting the list', () {
      fakeAsync((fake) {
        final n = ConnectionNotifier();
        addTearDown(n.dispose);

        // Exhaust the 5-entry list.
        for (var i = 0; i < 10; i++) {
          n.markReconnectStart();
          fake.elapse(const Duration(seconds: 11));
        }
        // Should remain at 30 s (last entry), never go out of bounds.
        expect(n.currentBackoffSeconds, 30);
      });
    });
  });

  // ── setStatus dispatcher ───────────────────────────────────────────────────

  group('ConnectionNotifier.setStatus', () {
    test('connected → markConnected path (resets attempt)', () {
      fakeAsync((fake) {
        final n = ConnectionNotifier();
        addTearDown(n.dispose);
        n.markReconnectStart();
        fake.elapse(const Duration(seconds: 11)); // attempt becomes 1

        n.setStatus(ConnectionStatus.connected);
        expect(n.state, ConnectionStatus.connected);
        expect(n.currentBackoffSeconds, 2); // attempt reset
      });
    });

    test('reconnecting → markReconnectStart path (sets reconnecting)', () {
      final n = ConnectionNotifier();
      addTearDown(n.dispose);
      n.setStatus(ConnectionStatus.reconnecting);
      expect(n.state, ConnectionStatus.reconnecting);
    });

    test('disconnected → sets state directly without timer', () {
      fakeAsync((fake) {
        final n = ConnectionNotifier();
        addTearDown(n.dispose);
        n.setStatus(ConnectionStatus.disconnected);
        expect(n.state, ConnectionStatus.disconnected);
        // No timer means no further state changes.
        fake.elapse(const Duration(seconds: 60));
        expect(n.state, ConnectionStatus.disconnected);
      });
    });
  });

  // ── connectionProvider wiring ──────────────────────────────────────────────

  group('connectionProvider', () {
    test('initial read returns connected', () {
      final c = _container();
      expect(c.read(connectionProvider), ConnectionStatus.connected);
    });

    test('notifier state mutations are visible through provider', () {
      final c = _container();
      c.read(connectionProvider.notifier).setStatus(ConnectionStatus.disconnected);
      expect(c.read(connectionProvider), ConnectionStatus.disconnected);
    });
  });

  // ── FutureProvider wiring ─────────────────────────────────────────────────
  //
  // These tests override the providers with controlled data to verify the
  // provider graph wires correctly — i.e. the reader gets back what the
  // provider produces.

  group('deviceInfoProvider wiring', () {
    const fakeDevice = AhcDevice(
      serial: 'SN-001',
      name: 'Home NAS',
      ip: '192.168.0.241',
      firmwareVersion: '1.2.3',
    );

    test('resolves with the device returned by the override', () async {
      final c = ProviderContainer(overrides: [
        deviceInfoProvider.overrideWith((_) async => fakeDevice),
      ]);
      addTearDown(c.dispose);

      final result = await c.read(deviceInfoProvider.future);
      expect(result.serial, 'SN-001');
      expect(result.name, 'Home NAS');
    });

    test('exposes AsyncError when override throws', () async {
      final c = ProviderContainer(overrides: [
        deviceInfoProvider.overrideWith((_) async => throw Exception('timeout')),
      ]);
      addTearDown(c.dispose);

      await c.read(deviceInfoProvider.future).catchError((_) => fakeDevice);
      expect(c.read(deviceInfoProvider), isA<AsyncError>());
    });
  });

  group('storageStatsProvider wiring', () {
    const fakeStats = StorageStats(totalGB: 500, usedGB: 120);

    test('resolves with the stats returned by the override', () async {
      final c = ProviderContainer(overrides: [
        storageStatsProvider.overrideWith((_) async => fakeStats),
      ]);
      addTearDown(c.dispose);

      final result = await c.read(storageStatsProvider.future);
      expect(result.totalGB, 500);
      expect(result.usedGB, 120);
      expect(result.freeGB, closeTo(380, 0.001));
      expect(result.usedPercent, closeTo(0.24, 0.001));
    });
  });

  group('storageDevicesProvider wiring', () {
    final fakeDevices = [
      const StorageDevice(
        name: 'sda',
        path: '/dev/sda',
        sizeBytes: 64000000000,
        sizeDisplay: '64.0 GB',
        transport: 'usb',
        mounted: true,
        isNasActive: true,
        isOsDisk: false,
        displayName: 'SanDisk Ultra (64 GB)',
      ),
    ];

    test('resolves with the device list returned by the override', () async {
      final c = ProviderContainer(overrides: [
        storageDevicesProvider.overrideWith((_) async => fakeDevices),
      ]);
      addTearDown(c.dispose);

      final result = await c.read(storageDevicesProvider.future);
      expect(result, hasLength(1));
      expect(result.first.name, 'sda');
      expect(result.first.isNasActive, isTrue);
    });

    test('resolves with empty list when no devices', () async {
      final c = ProviderContainer(overrides: [
        storageDevicesProvider.overrideWith((_) async => <StorageDevice>[]),
      ]);
      addTearDown(c.dispose);

      final result = await c.read(storageDevicesProvider.future);
      expect(result, isEmpty);
    });
  });

  group('systemStatsStreamProvider wiring', () {
    test('emits values from the stream returned by the override', () async {
      final stats = [_makeStats(cpu: 10), _makeStats(cpu: 55)];

      final c = ProviderContainer(overrides: [
        systemStatsStreamProvider.overrideWith(
          (_) => Stream.fromIterable(stats),
        ),
      ]);
      addTearDown(c.dispose);

      final emitted = <SystemStats>[];
      final sub = c.listen(
        systemStatsStreamProvider,
        (prev, next) {
          if (next is AsyncData<SystemStats>) emitted.add(next.value);
        },
      );
      addTearDown(sub.close);

      // Drain the stream.
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(2));
      expect(emitted.first.cpuPercent, 10);
      expect(emitted.last.cpuPercent, 55);
    });
  });
}
