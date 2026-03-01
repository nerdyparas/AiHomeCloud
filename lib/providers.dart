import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants.dart';
import 'models/models.dart';
import 'services/discovery_service.dart';
import 'services/mock_api_service.dart';

// ─── Core singletons ───────────────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in ProviderScope at app start');
});

final mockApiServiceProvider = Provider<MockApiService>((ref) {
  return MockApiService.instance;
});

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  return DiscoveryService.instance;
});

// ─── Auth / Setup ───────────────────────────────────────────────────────────

final isSetupDoneProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return prefs.getBool(CubieConstants.prefIsSetupDone) ?? false;
});

final authTokenProvider = StateProvider<String?>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return prefs.getString(CubieConstants.prefAuthToken);
});

final currentUserNameProvider = StateProvider<String?>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return prefs.getString(CubieConstants.prefUserName);
});

final deviceIpProvider = StateProvider<String?>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return prefs.getString(CubieConstants.prefDeviceIp);
});

final deviceSerialProvider = StateProvider<String?>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return prefs.getString(CubieConstants.prefDeviceSerial);
});

// ─── Device info ────────────────────────────────────────────────────────────

final deviceInfoProvider = FutureProvider<CubieDevice>((ref) async {
  final api = ref.read(mockApiServiceProvider);
  return api.getDeviceInfo();
});

// ─── System stats (live stream) ─────────────────────────────────────────────

final systemStatsStreamProvider = StreamProvider<SystemStats>((ref) {
  final api = ref.read(mockApiServiceProvider);
  return api.monitorSystemStats();
});

// ─── Storage ────────────────────────────────────────────────────────────────

final storageStatsProvider = FutureProvider<StorageStats>((ref) async {
  final api = ref.read(mockApiServiceProvider);
  return api.getStorageStats();
});

// ─── Files (parameterised by path) ──────────────────────────────────────────

final fileListProvider =
    FutureProvider.family<List<FileItem>, String>((ref, path) async {
  final api = ref.read(mockApiServiceProvider);
  return api.listFiles(path);
});

// ─── Family ─────────────────────────────────────────────────────────────────

final familyUsersProvider = FutureProvider<List<FamilyUser>>((ref) async {
  final api = ref.read(mockApiServiceProvider);
  return api.getFamilyUsers();
});

// ─── Services ───────────────────────────────────────────────────────────────

final servicesProvider = FutureProvider<List<ServiceInfo>>((ref) async {
  final api = ref.read(mockApiServiceProvider);
  return api.getServices();
});

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
  final DiscoveryService _discovery;
  final MockApiService _api;

  DiscoveryNotifier(this._discovery, this._api)
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
      await _api.pairDevice(serial, key);

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
    ref.read(discoveryServiceProvider),
    ref.read(mockApiServiceProvider),
  );
});
