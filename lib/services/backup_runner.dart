/// In-process backup runner.
///
/// Executes backup logic directly in the main isolate so the UI can display
/// real-time progress when the user taps "Back up now".
///
/// Background periodic runs still use [BackupWorker] (WorkManager) and are
/// unaffected by this file.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/backup_models.dart';
import 'api_service.dart';
import 'backup_batcher.dart';

// ── Progress model ─────────────────────────────────────────────────────────────

enum BackupPhase { idle, scanning, running, done, failed }

// Sentinel for nullable `copyWith` fields.
const _sentinel = Object();

class BackupProgress {
  final BackupPhase phase;

  /// Total file count detected after the initial scan.
  final int totalFiles;

  /// Files fully processed (uploaded or skipped via dedup).
  final int doneFiles;

  /// Files actually uploaded (new to the NAS).
  final int uploadedFiles;

  /// Files skipped because the NAS already has them.
  final int skippedFiles;

  /// Filename currently being processed.
  final String? currentFile;

  /// Measured upload speed for the last file, in bytes per second.
  final double? speedBytesPerSec;

  final String? errorMessage;

  const BackupProgress({
    this.phase = BackupPhase.idle,
    this.totalFiles = 0,
    this.doneFiles = 0,
    this.uploadedFiles = 0,
    this.skippedFiles = 0,
    this.currentFile,
    this.speedBytesPerSec,
    this.errorMessage,
  });

