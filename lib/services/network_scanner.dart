import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../core/constants.dart';

const _recognizedServiceNames = {'CubieCloud', 'AiHomeCloud'};

/// A discovered AiHomeCloud device on the local network.
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

/// Fast, service-based network scanner.
///
/// Discovery strategy (ordered by speed):
///   1. **mDNS** — query `_cubie-nas._tcp` for instant results (~1-2 s)
///   2. **Subnet sweep** — parallel HTTP probes on port 8443 to the root
///      endpoint, checking the `service` field for AiHomeCloud identity
///
/// Only AiHomeCloud backends are returned. Random hosts with port 8443 open
/// are silently ignored. This is hardware-agnostic — any board running the
/// backend (Radxa, RPi, x86, etc.) will be discovered.
class NetworkScanner {
  NetworkScanner._();
  static final NetworkScanner instance = NetworkScanner._();

  /// Discover the local Wi-Fi/LAN IP.
  ///
  /// Strategy 1 — routing trick: open a raw TCP socket toward a well-known
  /// external IP (8.8.8.8); the OS selects the correct outbound interface
  /// and we read back the *local* address. No data is sent.
  ///
  /// Strategy 2 — interface enumeration fallback: walk [NetworkInterface.list]
  /// sorted to prefer wlan/eth over virtual interfaces and skip reserved
  /// address ranges.
  Future<String?> getLocalIp() async {
    // Strategy 1: routing trick — most reliable on Android/iOS.
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
      // No internet path — fall through to interface enumeration.
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

  // ── mDNS fast path ──────────────────────────────────────────────────────

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
            // We found an mDNS-advertised device — verify it's ours via HTTP.
            final host = await _probeService(ip.address.address);
            if (host != null) results.add(host);
          }
        }
      }
    } catch (_) {
      // mDNS unavailable or timed out — that's fine, subnet scan follows.
    } finally {
      try { client.stop(); } catch (_) {}
    }

    return results;
  }

  // ── Subnet sweep ────────────────────────────────────────────────────────

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

    final found = <String>{}; // IPs already yielded — dedup across phases.

    // ── Phase 1: mDNS (instant) ──────────────────────────────────────────
    final mdnsHosts = await _mdnsDiscover();
    for (final h in mdnsHosts) {
      found.add(h.ip);
      yield h;
    }

    // ── Phase 2: parallel subnet sweep ───────────────────────────────────
    final prefix = _subnetPrefix(localIp);
    const total = 254;
    int scanned = 0;

    // Higher concurrency + short timeouts for Fing-like speed.
    const batchSize = 50;

    for (int batchStart = 1; batchStart <= total; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize - 1).clamp(1, total);
      final futures = <Future<DiscoveredHost?>>[];

      for (int i = batchStart; i <= batchEnd; i++) {
        final ip = '$prefix$i';
        if (found.contains(ip)) {
          // Already found via mDNS — skip.
          continue;
        }
        futures.add(_probeService(ip));
      }

      final results = await Future.wait(futures);
      scanned = batchEnd.clamp(0, total);
      onProgress?.call(scanned, total);

      for (final host in results) {
        if (host != null && !found.contains(host.ip)) {
          found.add(host.ip);
          yield host;
        }
      }
    }
  }

  // ── Single-host probe ───────────────────────────────────────────────────

  /// Probe a single IP for the AiHomeCloud root endpoint.
  /// Returns null if the host is unreachable, port closed, or not our service.
  Future<DiscoveredHost?> _probeService(String ip) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 1500)
      ..badCertificateCallback = (_, __, ___) => true; // self-signed OK

    try {
      final req = await client
          .getUrl(Uri.parse(
              '${AppConstants.apiScheme}://$ip:${AppConstants.apiPort}/'))
          .timeout(const Duration(seconds: 2));
      final resp = await req.close().timeout(const Duration(seconds: 2));

      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (!_recognizedServiceNames.contains(json['service'])) {
        return null; // Not our service — ignore entirely.
      }

      return DiscoveredHost(
        ip: ip,
        isCubie: true,
        deviceName: json['deviceName'] as String? ?? 'AiHomeCloud',
        serial: json['serial'] as String?,
      );
    } catch (_) {
      return null; // Unreachable, port closed, TLS error, etc.
    } finally {
      client.close();
    }
  }
}
