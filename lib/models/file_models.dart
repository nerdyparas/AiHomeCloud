/// File browser models — FileItem, FileListResponse, UploadStatus, UploadTask.
///
/// Used by the MyFolder / SharedFolder screens and file upload tracking.
import 'package:flutter/material.dart';

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

enum UploadStatus { queued, uploading, completed, failed }

class UploadTask {
  final String id;
  final String fileName;
  final int totalBytes;
  final String? filePath;
  final String? destinationPath;
  int uploadedBytes;
  UploadStatus status;
  String? error;

  UploadTask({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    this.filePath,
    this.destinationPath,
    this.uploadedBytes = 0,
    this.status = UploadStatus.queued,
    this.error,
  });

  double get progress =>
      totalBytes > 0 ? (uploadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
}

/// A browseable storage root — a mounted USB or NVMe drive.
class StorageRoot {
  final String name;
  final String path;
  final String device;
  final String transport;
  final int sizeBytes;
  final String sizeDisplay;
  final String fstype;
  final String label;
  final String model;

  const StorageRoot({
    required this.name,
    required this.path,
    required this.device,
    required this.transport,
    required this.sizeBytes,
    required this.sizeDisplay,
    required this.fstype,
    required this.label,
    required this.model,
  });

  factory StorageRoot.fromJson(Map<String, dynamic> json) {
    return StorageRoot(
      name: json['name'] as String,
      path: json['path'] as String,
      device: json['device'] as String,
      transport: json['transport'] as String,
      sizeBytes: json['sizeBytes'] as int,
      sizeDisplay: json['sizeDisplay'] as String,
      fstype: (json['fstype'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
    );
  }

  IconData get icon => switch (transport) {
        'usb' => Icons.usb_rounded,
        'nvme' => Icons.speed_rounded,
        _ => Icons.storage_rounded,
      };

  String get typeLabel => switch (transport) {
        'usb' => 'USB Drive',
        'nvme' => 'NVMe SSD',
        _ => transport.toUpperCase(),
      };
}

/// A trash item returned by GET /api/v1/files/trash.
class TrashItem {
  final String id;
  final String originalPath;
  final String trashPath;
  final String filename;
  final DateTime deletedAt;
  final int sizeBytes;
  final String deletedBy;

  const TrashItem({
    required this.id,
    required this.originalPath,
    required this.trashPath,
    required this.filename,
    required this.deletedAt,
    required this.sizeBytes,
    required this.deletedBy,
  });

  factory TrashItem.fromJson(Map<String, dynamic> json) {
    return TrashItem(
      id: json['id'] as String,
      originalPath: json['originalPath'] as String,
      trashPath: json['trashPath'] as String,
      filename: json['filename'] as String,
      deletedAt: DateTime.parse(json['deletedAt'] as String),
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      deletedBy: json['deletedBy'] as String,
    );
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// A document search result returned by GET /api/v1/files/search?q=...
class SearchResult {
  final String path;
  final String filename;
  final String addedBy;
  final DateTime addedAt;
  final String snippet;

  const SearchResult({
    required this.path,
    required this.filename,
    required this.addedBy,
    required this.addedAt,
    this.snippet = '',
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      path: json['path'] as String,
      filename: json['filename'] as String,
      addedBy: (json['added_by'] as String?) ?? '',
      addedAt: DateTime.parse((json['added_at'] as String?) ?? DateTime.now().toIso8601String()),
      snippet: (json['snippet'] as String?) ?? '',
    );
  }

  /// Convert to a FileItem for file preview navigation.
  FileItem toFileItem() => FileItem(
        name: filename,
        path: path,
        isDirectory: false,
        sizeBytes: 0,
        modified: addedAt,
      );
}
