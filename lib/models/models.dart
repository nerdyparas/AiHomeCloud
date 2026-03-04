import 'package:flutter/material.dart';

// ─── CubieDevice ────────────────────────────────────────────────────────────

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

// ─── StorageStats ───────────────────────────────────────────────────────────

class StorageStats {
  final double totalGB;
  final double usedGB;

  const StorageStats({required this.totalGB, required this.usedGB});

  double get freeGB => totalGB - usedGB;
  double get usedPercent => (usedGB / totalGB).clamp(0.0, 1.0);
}

// ─── SystemStats ────────────────────────────────────────────────────────────

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

// ─── FileItem ───────────────────────────────────────────────────────────────

class FileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime modified;
  final String? mimeType;

  const FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modified,
    this.mimeType,
  });

  /// Human-readable file size.
  String get formattedSize {
    if (isDirectory) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Icon based on file extension.
  IconData get icon {
    if (isDirectory) return Icons.folder_rounded;
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' ||
      'jpeg' ||
      'png' ||
      'gif' ||
      'webp' ||
      'heic' =>
        Icons.image_rounded,
      'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv' => Icons.movie_rounded,
      'mp3' || 'wav' || 'flac' || 'aac' || 'ogg' => Icons.music_note_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      'doc' || 'docx' || 'txt' || 'md' || 'rtf' => Icons.description_rounded,
      'xls' || 'xlsx' || 'csv' => Icons.table_chart_rounded,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.archive_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  /// Accent colour based on file type.
  Color get iconColor {
    if (isDirectory) return const Color(0xFFE8A84C);
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' ||
      'jpeg' ||
      'png' ||
      'gif' ||
      'webp' ||
      'heic' =>
        const Color(0xFF4CE88A),
      'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv' => const Color(0xFF4C9BE8),
      'mp3' || 'wav' || 'flac' || 'aac' || 'ogg' => const Color(0xFFE84CA8),
      'pdf' => const Color(0xFFE85C5C),
      _ => const Color(0xFF7A8499),
    };
  }
}

class FileListResponse {
  final List<FileItem> items;
  final int totalCount;
  final int page;
  final int pageSize;

  const FileListResponse({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });
}

// ─── FamilyUser ─────────────────────────────────────────────────────────────

class FamilyUser {
  final String id;
  final String name;
  final bool isAdmin;
  final double folderSizeGB;
  final Color avatarColor;

  const FamilyUser({
    required this.id,
    required this.name,
    required this.isAdmin,
    required this.folderSizeGB,
    required this.avatarColor,
  });
}

// ─── QrPairPayload ──────────────────────────────────────────────────────────

class QrPairPayload {
  final String serial;
  final String key;
  final String host;
  final int? expiresAt;

  const QrPairPayload({
    required this.serial,
    required this.key,
    required this.host,
    this.expiresAt,
  });

  factory QrPairPayload.fromUri(Uri uri) {
    final rawExpires = uri.queryParameters['expiresAt'];
    final expiresTimestamp =
        rawExpires != null ? int.tryParse(rawExpires) : null;
    return QrPairPayload(
      serial: uri.queryParameters['serial'] ?? '',
      key: uri.queryParameters['key'] ?? '',
      host: uri.queryParameters['host'] ?? '',
      expiresAt: expiresTimestamp,
    );
  }

  Duration? get timeUntilExpiry {
    if (expiresAt == null) return null;
    final now = DateTime.now().toUtc();
    final expiry =
        DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000, isUtc: true);
    final diff = expiry.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get isExpired {
    final remaining = timeUntilExpiry;
    return remaining != null && remaining == Duration.zero;
  }
}

// ─── UploadTask ─────────────────────────────────────────────────────────────

enum UploadStatus { queued, uploading, completed, failed }

class UploadTask {
  final String id;
  final String fileName;
  final int totalBytes;
  int uploadedBytes;
  UploadStatus status;
  String? error;

  UploadTask({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    this.uploadedBytes = 0,
    this.status = UploadStatus.queued,
    this.error,
  });

