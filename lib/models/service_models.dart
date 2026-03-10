/// Service and network models — ServiceInfo, NetworkStatus.
///
/// Used by the Services tab and network configuration screens.
library;
import 'package:flutter/material.dart';

class ServiceInfo {
  final String id;
  final String name;
  final String description;
  final bool isEnabled;
  final IconData icon;

  const ServiceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.isEnabled,
    required this.icon,
  });

  ServiceInfo copyWith({bool? isEnabled}) {
    return ServiceInfo(
      id: id,
      name: name,
      description: description,
      isEnabled: isEnabled ?? this.isEnabled,
      icon: icon,
    );
  }
}

/// Aggregated network state from the Cubie device.
class NetworkStatus {
  final bool wifiEnabled;
  final bool wifiConnected;
  final String? wifiSsid;
  final String? wifiIp;
  final bool hotspotEnabled;
  final String? hotspotSsid;
  final bool bluetoothEnabled;
  final bool lanConnected;
  final String? lanIp;
  final String? lanSpeed;

  const NetworkStatus({
    required this.wifiEnabled,
    required this.wifiConnected,
    this.wifiSsid,
    this.wifiIp,
    required this.hotspotEnabled,
    this.hotspotSsid,
    required this.bluetoothEnabled,
    required this.lanConnected,
    this.lanIp,
    this.lanSpeed,
  });

  factory NetworkStatus.fromJson(Map<String, dynamic> json) {
    return NetworkStatus(
      wifiEnabled: json['wifiEnabled'] as bool,
      wifiConnected: json['wifiConnected'] as bool,
      wifiSsid: json['wifiSsid'] as String?,
      wifiIp: json['wifiIp'] as String?,
      hotspotEnabled: json['hotspotEnabled'] as bool,
      hotspotSsid: json['hotspotSsid'] as String?,
      bluetoothEnabled: json['bluetoothEnabled'] as bool,
      lanConnected: json['lanConnected'] as bool,
      lanIp: json['lanIp'] as String?,
      lanSpeed: json['lanSpeed'] as String?,
    );
  }
}

/// A single Wi-Fi network from a scan result.
class WifiNetwork {
  final String ssid;
  final int signal;
  final String security;
  final bool inUse;
  final bool saved;

  const WifiNetwork({
    required this.ssid,
    required this.signal,
    required this.security,
    this.inUse = false,
    this.saved = false,
  });

  bool get isOpen => security == 'Open' || security.isEmpty;

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(
      ssid: json['ssid'] as String,
      signal: json['signal'] as int,
      security: json['security'] as String,
      inUse: json['inUse'] as bool? ?? false,
      saved: json['saved'] as bool? ?? false,
    );
  }
}

/// Result of a Wi-Fi connect attempt.
class WifiConnectionResult {
  final bool success;
  final String message;
  final String? ip;

  const WifiConnectionResult({
    required this.success,
    required this.message,
    this.ip,
  });

  factory WifiConnectionResult.fromJson(Map<String, dynamic> json) {
    return WifiConnectionResult(
      success: json['success'] as bool,
      message: json['message'] as String,
      ip: json['ip'] as String?,
    );
  }
}
