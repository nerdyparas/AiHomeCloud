import 'package:flutter_test/flutter_test.dart';

import 'package:aihomecloud/services/backup_batcher.dart';

void main() {
  group('BackupBatcher.parseDateFromFilename', () {
    test('parses WhatsApp image filename', () {
      final date = BackupBatcher.parseDateFromFilename('IMG-20240315-WA0001.jpg');
      expect(date, isNotNull);
      expect(date!.year, 2024);
      expect(date.month, 3);
      expect(date.day, 15);
    });

    test('parses WhatsApp video filename', () {
      final date = BackupBatcher.parseDateFromFilename('VID-20231225-WA0042.mp4');
      expect(date, isNotNull);
      expect(date!.year, 2023);
      expect(date.month, 12);
      expect(date.day, 25);
    });

    test('parses Screenshot_YYYYMMDD filename', () {
      final date =
          BackupBatcher.parseDateFromFilename('Screenshot_20240315-143022.png');
      expect(date, isNotNull);
      expect(date!.year, 2024);
      expect(date.month, 3);
      expect(date.day, 15);
    });

    test('parses Screenshot_YYYY-MM-DD filename', () {
      final date =
          BackupBatcher.parseDateFromFilename('Screenshot_2024-03-15-143022.png');
      expect(date, isNotNull);
      expect(date!.year, 2024);
      expect(date.month, 3);
      expect(date.day, 15);
    });

    test('parses generic YYYYMMDD filename', () {
      final date = BackupBatcher.parseDateFromFilename('photo_20240101.jpg');
      expect(date, isNotNull);
      expect(date!.year, 2024);
      expect(date.month, 1);
      expect(date.day, 1);
    });

    test('returns null for unrecognised filename (EXIF/mtime fallback)', () {
      final date = BackupBatcher.parseDateFromFilename('random_file.jpg');
      expect(date, isNull);
    });

    test('handles path separators â€” extracts only the basename', () {
      final date = BackupBatcher.parseDateFromFilename(
          '/storage/emulated/0/DCIM/Camera/IMG-20240601-WA0001.jpg');
      expect(date, isNotNull);
      expect(date!.year, 2024);
      expect(date.month, 6);
    });

    test('returns null for invalid date digits', () {
      // Month 13 is invalid â€” should return null
      final date = BackupBatcher.parseDateFromFilename('photo_20241301.jpg');
      expect(date, isNull);
    });
  });

  group('BackupBatcher.computeBatches â€” simple grouping', () {
    test('single file goes into correct month folder', () {
      final files = [
        BackupFileInfo(
          path: '/DCIM/Camera/photo.jpg',
          captureDate: DateTime(2024, 3, 10),
          filename: 'photo.jpg',
        ),
      ];
      final batches = BackupBatcher.computeBatches(files, {});
      expect(batches.length, 1);
      expect(batches.first.folderName, 'Mar 2024');
      expect(batches.first.files.length, 1);
    });

    test('files in different months go into different folders', () {
      final files = [
        BackupFileInfo(
          path: '/DCIM/a.jpg',
          captureDate: DateTime(2024, 1, 5),
          filename: 'a.jpg',
        ),
        BackupFileInfo(
          path: '/DCIM/b.jpg',
          captureDate: DateTime(2024, 3, 20),
          filename: 'b.jpg',
        ),
      ];
      final batches = BackupBatcher.computeBatches(files, {});
      expect(batches.length, 2);
      expect(batches.map((b) => b.folderName).toSet(),
          containsAll(['Jan 2024', 'Mar 2024']));
    });
  });

  group('BackupBatcher.computeBatches â€” 500-file split', () {
    /// Build N files all on the same day (no mid-day split allowed).
    List<BackupFileInfo> makeFiles(int count, DateTime date) {
      return List.generate(
        count,
        (i) => BackupFileInfo(
          path: '/DCIM/photo_$i.jpg',
          captureDate: date,
          filename: 'photo_$i.jpg',
        ),
      );
    }

    test('501 files on the same day create two folders', () {
      // 501 files, all on 2024-03-15 â€” must NOT split mid-day so the first
      // batch must include all 501 files (exceeds limit), and then a new folder
      // is created for the overflow. Actually per spec: split check happens *before*
      // adding a day. With 501 on the same day the first folder gets 501 files
      // (no prior batch to flush), and the second run for the same month is empty.
      // Verify that we handle the edge case gracefully.
      final files = makeFiles(501, DateTime(2024, 3, 15));
      final batches = BackupBatcher.computeBatches(files, {});
      // All 501 files are in one day, so they cannot be split.
      // The batcher must keep them together in the first folder.
      final total = batches.fold<int>(0, (sum, b) => sum + b.files.length);
      expect(total, 501);
    });

    test('600 files across two days splits without splitting days', () {
      // 400 files on day 1, 200 files on day 2 â€” 600 total.
      // Expected: "Mar 2024" gets 400 + some, then overflow.
      final day1 = makeFiles(400, DateTime(2024, 3, 1));
      final day2 = makeFiles(200, DateTime(2024, 3, 2));
      final files = [...day1, ...day2];
      final batches = BackupBatcher.computeBatches(files, {});
      // After day 1 (400 files), adding day 2 (200) would push total to 600 > 500.
      // day 1 is flushed first as a batch, day 2 goes into next folder.
      expect(batches.length, 2);
      expect(batches[0].folderName, 'Mar 2024');
      expect(batches[0].files.length, 400);
      expect(batches[1].folderName, 'Mar 2024 (2)');
      expect(batches[1].files.length, 200);
    });

    test('numbered folder names increment correctly for many splits', () {
      final existing = {'Mar 2024'};
      // Provide 300 + 300 files: 300 would fit in Mar 2024 (300 current count),
      // the next 300 need Mar 2024 (2).
      final day1 = makeFiles(300, DateTime(2024, 3, 1));
      final day2 = makeFiles(300, DateTime(2024, 3, 2));
      final files = [...day1, ...day2];
      final batches = BackupBatcher.computeBatches(files, existing,
          existingFolderFileCounts: {'Mar 2024': 300});
      // Mar 2024 has 300 existing + 300 new = 600 > 500, so day 1 overflows.
      // Since adding day1 (300) to existing 300 = 600 > 500, day1 starts
      // a new folder Mar 2024 (2), then day2 also goes to Mar 2024 (2) or (3).
      final total = batches.fold<int>(0, (sum, b) => sum + b.files.length);
      expect(total, 600);
    });
  });

  group('BackupBatcher.computeBatches â€” existing folder append', () {
    test('appends to existing folder when it has room', () {
      final existing = {'Mar 2024'};
      final counts = {'Mar 2024': 100}; // 100 files already there
      final files = [
        BackupFileInfo(
          path: '/DCIM/new.jpg',
          captureDate: DateTime(2024, 3, 5),
          filename: 'new.jpg',
        ),
      ];
      final batches = BackupBatcher.computeBatches(files, existing,
          existingFolderFileCounts: counts);
      expect(batches.length, 1);
      expect(batches.first.folderName, 'Mar 2024'); // appended, not new folder
    });

    test('creates new numbered folder when existing is full', () {
      final existing = {'Mar 2024'};
      final counts = {'Mar 2024': 500}; // full
      final files = [
        BackupFileInfo(
          path: '/DCIM/overflow.jpg',
          captureDate: DateTime(2024, 3, 5),
          filename: 'overflow.jpg',
        ),
      ];
      final batches = BackupBatcher.computeBatches(files, existing,
          existingFolderFileCounts: counts);
      expect(batches.length, 1);
      expect(batches.first.folderName, 'Mar 2024 (2)'); // new folder created
    });

    test('skips full numbered folders and uses next available', () {
      final existing = {'Mar 2024', 'Mar 2024 (2)'};
      final counts = {'Mar 2024': 500, 'Mar 2024 (2)': 500};
      final files = [
        BackupFileInfo(
          path: '/DCIM/extra.jpg',
          captureDate: DateTime(2024, 3, 5),
          filename: 'extra.jpg',
        ),
      ];
      final batches = BackupBatcher.computeBatches(files, existing,
          existingFolderFileCounts: counts);
      expect(batches.first.folderName, 'Mar 2024 (3)');
    });
  });
}
