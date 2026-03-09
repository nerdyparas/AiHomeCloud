/// File browser providers — file listing with pagination/sort and upload task tracking.
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

final fileListProvider =
    FutureProvider.family<FileListResponse, FileListQuery>((ref, q) async {
  final api = ref.read(apiServiceProvider);
  return api.listFiles(
    q.path,
    page: q.page,
    pageSize: q.pageSize,
    sortBy: q.sortBy,
    sortDir: q.sortDir,
  );
});

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
