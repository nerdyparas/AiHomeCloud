part of '../api_service.dart';

/// Backup API — phone-to-NAS auto backup endpoints.
extension BackupApi on ApiService {
  /// POST /api/v1/backup/check-duplicate
  /// Returns true if the SHA-256 hash is already recorded (file already backed up).
  Future<bool> checkBackupDuplicate(String sha256, String filename) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/backup/check-duplicate'),
            headers: _headers,
            body: jsonEncode({'sha256': sha256, 'filename': filename}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['exists'] as bool;
  }

  /// POST /api/v1/backup/record-hash
  /// Records the hash after a successful upload so future syncs skip the file.
  Future<void> recordBackupHash(
      String sha256, String filename, String destination) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/backup/record-hash'),
            headers: _headers,
            body: jsonEncode({
              'sha256': sha256,
              'filename': filename,
              'destination': destination,
            }),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// GET /api/v1/backup/status
  /// Returns current backup configuration and per-job stats.
  Future<BackupStatus> getBackupStatus() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/backup/status'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return BackupStatus.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /api/v1/backup/jobs
  /// Creates a new backup job (phone folder → NAS destination mapping).
  Future<BackupJob> createBackupJob(
      String phoneFolder, String destination) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/backup/jobs'),
            headers: _headers,
            body: jsonEncode({
              'phoneFolder': phoneFolder,
              'destination': destination,
            }),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return BackupJob.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// DELETE /api/v1/backup/jobs/{jobId}
  /// Removes a backup job configuration.
  Future<void> deleteBackupJob(String jobId) async {
    final res = await _withAutoRefresh(
      () => _client
          .delete(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/backup/jobs/$jobId'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// POST /api/v1/backup/jobs/{jobId}/report
  /// Updates job stats after a completed sync run.
  Future<void> reportBackupSyncRun(
    String jobId,
    int uploaded,
    int skipped,
    String lastSyncAt,
  ) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/backup/jobs/$jobId/report'),
            headers: _headers,
            body: jsonEncode({
              'uploaded': uploaded,
              'skipped': skipped,
              'lastSyncAt': lastSyncAt,
            }),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// POST /api/v1/files/upload?path=<destPath>
  /// Uploads a single file to the NAS for backup.
  /// Returns the HTTP status code (200 or 201 = success).
  Future<int> uploadBackupFile(
    String localPath,
    String destPath,
    String filename,
  ) async {
    final uri =
        Uri.parse('$_baseUrl${AppConstants.apiVersion}/files/upload')
            .replace(queryParameters: {'path': destPath});

    Future<http.Response> makeRequest() async {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = _headers['Authorization'] ?? '';
      request.files.add(
        await http.MultipartFile.fromPath('file', localPath,
            filename: filename),
      );
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 120));
      return http.Response.fromStream(streamed);
    }

    final res = await _withAutoRefresh(makeRequest);
    return res.statusCode;
  }

  /// POST /api/v1/backup/notify
  /// Send a backup summary or failure notification via the Telegram bot.
  Future<void> sendBackupNotification({
    required bool success,
    int uploaded = 0,
    int skipped = 0,
    int folders = 0,
    String errorMessage = '',
  }) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/backup/notify'),
            headers: _headers,
            body: jsonEncode({
              'success': success,
              'uploaded': uploaded,
              'skipped': skipped,
              'folders': folders,
              'error_message': errorMessage,
            }),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }
}
