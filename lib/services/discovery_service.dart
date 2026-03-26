import 'package:multicast_dns/multicast_dns.dart';

import '../core/constants.dart';

/// How the device was discovered.
enum DiscoveryMethod { mdns, manual }

/// Result returned after a successful discovery.
class DiscoveryResult {
  final String ip;
  final DiscoveryMethod method;
  const DiscoveryResult({required this.ip, required this.method});
}

/// Handles mDNS device discovery.
class DiscoveryService {
  DiscoveryService._();
  static final DiscoveryService instance = DiscoveryService._();

  /// Try mDNS for up to [AppConstants.mdnsTimeout].
  /// Throws if the device is not found.
  Future<DiscoveryResult> discover(
    String serial,
    void Function(String) onStatus,
  ) async {
    onStatus('Searching via mDNS…');
    final ip = await _tryMdns(serial);
    if (ip != null) {
      onStatus('Found device via mDNS!');
      return DiscoveryResult(ip: ip, method: DiscoveryMethod.mdns);
    }

    throw Exception(
      'Could not discover device. Make sure it is powered on '
      'and connected to your network.',
    );
  }

  /// Connect to a device at a known [ip] (manually entered by the user).
  DiscoveryResult discoverManual(String ip) {
    return DiscoveryResult(ip: ip.trim(), method: DiscoveryMethod.manual);
  }

  // ---------------------------------------------------------------------------
  // mDNS — real implementation using multicast_dns package
  // ---------------------------------------------------------------------------

  Future<String?> _tryMdns(String serial) async {
    final MDnsClient client = MDnsClient();
    try {
      await client.start();

      // Look for AiHomeCloud service type: _aihomecloud-nas._tcp
      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(AppConstants.mdnsType),
          )
          .timeout(AppConstants.mdnsTimeout, onTimeout: (sink) {
        sink.close();
      })) {
        await for (final SrvResourceRecord srv in client
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )
            .timeout(const Duration(seconds: 3), onTimeout: (sink) {
          sink.close();
        })) {
          await for (final IPAddressResourceRecord ip in client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              )
              .timeout(const Duration(seconds: 3), onTimeout: (sink) {
            sink.close();
          })) {
            client.stop();
            return ip.address.address;
          }
        }
      }

      client.stop();
      return null;
    } catch (_) {
      try {
        client.stop();
      } catch (_) {}
      return null;
    }
  }
}
