/// Data-fetching providers — family users, network status, services, notifications.
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error_utils.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/backup_runner.dart';
import 'core_providers.dart';

/// Fetches current backup configuration and job stats.
final backupStatusProvider = FutureProvider<BackupStatus>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getBackupStatus();
});

/// Live progress for the "Back up now" user-initiated backup run.
/// Remains [BackupPhase.idle] at rest; auto-resets 5 s after completion.
final backupProgressProvider =
    StateNotifierProvider<BackupProgressNotifier, BackupProgress>(
        (ref) => BackupProgressNotifier(ref.read(apiServiceProvider)));

class BackupProgressNotifier extends StateNotifier<BackupProgress> {
  final ApiService _api;

  BackupProgressNotifier(this._api)
      : super(const BackupProgress());

  /// Start an immediate backup run for [jobs].
  /// Fire-and-forget — progress is pushed through [state] updates.
  void startAll(List<BackupJob> jobs, String username) {
    if (state.isActive) return;
    BackupRunner.instance
        .runAll(
          jobs: jobs,
          username: username,
          api: _api,
          onProgress: (p) {
            if (mounted) state = p;
            if (p.phase == BackupPhase.done ||
                p.phase == BackupPhase.failed) {
              Future.delayed(const Duration(seconds: 10), () {
                if (mounted) state = const BackupProgress();
              });
            }
          },
        );
  }

  /// Cancel a running backup.
  void cancel() {
    BackupRunner.instance.cancel();
  }
}

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


