/// File browser providers — file listing with pagination/sort and upload task tracking.
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'core_providers.dart';

class FileListQuery {
  final String path;
  final int page;
  final int pageSize;
  final String sortBy;
  final String sortDir;

  const FileListQuery({
    required this.path,
    this.page = 0,
    this.pageSize = 50,
    this.sortBy = 'name',
    this.sortDir = 'asc',
  });
}

// ── In-memory folder listing cache (30s TTL) ────────────────────────────────

class _CacheEntry {
  final FileListResponse data;
  final DateTime fetchedAt;
  _CacheEntry(this.data) : fetchedAt = DateTime.now();
  bool get isStale => DateTime.now().difference(fetchedAt).inSeconds > 30;
}

class FileListNotifier
    extends AutoDisposeFamilyAsyncNotifier<FileListResponse, FileListQuery> {
  static final _cache = <String, _CacheEntry>{};

  static String _key(FileListQuery q) =>
      '${q.path}|${q.page}|${q.sortBy}|${q.sortDir}';

  /// Clear cached entries whose key starts with [pathPrefix].
  /// Call after uploads, deletes, or moves to ensure fresh data.
  static void invalidate(String pathPrefix) {
    _cache.removeWhere((k, _) => k.startsWith(pathPrefix));
  }

  /// Lookup a cached [FileListResponse] for a raw key built from path/page/sort.
  /// Returns null if not cached or stale.
  static FileListResponse? getCached(
      String path, int page, String sortBy, String sortDir) {
    final key = '$path|$page|$sortBy|$sortDir';
    final entry = _cache[key];
    if (entry != null && !entry.isStale) return entry.data;
    return null;
  }

  /// Store a [FileListResponse] in the cache.
  static void putCache(
      String path, int page, String sortBy, String sortDir, FileListResponse data) {
    final key = '$path|$page|$sortBy|$sortDir';
    _cache[key] = _CacheEntry(data);
  }

  @override
  Future<FileListResponse> build(FileListQuery arg) async {
    final key = _key(arg);
    final cached = _cache[key];
    if (cached != null && !cached.isStale) return cached.data;

    final api = ref.read(apiServiceProvider);
    final result = await api.listFiles(
      arg.path,
      page: arg.page,
      pageSize: arg.pageSize,
      sortBy: arg.sortBy,
      sortDir: arg.sortDir,
    );
    _cache[key] = _CacheEntry(result);
    return result;
  }
}

final fileListProvider = AsyncNotifierProvider.autoDispose
    .family<FileListNotifier, FileListResponse, FileListQuery>(
  FileListNotifier.new,
);

class UploadTasksNotifier extends StateNotifier<List<UploadTask>> {
  UploadTasksNotifier() : super([]);

  void addTask(UploadTask task) {
    state = [...state, task];
  }

  void updateTask(
    String id, {
    int? uploadedBytes,
    UploadStatus? status,
    String? error,
  }) {
    state = [
      for (final t in state)
        if (t.id == id)
          t
            ..uploadedBytes = uploadedBytes ?? t.uploadedBytes
            ..status = status ?? t.status
            ..error = error
        else
          t,
    ];
  }

  void removeTask(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void clearCompleted() {
    state = state.where((t) => t.status != UploadStatus.completed).toList();
  }
}

final uploadTasksProvider =
    StateNotifierProvider<UploadTasksNotifier, List<UploadTask>>((ref) {
  return UploadTasksNotifier();
});

/// FTS5 document search — FutureProvider.family keyed by query string.
/// Returns an empty list for blank queries (never calls the API).
final docSearchResultsProvider =
    FutureProvider.family<List<SearchResult>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  return ref.read(apiServiceProvider).searchDocuments(query.trim());
});

/// Trash items for the current user.
final trashItemsProvider = FutureProvider<List<TrashItem>>((ref) async {
  return ref.read(apiServiceProvider).getTrashItems();
});
