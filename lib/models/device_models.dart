/// Device state models — CubieDevice, SystemStats, StorageStats, ConnectionStatus.
///
/// Used on the dashboard and throughout system monitoring screens.
library;

class CubieDevice {
  final String serial;
  final String name;
  final String ip;
  final String firmwareVersion;

  const CubieDevice({
    required this.serial,
    required this.name,
    required this.ip,
    required this.firmwareVersion,
  });

  CubieDevice copyWith({
    String? name,
    String? ip,
    String? firmwareVersion,
  }) {
    return CubieDevice(
      serial: serial,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
    );
  }
}

class StorageStats {
  final double totalGB;
  final double usedGB;

  const StorageStats({required this.totalGB, required this.usedGB});

  double get freeGB => totalGB - usedGB;
  double get usedPercent => (usedGB / totalGB).clamp(0.0, 1.0);
}

class SystemStats {
  final double cpuPercent;
  final double ramPercent;
  final double tempCelsius;
  final Duration uptime;
  final double networkUpMbps;
  final double networkDownMbps;
  final StorageStats storage;

  const SystemStats({
    required this.cpuPercent,
    required this.ramPercent,
    required this.tempCelsius,
    required this.uptime,
    required this.networkUpMbps,
    required this.networkDownMbps,
    required this.storage,
  });
}

enum ConnectionStatus { connected, reconnecting, disconnected }
