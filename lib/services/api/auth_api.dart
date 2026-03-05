part of '../api_service.dart';

/// Authentication API — pairing, user creation, login/logout, PIN management.
extension AuthApi on ApiService {
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
          .timeout(ApiService._timeout),
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
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/auth/logout'),
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
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/pin'),
            headers: _headers,
            body: jsonEncode({'oldPin': oldPin, 'newPin': newPin}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }
}
