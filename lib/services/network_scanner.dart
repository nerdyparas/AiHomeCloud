import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';

/// A discovered host on the local network.
class DiscoveredHost {
  final String ip;
  final String? hostname;
  final bool isCubie;
  final String? deviceName;
  final String? serial;

  const DiscoveredHost({
    required this.ip,
    this.hostname,
    this.isCubie = false,
    this.deviceName,
    this.serial,
  });
}

/// Scans the local /24 subnet for devices and identifies CubieCloud backends.
class NetworkScanner {
  NetworkScanner._();
  static final NetworkScanner instance = NetworkScanner._();

  /// Discover the local Wi-Fi/LAN IP.
  ///
  /// Strategy 1 — routing trick: open a TCP socket toward a well-known
  /// external IP; the OS selects the correct outbound interface and we read
  /// back [Socket.address]. No data is actually sent because we destroy the
  /// socket immediately after reading the address.
  ///
  /// Strategy 2 — interface enumeration fallback: walk [NetworkInterface.list]
  /// sorted to prefer `wlan`/`eth` over virtual interfaces (USB tethering,
  /// Wi-Fi Direct, rmnet, dummy, tun, etc.) and skip reserved/virtual address
  /// ranges (`169.254.*`, `192.0.0.*`, `100.64.*`).
  Future<String?> getLocalIp() async {
    // Strategy 1: routing trick — most reliable on Android/iOS
    try {
      final socket = await Socket.connect(
        '8.8.8.8', // destination only used for route selection – no data sent
        443,
        timeout: const Duration(seconds: 2),
      );
      final ip = socket.address.address;
      socket.destroy();
      if (ip.isNotEmpty && ip != '0.0.0.0') return ip;
    } catch (_) {
      // No internet access – fall through to interface enumeration
    }

    // Strategy 2: interface enumeration, filtered and sorted
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      int _ifaceScore(NetworkInterface iface) {
        final n = iface.name.toLowerCase();
        if (n.startsWith('wlan') || n.startsWith('wifi')) return 0;
        if (n.startsWith('en') || n.startsWith('eth')) return 1;
        return 10; // virtual: rmnet, dummy, p2p, tun, usb, ccmni, v4-, etc.
      }

      final sorted = [...interfaces]
        ..sort((a, b) => _ifaceScore(a).compareTo(_ifaceScore(b)));

      for (final iface in sorted) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (addr.isLoopback) continue;
          if (ip.startsWith('169.254.')) continue; // link-local (APIPA)
          if (ip.startsWith('192.0.0.')) continue; // IANA DS-Lite reserved
          if (ip.startsWith('100.64.')) continue;  // CGNAT shared space
          return ip;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Get the /24 subnet prefix from a local IP address.
  /// e.g. "192.168.0.105" → "192.168.0."
  String _subnetPrefix(String ip) {
    final parts = ip.split('.');
    return '${parts[0]}.${parts[1]}.${parts[2]}.';
  }

  /// Scan the local /24 subnet for hosts with port [AppConstants.apiPort]
  /// open, then probe for CubieCloud health endpoint.
  ///
  /// [onFound] is called each time a host is discovered (for live UI updates).
  /// [onProgress] is called with (scanned, total) for progress tracking.
  Stream<DiscoveredHost> scanNetwork({
    void Function(int scanned, int total)? onProgress,
  }) async* {
    final localIp = await getLocalIp();
    if (localIp == null) return;

    final prefix = _subnetPrefix(localIp);
    const total = 254;
    int scanned = 0;

    // Scan in batches to avoid overwhelming the network
    const batchSize = 30;

    for (int batchStart = 1; batchStart <= total; batchStart += batchSize) {
      final batchEnd =
          (batchStart + batchSize - 1).clamp(1, total);
      final futures = <Future<DiscoveredHost?>>[];

      for (int i = batchStart; i <= batchEnd; i++) {
        final ip = '$prefix$i';
        futures.add(_probeHost(ip));
      }

      final results = await Future.wait(futures);
      scanned += results.length;
      onProgress?.call(scanned, total);

      for (final host in results) {
        if (host != null) yield host;
      }
    }
  }

  /// Try to connect to the CubieCloud API port and check the health endpoint.
  Future<DiscoveredHost?> _probeHost(String ip) async {
    try {
      // Quick TCP connect check
      final socket = await Socket.connect(
        ip,
        AppConstants.apiPort,
        timeout: const Duration(milliseconds: 800),
      );
      socket.destroy();

      // Port is open — probe for CubieCloud health endpoint
      return await _probeCubieApi(ip);
    } catch (_) {
      return null;
    }
  }

  /// Hit the CubieCloud health endpoint to verify it's our backend.
  Future<DiscoveredHost> _probeCubieApi(String ip) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..badCertificateCallback = (_, __, ___) => true; // self-signed OK

    try {
      // Try health endpoint first
      final healthReq = await client
          .getUrl(Uri.parse(
              '${AppConstants.apiScheme}://$ip:${AppConstants.apiPort}/api/health'))
          .timeout(const Duration(seconds: 3));
      final healthResp =
          await healthReq.close().timeout(const Duration(seconds: 3));

      if (healthResp.statusCode == 200) {
        await healthResp.drain<void>();
        // Try to get device info
        String? deviceName;
        String? serial;
        try {
          final rootReq = await client
              .getUrl(Uri.parse(
                  '${AppConstants.apiScheme}://$ip:${AppConstants.apiPort}/'))
              .timeout(const Duration(seconds: 2));
          final rootResp =
              await rootReq.close().timeout(const Duration(seconds: 2));
          if (rootResp.statusCode == 200) {
            final rootBody =
                await rootResp.transform(utf8.decoder).join();
            final json = jsonDecode(rootBody) as Map<String, dynamic>;
            if (json['service'] == 'CubieCloud') {
              deviceName = json['deviceName'] as String?;
              serial = json['serial'] as String?;
            }
          }
        } catch (_) {
          // Root endpoint info is optional
        }
        client.close();
        return DiscoveredHost(
          ip: ip,
          isCubie: true,
          deviceName: deviceName ?? 'CubieCloud',
          serial: serial,
        );
      }

      client.close();
      // Port open but not CubieCloud
      return DiscoveredHost(ip: ip, isCubie: false);
    } catch (_) {
      client.close();
      // Port open but health check failed — still show as a host
      return DiscoveredHost(ip: ip, isCubie: false);
    }
  }
}
