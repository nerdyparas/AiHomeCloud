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
        return 'Backing up $doneFiles of $totalFiles';
      case BackupPhase.done:
        if (uploadedFiles == 0 && skippedFiles == 0) {
          return 'No new files to back up';
        }
        if (uploadedFiles == 0) {
          return 'All caught up — $skippedFiles ${skippedFiles == 1 ? 'file' : 'files'} checked';
        }
        if (skippedFiles > 0) {
          return '$uploadedFiles backed up · $skippedFiles already synced';
        }
        return '$uploadedFiles ${uploadedFiles == 1 ? 'file' : 'files'} backed up';
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
  bool _cancelled = false;

  /// Whether a backup is currently in progress.
  bool get isRunning => _isRunning;

  /// Request cancellation of the current run.
  void cancel() {
    if (_isRunning) _cancelled = true;
  }

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
    _cancelled = false;

    try {
      // ── Phase 1: scan directories to count total files ─────────────────────
      onProgress(const BackupProgress(phase: BackupPhase.scanning));

      final jobFiles = <String, List<File>>{};
      int totalFiles = 0;
      int accessibleDirs = 0;

      for (final job in jobs) {
        final dir = Directory(job.phoneFolder);
        if (!dir.existsSync()) continue;
        accessibleDirs++;

        final allFiles = dir
            .listSync(recursive: true)
            .whereType<File>()
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

      if (accessibleDirs == 0) {
        onProgress(const BackupProgress(
          phase: BackupPhase.failed,
          errorMessage:
              'Could not read backup folders — check app storage permissions',
        ));
        return;
      }

      if (totalFiles == 0) {
        // Nothing new — still record the sync time so the card updates.
        final now = DateTime.now().toUtc().toIso8601String();
        for (final job in jobs) {
          try {
            await api.reportBackupSyncRun(job.id, 0, 0, now);
          } catch (_) {}
        }
        onProgress(const BackupProgress(phase: BackupPhase.done));

        // Notify via Telegram even when nothing new.
        try {
          await api.sendBackupNotification(
            success: true,
            uploaded: 0,
            skipped: 0,
            folders: jobs.length,
          );
        } catch (_) {}
        return;
      }

      // ── Phase 2: process each file ─────────────────────────────────────────
      int totalDone = 0;
      int totalUploaded = 0;
      int totalSkipped = 0;
      int totalBytesTransferred = 0;
      int totalTransferTimeMs = 0;
      double? avgSpeed;

      for (final job in jobs) {
        final files = jobFiles[job.id];
        if (files == null || files.isEmpty) continue;

        int jobUploaded = 0;
        int jobSkipped = 0;

        for (final file in files) {
          if (_cancelled) break;
          final filename = file.path.split(RegExp(r'[/\\]')).last;

          onProgress(BackupProgress(
            phase: BackupPhase.running,
            totalFiles: totalFiles,
            doneFiles: totalDone,
            uploadedFiles: totalUploaded,
            skippedFiles: totalSkipped,
            currentFile: filename,
            speedBytesPerSec: avgSpeed,
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
          final category = _categoryOf(filename);
          final destPath = '$nasSubdir/$category/$folderName';

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
              totalBytesTransferred += fileSize;
              totalTransferTimeMs += elapsedMs;
              avgSpeed =
                  totalBytesTransferred / (totalTransferTimeMs / 1000.0);
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
            speedBytesPerSec: avgSpeed,
          ));
        }

        // Check cancellation between jobs.
        if (_cancelled) break;

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

      if (_cancelled) {
        onProgress(BackupProgress(
          phase: BackupPhase.failed,
          totalFiles: totalFiles,
          doneFiles: totalDone,
          uploadedFiles: totalUploaded,
          skippedFiles: totalSkipped,
          errorMessage: totalUploaded > 0
              ? 'Cancelled — $totalUploaded files backed up'
              : 'Backup cancelled',
        ));

        // Notify partial results on cancel.
        try {
          await api.sendBackupNotification(
            success: false,
            uploaded: totalUploaded,
            skipped: totalSkipped,
            folders: jobs.length,
            errorMessage: 'Backup cancelled by user',
          );
        } catch (_) {}
        return;
      }

      onProgress(BackupProgress(
        phase: BackupPhase.done,
        totalFiles: totalFiles,
        doneFiles: totalDone,
        uploadedFiles: totalUploaded,
        skippedFiles: totalSkipped,
      ));

      // Send Telegram notification for manual backup summary.
      try {
        await api.sendBackupNotification(
          success: true,
          uploaded: totalUploaded,
          skipped: totalSkipped,
          folders: jobs.length,
        );
      } catch (_) {
        // Non-critical — notification failure should not affect backup result.
      }
    } catch (e) {
      onProgress(const BackupProgress(
        phase: BackupPhase.failed,
        errorMessage: 'Backup failed unexpectedly',
      ));

      // Notify failure via Telegram.
      try {
        await api.sendBackupNotification(
          success: false,
          folders: jobs.length,
          errorMessage: 'Backup failed unexpectedly',
        );
      } catch (_) {}
    } finally {
      _isRunning = false;
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Categorise a file by extension into one of five NAS sub-folders.
String _categoryOf(String filename) {
  const photoExts = {
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif',
    'raw', 'cr2', 'nef', 'arw', 'dng',
  };
  const videoExts = {
    'mp4', 'mov', 'avi', 'mkv', '3gp', 'wmv', 'm4v', 'webm',
  };
  const docExts = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'txt', 'csv', 'rtf', 'odt', 'ods', 'odp',
  };
  const audioExts = {
    'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus',
  };
  final ext = filename.split('.').last.toLowerCase();
  if (photoExts.contains(ext)) return 'Photos';
  if (videoExts.contains(ext)) return 'Videos';
  if (docExts.contains(ext)) return 'Documents';
  if (audioExts.contains(ext)) return 'Audio';
  return 'Other';
}

/// Maps a [BackupJob.destination] key to a NAS-relative path.
/// Category sub-folder (Photos/Videos/…) is appended by the caller.
String _destinationSubdir(String destination, String username) {
  switch (destination) {
    case 'personal':
      return '/personal/$username';
    case 'family':
      return '/family';
    default:
      return '/personal/$username';
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
