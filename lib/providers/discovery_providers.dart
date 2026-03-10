/// Discovery providers — QR payload, mDNS/BLE device discovery, fingerprint trust.
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/error_utils.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/discovery_service.dart';
import 'core_providers.dart';

final qrPayloadProvider = StateProvider<QrPairPayload?>((ref) => null);

enum DiscoveryStatus { idle, searching, found, failed }

const _pendingFingerprintUnset = Object();

class DiscoveryState {
  final DiscoveryStatus status;
  final String? deviceIp;
  final String statusMessage;
  final DiscoveryMethod? method;
  final String? pendingFingerprint;

  const DiscoveryState({
    this.status = DiscoveryStatus.idle,
    this.deviceIp,
    this.statusMessage = '',
    this.method,
    this.pendingFingerprint,
  });

  DiscoveryState copyWith({
    DiscoveryStatus? status,
    String? deviceIp,
    String? statusMessage,
    DiscoveryMethod? method,
    Object? pendingFingerprint = _pendingFingerprintUnset,
  }) {
    return DiscoveryState(
      status: status ?? this.status,
      deviceIp: deviceIp ?? this.deviceIp,
      statusMessage: statusMessage ?? this.statusMessage,
      method: method ?? this.method,
      pendingFingerprint: pendingFingerprint == _pendingFingerprintUnset
          ? this.pendingFingerprint
          : pendingFingerprint as String?,
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
      pendingFingerprint: null,
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
            port: AppConstants.apiPort,
            token: token,
            refreshToken: null,
            username: '',
            isAdmin: true,
          );

      final fingerprint = await _api.fetchServerFingerprint(
        host: result.ip,
        port: AppConstants.apiPort,
      );
      await _handleFingerprint(result, fingerprint);
    } catch (e) {
      state = state.copyWith(
        status: DiscoveryStatus.failed,
        statusMessage: friendlyError(e),
        pendingFingerprint: null,
      );
    }
  }

  Future<void> _handleFingerprint(
      DiscoveryResult result, String? fingerprint) async {
    final stored = _ref.read(certFingerprintProvider);
    if (fingerprint == null) {
      state = state.copyWith(
        status: DiscoveryStatus.found,
        deviceIp: result.ip,
        method: result.method,
        statusMessage:
            'Device paired, but unable to fetch certificate fingerprint.',
        pendingFingerprint: null,
      );
      return;
    }

    if (stored == null || stored.isEmpty) {
      state = state.copyWith(
        status: DiscoveryStatus.found,
        deviceIp: result.ip,
        method: result.method,
        statusMessage:
            'Confirm this server certificate fingerprint before trusting the device.',
        pendingFingerprint: fingerprint,
      );
      return;
    }

    if (stored != fingerprint) {
      state = state.copyWith(
        status: DiscoveryStatus.failed,
        deviceIp: result.ip,
        method: result.method,
        statusMessage: 'Server certificate fingerprint mismatch detected.',
        pendingFingerprint: null,
      );
      return;
    }

    _api.setTrustedFingerprint(stored);
    state = state.copyWith(
      status: DiscoveryStatus.found,
      deviceIp: result.ip,
      method: result.method,
      statusMessage: 'Device paired successfully!',
      pendingFingerprint: null,
    );
  }

  Future<void> trustFingerprint(String fingerprint) async {
    await persistServerFingerprint(_ref, fingerprint);
    state = state.copyWith(
      statusMessage: 'Server certificate trusted.',
      pendingFingerprint: null,
    );
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
