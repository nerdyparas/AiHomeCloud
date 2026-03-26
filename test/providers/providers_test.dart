/// Provider unit tests (P2-Task 20).
///
/// Covers the five provider files that had 0 test coverage:
///   - core_providers: certFingerprintProvider, isSetupDoneProvider
///   - discovery_providers: DiscoveryState.copyWith, DiscoveryNotifier.reset
///   - file_providers: UploadTasksNotifier CRUD, FileListNotifier static cache
///   - data_providers: NotificationHistoryNotifier add/clear/cap
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/core/constants.dart';
import 'package:aihomecloud/models/models.dart';
import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/providers/discovery_providers.dart';
import 'package:aihomecloud/services/discovery_service.dart';
import 'package:aihomecloud/providers/file_providers.dart';
import 'package:aihomecloud/providers/data_providers.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Future<SharedPreferences> _mockPrefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  // ─── core_providers ────────────────────────────────────────────────────────

  group('certFingerprintProvider', () {
    test('returns null when no fingerprint stored', () async {
      final prefs = await _mockPrefs();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);

      expect(container.read(certFingerprintProvider), isNull);
    });

    test('returns stored fingerprint on initialisation', () async {
      final prefs = await _mockPrefs({
        AppConstants.kCertFingerprintPrefKey: 'AB:CD:EF:12:34',
      });
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);

      expect(container.read(certFingerprintProvider), 'AB:CD:EF:12:34');
    });

    test('state can be updated after creation', () async {
      final prefs = await _mockPrefs();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);

      container.read(certFingerprintProvider.notifier).state = 'NEW:FP';
      expect(container.read(certFingerprintProvider), 'NEW:FP');
    });
  });

  group('isSetupDoneProvider', () {
    test('returns false when pref not set', () async {
      final prefs = await _mockPrefs();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);

      expect(container.read(isSetupDoneProvider), false);
    });

    test('returns true when pref is set to true', () async {
      final prefs = await _mockPrefs({AppConstants.prefIsSetupDone: true});
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);

      expect(container.read(isSetupDoneProvider), true);
    });
  });

  // ─── discovery_providers ───────────────────────────────────────────────────

  group('DiscoveryState.copyWith', () {
    const base = DiscoveryState();

    test('default state is idle with no IP', () {
      expect(base.status, DiscoveryStatus.idle);
      expect(base.deviceIp, isNull);
      expect(base.pendingFingerprint, isNull);
      expect(base.statusMessage, '');
    });

    test('copyWith replaces only the specified fields', () {
      final next = base.copyWith(
        status: DiscoveryStatus.searching,
        statusMessage: 'Looking…',
      );
      expect(next.status, DiscoveryStatus.searching);
      expect(next.statusMessage, 'Looking…');
      expect(next.deviceIp, isNull);   // unchanged
    });

    test('copyWith with explicit null pendingFingerprint clears it', () {
      const withFp = DiscoveryState(pendingFingerprint: 'AA:BB');
      final cleared = withFp.copyWith(pendingFingerprint: null);
      expect(cleared.pendingFingerprint, isNull);
    });

    test('copyWith without pendingFingerprint argument preserves existing value', () {
      const withFp = DiscoveryState(pendingFingerprint: 'AA:BB');
      final next = withFp.copyWith(status: DiscoveryStatus.found);
      expect(next.pendingFingerprint, 'AA:BB');  // preserved
    });

    test('found state carries IP and method', () {
      final found = base.copyWith(
        status: DiscoveryStatus.found,
        deviceIp: '192.168.0.50',
        method: DiscoveryMethod.mdns,
      );
      expect(found.deviceIp, '192.168.0.50');
      expect(found.method, DiscoveryMethod.mdns);
    });
  });

  // ─── file_providers ────────────────────────────────────────────────────────

  group('UploadTasksNotifier', () {
    late UploadTasksNotifier notifier;

    setUp(() => notifier = UploadTasksNotifier());
    tearDown(() => notifier.dispose());

    test('starts empty', () {
      expect(notifier.state, isEmpty);
    });

    test('addTask appends a task', () {
      final task = UploadTask(
        id: 'task-1',
        fileName: 'photo.jpg',
        totalBytes: 1024,
        uploadedBytes: 0,
        status: UploadStatus.queued,
      );
      notifier.addTask(task);
      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.id, 'task-1');
    });

    test('updateTask mutates only the matching task', () {
      notifier.addTask(UploadTask(
        id: 'a', fileName: 'a.jpg', totalBytes: 100,
        uploadedBytes: 0, status: UploadStatus.queued,
      ));
      notifier.addTask(UploadTask(
        id: 'b', fileName: 'b.jpg', totalBytes: 200,
        uploadedBytes: 0, status: UploadStatus.queued,
      ));

      notifier.updateTask('a', uploadedBytes: 50, status: UploadStatus.uploading);

      expect(notifier.state.firstWhere((t) => t.id == 'a').uploadedBytes, 50);
      expect(notifier.state.firstWhere((t) => t.id == 'b').uploadedBytes, 0);
    });

    test('removeTask removes only the matching task', () {
      notifier.addTask(UploadTask(
        id: 'x', fileName: 'x.jpg', totalBytes: 10,
        uploadedBytes: 0, status: UploadStatus.completed,
      ));
      notifier.addTask(UploadTask(
        id: 'y', fileName: 'y.jpg', totalBytes: 10,
        uploadedBytes: 0, status: UploadStatus.queued,
      ));

      notifier.removeTask('x');
      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.id, 'y');
    });

    test('clearCompleted removes completed tasks only', () {
      notifier.addTask(UploadTask(
        id: 'done', fileName: 'done.jpg', totalBytes: 10,
        uploadedBytes: 10, status: UploadStatus.completed,
      ));
      notifier.addTask(UploadTask(
        id: 'active', fileName: 'active.jpg', totalBytes: 10,
        uploadedBytes: 5, status: UploadStatus.uploading,
      ));

      notifier.clearCompleted();

      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.id, 'active');
    });
  });

  group('FileListNotifier static cache', () {
    setUp(() {
      // Start each test with a clean cache.
      FileListNotifier.invalidate('');
    });

    test('getCached returns null for an unknown path', () {
      expect(FileListNotifier.getCached('/unknown', 0, 'name', 'asc'), isNull);
    });

    test('putCache then getCached returns the stored response', () {
      final response = FileListResponse(
        items: [],
        totalCount: 0,
        page: 0,
        pageSize: 50,
      );
      FileListNotifier.putCache('/personal/alice', 0, 'name', 'asc', response);

      final hit = FileListNotifier.getCached('/personal/alice', 0, 'name', 'asc');
      expect(hit, isNotNull);
      expect(hit!.totalCount, 0);
    });

    test('getCached returns null after invalidate with matching prefix', () {
      final response = FileListResponse(
        items: [], totalCount: 0, page: 0, pageSize: 50,
      );
      FileListNotifier.putCache('/personal/alice/Photos', 0, 'name', 'asc', response);
      FileListNotifier.invalidate('/personal/alice');

      expect(FileListNotifier.getCached('/personal/alice/Photos', 0, 'name', 'asc'), isNull);
    });

    test('invalidate with non-matching prefix preserves other entries', () {
      final response = FileListResponse(
        items: [], totalCount: 0, page: 0, pageSize: 50,
      );
      FileListNotifier.putCache('/personal/bob/Photos', 0, 'name', 'asc', response);
      FileListNotifier.invalidate('/personal/alice');  // alice, not bob

      expect(
        FileListNotifier.getCached('/personal/bob/Photos', 0, 'name', 'asc'),
        isNotNull,
      );
    });

    test('different sort keys produce different cache entries', () {
      final r1 = FileListResponse(items: [], totalCount: 1, page: 0, pageSize: 50);
      final r2 = FileListResponse(items: [], totalCount: 2, page: 0, pageSize: 50);

      FileListNotifier.putCache('/x', 0, 'name', 'asc', r1);
      FileListNotifier.putCache('/x', 0, 'modified', 'desc', r2);

      expect(FileListNotifier.getCached('/x', 0, 'name', 'asc')!.totalCount, 1);
      expect(FileListNotifier.getCached('/x', 0, 'modified', 'desc')!.totalCount, 2);
    });
  });

  // ─── data_providers ────────────────────────────────────────────────────────

  group('NotificationHistoryNotifier', () {
    late NotificationHistoryNotifier notifier;

    setUp(() => notifier = NotificationHistoryNotifier());
    tearDown(() => notifier.dispose());

    AppNotification makeNotif(String id) => AppNotification(
          type: 'test',
          title: 'Test',
          body: 'body $id',
          severity: NotificationSeverity.info,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        );

    test('starts empty', () {
      expect(notifier.state, isEmpty);
    });

    test('add prepends to the list', () {
      notifier.add(makeNotif('1'));
      notifier.add(makeNotif('2'));

      // newest first
      expect(notifier.state.first.body, 'body 2');
      expect(notifier.state.last.body, 'body 1');
    });

    test('clear empties the list', () {
      notifier.add(makeNotif('x'));
      notifier.clear();
      expect(notifier.state, isEmpty);
    });

    test('list is capped at 50 entries', () {
      for (int i = 0; i < 60; i++) {
        notifier.add(makeNotif('$i'));
      }
      expect(notifier.state.length, 50);
      // Most recent (i=59) should be first
      expect(notifier.state.first.body, 'body 59');
    });
  });
}
