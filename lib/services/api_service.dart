import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

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

  /// Call once after discovery or on app start from saved prefs.
  void configure({required String host, String? token}) {
    _host = host;
    _token = token;
  }

  void setToken(String token) => _token = token;

  String get _baseUrl => 'http://$_host:${CubieConstants.apiPort}';

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

  /// POST /api/pair  body: {serial, key}
  Future<String> pairDevice(String serial, String key) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'serial': serial, 'key': key}),
    );
    _check(res);
    final data = jsonDecode(res.body);
    _token = data['token'];
    return _token!;
  }

  /// POST /api/users  body: {name, pin}
  Future<void> createUser(String name, String? pin) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/users'),
      headers: _headers,
      body: jsonEncode({'name': name, if (pin != null) 'pin': pin}),
    );
    _check(res);
  }

  /// POST /api/auth/logout
  Future<void> logout() async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/auth/logout'),
      headers: _headers,
    );
    _check(res);
    _token = null;
  }

  /// PUT /api/users/pin  body: {oldPin, newPin}
  Future<void> changePin(String? oldPin, String newPin) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/users/pin'),
      headers: _headers,
      body: jsonEncode({'oldPin': oldPin, 'newPin': newPin}),
    );
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SYSTEM / MONITORING
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/system/info
  Future<CubieDevice> getDeviceInfo() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/system/info'),
      headers: _headers,
    );
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
    final uri = Uri.parse('ws://$_host:${CubieConstants.apiPort}/ws/monitor');
    final channel = WebSocketChannel.connect(uri);

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

  /// GET /api/storage/stats
  Future<StorageStats> getStorageStats() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/storage/stats'),
      headers: _headers,
    );
    _check(res);
    final data = jsonDecode(res.body);
    return StorageStats(
      totalGB: (data['totalGB'] as num).toDouble(),
      usedGB: (data['usedGB'] as num).toDouble(),
    );
  }

  /// GET /api/system/firmware
  Future<Map<String, dynamic>> checkFirmwareUpdate() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/system/firmware'),
      headers: _headers,
    );
    _check(res);
    return jsonDecode(res.body);
  }

  /// POST /api/system/update
  Future<void> triggerOtaUpdate() async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/system/update'),
      headers: _headers,
    );
    _check(res);
  }

  /// PUT /api/system/name  body: {name}
  Future<void> updateDeviceName(String name) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/system/name'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FILES
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/files/list?path=<path>
  Future<List<FileItem>> listFiles(String path) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/files/list')
          .replace(queryParameters: {'path': path}),
      headers: _headers,
    );
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

  /// POST /api/files/mkdir  body: {path}
  Future<void> createFolder(String parentPath, String name) async {
    final fullPath =
        parentPath.endsWith('/') ? '$parentPath$name' : '$parentPath/$name';
    final res = await http.post(
      Uri.parse('$_baseUrl/api/files/mkdir'),
      headers: _headers,
      body: jsonEncode({'path': fullPath}),
    );
    _check(res);
  }

  /// DELETE /api/files/delete?path=<path>
  Future<void> deleteFile(String path) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/files/delete')
          .replace(queryParameters: {'path': path}),
      headers: _headers,
    );
    _check(res);
  }

  /// PUT /api/files/rename  body: {oldPath, newName}
  Future<void> renameFile(String path, String newName) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/files/rename'),
      headers: _headers,
      body: jsonEncode({'oldPath': path, 'newName': newName}),
    );
    _check(res);
  }

  /// POST /api/files/upload (multipart)
  /// Returns a stream of uploaded byte counts for progress tracking.
  Stream<int> uploadFile(
      String destinationPath, String fileName, int totalBytes) {
    final ctrl = StreamController<int>();

    () async {
      try {
        final uri = Uri.parse('$_baseUrl/api/files/upload')
            .replace(queryParameters: {'path': destinationPath});

        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $_token';

        // TODO: Replace with real file bytes from file_picker.
        // For now, send dummy bytes matching totalBytes.
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          List.filled(totalBytes, 0),
          filename: fileName,
        ));

        final response = await request.send();
        if (response.statusCode >= 200 && response.statusCode < 300) {
          ctrl.add(totalBytes);
          await ctrl.close();
        } else {
          ctrl.addError(Exception('Upload failed: ${response.statusCode}'));
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

  /// GET /api/users/family
  Future<List<FamilyUser>> getFamilyUsers() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/users/family'),
      headers: _headers,
    );
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

  /// POST /api/users/family  body: {name}
  Future<FamilyUser> addFamilyUser(String name) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/users/family'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
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

  /// DELETE /api/users/family/<id>
  Future<void> removeFamilyUser(String userId) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/users/family/$userId'),
      headers: _headers,
    );
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SERVICES
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/services
  Future<List<ServiceInfo>> getServices() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/services'),
      headers: _headers,
    );
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

  /// POST /api/services/<id>/toggle  body: {enabled}
  Future<void> toggleService(String serviceId, bool enabled) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/services/$serviceId/toggle'),
      headers: _headers,
      body: jsonEncode({'enabled': enabled}),
    );
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
