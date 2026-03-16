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
  final String iconEmoji;

  const AuthSession({
    required this.host,
    required this.port,
    required this.token,
    required this.refreshToken,
    required this.username,
    required this.isAdmin,
    this.iconEmoji = '',
  });

  AuthSession copyWith({
    String? host,
    int? port,
    String? token,
    String? refreshToken,
    String? username,
    bool? isAdmin,
    String? iconEmoji,
  }) {
    return AuthSession(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
      username: username ?? this.username,
      isAdmin: isAdmin ?? this.isAdmin,
      iconEmoji: iconEmoji ?? this.iconEmoji,
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
    String iconEmoji = '',
  }) async {
    final next = AuthSession(
      host: host,
      port: port,
      token: token,
      refreshToken: refreshToken,
      username: username,
      isAdmin: isAdmin,
      iconEmoji: iconEmoji,
    );

    state = next;

    // Persist to disk in parallel — SharedPreferences updates its in-memory
    // cache synchronously, so values are readable immediately.  Disk commits
    // happen in the background without blocking navigation.
    _persistLogin(host, port, token, refreshToken, username, isAdmin, iconEmoji);
  }

  void _persistLogin(String host, int port, String token,
      String? refreshToken, String username, bool isAdmin, String iconEmoji) {
    final writes = <Future<bool>>[
      _prefs.setString(AppConstants.prefDeviceIp, host),
      _prefs.setInt(AppConstants.prefDevicePort, port),
      _prefs.setString(AppConstants.prefAuthToken, token),
      _prefs.setString(AppConstants.prefUserName, username),
      _prefs.setBool(AppConstants.prefIsAdmin, isAdmin),
      _prefs.setBool(AppConstants.prefIsSetupDone, true),
      _prefs.setString('icon_emoji', iconEmoji),
    ];
    if (refreshToken != null && refreshToken.isNotEmpty) {
      writes.add(_prefs.setString(AppConstants.prefRefreshToken, refreshToken));
    } else {
      writes.add(_prefs.remove(AppConstants.prefRefreshToken));
    }
    Future.wait(writes);
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

    final iconEmoji = _prefs.getString('icon_emoji') ?? '';

    state = AuthSession(
      host: host,
      port: port,
      token: token,
      refreshToken: refreshToken,
      username: username,
      isAdmin: isAdmin,
      iconEmoji: iconEmoji,
    );

    if (_refreshTokenFn != null && refreshToken != null && refreshToken.isNotEmpty) {
      _refreshPersistedToken(host, port, refreshToken);
    }
  }

  Future<void> updateProfile({String? username, String? iconEmoji}) async {
    if (state == null) return;
    state = state!.copyWith(
      username: username ?? state!.username,
      iconEmoji: iconEmoji ?? state!.iconEmoji,
    );
    if (username != null) {
      await _prefs.setString(AppConstants.prefUserName, username);
    }
    if (iconEmoji != null) {
      await _prefs.setString('icon_emoji', iconEmoji);
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
