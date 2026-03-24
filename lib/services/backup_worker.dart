/// WorkManager-based background backup worker.
///
/// Runs every 6 hours (periodic) or on-demand (one-shot).
/// Only executes when on WiFi (unmetered network constraint).
/// Processes each configured backup job:
///   1. Lists media files in the phone folder
///   2. Filters by modified date (fast pre-filter)
///   3. Deduplicates via SHA-256 + backend check-duplicate endpoint
///   4. Uploads new files via the files upload endpoint
///   5. Reports stats to backend
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
    } catch (_) {
      // Silent failure — WorkManager will retry on the next scheduled run.
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

  /// Register the 6-hour periodic backup task (WiFi only).
  Future<void> schedulePeriodicBackup() async {
    await Workmanager().registerPeriodicTask(
      _kPeriodicTaskName,
      _kPeriodicTaskName,
      frequency: const Duration(hours: 6),
      constraints: Constraints(networkType: NetworkType.unmetered),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
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

    for (final job in jobs) {
      await _processJob(
          job, username, baseUrl, headers, client, notifications);
    }
  } finally {
    client.close();
  }
}

Future<void> _processJob(
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
  if (!dir.existsSync()) return;

  // List files directly in the folder (non-recursive — phone camera folders
  // are typically flat).
  final allFiles = dir
      .listSync(recursive: false)
      .whereType<File>()
      .where(_isMediaFile)
      .toList();

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

  if (toProcess.isEmpty) return;

  final nasSubdir = _destinationSubdir(destination, username);
  int uploaded = 0;
  int skipped = 0;
  final total = toProcess.length;

  // Process in batches of 20 to avoid hammering the NAS.
  for (int i = 0; i < toProcess.length; i += 20) {
    final batch = toProcess.skip(i).take(20).toList();
    for (final file in batch) {
      final filename = file.path.split(RegExp(r'[/\\]')).last;
      await _showProgress(notifications, i + 1, total, filename);

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

      final destPath = '$nasSubdir/$folderName';

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

String _destinationSubdir(String destination, String username) {
  switch (destination) {
    case 'personal':
      return '/srv/nas/personal/$username/Photos';
    case 'family':
      return '/srv/nas/family/Photos';
    case 'entertainment':
      return '/srv/nas/entertainment/Movies';
    default:
      return '/srv/nas/personal/$username/Photos';
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
    'Backing up photos',
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
    'Backed up $count ${count == 1 ? 'photo' : 'photos'} to AiHomeCloud',
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
