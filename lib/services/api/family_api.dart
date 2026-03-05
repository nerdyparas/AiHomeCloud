part of '../api_service.dart';

/// Family user management API.
extension FamilyApi on ApiService {
  /// GET /api/v1/users/family
  Future<List<FamilyUser>> getFamilyUsers() async {
    final res = await _withAutoRefresh(
      () => _client
          .get(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/family'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final List<dynamic> list = jsonDecode(res.body);
    return list.map((item) {
      // Parse hex colour string from backend (e.g. "FFE8A84C")
      final colorHex = item['avatarColor'] as String;
      final colorValue = int.parse(colorHex, radix: 16);

      return FamilyUser(
        id: item['id'],
        name: item['name'],
        isAdmin: item['isAdmin'] as bool,
        folderSizeGB: (item['folderSizeGB'] as num).toDouble(),
        avatarColor: Color(colorValue),
      );
    }).toList();
  }

  /// POST /api/v1/users/family  body: {name}
  Future<FamilyUser> addFamilyUser(String name) async {
    final res = await _withAutoRefresh(
      () => _client
          .post(
            Uri.parse('$_baseUrl${CubieConstants.apiVersion}/users/family'),
            headers: _headers,
            body: jsonEncode({'name': name}),
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
    final item = jsonDecode(res.body);
    final colorHex = item['avatarColor'] as String;
    final colorValue = int.parse(colorHex, radix: 16);

    return FamilyUser(
      id: item['id'],
      name: item['name'],
      isAdmin: item['isAdmin'] as bool,
      folderSizeGB: (item['folderSizeGB'] as num).toDouble(),
      avatarColor: Color(colorValue),
    );
  }

  /// DELETE /api/v1/users/family/<id>
  Future<void> removeFamilyUser(String userId) async {
    final res = await _withAutoRefresh(
      () => _client
          .delete(
            Uri.parse(
                '$_baseUrl${CubieConstants.apiVersion}/users/family/$userId'),
            headers: _headers,
          )
          .timeout(ApiService._timeout),
    );
    _check(res);
  }
}
