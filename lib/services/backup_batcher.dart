/// Pure-Dart folder naming and batching logic for the Auto Backup feature.
///
/// Given a list of files with resolved capture dates, this class groups them
/// into dated NAS sub-folders following these rules:
///
/// - Files are grouped by year + month.
/// - Each month group → a folder named "Mar 2024".
/// - If a month group has > 500 files, it is split into "Mar 2024 (1)",
///   "Mar 2024 (2)", etc. — never splitting mid-day within a group.
/// - If a folder already exists on the NAS and has room (<= 500 files),
///   the new files are appended to it.
library;

/// Metadata for a single file to be backed up.
class BackupFileInfo {
  final String path;
  final DateTime captureDate;
  final String filename;

  const BackupFileInfo({
    required this.path,
    required this.captureDate,
    required this.filename,
  });
}

/// A group of files that should be placed in the same NAS folder.
class FolderBatch {
  final String folderName;
  final List<BackupFileInfo> files;

  const FolderBatch({required this.folderName, required this.files});
}

/// Stateless utility class for grouping files into dated NAS folders.
class BackupBatcher {
  static const int maxFilesPerFolder = 500;

  BackupBatcher._();

  // ── Batch computation ──────────────────────────────────────────────────────

  /// Given [files] (with resolved capture dates) and the set of [existingFolders]
  /// already on the NAS, return the [FolderBatch] assignments.
  ///
  /// [existingFolderFileCounts] optionally supplies the current file count for
  /// each existing folder so that we can decide whether to append or create a
  /// new numbered variant.
  static List<FolderBatch> computeBatches(
    List<BackupFileInfo> files,
    Set<String> existingFolders, {
    Map<String, int>? existingFolderFileCounts,
  }) {
    if (files.isEmpty) return [];

    final counts = Map<String, int>.from(existingFolderFileCounts ?? {});

    // Sort chronologically
    final sorted = List<BackupFileInfo>.from(files)
      ..sort((a, b) => a.captureDate.compareTo(b.captureDate));

    // Group by year + month (preserving insertion order via LinkedHashMap
    // semantics of a regular Dart Map)
    final byMonth = <String, List<BackupFileInfo>>{};
    for (final file in sorted) {
      final key =
          '${file.captureDate.year}-${file.captureDate.month.toString().padLeft(2, '0')}';
      byMonth.putIfAbsent(key, () => []).add(file);
    }

    final result = <FolderBatch>[];

    for (final monthFiles in byMonth.values) {
      final baseName = _monthFolderName(monthFiles.first.captureDate);

      // Find a folder with room — try base name, then (2), (3), …
      String targetFolder = _findFolderWithRoom(
          baseName, existingFolders, counts);
      int currentCount = counts[targetFolder] ?? 0;

      // Group this month's files by day so we never split a day across folders.
      final days = _groupByDay(monthFiles);

      final currentBatch = <BackupFileInfo>[];

      for (final dayFiles in days) {
        // Would adding this day exceed the limit?
        if (currentBatch.isNotEmpty &&
            currentCount + currentBatch.length + dayFiles.length >
                maxFilesPerFolder) {
          // Flush current batch and advance to the next folder slot.
          result.add(FolderBatch(
              folderName: targetFolder, files: List.from(currentBatch)));
          // Mark this folder as "sealed" within this computation so that
          // _findFolderWithRoom will skip it and assign the next day's files
          // to a freshly-numbered folder instead of mixing days together.
          counts[targetFolder] = maxFilesPerFolder;
          existingFolders = {...existingFolders, targetFolder};
          currentBatch.clear();

          targetFolder = _findFolderWithRoom(
              baseName, existingFolders, counts);
          currentCount = counts[targetFolder] ?? 0;
        }
        currentBatch.addAll(dayFiles);
      }

      if (currentBatch.isNotEmpty) {
        result.add(FolderBatch(
            folderName: targetFolder, files: List.from(currentBatch)));
        counts[targetFolder] =
            (counts[targetFolder] ?? 0) + currentBatch.length;
        existingFolders = {...existingFolders, targetFolder};
      }
    }

    return result;
  }

