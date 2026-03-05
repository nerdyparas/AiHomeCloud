/// NAS service and network models — ServiceInfo, NetworkStatus.
///
/// Used by the Services tab and network configuration screens.
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
