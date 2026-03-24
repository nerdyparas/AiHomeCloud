/// Domain models for the Auto Backup feature.
library;

/// A single backup job — maps one phone folder to one NAS destination.
class BackupJob {
  final String id;
  final String phoneFolder;
  final String destination;
  final DateTime? lastSyncAt;
  final int totalUploaded;
  final int totalSkipped;

  const BackupJob({
    required this.id,
    required this.phoneFolder,
    required this.destination,
    this.lastSyncAt,
    this.totalUploaded = 0,
    this.totalSkipped = 0,
  });

  factory BackupJob.fromJson(Map<String, dynamic> json) {
    return BackupJob(
      id: json['id'] as String,
      phoneFolder: json['phoneFolder'] as String,
      destination: json['destination'] as String,
      lastSyncAt: json['lastSyncAt'] != null
          ? DateTime.tryParse(json['lastSyncAt'] as String)
          : null,
      totalUploaded: (json['totalUploaded'] as num?)?.toInt() ?? 0,
      totalSkipped: (json['totalSkipped'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phoneFolder': phoneFolder,
        'destination': destination,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'totalUploaded': totalUploaded,
        'totalSkipped': totalSkipped,
      };

  /// Human-readable destination label shown in the UI.
  String get destinationLabel {
    switch (destination) {
      case 'personal':
        return 'My Personal Files';
      case 'family':
        return 'Family Folder';
      case 'entertainment':
        return 'Entertainment';
      default:
        return destination;
    }
  }

  /// Display name derived from the last segment of the phone folder path.
  String get folderDisplayName {
    final segments = phoneFolder.split('/');
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => phoneFolder);
  }

  /// Human-readable relative time since last sync.
  String get lastSyncRelative {
    if (lastSyncAt == null) return 'Never synced';
    final diff = DateTime.now().difference(lastSyncAt!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Overall backup configuration returned by GET /backup/status.
class BackupStatus {
  final bool enabled;
  final List<BackupJob> jobs;

  const BackupStatus({
    required this.enabled,
    required this.jobs,
  });

  factory BackupStatus.fromJson(Map<String, dynamic> json) {
    return BackupStatus(
      enabled: json['enabled'] as bool? ?? false,
      jobs: (json['jobs'] as List<dynamic>? ?? [])
          .map((j) => BackupJob.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Subtitle shown in the More tab tile.
  String get statusSubtitle {
    if (jobs.isEmpty) return 'Not set up';
    final count = jobs.length;
    final folderLabel = count == 1 ? '1 folder' : '$count folders';

    // Find the most recent sync across all jobs
    DateTime? latest;
    for (final j in jobs) {
      if (j.lastSyncAt != null) {
        if (latest == null || j.lastSyncAt!.isAfter(latest)) {
          latest = j.lastSyncAt;
        }
      }
    }
    if (latest == null) return '$folderLabel · Never synced';
    final diff = DateTime.now().difference(latest);
    final timeStr = diff.inMinutes < 1
        ? 'just now'
        : diff.inHours < 1
            ? '${diff.inMinutes}m ago'
            : diff.inHours < 24
                ? '${diff.inHours}h ago'
                : '${diff.inDays}d ago';
    return '$folderLabel · Last backed up $timeStr';
  }
}
