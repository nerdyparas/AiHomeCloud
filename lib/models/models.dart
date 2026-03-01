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
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' =>
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
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' =>
        const Color(0xFF4CE88A),
      'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv' => const Color(0xFF4C9BE8),
      'mp3' || 'wav' || 'flac' || 'aac' || 'ogg' => const Color(0xFFE84CA8),
      'pdf' => const Color(0xFFE85C5C),
      _ => const Color(0xFF7A8499),
    };
  }
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

  const QrPairPayload({
    required this.serial,
    required this.key,
    required this.host,
  });

  factory QrPairPayload.fromUri(Uri uri) {
    return QrPairPayload(
      serial: uri.queryParameters['serial'] ?? '',
      key: uri.queryParameters['key'] ?? '',
      host: uri.queryParameters['host'] ?? '',
    );
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
