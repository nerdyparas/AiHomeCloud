part of '../api_service.dart';

/// NAS service control and network toggle API.
extension ServicesNetworkApi on ApiService {
  /// GET /api/v1/services
  Future<List<ServiceInfo>> getServices() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/services'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) {
      return ServiceInfo(
        id: item['id'],
        name: item['name'],
        description: item['description'],
        isEnabled: item['isEnabled'] as bool,
        icon: ApiService._serviceIcon(item['id']),
      );
    }).toList();
  }

  /// POST /api/v1/services/<id>/toggle  body: {enabled}
  Future<void> toggleService(String serviceId, bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/services/$serviceId/toggle'),
            headers: _headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// GET /api/v1/network/status
  Future<NetworkStatus> getNetworkStatus() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/network/status'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return NetworkStatus.fromJson(jsonDecode(res.body));
  }

  /// POST /api/v1/network/wifi  body: {enabled}
  Future<void> toggleWifi(bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/network/wifi'),
            headers: _headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// POST /api/v1/network/hotspot  body: {enabled}
  Future<void> toggleHotspot(bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/network/hotspot'),
            headers: _headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 15)),
    );
    _check(res);
  }

  /// POST /api/v1/network/bluetooth  body: {enabled}
  Future<void> toggleBluetooth(bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/network/bluetooth'),
            headers: _headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// GET /api/v1/network/wifi/scan — list available Wi-Fi networks
  Future<List<WifiNetwork>> scanWifiNetworks() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/network/wifi/scan'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15)),
    );
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) => WifiNetwork.fromJson(item)).toList();
  }

  /// POST /api/v1/network/wifi/connect  body: {ssid, password}
  Future<WifiConnectionResult> connectWifi(String ssid, String password) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/network/wifi/connect'),
            headers: _headers,
            body: jsonEncode({'ssid': ssid, 'password': password}),
          )
          .timeout(const Duration(seconds: 35)),
    );
    _check(res);
    return WifiConnectionResult.fromJson(jsonDecode(res.body));
  }

  /// POST /api/v1/network/wifi/disconnect
  Future<void> disconnectWifi() async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/network/wifi/disconnect'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// DELETE /api/v1/network/wifi/saved/{ssid}
  Future<void> forgetWifiNetwork(String ssid) async {
    final encoded = Uri.encodeComponent(ssid);
    final res = await _withAutoRefresh(
      () => _client
          .delete(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/network/wifi/saved/$encoded'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// GET /api/v1/network/wifi/saved — list saved Wi-Fi profiles
  Future<List<WifiNetwork>> getSavedWifiNetworks() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse(
                '$_baseUrl${AppConstants.apiVersion}/network/wifi/saved'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) => WifiNetwork.fromJson(item)).toList();
  }

  // ── AdGuard Home proxy endpoints ──────────────────────────────────────────

  /// GET /api/v1/adguard/stats
  Future<Map<String, dynamic>> getAdGuardStats() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/adguard/stats'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return (jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /api/v1/adguard/toggle  body: {enabled}
  Future<void> toggleAdGuard(bool enabled) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/adguard/toggle'),
            headers: _headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  /// POST /api/v1/adguard/pause  body: {minutes}
  Future<void> pauseAdGuard(int minutes) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/adguard/pause'),
            headers: _headers,
            body: jsonEncode({'minutes': minutes}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }

  // ── Telegram Bot config endpoints ─────────────────────────────────────────

  /// GET /api/v1/telegram/config
  Future<Map<String, dynamic>> getTelegramConfig() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/telegram/config'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    return (jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /api/v1/telegram/config  body: {bot_token}
  Future<void> saveTelegramConfig(String botToken) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${AppConstants.apiVersion}/telegram/config'),
            headers: _headers,
            body: jsonEncode({'bot_token': botToken}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }
}
