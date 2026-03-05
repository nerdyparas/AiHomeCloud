/// Device state providers — device info, system stats stream, connection status,
/// storage stats, and storage device listing.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'core_providers.dart';

final deviceInfoProvider = FutureProvider<CubieDevice>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getDeviceInfo();
});

final systemStatsStreamProvider = StreamProvider<SystemStats>((ref) {
  final api = ref.read(apiServiceProvider);
  return api.monitorSystemStats();
});

class ConnectionNotifier extends StateNotifier<ConnectionStatus> {
  ConnectionNotifier() : super(ConnectionStatus.connected);

  Timer? _debounceTimer;
  final List<int> reconnectBackoff = [2, 4, 8, 16, 30];
  int _attempt = 0;

  int get currentBackoffSeconds =>
      reconnectBackoff[_attempt.clamp(0, reconnectBackoff.length - 1)];

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

final storageStatsProvider = FutureProvider<StorageStats>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getStorageStats();
});

final storageDevicesProvider = FutureProvider<List<StorageDevice>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getStorageDevices();
});
