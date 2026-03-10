import 'package:flutter_test/flutter_test.dart';
import 'package:cubie_cloud/services/network_scanner.dart';

void main() {
  group('DiscoveredHost', () {
    test('defaults isCubie to false', () {
      const host = DiscoveredHost(ip: '192.168.0.1');
      expect(host.isCubie, isFalse);
      expect(host.hostname, isNull);
      expect(host.deviceName, isNull);
      expect(host.serial, isNull);
    });

    test('stores all fields when provided', () {
      const host = DiscoveredHost(
        ip: '192.168.0.212',
        hostname: 'cubie.local',
        isCubie: true,
        deviceName: 'My AiHomeCloud',
        serial: 'ABC123',
      );
      expect(host.ip, '192.168.0.212');
      expect(host.hostname, 'cubie.local');
      expect(host.isCubie, isTrue);
      expect(host.deviceName, 'My AiHomeCloud');
      expect(host.serial, 'ABC123');
    });
  });

  group('NetworkScanner', () {
    test('instance is a singleton', () {
      final a = NetworkScanner.instance;
      final b = NetworkScanner.instance;
      expect(identical(a, b), isTrue);
    });
  });
}