  BackupProgress copyWith({
    BackupPhase? phase,
    int? totalFiles,
    int? doneFiles,
    int? uploadedFiles,
    int? skippedFiles,
    Object? currentFile = _sentinel,
    Object? speedBytesPerSec = _sentinel,
    Object? errorMessage = _sentinel,
  }) {
    return BackupProgress(
      phase: phase ?? this.phase,
      totalFiles: totalFiles ?? this.totalFiles,
      doneFiles: doneFiles ?? this.doneFiles,
      uploadedFiles: uploadedFiles ?? this.uploadedFiles,
      skippedFiles: skippedFiles ?? this.skippedFiles,
      currentFile:
          currentFile == _sentinel ? this.currentFile : currentFile as String?,
      speedBytesPerSec: speedBytesPerSec == _sentinel
          ? this.speedBytesPerSec
          : speedBytesPerSec as double?,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  /// True while scanning or uploading files.
  bool get isActive =>
      phase == BackupPhase.scanning || phase == BackupPhase.running;

  /// Human-readable status line for the progress card.
  String get statusLine {
    switch (phase) {
      case BackupPhase.idle:
        return '';
      case BackupPhase.scanning:
        return totalFiles > 0
            ? 'Found $totalFiles files to check…'
            : 'Scanning files…';
      case BackupPhase.running:
        return '$doneFiles / $totalFiles files processed';
      case BackupPhase.done:
        if (uploadedFiles == 0) {
          return skippedFiles > 0
              ? 'Already up to date · $skippedFiles files'
              : 'No new files to back up';
        }
        return '$uploadedFiles new ${uploadedFiles == 1 ? 'file' : 'files'} backed up';
      case BackupPhase.failed:
        return errorMessage ?? 'Backup failed';
    }
  }

  /// Human-readable upload speed, or null when not applicable.
  String? get speedText {
    if (phase != BackupPhase.running) return null;
    final s = speedBytesPerSec;
    if (s == null || s <= 0) return null;
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB/s';
    return '${(s / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

// ── BackupRunner ───────────────────────────────────────────────────────────────

/// Runs backup jobs in the main isolate so progress callbacks reach the UI.
class BackupRunner {
  BackupRunner._();
  static final BackupRunner instance = BackupRunner._();

  bool _isRunning = false;

  /// Whether a backup is currently in progress.
  bool get isRunning => _isRunning;

  /// Process all [jobs] and fire [onProgress] on every state change.
  ///
  /// Safe to call from a StateNotifier — all exceptions are caught internally
  /// and reported through [onProgress] as [BackupPhase.failed].
  Future<void> runAll({
    required List<BackupJob> jobs,
    required String username,
    required ApiService api,
    required void Function(BackupProgress) onProgress,
  }) async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      // ── Phase 1: scan directories to count total files ─────────────────────
      onProgress(const BackupProgress(phase: BackupPhase.scanning));

      final jobFiles = <String, List<File>>{};
      int totalFiles = 0;

      for (final job in jobs) {
        final dir = Directory(job.phoneFolder);
        if (!dir.existsSync()) continue;

        final allFiles = dir
            .listSync(recursive: false)
            .whereType<File>()
            .where(_isMediaFile)
            .toList();

        final lastSyncAt = job.lastSyncAt;
        final toProcess = lastSyncAt == null
            ? allFiles
            : allFiles.where((f) {
                try {
                  return f.lastModifiedSync().isAfter(lastSyncAt);
                } catch (_) {
                  return true;
                }
              }).toList();

        jobFiles[job.id] = toProcess;
        totalFiles += toProcess.length;
      }

      onProgress(BackupProgress(
        phase: BackupPhase.scanning,
        totalFiles: totalFiles,
      ));

      if (totalFiles == 0) {
        onProgress(const BackupProgress(phase: BackupPhase.done));
        return;
      }

      // ── Phase 2: process each file ─────────────────────────────────────────
      int totalDone = 0;
      int totalUploaded = 0;
      int totalSkipped = 0;
      double? lastSpeed;

      for (final job in jobs) {
        final files = jobFiles[job.id];
        if (files == null || files.isEmpty) continue;

        int jobUploaded = 0;
        int jobSkipped = 0;

        for (final file in files) {
          final filename = file.path.split(RegExp(r'[/\\]')).last;

          onProgress(BackupProgress(
            phase: BackupPhase.running,
            totalFiles: totalFiles,
            doneFiles: totalDone,
            uploadedFiles: totalUploaded,
            skippedFiles: totalSkipped,
            currentFile: filename,
            speedBytesPerSec: lastSpeed,
          ));

          // Compute SHA-256 hash.
          final sha = await _computeSha256(file);

          // Deduplication check.
          bool alreadyBacked = false;
          try {
            alreadyBacked = await api.checkBackupDuplicate(sha, filename);
          } catch (_) {
            totalDone++;
            continue;
          }

          if (alreadyBacked) {
            jobSkipped++;
            totalSkipped++;
            totalDone++;
            continue;
          }

          // Compute NAS destination path.
          final captureDate = BackupBatcher.parseDateFromFilename(filename) ??
              file.lastModifiedSync();
          final batches = BackupBatcher.computeBatches(
            [
              BackupFileInfo(
                path: file.path,
                captureDate: captureDate,
                filename: filename,
              )
            ],
            {},
          );
          final folderName = batches.isNotEmpty
              ? batches.first.folderName
              : _fallbackFolderName(captureDate);

          final nasSubdir = _destinationSubdir(job.destination, username);
          final destPath = '$nasSubdir/$folderName';

          // Upload with speed measurement.
          final fileSize = file.statSync().size;
          final uploadStart = DateTime.now();
          int? statusCode;
          try {
            statusCode =
                await api.uploadBackupFile(file.path, destPath, filename);
          } catch (_) {
            totalDone++;
            continue;
          }

          if (statusCode == 200 || statusCode == 201) {
            final elapsedMs =
                DateTime.now().difference(uploadStart).inMilliseconds;
            if (elapsedMs > 0) {
              lastSpeed = fileSize / (elapsedMs / 1000.0);
            }

            try {
              await api.recordBackupHash(sha, filename, job.destination);
            } catch (_) {
              // Non-critical — dedup will miss this file on the next run.
            }
            jobUploaded++;
            totalUploaded++;
          }

          totalDone++;

          onProgress(BackupProgress(
            phase: BackupPhase.running,
            totalFiles: totalFiles,
            doneFiles: totalDone,
            uploadedFiles: totalUploaded,
            skippedFiles: totalSkipped,
            currentFile: filename,
            speedBytesPerSec: lastSpeed,
          ));
        }

        // Report per-job stats to backend.
        try {
          await api.reportBackupSyncRun(
            job.id,
            jobUploaded,
            jobSkipped,
            DateTime.now().toUtc().toIso8601String(),
          );
        } catch (_) {
          // Non-critical.
        }
      }

      onProgress(BackupProgress(
        phase: BackupPhase.done,
        totalFiles: totalFiles,
        doneFiles: totalDone,
        uploadedFiles: totalUploaded,
        skippedFiles: totalSkipped,
      ));
    } catch (e) {
      onProgress(const BackupProgress(
        phase: BackupPhase.failed,
        errorMessage: 'Backup failed unexpectedly',
      ));
    } finally {
      _isRunning = false;
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

bool _isMediaFile(File f) {
  const mediaExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif',
    'mp4', 'mov', 'avi', 'mkv', '3gp', 'wmv', 'm4v',
  };
  final ext = f.path.split('.').last.toLowerCase();
  return mediaExtensions.contains(ext);
}

/// Maps a [BackupJob.destination] key to a NAS-relative path.
/// The backend's `_safe_resolve()` accepts both `/personal/…` (relative) and
/// `/srv/nas/personal/…` (full), so the relative form is used here.
String _destinationSubdir(String destination, String username) {
  switch (destination) {
    case 'personal':
      return '/personal/$username/Photos';
    case 'family':
      return '/family/Photos';
    case 'entertainment':
      return '/entertainment/Movies';
    default:
      return '/personal/$username/Photos';
  }
}

String _fallbackFolderName(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[d.month - 1]} ${d.year}';
}

Future<String> _computeSha256(File file) async {
  final stream = file.openRead();
  final hash = await sha256.bind(stream).first;
  return hash.toString();
}
