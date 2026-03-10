/// Storage device and async job models — StorageDevice, JobStatus.
///
/// Used by the storage management screen for device detection, formatting,
/// and mount/unmount operations.
library;
import 'package:flutter/material.dart';

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
