import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/models.dart';

/// Singleton mock API service.
/// Every method documents the real endpoint it maps to.
/// Swap this class for a real HTTP client without touching any screen.
class MockApiService {
  MockApiService._();
  static final MockApiService instance = MockApiService._();

  final _rng = Random();

  Future<void> _delay([int minMs = 300, int maxMs = 800]) async {
    await Future.delayed(
        Duration(milliseconds: minMs + _rng.nextInt(maxMs - minMs)));
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // AUTH
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// TODO: POST https://<host>:8443/api/v1/pair  body: {serial, key}
  /// Returns a JWT token on success.
  Future<String> pairDevice(String serial, String key) async {
    await _delay();
    if (serial.isEmpty || key.isEmpty) {
      throw Exception('Invalid serial or pairing key');
    }
    return 'mock_jwt_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// TODO: POST https://<host>:8443/api/v1/users  body: {name, pin}
  Future<void> createUser(String name, String? pin) async {
    await _delay();
    if (name.trim().isEmpty) throw Exception('Name cannot be empty');
  }

  /// TODO: POST https://<host>:8443/api/v1/auth/logout
  Future<void> logout() async {
    await _delay(200, 400);
  }

  /// TODO: PUT https://<host>:8443/api/v1/users/pin  body: {old_pin, new_pin}
  Future<void> changePin(String? oldPin, String newPin) async {
    await _delay();
    if (newPin.length < 4) throw Exception('PIN must be at least 4 digits');
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // SYSTEM / MONITORING
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// TODO: GET https://<host>:8443/api/v1/system/info
  Future<AhcDevice> getDeviceInfo() async {
    await _delay();
    return const AhcDevice(
      serial: 'AHC-A5E-2024-001',
      name: 'My AiHomeCloud',
      ip: '192.168.1.42',
      firmwareVersion: '2.1.4',
    );
  }

  /// TODO: WebSocket wss://<host>:8443/ws/monitor
  /// Simulates live system stats every 2 seconds.
  Stream<SystemStats> monitorSystemStats() {
    return Stream.periodic(const Duration(seconds: 2), (tick) {
      return SystemStats(
        cpuPercent: 12.0 + _rng.nextDouble() * 30.0,
        ramPercent: 45.0 + _rng.nextDouble() * 20.0,
        tempCelsius: 38.0 + _rng.nextDouble() * 12.0,
        uptime: Duration(hours: 72 + tick, minutes: 34),
        networkUpMbps: 0.5 + _rng.nextDouble() * 15.0,
        networkDownMbps: 1.0 + _rng.nextDouble() * 45.0,
        storage: StorageStats(
          totalGB: AppConstants.totalStorageGB,
          usedGB: 127.3 + _rng.nextDouble() * 0.1,
        ),
      );
    });
  }

  /// TODO: GET https://<host>:8443/api/v1/storage/stats
  Future<StorageStats> getStorageStats() async {
    await _delay();
    return StorageStats(
      totalGB: AppConstants.totalStorageGB,
      usedGB: 127.3 + _rng.nextDouble() * 0.1,
    );
  }

  /// TODO: GET https://<host>:8443/api/v1/system/firmware
  Future<Map<String, dynamic>> checkFirmwareUpdate() async {
    await _delay(500, 1500);
    return {
      'current_version': '2.1.4',
      'latest_version': '2.2.0',
      'update_available': true,
      'changelog':
          'Bug fixes and performance improvements.\nAdded SMB3 support.\nImproved thermal management.',
      'size_mb': 156.2,
    };
  }

  /// TODO: POST https://<host>:8443/api/v1/system/update
  Future<void> triggerOtaUpdate() async {
    await _delay(1000, 2000);
  }

  /// TODO: PUT https://<host>:8443/api/v1/system/name  body: {name}
  Future<void> updateDeviceName(String name) async {
    await _delay();
    if (name.trim().isEmpty) throw Exception('Name cannot be empty');
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // FILES
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// TODO: GET https://<host>:8443/api/v1/files/list?path=<path>
  Future<List<FileItem>> listFiles(String path) async {
    await _delay();
    if (path == AppConstants.sharedPath) return _sharedFiles();
    if (path.startsWith(AppConstants.personalBasePath)) {
      return _personalFiles(path);
    }
    return _genericFiles(path);
  }

  /// TODO: POST https://<host>:8443/api/v1/files/mkdir  body: {path}
  Future<void> createFolder(String parentPath, String name) async {
    await _delay();
    if (name.trim().isEmpty) throw Exception('Folder name cannot be empty');
  }

  /// TODO: DELETE https://<host>:8443/api/v1/files/delete?path=<path>
  Future<void> deleteFile(String path) async {
    await _delay();
  }

  /// TODO: PUT https://<host>:8443/api/v1/files/rename  body: {old_path, new_name}
  Future<void> renameFile(String path, String newName) async {
    await _delay();
    if (newName.trim().isEmpty) throw Exception('Name cannot be empty');
  }

  /// TODO: POST https://<host>:8443/api/v1/files/upload (multipart, chunked 1 MB)
  /// Emits cumulative uploaded bytes until complete.
  Stream<int> uploadFile(
      String destinationPath, String fileName, int totalBytes) {
    final ctrl = StreamController<int>();
    int uploaded = 0;

    Timer.periodic(const Duration(milliseconds: 150), (timer) {
      final chunk = min(AppConstants.uploadChunkSize, totalBytes - uploaded);
      uploaded += chunk;
      ctrl.add(uploaded);

      if (uploaded >= totalBytes) {
        timer.cancel();
        ctrl.close();
      }
    });

    return ctrl.stream;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // FAMILY / USERS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// TODO: GET https://<host>:8443/api/v1/users/family
  Future<List<FamilyUser>> getFamilyUsers() async {
    await _delay();
    return const [
      FamilyUser(
          id: 'user_1',
          name: 'Dad',
          isAdmin: true,
          folderSizeGB: 45.2,
          avatarColor: Color(0xFFE8A84C)),
      FamilyUser(
          id: 'user_2',
          name: 'Mom',
          isAdmin: false,
          folderSizeGB: 32.7,
          avatarColor: Color(0xFF4C9BE8)),
      FamilyUser(
          id: 'user_3',
          name: 'Alex',
          isAdmin: false,
          folderSizeGB: 18.5,
          avatarColor: Color(0xFF4CE88A)),
      FamilyUser(
          id: 'user_4',
          name: 'Sophie',
          isAdmin: false,
          folderSizeGB: 12.1,
          avatarColor: Color(0xFFE84CA8)),
    ];
  }

  /// TODO: POST https://<host>:8443/api/v1/users/family  body: {name}
  Future<FamilyUser> addFamilyUser(String name) async {
    await _delay();
    if (name.trim().isEmpty) throw Exception('Name cannot be empty');
    return FamilyUser(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      isAdmin: false,
      folderSizeGB: 0.0,
      avatarColor: Color(0xFF000000 + _rng.nextInt(0xFFFFFF)),
    );
  }

  /// TODO: DELETE https://<host>:8443/api/v1/users/family/<id>
  Future<void> removeFamilyUser(String userId) async {
    await _delay();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // SERVICES
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// TODO: GET https://<host>:8443/api/v1/services
  Future<List<ServiceInfo>> getServices() async {
    await _delay();
    return const [
      ServiceInfo(
          id: 'media',
          name: 'TV & Computer Sharing',
          description: 'DLNA streaming + SMB file sharing',
          isEnabled: true,
          icon: Icons.tv_rounded),
      ServiceInfo(
          id: 'nfs',
          name: 'NFS',
          description: 'Linux / Mac network filesystem',
          isEnabled: false,
          icon: Icons.dns_rounded),
      ServiceInfo(
          id: 'ssh',
          name: 'SSH',
          description: 'Secure remote terminal',
          isEnabled: true,
          icon: Icons.terminal_rounded),
    ];
  }

  /// TODO: POST https://<host>:8443/api/v1/services/<name>/toggle  body: {enabled}
  Future<void> toggleService(String serviceId, bool enabled) async {
    await _delay();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // PRIVATE â€” mock file listings
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  List<FileItem> _sharedFiles() {
    final now = DateTime.now();
    return [
      FileItem(
          name: 'Family Photos',
          path: '${AppConstants.sharedPath}Family Photos/',
          isDirectory: true,
          sizeBytes: 0,
          modified: now.subtract(const Duration(hours: 2))),
      FileItem(
          name: 'Movies',
          path: '${AppConstants.sharedPath}Movies/',
          isDirectory: true,
          sizeBytes: 0,
          modified: now.subtract(const Duration(days: 5))),
      FileItem(
          name: 'Music',
          path: '${AppConstants.sharedPath}Music/',
          isDirectory: true,
          sizeBytes: 0,
          modified: now.subtract(const Duration(days: 12))),
      FileItem(
          name: 'Documents',
          path: '${AppConstants.sharedPath}Documents/',
          isDirectory: true,
          sizeBytes: 0,
          modified: now.subtract(const Duration(days: 1))),
      FileItem(
          name: 'vacation_2025.mp4',
          path: '${AppConstants.sharedPath}vacation_2025.mp4',
          isDirectory: false,
          sizeBytes: 2147483648,
          modified: now.subtract(const Duration(days: 30)),
          mimeType: 'video/mp4'),
      FileItem(
          name: 'recipe_collection.pdf',
          path: '${AppConstants.sharedPath}recipe_collection.pdf',
          isDirectory: false,
          sizeBytes: 15728640,
          modified: now.subtract(const Duration(days: 3)),
          mimeType: 'application/pdf'),
    ];
  }

  List<FileItem> _personalFiles(String path) {
    final now = DateTime.now();
    final bp = path.endsWith('/') ? path : '$path/';
    return [
      FileItem(
          name: 'Work',
          path: '${bp}Work/',
          isDirectory: true,
          sizeBytes: 0,
          modified: now.subtract(const Duration(hours: 6))),
      FileItem(
          name: 'Backups',
          path: '${bp}Backups/',
          isDirectory: true,
          sizeBytes: 0,
          modified: now.subtract(const Duration(days: 2))),
      FileItem(
          name: 'Screenshots',
          path: '${bp}Screenshots/',
          isDirectory: true,
          sizeBytes: 0,
          modified: now.subtract(const Duration(hours: 1))),
      FileItem(
          name: 'notes.txt',
          path: '${bp}notes.txt',
          isDirectory: false,
          sizeBytes: 4096,
          modified: now.subtract(const Duration(minutes: 30)),
          mimeType: 'text/plain'),
      FileItem(
          name: 'presentation.pdf',
          path: '${bp}presentation.pdf',
          isDirectory: false,
          sizeBytes: 8388608,
          modified: now.subtract(const Duration(days: 1)),
          mimeType: 'application/pdf'),
      FileItem(
          name: 'profile_photo.jpg',
          path: '${bp}profile_photo.jpg',
          isDirectory: false,
          sizeBytes: 3145728,
          modified: now.subtract(const Duration(days: 14)),
          mimeType: 'image/jpeg'),
      FileItem(
          name: 'budget_2025.xlsx',
          path: '${bp}budget_2025.xlsx',
          isDirectory: false,
          sizeBytes: 524288,
          modified: now.subtract(const Duration(days: 7))),
      FileItem(
          name: 'project_archive.zip',
          path: '${bp}project_archive.zip',
          isDirectory: false,
          sizeBytes: 104857600,
          modified: now.subtract(const Duration(days: 21)),
          mimeType: 'application/zip'),
    ];
  }

  List<FileItem> _genericFiles(String path) {
    final now = DateTime.now();
    final bp = path.endsWith('/') ? path : '$path/';
    return [
      FileItem(
          name: 'Subfolder',
          path: '${bp}Subfolder/',
          isDirectory: true,
          sizeBytes: 0,
          modified: now.subtract(const Duration(hours: 3))),
      FileItem(
          name: 'document.pdf',
          path: '${bp}document.pdf',
          isDirectory: false,
          sizeBytes: 2097152,
          modified: now.subtract(const Duration(days: 2)),
          mimeType: 'application/pdf'),
      FileItem(
          name: 'photo.jpg',
          path: '${bp}photo.jpg',
          isDirectory: false,
          sizeBytes: 4194304,
          modified: now.subtract(const Duration(days: 1)),
          mimeType: 'image/jpeg'),
      FileItem(
          name: 'song.mp3',
          path: '${bp}song.mp3',
          isDirectory: false,
          sizeBytes: 7340032,
          modified: now.subtract(const Duration(days: 5)),
          mimeType: 'audio/mpeg'),
    ];
  }
}
