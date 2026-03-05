import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';

import '../core/constants.dart';
import '../models/models.dart';
import 'auth_session.dart';

/// Real API service — talks to the CubieCloud backend running on the device.
///
/// Drop-in replacement for MockApiService. Every method has the same signature
/// so screens don't need to change.
class ApiService {
  ApiService._() {
    _initHttpClient();
  }
  static final ApiService instance = ApiService._();

  AuthSession? Function()? _sessionResolver;
  void Function(ConnectionStatus status)? _connectionStatusCallback;
  Future<void> Function(String token)? _tokenUpdatedCallback;
  bool _isRefreshing = false;
  Future<void>? _refreshFuture;

  String? _trustedFingerprint;
  late final HttpClient _httpClient;
  late final http.Client _client;

  /// Initialize TLS HTTP client. By default trusts any cert until a fingerprint
  /// is set via `setTrustedFingerprint`.
  void _initHttpClient() {
    _httpClient = _createPinnedHttpClient();
    _client = IOClient(_httpClient);
  }

  HttpClient _createPinnedHttpClient() {
    final context = SecurityContext(withTrustedRoots: true);
    final httpClient = HttpClient(context: context);
    httpClient.badCertificateCallback = (cert, host, port) =>
        _trustedFingerprint == null ? true : _validateCertFingerprint(cert);
    return httpClient;
  }

  // Note: _createTlsClient is kept commented for potential future TLS implementation
  // static http.Client _createTlsClient() {
  //   final context = SecurityContext(withTrustedRoots: true);
  //   final httpClient = HttpClient(context: context)
  //     ..badCertificateCallback = (cert, host, port) => true;
  //   return IOClient(httpClient);
  // }

  /// Set or clear the trusted certificate fingerprint used for cert pinning.
  void setTrustedFingerprint(String? hexFingerprint) {
    _trustedFingerprint = hexFingerprint?.toLowerCase();
    // Ensure http client exists and update callback
    _httpClient.badCertificateCallback = (cert, host, port) =>
        _trustedFingerprint == null ? true : _validateCertFingerprint(cert);
  }

  bool _validateCertFingerprint(X509Certificate cert) {
    try {
      final pem = cert.pem;
      // Extract base64 body
      final lines = pem.split('\n');
      final buffer = StringBuffer();
      var inside = false;
      for (final l in lines) {
        if (l.contains('BEGIN CERTIFICATE')) {
          inside = true;
          continue;
        }
        if (l.contains('END CERTIFICATE')) break;
        if (inside) buffer.write(l.trim());
      }
      final der = base64Decode(buffer.toString());
      final fp = sha256.convert(der).toString().toLowerCase();
      return _trustedFingerprint == fp;
    } catch (_) {
      return false;
    }
  }

  /// Fetch the server certificate fingerprint from the backend.
  Future<String?> fetchServerFingerprint({String? host, int? port}) async {
    final resolvedHost = host ?? _session?.host;
    final resolvedPort = port ?? _session?.port ?? CubieConstants.apiPort;
    if (resolvedHost == null || resolvedHost.isEmpty) return null;
    final uri = Uri.parse(
      'https://$resolvedHost:$resolvedPort${CubieConstants.apiVersion}/auth/cert-fingerprint',
    );
    final res = await _withAutoRefresh(
      () => _client.get(uri, headers: _headers).timeout(_timeout),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final fingerprint = body['fingerprint'] as String?;
      if (fingerprint != null && fingerprint.isNotEmpty) {
        return fingerprint.toLowerCase();
      }
    }
    return null;
  }

  void bindSessionResolver(AuthSession? Function() resolver) {
    _sessionResolver = resolver;
  }

  void bindConnectionStatusCallback(
      void Function(ConnectionStatus status) callback) {
    _connectionStatusCallback = callback;
  }

  void bindTokenUpdater(Future<void> Function(String token) callback) {
    _tokenUpdatedCallback = callback;
  }

  /// Connection timeout for all HTTP requests.
  static const _timeout = Duration(seconds: 10);

  AuthSession? get _session => _sessionResolver?.call();

  String get _baseUrl {
    final host = _session?.host;
    final port = _session?.port ?? CubieConstants.apiPort;
    if (host == null || host.isEmpty) {
      throw StateError('Host is not configured in auth session');
    }
    return 'https://$host:$port';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_session?.token != null)
          'Authorization': 'Bearer ${_session!.token}',
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

  Future<http.Response> _withAutoRefresh(
    Future<http.Response> Function() request,
  ) async {
    final response = await request();
    if (response.statusCode != 401) return response;

    final refreshToken = _session?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return response;
    }

