/// DiscoveryService model tests (P2-Task 21).
///
/// The actual mDNS and BLE discovery requires platform plugins that are not
/// available in the unit-test host. These tests cover:
///   - DiscoveryResult model construction
///   - DiscoveryMethod enum values
///   - discover() throws a meaningful exception when no device is reachable
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:aihomecloud/services/discovery_service.dart';

void main() {
  // ─── DiscoveryMethod ────────────────────────────────────────────────────────

  group('DiscoveryMethod', () {
    test('has mdns and manual values', () {
      expect(DiscoveryMethod.values, contains(DiscoveryMethod.mdns));
      expect(DiscoveryMethod.values, contains(DiscoveryMethod.manual));
    });
  });

  // ─── DiscoveryResult ────────────────────────────────────────────────────────

  group('DiscoveryResult', () {
    test('stores ip and method correctly', () {
      const result = DiscoveryResult(ip: '192.168.0.5', method: DiscoveryMethod.mdns);
      expect(result.ip, '192.168.0.5');
      expect(result.method, DiscoveryMethod.mdns);
    });

    test('two results with same values are logically equivalent', () {
      const a = DiscoveryResult(ip: '10.0.0.1', method: DiscoveryMethod.manual);
      const b = DiscoveryResult(ip: '10.0.0.1', method: DiscoveryMethod.manual);
      expect(a.ip, b.ip);
      expect(a.method, b.method);
    });
  });

  // ─── DiscoveryService singleton ─────────────────────────────────────────────

  group('DiscoveryService', () {
    setUp(() {
      // Force "not found" so the test is not affected by real mDNS devices
      // on the local network (e.g., the dev machine's paired Radxa SBC).
      DiscoveryService.instance.mdnsOverride = (_) async => null;
    });

    tearDown(() {
      DiscoveryService.instance.mdnsOverride = null;
    });

    test('instance is a singleton', () {
      expect(DiscoveryService.instance, same(DiscoveryService.instance));
    });

    test('discover() throws when device is not reachable', () async {
      await expectLater(
        () => DiscoveryService.instance.discover('AHC-TESTDEV', (_) {}),
        throwsA(isA<Exception>()),
      );
    });
  });
}
