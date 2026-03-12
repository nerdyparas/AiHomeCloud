import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

class AuthSession {
  final String host;
  final int port;
  final String token;
  final String? refreshToken;
  final String username;
  final bool isAdmin;

  const AuthSession({
    required this.host,
    required this.port,
    required this.token,
    required this.refreshToken,
    required this.username,
    required this.isAdmin,
  });

  AuthSession copyWith({
    String? host,
    int? port,
    String? token,
    String? refreshToken,
    String? username,
    bool? isAdmin,
  }) {
    return AuthSession(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
      username: username ?? this.username,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }
}

class AuthSessionNotifier extends StateNotifier<AuthSession?> {
  final SharedPreferences _prefs;
  final Future<String> Function(String host, int port, String refreshToken)? _refreshTokenFn;

  AuthSessionNotifier(
    this._prefs, {
    Future<String> Function(String host, int port, String refreshToken)? refreshTokenFn,
  })  : _refreshTokenFn = refreshTokenFn,
        super(null) {
    _restorePersistedSession();
  }

  Future<void> login({
    required String host,
    required int port,
    required String token,
    required String? refreshToken,
    required String username,
    required bool isAdmin,
  }) async {
    final next = AuthSession(
      host: host,
      port: port,
      token: token,
      refreshToken: refreshToken,
      username: username,
      isAdmin: isAdmin,
    );

    state = next;

    await _prefs.setString(AppConstants.prefDeviceIp, host);
    await _prefs.setInt(AppConstants.prefDevicePort, port);
    await _prefs.setString(AppConstants.prefAuthToken, token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _prefs.setString(AppConstants.prefRefreshToken, refreshToken);
    } else {
      await _prefs.remove(AppConstants.prefRefreshToken);
    }
    await _prefs.setString(AppConstants.prefUserName, username);
    await _prefs.setBool(AppConstants.prefIsAdmin, isAdmin);
    await _prefs.setBool(AppConstants.prefIsSetupDone, true);
  }

  Future<void> logout() async {
    state = null;
    await _prefs.remove(AppConstants.prefAuthToken);
    await _prefs.remove(AppConstants.prefRefreshToken);
    await _prefs.remove(AppConstants.prefUserName);
    await _prefs.remove(AppConstants.prefIsAdmin);
    await _prefs.remove(AppConstants.prefDeviceIp);
    await _prefs.remove(AppConstants.prefDevicePort);
    await _prefs.setBool(AppConstants.prefIsSetupDone, false);
  }

  Future<void> updateToken(String token) async {
    if (state == null) return;
    state = state!.copyWith(token: token);
    await _prefs.setString(AppConstants.prefAuthToken, token);
  }

  void _restorePersistedSession() {
    final host = _prefs.getString(AppConstants.prefDeviceIp);
    final token = _prefs.getString(AppConstants.prefAuthToken);

    if (host == null || token == null || host.isEmpty || token.isEmpty) {
      state = null;
      return;
    }

    final port = _prefs.getInt(AppConstants.prefDevicePort) ?? AppConstants.apiPort;
    final refreshToken = _prefs.getString(AppConstants.prefRefreshToken);
    final username = _prefs.getString(AppConstants.prefUserName) ?? '';
    final isAdmin = _prefs.getBool(AppConstants.prefIsAdmin) ?? false;

    state = AuthSession(
      host: host,
      port: port,
      token: token,
      refreshToken: refreshToken,
      username: username,
      isAdmin: isAdmin,
    );

    if (_refreshTokenFn != null && refreshToken != null && refreshToken.isNotEmpty) {
      _refreshPersistedToken(host, port, refreshToken);
    }
  }

  Future<void> _refreshPersistedToken(
    String host,
    int port,
    String refreshToken,
  ) async {
    try {
      final refreshed = await _refreshTokenFn!(host, port, refreshToken);
      if (refreshed.isNotEmpty &&
          state?.host == host &&
          state?.port == port &&
          state?.refreshToken == refreshToken) {
        await updateToken(refreshed);
      }
    } catch (_) {
      // Silent failure; session remains as-is until next manual login.
    }
  }
}
