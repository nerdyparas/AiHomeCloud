/// Core singleton providers — SharedPreferences, auth, certificates, API service.
///
/// These are the foundational providers that almost every other provider depends on.
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import '../services/auth_session.dart';
import '../services/discovery_service.dart';
import 'device_providers.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in ProviderScope at app start');
});

final certFingerprintProvider = StateProvider<String?>((ref) {
  final stored = ref
      .read(sharedPreferencesProvider)
      .getString(AppConstants.kCertFingerprintPrefKey);
  if (stored == null || stored.isEmpty) return null;
  return stored;
});

final authSessionProvider =
    StateNotifierProvider<AuthSessionNotifier, AuthSession?>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return AuthSessionNotifier(
    prefs,
    refreshTokenFn: (host, port, refreshToken) async {
      return ApiService.instance.refreshAccessToken(
        host: host,
        port: port,
        refreshToken: refreshToken,
      );
    },
  );
});

final apiServiceProvider = Provider<ApiService>((ref) {
  final storedFingerprint = ref.watch(certFingerprintProvider);
  final api = ApiService.instance;
  api.setTrustedFingerprint(storedFingerprint);
  api.bindSessionResolver(() => ref.read(authSessionProvider));
  api.bindConnectionStatusCallback(
      (status) => ref.read(connectionProvider.notifier).setStatus(status));
  api.bindTokenUpdater(
    (token) => ref.read(authSessionProvider.notifier).updateToken(token),
  );
  // Restore persisted Tailscale IP so remote fallback works after relaunch.
  final prefs = ref.read(sharedPreferencesProvider);
  final tailscaleIp = prefs.getString(AppConstants.prefTailscaleIp);
  api.setTailscaleIp(tailscaleIp);
  return api;
});

Future<void> persistServerFingerprint(dynamic ref, String fingerprint) async {
  final prefs = ref.read(sharedPreferencesProvider);
  await prefs.setString(AppConstants.kCertFingerprintPrefKey, fingerprint);
  ref.read(certFingerprintProvider.notifier).state = fingerprint;
  ref.read(apiServiceProvider).setTrustedFingerprint(fingerprint);
}

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  return DiscoveryService.instance;
});

final isSetupDoneProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return prefs.getBool(AppConstants.prefIsSetupDone) ?? false;
});
