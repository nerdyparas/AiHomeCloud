/// WorkManager-based background backup worker.
///
/// Runs daily at approximately 2:30 AM (periodic) or on-demand (one-shot).
/// Only executes when on WiFi (unmetered network constraint).
/// Processes each configured backup job:
///   1. Lists all files in the phone folder
///   2. Filters by modified date (fast pre-filter)
///   3. Deduplicates via SHA-256 + backend check-duplicate endpoint
///   4. Categorises files (Photos/Videos/Documents/Audio/Other)
///   5. Uploads new files via the files upload endpoint
///   6. Reports stats to backend
///   7. Sends Telegram notification on failure
///
/// **Top-level [callbackDispatcher] is required by WorkManager — it must be
/// annotated with @pragma('vm:entry-point') so the AOT compiler keeps it.**
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../core/constants.dart';
import 'backup_batcher.dart';

// ── Task name constants ────────────────────────────────────────────────────────

const _kPeriodicTaskName = 'ahc_backup_periodic';
const _kOneShotTaskName = 'ahc_backup_oneshot';

const _kNotificationChannelId = 'ahc_backup';
const _kNotificationChannelName = 'Auto Backup';
const _kProgressNotificationId = 42001;
const _kSummaryNotificationId = 42002;

// ── WorkManager entry point ────────────────────────────────────────────────────

/// Top-level dispatcher called by WorkManager in a background isolate.
/// Must be a top-level function — not a class method.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await _runAllJobs();
    } catch (e) {
      // Send Telegram failure notification for scheduled backups.
      try {
        await _sendTelegramNotification(
          success: false,
          errorMessage: 'Scheduled backup failed: $e',
        );
      } catch (_) {}
    }
    return true;
  });
}

// ── BackupWorker public API ───────────────────────────────────────────────────

/// Manages WorkManager task registration and scheduling.
class BackupWorker {
  BackupWorker._();
  static final BackupWorker instance = BackupWorker._();

  /// Initialise WorkManager with the top-level [callbackDispatcher].
  /// Call once from main() after WidgetsFlutterBinding.ensureInitialized().
  Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Register a daily backup task targeting ~2:30 AM (WiFi only).
  Future<void> schedulePeriodicBackup() async {
    // Compute initial delay so the first run targets 2:30 AM.
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, 2, 30);
    if (target.isBefore(now)) target = target.add(const Duration(days: 1));
    final delay = target.difference(now);

