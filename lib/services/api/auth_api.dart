part of '../api_service.dart';

/// Model returned by the login picker endpoint.
class UserPickerEntry {
  final String name;
  final bool hasPin;
  final String iconEmoji;
  const UserPickerEntry({
    required this.name,
    required this.hasPin,
    this.iconEmoji = '',
  });
}

/// Authentication API — pairing, user creation, login/logout, PIN management.
extension AuthApi on ApiService {
  /// GET /api/v1/pair/qr — fetch pairing info from a discovered Cubie.
  Future<Map<String, dynamic>> fetchPairingInfo(String host) async {
    final base = 'https://$host:${AppConstants.apiPort}';
    final res = await _client
        .get(Uri.parse('$base${AppConstants.apiVersion}/pair/qr'))
        .timeout(ApiService._timeout);
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// POST /api/v1/pair  body: {serial, key}
  Future<String> pairDevice(String serial, String key,
      {String? hostOverride}) async {
    final host = hostOverride ?? _session?.host;
    if (host == null || host.isEmpty) {
      throw StateError('Host is required to pair device');
    }
    final base = 'https://$host:${AppConstants.apiPort}';
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$base${AppConstants.apiVersion}/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'serial': serial, 'key': key}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final data = jsonDecode(res.body);
    return data['token'] as String;
  }

  /// POST /api/v1/users  body: {name, pin}
  Future<void> createUser(
    String name,
    String? pin, {
    String? hostOverride,
    String iconEmoji = '',
  }) async {
    final host = hostOverride ?? _session?.host;
    final port = _session?.port ?? AppConstants.apiPort;
    if (host == null || host.isEmpty) {
      throw StateError('Host is required to create a user');
    }
    final base = 'https://$host:$port';
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$base${AppConstants.apiVersion}/users'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              if (pin != null && pin.isNotEmpty) 'pin': pin,
              if (iconEmoji.isNotEmpty) 'icon_emoji': iconEmoji,
            }),
          )
          .timeout(ApiService._timeout),
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
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/auth/logout'),
            headers: _headers,
            body: payload,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// PUT /api/v1/users/pin  body: {oldPin, newPin}
  Future<void> changePin(String? oldPin, String newPin) async {
    final res = await _withAutoRefresh(
      () => _client
          .put(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/users/pin'),
            headers: _headers,
            body: jsonEncode({'oldPin': oldPin, 'newPin': newPin}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// POST /api/v1/auth/login  body: {name, pin}
  /// Returns the full login response map (accessToken, refreshToken, user).
  Future<Map<String, dynamic>> loginWithPin(String host, String name, String pin) async {
    final base = 'https://$host:${AppConstants.apiPort}';
    final res = await _client
        .post(
          Uri.parse('$base${AppConstants.apiVersion}/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': name, 'pin': pin}),
        )
        .timeout(ApiService._timeout);
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// GET /api/v1/auth/users/names — fetch available user names (no auth).
  /// GET /api/v1/auth/users/names — fetch user names + PIN status for the login picker (no auth).
  Future<List<UserPickerEntry>> fetchUserEntries(String host) async {
    final base = 'https://$host:${AppConstants.apiPort}';
    final res = await _client
        .get(Uri.parse('$base${AppConstants.apiVersion}/auth/users/names'))
        .timeout(ApiService._timeout);
    _check(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['users'] as List<dynamic>;
    return list.map((e) => UserPickerEntry(
      name: e['name'] as String,
      hasPin: e['has_pin'] as bool? ?? false,
      iconEmoji: e['icon_emoji'] as String? ?? '',
    )).toList();
  }
}
