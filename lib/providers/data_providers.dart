/// Data-fetching providers — family users, network status, services, notifications.
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error_utils.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'core_providers.dart';

/// Fetches current backup configuration and job stats.
final backupStatusProvider = FutureProvider<BackupStatus>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getBackupStatus();
});

final familyUsersProvider = FutureProvider<List<FamilyUser>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getFamilyUsers();
});

final networkStatusProvider = FutureProvider<NetworkStatus>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getNetworkStatus();
});

class ServicesNotifier
    extends StateNotifier<AsyncValue<List<ServiceInfo>>> {
  final ApiService _api;

  ServicesNotifier(this._api) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _api.getServices());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> toggle(
    String serviceId,
    bool enabled, {
    required void Function(String message) onError,
  }) async {
    final previous = state;
    // Optimistic update
    state = state.whenData((list) => [
          for (final s in list)
            if (s.id == serviceId) s.copyWith(isEnabled: enabled) else s,
        ]);
    try {
      await _api.toggleService(serviceId, enabled);
    } catch (e) {
      state = previous; // rollback
      onError(friendlyError(e));
    }
  }
}

final servicesProvider =
    StateNotifierProvider<ServicesNotifier, AsyncValue<List<ServiceInfo>>>(
  (ref) => ServicesNotifier(ref.read(apiServiceProvider)),
);

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