    await Workmanager().registerPeriodicTask(
      _kPeriodicTaskName,
      _kPeriodicTaskName,
      frequency: const Duration(hours: 24),
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.unmetered),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// Trigger an immediate backup run (WiFi only constraint still applies).
  Future<void> triggerImmediate() async {
    await Workmanager().registerOneOffTask(
      _kOneShotTaskName,
      _kOneShotTaskName,
      constraints: Constraints(networkType: NetworkType.unmetered),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Cancel all scheduled backup tasks.
  Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}

// ── Core worker logic (runs in background isolate) ───────────────────────────

Future<void> _runAllJobs() async {
  final prefs = await SharedPreferences.getInstance();
  final host = prefs.getString(AppConstants.prefDeviceIp);
  final port =
      prefs.getInt(AppConstants.prefDevicePort) ?? AppConstants.apiPort;
  final token = prefs.getString(AppConstants.prefAuthToken);
  final username = prefs.getString(AppConstants.prefUserName) ?? '';

  if (host == null || host.isEmpty || token == null || token.isEmpty) return;

  final client = _buildHttpClient();
  final baseUrl = '${AppConstants.apiScheme}://$host:$port';
  final headers = {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  try {
    // Fetch configured jobs
    final statusRes = await client
        .get(
          Uri.parse('$baseUrl${AppConstants.apiVersion}/backup/status'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));

    if (statusRes.statusCode != 200) return;

    final statusBody =
        jsonDecode(statusRes.body) as Map<String, dynamic>;
    final jobs = (statusBody['jobs'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    if (jobs.isEmpty) return;

    final notifications = FlutterLocalNotificationsPlugin();
    await _initNotifications(notifications);

    int inaccessibleCount = 0;
    for (final job in jobs) {
      final accessible = await _processJob(
          job, username, baseUrl, headers, client, notifications);
      if (!accessible) inaccessibleCount++;
    }

    // Send one Telegram failure notification if any folder was unreadable.
    if (inaccessibleCount > 0) {
      try {
        await _sendTelegramNotification(
          success: false,
          folders: jobs.length,
          errorMessage:
              'Backup failed: cannot access $inaccessibleCount phone '
              'folder${inaccessibleCount == 1 ? '' : 's'}. '
              'Open the app and check storage permissions.',
        );
      } catch (_) {}
    }
  } finally {
    client.close();
  }
}

/// Returns true if the phone folder was accessible, false if it could not be read.
Future<bool> _processJob(
  Map<String, dynamic> job,
  String username,
  String baseUrl,
  Map<String, String> headers,
  http.Client client,
  FlutterLocalNotificationsPlugin notifications,
) async {
  final jobId = job['id'] as String;
  final phoneFolder = job['phoneFolder'] as String;
  final destination = job['destination'] as String;
  final lastSyncAtStr = job['lastSyncAt'] as String?;
  final lastSyncAt =
      lastSyncAtStr != null ? DateTime.tryParse(lastSyncAtStr) : null;

  final dir = Directory(phoneFolder);
  if (!dir.existsSync()) return false;

  // List all files recursively (matches BackupRunner behaviour).
  List<File> allFiles;
  try {
    allFiles = dir
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
  } catch (_) {
    // Permission denied — scoped storage blocked the listing.
    return false;
  }

  // Fast pre-filter by modification date before computing any SHA-256.
  final toProcess = lastSyncAt == null
      ? allFiles
      : allFiles.where((f) {
          try {
            return f.lastModifiedSync().isAfter(lastSyncAt);
          } catch (_) {
            return true;
          }
        }).toList();

  if (toProcess.isEmpty) {
    // Still update lastSyncAt so the job card shows when the last check ran.
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await client
          .post(
            Uri.parse(
                '$baseUrl${AppConstants.apiVersion}/backup/jobs/$jobId/report'),
            headers: headers,
            body: jsonEncode({
              'uploaded': 0,
              'skipped': 0,
              'lastSyncAt': now,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
    return true;
  }

  final nasSubdir = _destinationSubdir(destination, username);
  int uploaded = 0;
  int skipped = 0;
  final total = toProcess.length;

  // Process in batches of 20 to avoid hammering the NAS.
  int fileIndex = 0;
  for (int i = 0; i < toProcess.length; i += 20) {
    final batch = toProcess.skip(i).take(20).toList();
    for (final file in batch) {
      fileIndex++;
      final filename = file.path.split(RegExp(r'[/\\]')).last;
      await _showProgress(notifications, fileIndex, total, filename);

      final sha = await _computeSha256(file);

      // Check for duplicate
      try {
        final dupRes = await client
            .post(
              Uri.parse(
                  '$baseUrl${AppConstants.apiVersion}/backup/check-duplicate'),
              headers: headers,
              body: jsonEncode({'sha256': sha, 'filename': filename}),
            )
            .timeout(const Duration(seconds: 15));

        if (dupRes.statusCode == 200) {
          final dupBody = jsonDecode(dupRes.body) as Map<String, dynamic>;
          if (dupBody['exists'] == true) {
            skipped++;
            continue;
          }
        }
      } catch (_) {
        continue; // Network error — skip file this run
      }

      // Determine target folder name using the batcher
      final captureDate =
          BackupBatcher.parseDateFromFilename(filename) ??
              file.lastModifiedSync();
      final batches = BackupBatcher.computeBatches(
        [BackupFileInfo(path: file.path, captureDate: captureDate, filename: filename)],
        {},
      );
      final folderName = batches.isNotEmpty
          ? batches.first.folderName
          : _fallbackFolderName(captureDate);

      final category = _categoryOf(filename);
      final destPath = '$nasSubdir/$category/$folderName';

      // Upload the file
      try {
        final uri =
            Uri.parse('$baseUrl${AppConstants.apiVersion}/files/upload')
                .replace(queryParameters: {'path': destPath});
        final request = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = headers['Authorization']!;
        request.files
            .add(await http.MultipartFile.fromPath('file', file.path,
                filename: filename));

        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 120));

        if (streamed.statusCode == 200 || streamed.statusCode == 201) {
          // Record the hash so future runs skip this file
          await client
              .post(
                Uri.parse(
                    '$baseUrl${AppConstants.apiVersion}/backup/record-hash'),
                headers: headers,
                body: jsonEncode({
                  'sha256': sha,
                  'filename': filename,
                  'destination': destination,
                }),
              )
              .timeout(const Duration(seconds: 15));
          uploaded++;
        }
      } catch (_) {
        // Upload error — skip this file; it will be retried next run
      }
    }
  }

  // Dismiss progress notification
  await notifications.cancel(_kProgressNotificationId);

  // Report results to the backend
  final now = DateTime.now().toUtc().toIso8601String();
  try {
    await client
        .post(
          Uri.parse(
              '$baseUrl${AppConstants.apiVersion}/backup/jobs/$jobId/report'),
          headers: headers,
          body: jsonEncode({
            'uploaded': uploaded,
            'skipped': skipped,
            'lastSyncAt': now,
          }),
        )
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    // Non-critical — stats will be out of date but the files were uploaded.
  }

  if (uploaded > 0) {
    await _showSummary(notifications, uploaded);
  }
  return true;
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

/// Build an HTTP client that trusts self-signed certificates (same as the
/// app-wide _CubieHttpOverrides in main.dart).
http.Client _buildHttpClient() {
  final context = SecurityContext(withTrustedRoots: true);
  final inner = HttpClient(context: context)
    ..badCertificateCallback = (cert, host, port) => true;
  inner.connectionTimeout = const Duration(seconds: 10);
  return IOClient(inner);
}

Future<void> _initNotifications(
    FlutterLocalNotificationsPlugin notifications) async {
  const androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifications.initialize(
      const InitializationSettings(android: androidInit));
}

Future<void> _showProgress(
  FlutterLocalNotificationsPlugin notifications,
  int current,
  int total,
  String filename,
) async {
  await notifications.show(
    _kProgressNotificationId,
    'Backing up files',
    '$current of $total — $filename',
    NotificationDetails(
      android: AndroidNotificationDetails(
        _kNotificationChannelId,
        _kNotificationChannelName,
        channelDescription: 'AiHomeCloud auto backup progress',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        showProgress: true,
        maxProgress: total,
        progress: current,
        onlyAlertOnce: true,
      ),
    ),
  );
}

Future<void> _showSummary(
    FlutterLocalNotificationsPlugin notifications, int count) async {
  await notifications.show(
    _kSummaryNotificationId,
    'Backup complete',
    'Backed up $count ${count == 1 ? 'file' : 'files'} to AiHomeCloud',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _kNotificationChannelId,
        _kNotificationChannelName,
        channelDescription: 'AiHomeCloud auto backup progress',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    ),
  );
}

/// Send a backup notification via the Telegram bot (best-effort).
Future<void> _sendTelegramNotification({
  required bool success,
  int uploaded = 0,
  int skipped = 0,
  int folders = 0,
  String errorMessage = '',
}) async {
  final prefs = await SharedPreferences.getInstance();
  final host = prefs.getString(AppConstants.prefDeviceIp);
  final port =
      prefs.getInt(AppConstants.prefDevicePort) ?? AppConstants.apiPort;
  final token = prefs.getString(AppConstants.prefAuthToken);

  if (host == null || host.isEmpty || token == null || token.isEmpty) return;

  final client = _buildHttpClient();
  try {
    await client
        .post(
          Uri.parse(
              '${AppConstants.apiScheme}://$host:$port${AppConstants.apiVersion}/backup/notify'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'success': success,
            'uploaded': uploaded,
            'skipped': skipped,
            'folders': folders,
            'error_message': errorMessage,
          }),
        )
        .timeout(const Duration(seconds: 15));
  } finally {
    client.close();
  }
}
