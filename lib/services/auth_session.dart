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

  AuthSessionNotifier(this._prefs) : super(null) {
    restoreFromPrefs();
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

    await _prefs.setString(CubieConstants.prefDeviceIp, host);
    await _prefs.setInt(CubieConstants.prefDevicePort, port);
    await _prefs.setString(CubieConstants.prefAuthToken, token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _prefs.setString(CubieConstants.prefRefreshToken, refreshToken);
    } else {
      await _prefs.remove(CubieConstants.prefRefreshToken);
    }
    await _prefs.setString(CubieConstants.prefUserName, username);
    await _prefs.setBool(CubieConstants.prefIsAdmin, isAdmin);
    await _prefs.setBool(CubieConstants.prefIsSetupDone, true);
  }

  Future<void> logout() async {
    state = null;
    await _prefs.remove(CubieConstants.prefAuthToken);
    await _prefs.remove(CubieConstants.prefRefreshToken);
    await _prefs.remove(CubieConstants.prefUserName);
    await _prefs.remove(CubieConstants.prefIsAdmin);
    await _prefs.remove(CubieConstants.prefDeviceIp);
    await _prefs.remove(CubieConstants.prefDevicePort);
    await _prefs.setBool(CubieConstants.prefIsSetupDone, false);
  }

  Future<void> restoreFromPrefs() async {
    final host = _prefs.getString(CubieConstants.prefDeviceIp);
    final token = _prefs.getString(CubieConstants.prefAuthToken);

    if (host == null || token == null || host.isEmpty || token.isEmpty) {
      state = null;
      return;
    }

    final port = _prefs.getInt(CubieConstants.prefDevicePort) ?? CubieConstants.apiPort;
    final refreshToken = _prefs.getString(CubieConstants.prefRefreshToken);
    final username = _prefs.getString(CubieConstants.prefUserName) ?? '';
    final isAdmin = _prefs.getBool(CubieConstants.prefIsAdmin) ?? false;

    state = AuthSession(
      host: host,
      port: port,
      token: token,
      refreshToken: refreshToken,
      username: username,
      isAdmin: isAdmin,
    );
  }
}
