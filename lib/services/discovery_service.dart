import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';

/// How the device was discovered.
enum DiscoveryMethod { mdns, ble, manual }

/// Result returned after a successful discovery.
class DiscoveryResult {
  final String ip;
  final DiscoveryMethod method;
  const DiscoveryResult({required this.ip, required this.method});
}

/// Handles mDNS and BLE device discovery.
class DiscoveryService {
  DiscoveryService._();
  static final DiscoveryService instance = DiscoveryService._();

  /// Orchestrates the full discovery flow:
  /// 1. Try mDNS for 10 s
  /// 2. If mDNS fails â†’ BLE fallback
  /// [onStatus] receives human-readable progress messages for the UI.
  Future<DiscoveryResult> discover(
    String serial,
    void Function(String) onStatus,
  ) async {
    // â”€â”€ Step 1: mDNS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    onStatus('Searching via mDNSâ€¦');
    final mdnsResult = await _tryMdns(serial);
    if (mdnsResult != null) {
      onStatus('Found device via mDNS!');
      return DiscoveryResult(ip: mdnsResult, method: DiscoveryMethod.mdns);
    }

    // â”€â”€ Step 2: BLE fallback â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    onStatus('mDNS timed out. Trying Bluetoothâ€¦');
    await Future.delayed(const Duration(seconds: 1));

    final bleResult = await _tryBle(serial, onStatus);
    if (bleResult != null) {
      onStatus('Found device via Bluetooth!');
      return DiscoveryResult(ip: bleResult, method: DiscoveryMethod.ble);
    }

    throw Exception(
      'Could not discover device. Make sure it is powered on '
      'and connected to your network.',
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // mDNS â€” real implementation using multicast_dns package
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        // Optionally match by serial in the service name
        // Service name is typically "ahc-<SERIAL>._aihomecloud-nas._tcp"
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
            return ip.address.address; // e.g. '192.168.0.212'
          }
        }
      }

      client.stop();
      return null; // Not found within timeout
    } catch (_) {
      try {
        client.stop();
      } catch (_) {}
      return null;
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // BLE â€” real implementation using flutter_blue_plus package
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<String?> _tryBle(
    String serial,
    void Function(String) onStatus,
  ) async {
    // Request BLE permissions on Android
    if (Platform.isAndroid) {
      final btScan = await Permission.bluetoothScan.request();
      final btConnect = await Permission.bluetoothConnect.request();
      final location = await Permission.locationWhenInUse.request();

      if (!btScan.isGranted || !btConnect.isGranted || !location.isGranted) {
        onStatus('Bluetooth permissions not granted');
        return null;
      }
    }

    // Check if Bluetooth is on
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      onStatus('Bluetooth is not enabled');
      return null;
    }

    onStatus('Scanning for AiHomeCloud via Bluetoothâ€¦');

    try {
      // Start scanning for devices with our service UUID
      await FlutterBluePlus.startScan(
        withServices: [Guid(AppConstants.bleServiceUuid)],
        timeout: const Duration(seconds: 15),
      );

      // Listen for scan results
      BluetoothDevice? discoveredDevice;

      await for (final results in FlutterBluePlus.onScanResults) {
        for (final r in results) {
          final name = r.device.platformName;
          if (name.startsWith(AppConstants.bleDevicePrefix)) {
            discoveredDevice = r.device;
            break;
          }
        }
        if (discoveredDevice != null) break;
      }

      await FlutterBluePlus.stopScan();

      if (discoveredDevice == null) {
        onStatus('No AiHomeCloud device found via Bluetooth');
        return null;
      }

      onStatus('Connecting to ${discoveredDevice.platformName}â€¦');

      // Connect and read the IP characteristic
      await discoveredDevice.connect(timeout: const Duration(seconds: 10));

      try {
        final services = await discoveredDevice.discoverServices();
        for (final s in services) {
          if (s.uuid == Guid(AppConstants.bleServiceUuid)) {
            for (final c in s.characteristics) {
              if (c.uuid == Guid(AppConstants.bleCharUuid)) {
                final value = await c.read();
                final ip = String.fromCharCodes(value);
                await discoveredDevice.disconnect();
                return ip; // e.g. '192.168.0.212'
              }
            }
          }
        }
        await discoveredDevice.disconnect();
      } catch (e) {
        try {
          await discoveredDevice.disconnect();
        } catch (_) {}
        onStatus('BLE read failed: $e');
      }

      return null;
    } catch (e) {
      await FlutterBluePlus.stopScan();
      onStatus('BLE scan error: $e');
      return null;
    }
  }
}
