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

part 'api/auth_api.dart';
part 'api/system_api.dart';
part 'api/files_api.dart';
part 'api/storage_api.dart';
part 'api/family_api.dart';
part 'api/services_network_api.dart';

/// AiHomeCloud API service — singleton HTTP + WebSocket client.
///
/// Core infrastructure: TLS pinning, auto-refresh tokens, session management.
/// Domain-specific methods are split into part files under `api/`:
///   - [AuthApi] — pairing, user creation, login/logout
///   - [SystemApi] — device info, firmware, monitoring WebSockets
///   - [FilesApi] — file list, upload, download, rename, delete
///   - [StorageApi] — device scan, format, mount/unmount, eject
///   - [FamilyApi] — family user management
///   - [ServicesNetworkApi] — NAS services and network toggles
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
    final httpClient = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 25);
    httpClient.badCertificateCallback = (cert, host, port) =>
        _trustedFingerprint == null ? true : _validateCertFingerprint(cert);
    return httpClient;
  }

  /// Set or clear the trusted certificate fingerprint used for cert pinning.
  ///
  /// When set, all HTTPS connections validate the server certificate's SHA-256
  /// fingerprint against this value. Null = trust any certificate (dev mode).
  void setTrustedFingerprint(String? hexFingerprint) {
    _trustedFingerprint = hexFingerprint?.toLowerCase();
    _httpClient.badCertificateCallback = (cert, host, port) =>
        _trustedFingerprint == null ? true : _validateCertFingerprint(cert);
  }

  /// Validate a server certificate against the stored fingerprint.
  ///
  /// Extracts the DER-encoded certificate from PEM, computes SHA-256 hash,
  /// and compares against the trusted fingerprint.
  bool _validateCertFingerprint(X509Certificate cert) {
    try {
      final pem = cert.pem;
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
    final resolvedPort = port ?? _session?.port ?? AppConstants.apiPort;
    if (resolvedHost == null || resolvedHost.isEmpty) return null;
    final uri = Uri.parse(
      'https://$resolvedHost:$resolvedPort${AppConstants.apiVersion}/auth/cert-fingerprint',
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

  /// The device host from the current auth session. Null if not configured.
  String? get host => _session?.host;

  String get _baseUrl {
    final host = _session?.host;
    final port = _session?.port ?? AppConstants.apiPort;
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

  /// Wrap a request with automatic token refresh on 401.
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
    final resolvedPort = port ?? _session?.port ?? AppConstants.apiPort;
    final token = refreshToken ?? _session?.refreshToken;
    if (resolvedHost == null ||
        resolvedHost.isEmpty ||
        token == null ||
        token.isEmpty) {
      throw StateError('Refresh credentials are missing');
    }
    final uri = Uri.parse(
      'https://$resolvedHost:$resolvedPort${AppConstants.apiVersion}/auth/refresh',
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

  /// Map service IDs to Material icons (backend doesn't send icons).
  static IconData _serviceIcon(String id) {
    return switch (id) {
      'media' => Icons.tv_rounded,
      'samba' => Icons.desktop_windows_rounded,
      'nfs' => Icons.dns_rounded,
      'ssh' => Icons.terminal_rounded,
      'dlna' => Icons.tv_rounded,
      _ => Icons.miscellaneous_services_rounded,
    };
  }
}