    try {
      await _refreshTokenIfNeeded();
    } catch (_) {
      return response;
    }
    return await request();
  }

  Future<void> _refreshTokenIfNeeded() async {
    if (_isRefreshing) {
      await _refreshFuture;
      return;
    }

    final current = _session;
    final refreshToken = current?.refreshToken;
    if (current == null || refreshToken == null || refreshToken.isEmpty) {
      throw StateError('No refresh token available');
    }

    _isRefreshing = true;
    _refreshFuture = refreshAccessToken()
        .then((token) => _notifyTokenUpdated(token))
        .whenComplete(() {
      _isRefreshing = false;
      _refreshFuture = null;
    });
    await _refreshFuture;
  }

  Future<void> _notifyTokenUpdated(String token) async {
    if (_tokenUpdatedCallback != null) {
      await _tokenUpdatedCallback!(token);
    }
  }

  Future<String> refreshAccessToken({
    String? host,
    int? port,
    String? refreshToken,
  }) async {
    final resolvedHost = host ?? _session?.host;
    final resolvedPort = port ?? _session?.port ?? CubieConstants.apiPort;
    final token = refreshToken ?? _session?.refreshToken;
    if (resolvedHost == null ||
        resolvedHost.isEmpty ||
        token == null ||
        token.isEmpty) {
      throw StateError('Refresh credentials are missing');
    }
    final uri = Uri.parse(
      'https://$resolvedHost:$resolvedPort${CubieConstants.apiVersion}/auth/refresh',
    );
    final res = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': token}),
        )
        .timeout(_timeout);
    _check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final newToken = body['accessToken'] as String?;
    if (newToken == null || newToken.isEmpty) {
      throw Exception('Refresh response missing accessToken');
    }
    return newToken;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // AUTH
  // ──────────────────────────────────────────────────────────────────────────

  /// POST /api/v1/pair  body: {serial, key}
  Future<String> pairDevice(String serial, String key,
      {String? hostOverride}) async {
    final host = hostOverride ?? _session?.host;
    if (host == null || host.isEmpty) {
      throw StateError('Host is required to pair device');
    }
    final base = 'https://$host:${CubieConstants.apiPort}';
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$base${CubieConstants.apiVersion}/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'serial': serial, 'key': key}),
          )
          .timeout(_timeout),
    );
    _check(res);
    final data = jsonDecode(res.body);
    return data['token'] as String;
  }

  /// POST /api/v1/users  body: {name, pin}
  Future<void> createUser(String name, String? pin) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users'),
            headers: _headers,
            body: jsonEncode({'name': name, if (pin != null) 'pin': pin}),
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  /// POST /api/v1/auth/logout
  Future<void> logout() async {
    final payload = _session?.refreshToken != null
        ? jsonEncode({'refreshToken': _session!.refreshToken})
        : null;
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/auth/logout'),
            headers: _headers,
            body: payload,
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  /// PUT /api/v1/users/pin  body: {oldPin, newPin}
  Future<void> changePin(String? oldPin, String newPin) async {
    final res = await _withAutoRefresh(
      () => _client
          .put(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/pin'),
            headers: _headers,
            body: jsonEncode({'oldPin': oldPin, 'newPin': newPin}),
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SYSTEM / MONITORING
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/v1/system/info
  Future<CubieDevice> getDeviceInfo() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/system/info'),
            headers: _headers,
          )
          .timeout(_timeout),
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
    final host = _session?.host;
    final port = _session?.port ?? CubieConstants.apiPort;
    if (host == null || host.isEmpty) {
      throw StateError('Host is not configured in auth session');
    }
    final uri = Uri.parse('wss://$host:$port/ws/monitor');
    final channel = IOWebSocketChannel.connect(
      uri,
      customClient: _createPinnedHttpClient(),
    );

    _connectionStatusCallback?.call(ConnectionStatus.connected);
    final ctrl = StreamController<SystemStats>();
    channel.stream.listen(
      (raw) {
        _connectionStatusCallback?.call(ConnectionStatus.connected);
        final data = jsonDecode(raw as String);
        ctrl.add(SystemStats(
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
        ));
      },
      onError: (e, st) {
        _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
        ctrl.addError(e, st);
      },
      onDone: () {
        _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
        ctrl.close();
      },
      cancelOnError: false,
    );
    return ctrl.stream;
  }

  /// WebSocket /ws/events — real-time notification stream from the backend.
  Stream<AppNotification> notificationStream() {
    final host = _session?.host;
    final port = _session?.port ?? CubieConstants.apiPort;
    if (host == null || host.isEmpty) {
      throw StateError('Host is not configured in auth session');
    }
    final uri = Uri.parse('wss://$host:$port/ws/events');
    final channel = IOWebSocketChannel.connect(
      uri,
      customClient: _createPinnedHttpClient(),
    );

    final ctrl = StreamController<AppNotification>();
    channel.stream.listen(
      (raw) {
        _connectionStatusCallback?.call(ConnectionStatus.connected);
        final data = jsonDecode(raw as String);
        ctrl.add(AppNotification.fromJson(data));
      },
      onError: (e, st) {
        _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
        ctrl.addError(e, st);
      },
      onDone: () {
        _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
        ctrl.close();
      },
      cancelOnError: false,
    );
    return ctrl.stream;
  }

  /// GET /api/v1/storage/stats
  Future<StorageStats> getStorageStats() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/storage/stats'),
            headers: _headers,
          )
          .timeout(_timeout),
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
          .timeout(_timeout),
    );
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) => StorageDevice.fromJson(item)).toList();
  }

  /// GET /api/v1/storage/scan — re-scan for newly connected devices
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
          .timeout(_timeout),
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

  /// GET /api/v1/storage/check-usage — pre-unmount blocker check
  Future<Map<String, dynamic>> checkStorageUsage() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse(
                '$_baseUrl${CubieConstants.apiVersion}/storage/check-usage'),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    _check(res);
    return jsonDecode(res.body);
  }

  /// GET /api/v1/system/firmware
  Future<Map<String, dynamic>> checkFirmwareUpdate() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/system/firmware'),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    _check(res);
    return jsonDecode(res.body);
  }

  /// POST /api/v1/system/update
  Future<void> triggerOtaUpdate() async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/system/update'),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  /// PUT /api/v1/system/name  body: {name}
  Future<void> updateDeviceName(String name) async {
    final res = await _withAutoRefresh(
      () => _client
          .put(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/system/name'),
            headers: _headers,
            body: jsonEncode({'name': name}),
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FILES
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/v1/files/list?path=<path>
  Future<FileListResponse> listFiles(
    String path, {
    int page = 0,
    int pageSize = 50,
    String sortBy = 'name',
    String sortDir = 'asc',
  }) async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/list')
                .replace(queryParameters: {
              'path': path,
              'page': '$page',
              'page_size': '$pageSize',
              'sort_by': sortBy,
              'sort_dir': sortDir,
            }),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    _check(res);
    final Map<String, dynamic> body = jsonDecode(res.body);
    final List<dynamic> list = body['items'] as List<dynamic>;
    final items = list.map((item) {
      return FileItem(
        name: item['name'],
        path: item['path'],
        isDirectory: item['isDirectory'] as bool,
        sizeBytes: item['sizeBytes'] as int,
        modified: DateTime.parse(item['modified']),
        mimeType: item['mimeType'],
      );
    }).toList();

    return FileListResponse(
      items: items,
      totalCount: (body['totalCount'] as num?)?.toInt() ?? items.length,
      page: (body['page'] as num?)?.toInt() ?? page,
      pageSize: (body['pageSize'] as num?)?.toInt() ?? pageSize,
    );
  }

  /// POST /api/v1/files/mkdir  body: {path}
  Future<void> createFolder(String parentPath, String name) async {
    final fullPath =
        parentPath.endsWith('/') ? '$parentPath$name' : '$parentPath/$name';
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/mkdir'),
            headers: _headers,
            body: jsonEncode({'path': fullPath}),
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  /// DELETE /api/v1/files/delete?path=<path>
  Future<void> deleteFile(String path) async {
    final res = await _withAutoRefresh(
      () => _client
          .delete(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/delete')
                .replace(queryParameters: {'path': path}),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  /// PUT /api/v1/files/rename  body: {oldPath, newName}
  Future<void> renameFile(String path, String newName) async {
    final res = await _withAutoRefresh(
      () => _client
          .put(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/rename'),
            headers: _headers,
            body: jsonEncode({'oldPath': path, 'newName': newName}),
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  /// GET /api/v1/files/download?path=...
  /// Returns the raw file bytes for saving or previewing.
  Future<http.Response> downloadFile(String filePath) async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/download')
                .replace(queryParameters: {'path': filePath}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 60)),
    );
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
        final uri =
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/files/upload')
                .replace(queryParameters: {'path': destinationPath});

        final request = http.MultipartRequest('POST', uri);
        final token = _session?.token;
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }

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
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/family'),
            headers: _headers,
          )
          .timeout(_timeout),
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

  /// POST /api/v1/users/family  body: {name}
  Future<FamilyUser> addFamilyUser(String name) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/family'),
            headers: _headers,
            body: jsonEncode({'name': name}),
          )
          .timeout(_timeout),
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

  /// DELETE /api/v1/users/family/<id>
  Future<void> removeFamilyUser(String userId) async {
    final res = await _withAutoRefresh(
      () => _client
          .delete(
            Uri.parse(
                '$_baseUrl${CubieConstants.apiVersion}/users/family/$userId'),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SERVICES
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/v1/services
  Future<List<ServiceInfo>> getServices() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/services'),
            headers: _headers,
          )
          .timeout(_timeout),
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

  /// POST /api/v1/services/<id>/toggle  body: {enabled}
  Future<void> toggleService(String serviceId, bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${CubieConstants.apiVersion}/services/$serviceId/toggle'),
            headers: _headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // NETWORK
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/v1/network/status
  Future<NetworkStatus> getNetworkStatus() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/network/status'),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    _check(res);
    return NetworkStatus.fromJson(jsonDecode(res.body));
  }

  /// POST /api/v1/network/wifi  body: {enabled}
  Future<void> toggleWifi(bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/network/wifi'),
            headers: _headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(_timeout),
    );
    _check(res);
  }

  /// POST /api/v1/network/hotspot  body: {enabled}
  Future<void> toggleHotspot(bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/network/hotspot'),
            headers: _headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 15)),
    );
    _check(res);
  }

  /// POST /api/v1/network/bluetooth  body: {enabled}
  Future<void> toggleBluetooth(bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${CubieConstants.apiVersion}/network/bluetooth'),
            headers: _headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(_timeout),
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
