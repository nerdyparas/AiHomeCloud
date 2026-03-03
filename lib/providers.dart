import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants.dart';
import 'models/models.dart';
import 'services/discovery_service.dart';
import 'services/api_service.dart';
import 'services/auth_session.dart';

// ─── Core singletons ───────────────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in ProviderScope at app start');
});

final authSessionProvider =
    StateNotifierProvider<AuthSessionNotifier, AuthSession?>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return AuthSessionNotifier(prefs);
});

final apiServiceProvider = Provider<ApiService>((ref) {
  final api = ApiService.instance;
  api.bindSessionResolver(() => ref.read(authSessionProvider));
  api.bindConnectionStatusCallback(
      (status) => ref.read(connectionProvider.notifier).setStatus(status));
  return api;
});

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  return DiscoveryService.instance;
});

// ─── Auth / Setup ───────────────────────────────────────────────────────────

final isSetupDoneProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return prefs.getBool(CubieConstants.prefIsSetupDone) ?? false;
});

// ─── Device info ────────────────────────────────────────────────────────────

final deviceInfoProvider = FutureProvider<CubieDevice>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getDeviceInfo();
});

// ─── System stats (live stream) ─────────────────────────────────────────────

final systemStatsStreamProvider = StreamProvider<SystemStats>((ref) {
  final api = ref.read(apiServiceProvider);
  return api.monitorSystemStats();
});

class ConnectionNotifier extends StateNotifier<ConnectionStatus> {
  ConnectionNotifier() : super(ConnectionStatus.connected);

  Timer? _debounceTimer;
  final List<int> reconnectBackoff = [2, 4, 8, 16, 30];
  int _attempt = 0;

  int get currentBackoffSeconds => reconnectBackoff[_attempt.clamp(0, reconnectBackoff.length - 1)];

  void markConnected() {
    _debounceTimer?.cancel();
    _attempt = 0;
    state = ConnectionStatus.connected;
  }

  void markReconnectStart() {
    _debounceTimer?.cancel();
    state = ConnectionStatus.reconnecting;
    _debounceTimer = Timer(const Duration(seconds: 10), () {
      state = ConnectionStatus.disconnected;
      if (_attempt < reconnectBackoff.length - 1) {
        _attempt += 1;
      }
    });
  }

  void setStatus(ConnectionStatus status) {
    if (status == ConnectionStatus.connected) {
      markConnected();
    } else if (status == ConnectionStatus.reconnecting) {
      markReconnectStart();
    } else {
      state = ConnectionStatus.disconnected;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionStatus>((ref) {
  return ConnectionNotifier();
});

// ─── Storage ────────────────────────────────────────────────────────────────

final storageStatsProvider = FutureProvider<StorageStats>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getStorageStats();
});

// ─── Storage devices ────────────────────────────────────────────────────────

final storageDevicesProvider =
    FutureProvider<List<StorageDevice>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getStorageDevices();
});

// ─── Files (parameterised by path) ──────────────────────────────────────────

class FileListQuery {
  final String path;
  final int page;
  final int pageSize;
  final String sortBy;
  final String sortDir;

  const FileListQuery({
    required this.path,
    this.page = 0,
    this.pageSize = 50,
    this.sortBy = 'name',
    this.sortDir = 'asc',
  });
}

final fileListProvider =
    FutureProvider.family<FileListResponse, FileListQuery>((ref, q) async {
  final api = ref.read(apiServiceProvider);
  return api.listFiles(
    q.path,
    page: q.page,
    pageSize: q.pageSize,
    sortBy: q.sortBy,
    sortDir: q.sortDir,
  );
});

// ─── Family ─────────────────────────────────────────────────────────────────

final familyUsersProvider = FutureProvider<List<FamilyUser>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getFamilyUsers();
});

// ─── Network ────────────────────────────────────────────────────────────────

final networkStatusProvider = FutureProvider<NetworkStatus>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getNetworkStatus();
});

// ─── Services ───────────────────────────────────────────────────────────────

final servicesProvider = FutureProvider<List<ServiceInfo>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getServices();
});

// ─── Notifications (real-time from backend) ─────────────────────────────────

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

// ─── Upload tasks ───────────────────────────────────────────────────────────

class UploadTasksNotifier extends StateNotifier<List<UploadTask>> {
  UploadTasksNotifier() : super([]);

  void addTask(UploadTask task) {
    state = [...state, task];
  }

  void updateTask(
    String id, {
    int? uploadedBytes,
    UploadStatus? status,
    String? error,
  }) {
    state = [
      for (final t in state)
        if (t.id == id)
          t
            ..uploadedBytes = uploadedBytes ?? t.uploadedBytes
            ..status = status ?? t.status
            ..error = error
        else
          t,
    ];
  }

  void removeTask(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void clearCompleted() {
    state = state.where((t) => t.status != UploadStatus.completed).toList();
  }
}

final uploadTasksProvider =
    StateNotifierProvider<UploadTasksNotifier, List<UploadTask>>((ref) {
  return UploadTasksNotifier();
});

// ─── QR scan payload ────────────────────────────────────────────────────────

final qrPayloadProvider = StateProvider<QrPairPayload?>((ref) => null);

// ─── Discovery ──────────────────────────────────────────────────────────────

enum DiscoveryStatus { idle, searching, found, failed }

class DiscoveryState {
  final DiscoveryStatus status;
  final String? deviceIp;
  final String statusMessage;
  final DiscoveryMethod? method;

  const DiscoveryState({
    this.status = DiscoveryStatus.idle,
    this.deviceIp,
    this.statusMessage = '',
    this.method,
  });

  DiscoveryState copyWith({
    DiscoveryStatus? status,
    String? deviceIp,
    String? statusMessage,
    DiscoveryMethod? method,
  }) {
    return DiscoveryState(
      status: status ?? this.status,
      deviceIp: deviceIp ?? this.deviceIp,
      statusMessage: statusMessage ?? this.statusMessage,
      method: method ?? this.method,
    );
  }
}

class DiscoveryNotifier extends StateNotifier<DiscoveryState> {
  final Ref _ref;
  final DiscoveryService _discovery;
  final ApiService _api;

  DiscoveryNotifier(this._ref, this._discovery, this._api)
      : super(const DiscoveryState());

  Future<void> startDiscovery(String serial, String key) async {
    state = state.copyWith(
      status: DiscoveryStatus.searching,
      statusMessage: 'Starting discovery…',
    );

    try {
      final result = await _discovery.discover(serial, (msg) {
        state = state.copyWith(statusMessage: msg);
      });

      state = state.copyWith(statusMessage: 'Pairing with device…');

      // Pair with device
      final token = await _api.pairDevice(serial, key, hostOverride: result.ip);

      await _ref.read(authSessionProvider.notifier).login(
            host: result.ip,
            port: CubieConstants.apiPort,
            token: token,
            refreshToken: null,
            username: '',
            isAdmin: true,
          );

      state = state.copyWith(
        status: DiscoveryStatus.found,
        deviceIp: result.ip,
        method: result.method,
        statusMessage: 'Device paired successfully!',
      );
    } catch (e) {
      state = state.copyWith(
        status: DiscoveryStatus.failed,
        statusMessage: e.toString(),
      );
    }
  }

  void reset() => state = const DiscoveryState();
}

final discoveryNotifierProvider =
    StateNotifierProvider<DiscoveryNotifier, DiscoveryState>((ref) {
  return DiscoveryNotifier(
    ref,
    ref.read(discoveryServiceProvider),
    ref.read(apiServiceProvider),
  );
});
