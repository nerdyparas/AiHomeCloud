import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';

import '../core/constants.dart';
import '../models/models.dart';

/// Real API service — talks to the CubieCloud backend running on the device.
///
/// Drop-in replacement for MockApiService. Every method has the same signature
/// so screens don't need to change.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  /// Set after pairing / loaded from SharedPreferences.
  String? _host;
  String? _token;

  /// HTTP client that trusts self-signed certificates.
  late final http.Client _client = _createTlsClient();

  static http.Client _createTlsClient() {
    final context = SecurityContext(withTrustedRoots: true);
    final httpClient = HttpClient(context: context)
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(httpClient);
  }

  /// Call once after discovery or on app start from saved prefs.
  void configure({required String host, String? token}) {
    _host = host;
    _token = token;
  }

  void setToken(String token) => _token = token;

  /// Connection timeout for all HTTP requests.
  static const _timeout = Duration(seconds: 10);

  String get _baseUrl => 'https://$_host:${CubieConstants.apiPort}';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Throws on non-2xx responses with the server error detail.
  void _check(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String msg;
    try {
      final body = jsonDecode(res.body);
      msg = body['detail'] ?? res.body;
    } catch (_) {
      msg = res.body;
    }
    throw Exception(msg);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // AUTH
  // ──────────────────────────────────────────────────────────────────────────

  /// POST /api/v1/pair  body: {serial, key}
  Future<String> pairDevice(String serial, String key) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'serial': serial, 'key': key}),
    ).timeout(_timeout);
    _check(res);
    final data = jsonDecode(res.body);
    _token = data['token'];
    return _token!;
  }

  /// POST /api/v1/users  body: {name, pin}
  Future<void> createUser(String name, String? pin) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users'),
      headers: _headers,
      body: jsonEncode({'name': name, if (pin != null) 'pin': pin}),
    ).timeout(_timeout);
    _check(res);
  }

  /// POST /api/v1/auth/logout
  Future<void> logout() async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/auth/logout'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    _token = null;
  }

  /// PUT /api/v1/users/pin  body: {oldPin, newPin}
  Future<void> changePin(String? oldPin, String newPin) async {
    final res = await _client.put(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/pin'),
      headers: _headers,
      body: jsonEncode({'oldPin': oldPin, 'newPin': newPin}),
    ).timeout(_timeout);
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SYSTEM / MONITORING
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/v1/system/info
  Future<CubieDevice> getDeviceInfo() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/system/info'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    final data = jsonDecode(res.body);
    return CubieDevice(
      serial: data['serial'],
      name: data['name'],
      ip: data['ip'],
      firmwareVersion: data['firmwareVersion'],
    );
  }

  /// WebSocket /ws/monitor — streams SystemStats every 2 s.
  Stream<SystemStats> monitorSystemStats() {
    final uri = Uri.parse('wss://$_host:${CubieConstants.apiPort}/ws/monitor');
    final channel = IOWebSocketChannel.connect(
      uri,
      customClient: HttpClient()..badCertificateCallback = (_, __, ___) => true,
    );

    return channel.stream.map((raw) {
      final data = jsonDecode(raw as String);
      return SystemStats(
        cpuPercent: (data['cpuPercent'] as num).toDouble(),
        ramPercent: (data['ramPercent'] as num).toDouble(),
        tempCelsius: (data['tempCelsius'] as num).toDouble(),
        uptime: Duration(seconds: data['uptimeSeconds'] as int),
        networkUpMbps: (data['networkUpMbps'] as num).toDouble(),
        networkDownMbps: (data['networkDownMbps'] as num).toDouble(),
        storage: StorageStats(
          totalGB: (data['storage']['totalGB'] as num).toDouble(),
          usedGB: (data['storage']['usedGB'] as num).toDouble(),
        ),
      );
    });
  }

  /// WebSocket /ws/events — real-time notification stream from the backend.
  Stream<AppNotification> notificationStream() {
    final uri = Uri.parse('wss://$_host:${CubieConstants.apiPort}/ws/events');
    final channel = IOWebSocketChannel.connect(
      uri,
      customClient: HttpClient()..badCertificateCallback = (_, __, ___) => true,
    );

    return channel.stream.map((raw) {
      final data = jsonDecode(raw as String);
      return AppNotification.fromJson(data);
    });
  }

  /// GET /api/v1/storage/stats
  Future<StorageStats> getStorageStats() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/stats'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    final data = jsonDecode(res.body);
    return StorageStats(
      totalGB: (data['totalGB'] as num).toDouble(),
      usedGB: (data['usedGB'] as num).toDouble(),
    );
  }

  /// GET /api/v1/storage/devices
  Future<List<StorageDevice>> getStorageDevices() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/devices'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) => StorageDevice.fromJson(item)).toList();
  }

  /// GET /api/v1/storage/scan — re-scan for newly connected devices
  Future<List<StorageDevice>> scanDevices() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/scan'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) => StorageDevice.fromJson(item)).toList();
  }

  /// POST /api/v1/storage/format  body: {device, label, confirmDevice}
  Future<Map<String, dynamic>> formatDevice(
      String device, String label, String confirmDevice) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/format'),
      headers: _headers,
      body: jsonEncode({
        'device': device,
        'label': label,
        'confirmDevice': confirmDevice,
      }),
    ).timeout(const Duration(seconds: 120));
    _check(res);
    return jsonDecode(res.body);
  }

  /// POST /api/v1/storage/mount  body: {device}
  Future<Map<String, dynamic>> mountDevice(String device) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/mount'),
      headers: _headers,
      body: jsonEncode({'device': device}),
    ).timeout(const Duration(seconds: 30));
    _check(res);
    return jsonDecode(res.body);
  }

  /// POST /api/v1/storage/unmount?force=<bool>
  Future<Map<String, dynamic>> unmountDevice({bool force = false}) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/unmount?force=$force'),
      headers: _headers,
    ).timeout(const Duration(seconds: 30));
    _check(res);
    return jsonDecode(res.body);
  }

  /// POST /api/v1/storage/eject  body: {device}
  Future<Map<String, dynamic>> ejectDevice(String device) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/eject'),
      headers: _headers,
      body: jsonEncode({'device': device}),
    ).timeout(const Duration(seconds: 30));
    _check(res);
    return jsonDecode(res.body);
  }

  /// GET /api/v1/storage/check-usage — pre-unmount blocker check
  Future<Map<String, dynamic>> checkStorageUsage() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/check-usage'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    return jsonDecode(res.body);
  }

  /// GET /api/v1/system/firmware
  Future<Map<String, dynamic>> checkFirmwareUpdate() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/system/firmware'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    return jsonDecode(res.body);
  }

  /// POST /api/v1/system/update
  Future<void> triggerOtaUpdate() async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/system/update'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
  }

  /// PUT /api/v1/system/name  body: {name}
  Future<void> updateDeviceName(String name) async {
    final res = await _client.put(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/system/name'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    ).timeout(_timeout);
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FILES
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/v1/files/list?path=<path>
  Future<List<FileItem>> listFiles(String path) async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/list')
          .replace(queryParameters: {'path': path}),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) {
      return FileItem(
        name: item['name'],
        path: item['path'],
        isDirectory: item['isDirectory'] as bool,
        sizeBytes: item['sizeBytes'] as int,
        modified: DateTime.parse(item['modified']),
        mimeType: item['mimeType'],
      );
    }).toList();
  }

  /// POST /api/v1/files/mkdir  body: {path}
  Future<void> createFolder(String parentPath, String name) async {
    final fullPath =
        parentPath.endsWith('/') ? '$parentPath$name' : '$parentPath/$name';
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/mkdir'),
      headers: _headers,
      body: jsonEncode({'path': fullPath}),
    ).timeout(_timeout);
    _check(res);
  }

  /// DELETE /api/v1/files/delete?path=<path>
  Future<void> deleteFile(String path) async {
    final res = await _client.delete(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/delete')
          .replace(queryParameters: {'path': path}),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
  }

  /// PUT /api/v1/files/rename  body: {oldPath, newName}
  Future<void> renameFile(String path, String newName) async {
    final res = await _client.put(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/rename'),
      headers: _headers,
      body: jsonEncode({'oldPath': path, 'newName': newName}),
    ).timeout(_timeout);
    _check(res);
  }

  /// GET /api/v1/files/download?path=...
  /// Returns the raw file bytes for saving or previewing.
  Future<http.Response> downloadFile(String filePath) async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/download')
          .replace(queryParameters: {'path': filePath}),
      headers: _headers,
    ).timeout(const Duration(seconds: 60));
    _check(res);
    return res;
  }

  /// Returns the download URL for a file (for image display etc.)
  String getDownloadUrl(String filePath) {
    return '$_baseUrl${CubieConstants.apiVersion}/files/download?path=${Uri.encodeComponent(filePath)}';
  }

  /// Returns auth headers for use in image widgets.
  Map<String, String> get authHeaders => _headers;

  /// POST /api/v1/files/upload (multipart)
  /// Uploads a real file from [filePath] to [destinationPath] on the NAS.
  /// Returns a stream of uploaded byte counts for progress tracking.
  Stream<int> uploadFile(
      String destinationPath, String fileName, int totalBytes,
      {String? filePath}) {
    final ctrl = StreamController<int>();

    () async {
      try {
        final uri = Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/upload')
            .replace(queryParameters: {'path': destinationPath});

        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $_token';

        if (filePath != null) {
          // Real file from device
          request.files.add(
            await http.MultipartFile.fromPath('file', filePath,
                filename: fileName),
          );
        } else {
          // Fallback: empty bytes (shouldn't happen in production)
          request.files.add(http.MultipartFile.fromBytes(
            'file',
            [],
            filename: fileName,
          ));
        }

        final response = await _client.send(request);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          ctrl.add(totalBytes);
          await ctrl.close();
        } else {
          ctrl.addError(Exception('Upload failed: \${response.statusCode}'));
          await ctrl.close();
        }
      } catch (e) {
        ctrl.addError(e);
        await ctrl.close();
      }
    }();

    return ctrl.stream;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FAMILY / USERS
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/v1/users/family
  Future<List<FamilyUser>> getFamilyUsers() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/family'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) {
      // Parse hex colour string from backend (e.g. "FFE8A84C")
      final colorHex = item['avatarColor'] as String;
      final colorValue = int.parse(colorHex, radix: 16);

      return FamilyUser(
        id: item['id'],
        name: item['name'],
        isAdmin: item['isAdmin'] as bool,
        folderSizeGB: (item['folderSizeGB'] as num).toDouble(),
        avatarColor: Color(colorValue),
      );
    }).toList();
  }

  /// POST /api/v1/users/family  body: {name}
  Future<FamilyUser> addFamilyUser(String name) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/family'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    ).timeout(_timeout);
    _check(res);
    final item = jsonDecode(res.body);
    final colorHex = item['avatarColor'] as String;
    final colorValue = int.parse(colorHex, radix: 16);

    return FamilyUser(
      id: item['id'],
      name: item['name'],
      isAdmin: item['isAdmin'] as bool,
      folderSizeGB: (item['folderSizeGB'] as num).toDouble(),
      avatarColor: Color(colorValue),
    );
  }

  /// DELETE /api/v1/users/family/<id>
  Future<void> removeFamilyUser(String userId) async {
    final res = await _client.delete(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/family/$userId'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SERVICES
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/v1/services
  Future<List<ServiceInfo>> getServices() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/services'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) {
      return ServiceInfo(
        id: item['id'],
        name: item['name'],
        description: item['description'],
        isEnabled: item['isEnabled'] as bool,
        icon: _serviceIcon(item['id']),
      );
    }).toList();
  }

  /// POST /api/v1/services/<id>/toggle  body: {enabled}
  Future<void> toggleService(String serviceId, bool enabled) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/services/$serviceId/toggle'),
      headers: _headers,
      body: jsonEncode({'enabled': enabled}),
    ).timeout(_timeout);
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // NETWORK
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/v1/network/status
  Future<NetworkStatus> getNetworkStatus() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/network/status'),
      headers: _headers,
    ).timeout(_timeout);
    _check(res);
    return NetworkStatus.fromJson(jsonDecode(res.body));
  }

  /// POST /api/v1/network/wifi  body: {enabled}
  Future<void> toggleWifi(bool enabled) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/network/wifi'),
      headers: _headers,
      body: jsonEncode({'enabled': enabled}),
    ).timeout(_timeout);
    _check(res);
  }

  /// POST /api/v1/network/hotspot  body: {enabled}
  Future<void> toggleHotspot(bool enabled) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/network/hotspot'),
      headers: _headers,
      body: jsonEncode({'enabled': enabled}),
    ).timeout(const Duration(seconds: 15));
    _check(res);
  }

  /// POST /api/v1/network/bluetooth  body: {enabled}
  Future<void> toggleBluetooth(bool enabled) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl${CubieConstants.apiVersion}/network/bluetooth'),
      headers: _headers,
      body: jsonEncode({'enabled': enabled}),
    ).timeout(_timeout);
    _check(res);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Map service IDs to Material icons (backend doesn't send icons).
  static IconData _serviceIcon(String id) {
    return switch (id) {
      'samba' => Icons.desktop_windows_rounded,
      'nfs' => Icons.dns_rounded,
      'ssh' => Icons.terminal_rounded,
      'dlna' => Icons.tv_rounded,
      _ => Icons.miscellaneous_services_rounded,
    };
  }
}
