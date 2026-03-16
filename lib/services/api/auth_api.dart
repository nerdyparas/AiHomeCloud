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

  /// POST /api/v1/users  body: {name, pin, icon_emoji}
  /// Returns the created user plus auto-login tokens {id, name, isAdmin,
  /// accessToken, refreshToken} so the caller avoids a second login request.
  Future<Map<String, dynamic>> createUser(
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
    return jsonDecode(res.body) as Map<String, dynamic>;
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
  /// Retries once on connection failure (handles backend mid-restart).
  Future<Map<String, dynamic>> loginWithPin(String host, String name, String pin) async {
    final base = 'https://$host:${AppConstants.apiPort}';
    final uri = Uri.parse('$base${AppConstants.apiVersion}/auth/login');
    final body = jsonEncode({'name': name, 'pin': pin});
    const headers = {'Content-Type': 'application/json'};

    try {
      final res = await _client
          .post(uri, headers: headers, body: body)
          .timeout(ApiService._timeout);
      _check(res);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on SocketException {
      // Single retry after a short delay — covers backend mid-restart
      await Future.delayed(const Duration(milliseconds: 800));
      final res = await _client
          .post(uri, headers: headers, body: body)
          .timeout(ApiService._timeout);
      _check(res);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on HandshakeException {
      await Future.delayed(const Duration(milliseconds: 800));
      final res = await _client
          .post(uri, headers: headers, body: body)
          .timeout(ApiService._timeout);
      _check(res);
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
  }

  /// GET /api/v1/auth/users/names — fetch user names + PIN status for the login picker (no auth).
  /// Retries once on connection failure to handle backend mid-restart.
  Future<List<UserPickerEntry>> fetchUserEntries(String host) async {
    final base = 'https://$host:${AppConstants.apiPort}';
    final uri = Uri.parse('$base${AppConstants.apiVersion}/auth/users/names');

    List<UserPickerEntry> _parse(http.Response res) {
      _check(res);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['users'] as List<dynamic>;
      return list.map((e) => UserPickerEntry(
        name: e['name'] as String,
        hasPin: e['has_pin'] as bool? ?? false,
        iconEmoji: e['icon_emoji'] as String? ?? '',
      )).toList();
    }

    try {
      return _parse(await _client.get(uri).timeout(ApiService._timeout));
    } on SocketException {
      await Future.delayed(const Duration(milliseconds: 800));
      return _parse(await _client.get(uri).timeout(ApiService._timeout));
    } on HandshakeException {
      await Future.delayed(const Duration(milliseconds: 800));
      return _parse(await _client.get(uri).timeout(ApiService._timeout));
    }
  }

  /// GET /api/v1/users/me
  Future<Map<String, dynamic>> getMyProfile() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/users/me'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// PUT /api/v1/users/me
  Future<void> updateMyProfile({String? name, String? iconEmoji}) async {
    final res = await _withAutoRefresh(
      () => _client
          .put(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/users/me'),
            headers: _headers,
            body: jsonEncode({
              if (name != null) 'name': name,
              if (iconEmoji != null) 'icon_emoji': iconEmoji,
            }),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// DELETE /api/v1/users/me
  Future<void> deleteMyProfile() async {
    final res = await _withAutoRefresh(
      () => _client
          .delete(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/users/me'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// DELETE /api/v1/users/pin — remove PIN entirely
  Future<void> removePin() async {
    final res = await _withAutoRefresh(
      () => _client
          .delete(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/users/pin'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }
}
