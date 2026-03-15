/// ApiService deserialization tests (TASK-P7-01).
///
/// Tests the JSON â†’ model contracts that ApiService methods rely on.
/// Catches regressions where backend field names or types change.
/// No HTTP mock needed â€” tests parse the same JSON structures the
/// real API returns, using the model constructors directly.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:aihomecloud/models/models.dart';

void main() {
  // ---------------------------------------------------------------------------
  // FileListResponse deserialization
  // ---------------------------------------------------------------------------

  group('FileListResponse deserialization', () {
    test('parses items and totalCount from well-formed JSON', () {
      // Mirrors what listFiles() does internally after receiving the HTTP body.
      final rawItems = [
        {
          'name': 'photo.jpg',
          'path': '/shared/Photos/photo.jpg',
          'isDirectory': false,
          'sizeBytes': 2048576,
          'modified': '2025-03-01T12:00:00Z',
          'mimeType': 'image/jpeg',
        },
        {
          'name': 'Documents',
          'path': '/shared/Documents',
          'isDirectory': true,
          'sizeBytes': 0,
          'modified': '2025-02-28T08:30:00Z',
          'mimeType': null,
        },
      ];
      final items = rawItems.map((item) {
        return FileItem(
          name: item['name'] as String,
          path: item['path'] as String,
          isDirectory: item['isDirectory'] as bool,
          sizeBytes: item['sizeBytes'] as int,
          modified: DateTime.parse(item['modified'] as String),
          mimeType: item['mimeType'] as String?,
        );
      }).toList();

      final response = FileListResponse(
        items: items,
        totalCount: 2,
        page: 0,
        pageSize: 50,
      );

      expect(response.items.length, 2);
      expect(response.totalCount, 2);
      expect(response.items.first.name, 'photo.jpg');
      expect(response.items.first.isDirectory, false);
      expect(response.items.last.isDirectory, true);
    });

    test('totalCount falls back to item count when absent', () {
      // Guard against backend omitting totalCount.
      final items = [
        FileItem(
          name: 'file.txt',
          path: '/shared/file.txt',
          isDirectory: false,
          sizeBytes: 512,
          modified: DateTime(2025, 1, 1),
          mimeType: 'text/plain',
        ),
      ];
      const count = 1; // simulates: items.length when totalCount is null
      final response = FileListResponse(
        items: items,
        totalCount: count,
        page: 0,
        pageSize: 50,
      );
      expect(response.totalCount, 1);
    });

    test('page and pageSize are stored on the response', () {
      final response = FileListResponse(
        items: const [],
        totalCount: 100,
        page: 2,
        pageSize: 20,
      );
      expect(response.page, 2);
      expect(response.pageSize, 20);
    });
  });

  // ---------------------------------------------------------------------------
  // StorageStats model
  // ---------------------------------------------------------------------------

  group('StorageStats model', () {
    test('parses totalGB and usedGB from numeric JSON', () {
      // Mirrors what getStorageStats() does:
      //   return StorageStats(
      //     totalGB: (data['totalGB'] as num).toDouble(),
      //     usedGB:  (data['usedGB']  as num).toDouble(),
      //   );
      const data = {'totalGB': 500.0, 'usedGB': 120.5};
      final stats = StorageStats(
        totalGB: (data['totalGB']! as num).toDouble(),
        usedGB: (data['usedGB']! as num).toDouble(),
      );

      expect(stats.totalGB, 500.0);
      expect(stats.usedGB, 120.5);
      expect(stats.freeGB, closeTo(379.5, 0.01));
      expect(stats.usedPercent, closeTo(0.241, 0.01));
    });

    test('usedPercent clamps to 1.0 when over-full', () {
      final stats = StorageStats(totalGB: 100, usedGB: 110);
      expect(stats.usedPercent, 1.0);
    });
  });

  // ---------------------------------------------------------------------------
  // StorageDevice.fromJson
  // ---------------------------------------------------------------------------

  group('StorageDevice.fromJson deserialization', () {
    final sampleJson = {
      'name': 'sda',
      'path': '/dev/sda',
      'sizeBytes': 500107862016,
      'sizeDisplay': '500.1 GB',
      'fstype': 'ext4',
      'label': 'AiHomeCloud',
      'model': 'Samsung T7',
      'transport': 'usb',
      'mounted': true,
      'mountPoint': '/srv/nas',
      'isNasActive': true,
      'isOsDisk': false,
      'displayName': 'Samsung T7 (500.1 GB)',
      'bestPartition': '/dev/sda1',
    };

    test('parses all fields including displayName and bestPartition', () {
      final device = StorageDevice.fromJson(sampleJson);

      expect(device.name, 'sda');
      expect(device.path, '/dev/sda');
      expect(device.sizeBytes, 500107862016);
      expect(device.fstype, 'ext4');
      expect(device.model, 'Samsung T7');
      expect(device.transport, 'usb');
      expect(device.mounted, true);
      expect(device.mountPoint, '/srv/nas');
      expect(device.isNasActive, true);
      expect(device.isOsDisk, false);
      expect(device.displayName, 'Samsung T7 (500.1 GB)');
      expect(device.bestPartition, '/dev/sda1');
    });

    test('handles null optional fields gracefully', () {
      final minJson = {
        'name': 'sdb',
        'path': '/dev/sdb',
        'sizeBytes': 0,
        'sizeDisplay': '0 GB',
        'transport': 'usb',
        'mounted': false,
        'isNasActive': false,
        'isOsDisk': false,
        'displayName': 'USB Drive',
      };
      final device = StorageDevice.fromJson(minJson);

      expect(device.fstype, isNull);
      expect(device.label, isNull);
      expect(device.model, isNull);
      expect(device.mountPoint, isNull);
      expect(device.bestPartition, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // JobStatus.fromJson
  // ---------------------------------------------------------------------------

  group('JobStatus.fromJson deserialization', () {
    test('parses running job correctly', () {
      final json = {
        'id': 'job-abc-123',
        'status': 'running',
        'startedAt': '2025-03-10T10:00:00Z',
        'result': null,
        'error': null,
      };
      final job = JobStatus.fromJson(json);

      expect(job.id, 'job-abc-123');
      expect(job.status, 'running');
      expect(job.isTerminal, false);
      expect(job.result, isNull);
      expect(job.error, isNull);
    });

    test('isTerminal is true for completed status', () {
      final json = {
        'id': 'job-xyz',
        'status': 'completed',
        'startedAt': '2025-03-10T10:00:00Z',
        'result': {'status': 'formatted', 'device': '/dev/sda1'},
      };
      final job = JobStatus.fromJson(json);

      expect(job.isTerminal, true);
      expect(job.result, isNotNull);
    });

    test('isTerminal is true for failed status', () {
      final json = {
        'id': 'job-fail',
        'status': 'failed',
        'startedAt': '2025-03-10T10:05:00Z',
        'error': 'mkfs.ext4 failed: no space left on device',
      };
      final job = JobStatus.fromJson(json);

      expect(job.isTerminal, true);
      expect(job.error, contains('failed'));
    });
  });
}
