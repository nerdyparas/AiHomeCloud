part of '../api_service.dart';

/// Device info, firmware, system monitoring, and WebSocket streams.
extension SystemApi on ApiService {
  /// GET /api/v1/system/info
  Future<CubieDevice> getDeviceInfo() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/system/info'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final data = jsonDecode(res.body);
    return CubieDevice(
      serial: data['serial'],
      name: data['name'],
      ip: data['ip'],
      firmwareVersion: data['firmwareVersion'],
    );
  }

  /// WebSocket /ws/monitor â€” streams SystemStats every 2 s.
  Stream<SystemStats> monitorSystemStats() {
    final host = _session?.host;
    final port = _session?.port ?? AppConstants.apiPort;
    final token = _session?.token;
    if (host == null || host.isEmpty) {
      throw StateError('Host is not configured in auth session');
    }
    final uri = Uri.parse(
      'wss://$host:$port/ws/monitor${token != null ? '?token=$token' : ''}',
    );
    final channel = IOWebSocketChannel.connect(
      uri,
      customClient: _createPinnedHttpClient(),
    );

    _connectionStatusCallback?.call(ConnectionStatus.connected);
    int missedBeats = 0;
    final ctrl = StreamController<SystemStats>();
    channel.stream.listen(
      (raw) {
        missedBeats = 0;
        _connectionStatusCallback?.call(ConnectionStatus.connected);
        final data = jsonDecode(raw as String);
        ctrl.add(SystemStats(
          cpuPercent: (data['cpuPercent'] as num).toDouble(),
          ramPercent: (data['ramPercent'] as num).toDouble(),
          tempCelsius: (data['tempCelsius'] as num).toDouble(),
          uptime: Duration(seconds: data['uptimeSeconds'] as int),
          networkUpMbps: (data['networkUpMbps'] as num).toDouble(),
          networkDownMbps: (data['networkDownMbps'] as num).toDouble(),
          storage: StorageStats(
            totalGB: (data['storage']['totalGB'] as num).toDouble(),
            usedGB: (data['storage']['usedGB'] as num).toDouble(),
          ),
        ));
      },
      onError: (e, st) {
        missedBeats++;
        if (missedBeats >= 2) {
          _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
        }
        ctrl.addError(e, st);
      },
      onDone: () {
        missedBeats++;
        if (missedBeats >= 2) {
          _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
        }
        ctrl.close();
      },
      cancelOnError: false,
    );
    return ctrl.stream;
  }

  /// WebSocket /ws/events â€” real-time notification stream from the backend.
  Stream<AppNotification> notificationStream() {
    final host = _session?.host;
    final port = _session?.port ?? AppConstants.apiPort;
    final token = _session?.token;
    if (host == null || host.isEmpty) {
      throw StateError('Host is not configured in auth session');
    }
    final uri = Uri.parse(
      'wss://$host:$port/ws/events${token != null ? '?token=$token' : ''}',
    );
    final channel = IOWebSocketChannel.connect(
      uri,
      customClient: _createPinnedHttpClient(),
    );

    int missedBeats = 0;
    final ctrl = StreamController<AppNotification>();
    channel.stream.listen(
      (raw) {
        missedBeats = 0;
        _connectionStatusCallback?.call(ConnectionStatus.connected);
        final data = jsonDecode(raw as String);
        ctrl.add(AppNotification.fromJson(data));
      },
      onError: (e, st) {
        missedBeats++;
        if (missedBeats >= 2) {
          _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
        }
        ctrl.addError(e, st);
      },
      onDone: () {
        missedBeats++;
        if (missedBeats >= 2) {
          _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
        }
        ctrl.close();
      },
      cancelOnError: false,
    );
    return ctrl.stream;
  }

  /// GET /api/v1/system/firmware
  Future<Map<String, dynamic>> checkFirmwareUpdate() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/system/firmware'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return jsonDecode(res.body);
  }

  /// POST /api/v1/system/update
  Future<void> triggerOtaUpdate() async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/system/update'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// PUT /api/v1/system/name  body: {name}
  Future<void> updateDeviceName(String name) async {
    final res = await _withAutoRefresh(
      () => _client
          .put(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/system/name'),
            headers: _headers,
            body: jsonEncode({'name': name}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// POST /api/v1/system/shutdown — stop all services and power off
  Future<void> shutdownDevice() async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/system/shutdown'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30)),
    );
    _check(res);
  }

  /// POST /api/v1/system/reboot — restart the device
  Future<void> rebootDevice() async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/system/reboot'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30)),
    );
    _check(res);
  }

  /// GET /api/v1/system/tailscale-status — current Tailscale connectivity state.
  Future<Map<String, dynamic>> getTailscaleStatus() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/system/tailscale-status'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// POST /api/v1/system/tailscale-up — bring Tailscale up (admin only).
  Future<Map<String, dynamic>> tailscaleUp() async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/system/tailscale-up'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

}
