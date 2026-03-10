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
  /// 2. If mDNS fails → BLE fallback
  /// [onStatus] receives human-readable progress messages for the UI.
  Future<DiscoveryResult> discover(
    String serial,
    void Function(String) onStatus,
  ) async {
    // ── Step 1: mDNS ────────────────────────────────────────────────────────
    onStatus('Searching via mDNS…');
    final mdnsResult = await _tryMdns(serial);
    if (mdnsResult != null) {
      onStatus('Found device via mDNS!');
      return DiscoveryResult(ip: mdnsResult, method: DiscoveryMethod.mdns);
    }

    // ── Step 2: BLE fallback ────────────────────────────────────────────────
    onStatus('mDNS timed out. Trying Bluetooth…');
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

  // ────────────────────────────────────────────────────────────────────────────
  // mDNS — real implementation using multicast_dns package
  // ────────────────────────────────────────────────────────────────────────────

  Future<String?> _tryMdns(String serial) async {
    final MDnsClient client = MDnsClient();
    try {
      await client.start();

      // Look for CubieCloud service type: _cubie-nas._tcp
      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(AppConstants.mdnsType),
          )
          .timeout(AppConstants.mdnsTimeout, onTimeout: (sink) {
        sink.close();
      })) {
        // Optionally match by serial in the service name
        // Service name is typically "cubie-<SERIAL>._cubie-nas._tcp"
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

  // ────────────────────────────────────────────────────────────────────────────
  // BLE — real implementation using flutter_blue_plus package
  // ────────────────────────────────────────────────────────────────────────────

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

    onStatus('Scanning for CubieCloud via Bluetooth…');

    try {
      // Start scanning for devices with our service UUID
      await FlutterBluePlus.startScan(
        withServices: [Guid(AppConstants.bleServiceUuid)],
        timeout: const Duration(seconds: 15),
      );

      // Listen for scan results
      BluetoothDevice? cubieDevice;

      await for (final results in FlutterBluePlus.onScanResults) {
        for (final r in results) {
          final name = r.device.platformName;
          if (name.startsWith(AppConstants.bleDevicePrefix)) {
            cubieDevice = r.device;
            break;
          }
        }
        if (cubieDevice != null) break;
      }

      await FlutterBluePlus.stopScan();

      if (cubieDevice == null) {
        onStatus('No CubieCloud device found via Bluetooth');
        return null;
      }

      onStatus('Connecting to ${cubieDevice.platformName}…');

      // Connect and read the IP characteristic
      await cubieDevice.connect(timeout: const Duration(seconds: 10));

      try {
        final services = await cubieDevice.discoverServices();
        for (final s in services) {
          if (s.uuid == Guid(AppConstants.bleServiceUuid)) {
            for (final c in s.characteristics) {
              if (c.uuid == Guid(AppConstants.bleCharUuid)) {
                final value = await c.read();
                final ip = String.fromCharCodes(value);
                await cubieDevice.disconnect();
                return ip; // e.g. '192.168.0.212'
              }
            }
          }
        }
        await cubieDevice.disconnect();
      } catch (e) {
        try {
          await cubieDevice.disconnect();
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