  // ── Date parsing ───────────────────────────────────────────────────────────

  /// Attempt to extract a capture date from [filename].
  ///
  /// Patterns tried in order:
  ///   1. WhatsApp images:    IMG-20240315-WA0001.jpg  → 2024-03-15
  ///   2. Screenshots:        Screenshot_20240315-143022.png → 2024-03-15
  ///                          Screenshot_2024-03-15-143022.png → 2024-03-15
  ///   3. Generic 8-digit:    any YYYYMMDD run in the filename
  ///
  /// Returns null if no date pattern is recognised — caller should fall back to
  /// file modification time (or EXIF reading at a higher level).
  static DateTime? parseDateFromFilename(String filename) {
    // Strip directory components if any
    final name = filename.split(RegExp(r'[/\\]')).last;

    // 1. WhatsApp: IMG-YYYYMMDD-WA…
    final waMatch = RegExp(r'IMG-(\d{8})-WA').firstMatch(name);
    if (waMatch != null) {
      return _parseYYYYMMDD(waMatch.group(1)!);
    }

    // 2a. Screenshot_YYYYMMDD-HHmmss…
    final ssMatch1 =
        RegExp(r'Screenshot_(\d{4})(\d{2})(\d{2})').firstMatch(name);
    if (ssMatch1 != null) {
      return DateTime.tryParse(
          '${ssMatch1.group(1)}-${ssMatch1.group(2)}-${ssMatch1.group(3)}');
    }

    // 2b. Screenshot_YYYY-MM-DD…
    final ssMatch2 =
        RegExp(r'Screenshot_(\d{4})-(\d{2})-(\d{2})').firstMatch(name);
    if (ssMatch2 != null) {
      return DateTime.tryParse(
          '${ssMatch2.group(1)}-${ssMatch2.group(2)}-${ssMatch2.group(3)}');
    }

    // 3. Generic YYYYMMDD
    final gMatch = RegExp(r'(\d{4})(\d{2})(\d{2})').firstMatch(name);
    if (gMatch != null) {
      return _parseYYYYMMDD(
          '${gMatch.group(1)}${gMatch.group(2)}${gMatch.group(3)}');
    }

    return null;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static String _monthFolderName(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  /// Find the first folder (base or numbered) that has room for more files.
  /// If none of the existing folders have room, return the next fresh name.
  static String _findFolderWithRoom(
    String baseName,
    Set<String> existing,
    Map<String, int> counts,
  ) {
    // Try base name
    if (!existing.contains(baseName) ||
        (counts[baseName] ?? 0) < maxFilesPerFolder) {
      return baseName;
    }
    // Try (2), (3), …
    for (int n = 2; n <= existing.length + 2; n++) {
      final candidate = '$baseName ($n)';
      if (!existing.contains(candidate) ||
          (counts[candidate] ?? 0) < maxFilesPerFolder) {
        return candidate;
      }
    }
    return '$baseName (${existing.length + 2})';
  }

  /// Group a list of files by calendar day (yyyy-MM-dd key), preserving order.
  static List<List<BackupFileInfo>> _groupByDay(List<BackupFileInfo> files) {
    final map = <String, List<BackupFileInfo>>{};
    for (final f in files) {
      final key =
          '${f.captureDate.year}-${f.captureDate.month.toString().padLeft(2, '0')}-${f.captureDate.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(f);
    }
    return map.values.toList();
  }

  static DateTime? _parseYYYYMMDD(String s) {
    if (s.length != 8) return null;
    try {
      final year = int.parse(s.substring(0, 4));
      final month = int.parse(s.substring(4, 6));
      final day = int.parse(s.substring(6, 8));
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }
}
