/// Data-fetching providers — family users, network status, services, notifications.
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'core_providers.dart';

final familyUsersProvider = FutureProvider<List<FamilyUser>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getFamilyUsers();
});

final networkStatusProvider = FutureProvider<NetworkStatus>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getNetworkStatus();
});

final servicesProvider = FutureProvider<List<ServiceInfo>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getServices();
});

final tailscaleStatusProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getTailscaleStatus();
});

final notificationStreamProvider = StreamProvider<AppNotification>((ref) {
  final api = ref.read(apiServiceProvider);
  return api.notificationStream();
});

/// Keeps a list of recent notifications for the bell icon / history.
class NotificationHistoryNotifier extends StateNotifier<List<AppNotification>> {
  NotificationHistoryNotifier() : super([]);

  void add(AppNotification n) {
    state = [n, ...state].take(50).toList();
  }

  void clear() => state = [];
}

final notificationHistoryProvider =
    StateNotifierProvider<NotificationHistoryNotifier, List<AppNotification>>(
  (ref) => NotificationHistoryNotifier(),
);

/// Ad Blocking stats — silently returns null if AdGuard is disabled/unreachable.
/// Used on the Home tab to optionally show the ad blocking badge.
/// Checks /status first to avoid a 503 from /stats when AdGuard is not configured.
final adGuardStatsSilentProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    final status = await ref.read(apiServiceProvider).getAdGuardStatus();
    final installed = status['installed'] as bool? ?? false;
    final running = status['service_running'] as bool? ?? false;
    final enabled = status['app_enabled'] as bool? ?? false;
    if (!installed || !running || !enabled) return null;
    return await ref.read(apiServiceProvider).getAdGuardStats();
  } catch (_) {
    return null;
  }
});