  double get progress =>
      totalBytes > 0 ? (uploadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
}

// ─── ServiceInfo ────────────────────────────────────────────────────────────

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

// ─── StorageDevice ──────────────────────────────────────────────────────────

/// A block device (partition) detected on the Cubie hardware.
class StorageDevice {
  final String name; // "sda1", "nvme0n1p1"
  final String path; // "/dev/sda1"
  final int sizeBytes;
  final String sizeDisplay; // "64.0 GB"
  final String? fstype; // "ext4", null if unformatted
  final String? label;
  final String? model; // "SanDisk Ultra"
  final String transport; // "usb", "nvme", "sd"
  final bool mounted;
  final String? mountPoint;
  final bool isNasActive; // currently used as NAS storage
  final bool isOsDisk; // SD card OS partition

  const StorageDevice({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.sizeDisplay,
    this.fstype,
    this.label,
    this.model,
    required this.transport,
    required this.mounted,
    this.mountPoint,
    required this.isNasActive,
    required this.isOsDisk,
  });

  factory StorageDevice.fromJson(Map<String, dynamic> json) {
    return StorageDevice(
      name: json['name'] as String,
      path: json['path'] as String,
      sizeBytes: json['sizeBytes'] as int,
      sizeDisplay: json['sizeDisplay'] as String,
      fstype: json['fstype'] as String?,
      label: json['label'] as String?,
      model: json['model'] as String?,
      transport: json['transport'] as String,
      mounted: json['mounted'] as bool,
      mountPoint: json['mountPoint'] as String?,
      isNasActive: json['isNasActive'] as bool,
      isOsDisk: json['isOsDisk'] as bool,
    );
  }

  /// Human-readable device type label.
  String get typeLabel => switch (transport) {
        'usb' => 'USB Drive',
        'nvme' => 'NVMe SSD',
        'sd' => 'SD Card',
        _ => transport.toUpperCase(),
      };

  /// Icon for this device type.
  IconData get icon => switch (transport) {
        'usb' => Icons.usb_rounded,
        'nvme' => Icons.speed_rounded,
        'sd' => Icons.sd_card_rounded,
        _ => Icons.storage_rounded,
      };
}

// ─── NetworkStatus ──────────────────────────────────────────────────────────

/// Severity level for in-app notifications.
enum NotificationSeverity { info, success, warning, error }

/// A real-time notification pushed from the backend via /ws/events.
class AppNotification {
  final String type;
  final String title;
  final String body;
  final NotificationSeverity severity;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  const AppNotification({
    required this.type,
    required this.title,
    required this.body,
    required this.severity,
    required this.timestamp,
    this.data,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      severity: NotificationSeverity.values.firstWhere(
        (s) => s.name == json['severity'],
        orElse: () => NotificationSeverity.info,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        ((json['timestamp'] as num) * 1000).toInt(),
      ),
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  /// Color accent for this severity.
  Color get color => switch (severity) {
        NotificationSeverity.info => const Color(0xFF4C9BE8),
        NotificationSeverity.success => const Color(0xFF4CE88A),
        NotificationSeverity.warning => const Color(0xFFE8A84C),
        NotificationSeverity.error => const Color(0xFFE85C5C),
      };

  /// Icon for this severity.
  IconData get icon => switch (severity) {
        NotificationSeverity.info => Icons.info_outline_rounded,
        NotificationSeverity.success => Icons.check_circle_outline_rounded,
        NotificationSeverity.warning => Icons.warning_amber_rounded,
        NotificationSeverity.error => Icons.error_outline_rounded,
      };
}

// ─── NetworkStatus (existing) ───────────────────────────────────────────────

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

class JobStatus {
  final String id;
  final String status;
  final DateTime startedAt;
  final Map<String, dynamic>? result;
  final String? error;

  const JobStatus({
    required this.id,
    required this.status,
    required this.startedAt,
    this.result,
    this.error,
  });

  bool get isTerminal => status == 'completed' || status == 'failed';

  factory JobStatus.fromJson(Map<String, dynamic> json) {
    return JobStatus(
      id: json['id'] as String,
      status: json['status'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      result: json['result'] as Map<String, dynamic>?,
      error: json['error'] as String?,
    );
  }
}
