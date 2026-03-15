import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../core/constants.dart';

const _recognizedServiceNames = {'AiHomeCloud'};

/// A discovered AiHomeCloud device on the local network.
class DiscoveredHost {
  final String ip;
  final String? hostname;
  final bool isAhc;
  final String? deviceName;
  final String? serial;

  const DiscoveredHost({
    required this.ip,
    this.hostname,
    this.isAhc = false,
    this.deviceName,
    this.serial,
  });
}

/// Fast, service-based network scanner.
///
/// Discovery strategy (ordered by speed):
///   1. **mDNS** â€” query `_aihomecloud-nas._tcp` for instant results (~1-2 s)
///   2. **Subnet sweep** â€” parallel HTTP probes on port 8443 to the root
///      endpoint, checking the `service` field for AiHomeCloud identity
///
/// Only AiHomeCloud backends are returned. Random hosts with port 8443 open
/// are silently ignored. This is hardware-agnostic â€” any board running the
/// backend (Radxa, RPi, x86, etc.) will be discovered.
class NetworkScanner {
  NetworkScanner._();
  static final NetworkScanner instance = NetworkScanner._();

  /// Discover the local Wi-Fi/LAN IP.
  ///
  /// Strategy 1 â€” routing trick: open a raw TCP socket toward a well-known
  /// external IP (8.8.8.8); the OS selects the correct outbound interface
  /// and we read back the *local* address. No data is sent.
  ///
  /// Strategy 2 â€” interface enumeration fallback: walk [NetworkInterface.list]
  /// sorted to prefer wlan/eth over virtual interfaces and skip reserved
  /// address ranges.
  Future<String?> getLocalIp() async {
    // Strategy 1: routing trick â€” most reliable on Android/iOS.
    try {
      final raw = await RawSocket.connect(
        '8.8.8.8',
        443,
        timeout: const Duration(seconds: 2),
      );
      final ip = raw.address.address;
      raw.close();
      if (ip.isNotEmpty && ip != '0.0.0.0') return ip;
    } catch (_) {
      // No internet path â€” fall through to interface enumeration.
    }

    // Strategy 2: interface enumeration, filtered and sorted.
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      int ifaceScore(NetworkInterface iface) {
        final n = iface.name.toLowerCase();
        if (n.startsWith('wlan') || n.startsWith('wifi')) return 0;
        if (n.startsWith('en') || n.startsWith('eth')) return 1;
        return 10;
      }

      final sorted = [...interfaces]
        ..sort((a, b) => ifaceScore(a).compareTo(ifaceScore(b)));

      for (final iface in sorted) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (addr.isLoopback) continue;
          if (ip.startsWith('169.254.')) continue;
          if (ip.startsWith('192.0.0.')) continue;
          if (ip.startsWith('100.64.')) continue;
          return ip;
        }
      }
    } catch (_) {}

    return null;
  }

  // â”€â”€ mDNS fast path â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Try mDNS service discovery for up to [timeout].
  /// Returns all AiHomeCloud devices found during that window.
  Future<List<DiscoveredHost>> _mdnsDiscover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final results = <DiscoveredHost>[];
    final MDnsClient client = MDnsClient();

    try {
      await client.start();

      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(AppConstants.mdnsType),
          )
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        await for (final SrvResourceRecord srv in client
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )
            .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
          await for (final IPAddressResourceRecord ip in client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              )
              .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
            // We found an mDNS-advertised device â€” verify it's ours via HTTP.
            final host = await _probeService(ip.address.address);
            if (host != null) results.add(host);
          }
        }
      }
    } catch (_) {
      // mDNS unavailable or timed out â€” that's fine, subnet scan follows.
    } finally {
      try { client.stop(); } catch (_) {}
    }

    return results;
  }

  // â”€â”€ Subnet sweep â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _subnetPrefix(String ip) {
    final parts = ip.split('.');
    return '${parts[0]}.${parts[1]}.${parts[2]}.';
  }

  /// Full scan: mDNS first (fast), then subnet sweep for anything not yet found.
  ///
  /// Only AiHomeCloud backends are yielded. Random hosts are silently skipped.
  Stream<DiscoveredHost> scanNetwork({
    void Function(int scanned, int total)? onProgress,
  }) async* {
    final localIp = await getLocalIp();
    if (localIp == null) return;

    final found = <String>{}; // IPs already yielded â€” dedup across phases.

    // â”€â”€ Phase 1: mDNS (instant) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final mdnsHosts = await _mdnsDiscover();
    for (final h in mdnsHosts) {
      found.add(h.ip);
      yield h;
    }

    // â”€â”€ Phase 2: parallel subnet sweep â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Step 1: Fast TCP connect scan to find IPs with port 8443 open.
    // Step 2: HTTPS verify only the handful of IPs that passed TCP check.
    final prefix = _subnetPrefix(localIp);
    const total = 254;
    int scanned = 0;
    const batchSize = 50;

    final openIps = <String>[];

    for (int batchStart = 1; batchStart <= total; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize - 1).clamp(1, total);
      final futures = <Future<String?>>[];

      for (int i = batchStart; i <= batchEnd; i++) {
        final ip = '$prefix$i';
        if (found.contains(ip)) continue;
        futures.add(_tcpCheck(ip));
      }

      final results = await Future.wait(futures);
      scanned = batchEnd.clamp(0, total);
      onProgress?.call(scanned, total);

      for (final ip in results) {
        if (ip != null) openIps.add(ip);
      }
    }

    // Step 2: HTTPS verify only the IPs with open port 8443.
    // Typically 0-3 hosts, so sequential is fine â€” avoids socket exhaustion.
    for (final ip in openIps) {
      if (found.contains(ip)) continue;
      final host = await _probeService(ip);
      if (host != null) {
        found.add(host.ip);
        yield host;
      }
    }
  }

  // â”€â”€ TCP pre-check â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Lightweight TCP connect to check if port 8443 is open.
  /// Returns the IP if open, null otherwise. No TLS, no HTTP â€” just TCP SYN.
  Future<String?> _tcpCheck(String ip) async {
    try {
      final socket = await Socket.connect(
        ip,
        AppConstants.apiPort,
        timeout: const Duration(milliseconds: 800),
      );
      socket.destroy();
      return ip;
    } catch (_) {
      return null;
    }
  }

  // â”€â”€ Single-host HTTPS probe â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Probe a single IP for the AiHomeCloud root endpoint via HTTPS.
  /// Returns null if not our service or unreachable.
  Future<DiscoveredHost?> _probeService(String ip) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..badCertificateCallback = (_, __, ___) => true; // self-signed OK

    try {
      final req = await client
          .getUrl(Uri.parse(
              '${AppConstants.apiScheme}://$ip:${AppConstants.apiPort}/'))
          .timeout(const Duration(seconds: 5));
      final resp = await req.close().timeout(const Duration(seconds: 5));

      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (!_recognizedServiceNames.contains(json['service'])) {
        return null;
      }

      return DiscoveredHost(
        ip: ip,
        isAhc: true,
        deviceName: json['deviceName'] as String? ?? 'AiHomeCloud',
        serial: json['serial'] as String?,
      );
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
