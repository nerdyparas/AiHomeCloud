part of '../api_service.dart';

/// Storage operations â€” device listing, scan, format, mount/unmount, eject, stats.
extension StorageApi on ApiService {
  /// GET /api/v1/storage/stats
  Future<StorageStats> getStorageStats() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/stats'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final data = jsonDecode(res.body);
    return StorageStats(
      totalGB: (data['totalGB'] as num).toDouble(),
      usedGB: (data['usedGB'] as num).toDouble(),
    );
  }

  /// GET /api/v1/storage/devices
  Future<List<StorageDevice>> getStorageDevices() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/devices'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) => StorageDevice.fromJson(item)).toList();
  }

  /// GET /api/v1/storage/scan â€” re-scan for newly connected devices
  Future<List<StorageDevice>> scanDevices() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/scan'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15)),
    );
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) => StorageDevice.fromJson(item)).toList();
  }

  /// POST /api/v1/storage/format  body: {device, label, confirmDevice}
  Future<Map<String, dynamic>> startFormatJob(
      String device, String label, String confirmDevice) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/format'),
            headers: _headers,
            body: jsonEncode({
              'device': device,
              'label': label,
              'confirmDevice': confirmDevice,
            }),
          )
          .timeout(const Duration(seconds: 120)),
    );
    _check(res);
    return jsonDecode(res.body);
  }

  /// GET /api/v1/jobs/<id>
  Future<JobStatus> getJobStatus(String jobId) async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/jobs/$jobId'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return JobStatus.fromJson(jsonDecode(res.body));
  }

  /// POST /api/v1/storage/mount  body: {device}
  Future<Map<String, dynamic>> mountDevice(String device) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/mount'),
            headers: _headers,
            body: jsonEncode({'device': device}),
          )
          .timeout(const Duration(seconds: 30)),
    );
    _check(res);
    return jsonDecode(res.body);
  }

  /// POST /api/v1/storage/unmount?force=<bool>
  Future<Map<String, dynamic>> unmountDevice({bool force = false}) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${CubieConstants.apiVersion}/storage/unmount?force=$force'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30)),
    );
    _check(res);
    return jsonDecode(res.body);
  }

  /// POST /api/v1/storage/eject  body: {device}
  Future<Map<String, dynamic>> ejectDevice(String device) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/eject'),
            headers: _headers,
            body: jsonEncode({'device': device}),
          )
          .timeout(const Duration(seconds: 30)),
    );
    _check(res);
    return jsonDecode(res.body);
  }

  /// GET /api/v1/storage/check-usage â€” pre-unmount blocker check
  Future<Map<String, dynamic>> checkStorageUsage() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse(
                '$_baseUrl${CubieConstants.apiVersion}/storage/check-usage'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return jsonDecode(res.body);
  }
}
