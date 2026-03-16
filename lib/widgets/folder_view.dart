import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../core/error_utils.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers.dart';
import 'app_card.dart';
import 'file_list_tile.dart';

/// Reusable file-browser widget embedded in My Files, Shared, and the
/// standalone FolderViewScreen.
class FolderView extends ConsumerStatefulWidget {
  final String title;
  final String folderPath;
  final bool readOnly;
  final bool showHeader;
  final VoidCallback? onBack;

  const FolderView({
    super.key,
    required this.title,
    required this.folderPath,
    this.readOnly = false,
    this.showHeader = true,
    this.onBack,
  });

  @override
  ConsumerState<FolderView> createState() => _FolderViewState();
}

class _FolderViewState extends ConsumerState<FolderView> {
  late String _currentPath;
  final List<String> _pathStack = [];
  final int _pageSize = 50;
  int _currentPage = 0;
  int _totalCount = 0;
  bool _initialLoading = true;
  bool _loadingMore = false;
  String? _error;
  List<FileItem> _items = [];

  /// Active upload subscriptions keyed by task ID — used for cancellation.
  final Map<String, StreamSubscription<int>> _uploadSubscriptions = {};

  /// Guard to prevent multiple file pickers opening simultaneously.
  bool _isPickerOpen = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.folderPath;
    _loadFiles(reset: true);
  }

  @override
  void dispose() {
    for (final sub in _uploadSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadFiles({required bool reset}) async {
    try {
      if (reset) {
        setState(() {
          _currentPage = 0;
          _items = [];
          _totalCount = 0;
          _error = null;
          _initialLoading = true;
        });
      }

      // Check in-memory cache first (30s TTL)
      final cached = FileListNotifier.getCached(
          _currentPath, _currentPage, 'name', 'asc');
      late final FileListResponse response;
      if (cached != null) {
        response = cached;
      } else {
        response = await ref.read(apiServiceProvider).listFiles(
              _currentPath,
              page: _currentPage,
              pageSize: _pageSize,
              sortBy: 'name',
              sortDir: 'asc',
            );
        FileListNotifier.putCache(
            _currentPath, _currentPage, 'name', 'asc', response);
      }

      if (!mounted) return;
      setState(() {
        if (_currentPage == 0) {
          _items = response.items;
        } else {
          _items = [..._items, ...response.items];
        }
        _totalCount = response.totalCount;
        _error = null;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _totalCount) return;
    setState(() => _loadingMore = true);
    _currentPage += 1;
    await _loadFiles(reset: false);
    if (mounted) setState(() => _loadingMore = false);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateInto(FileItem folder) {
    setState(() {
      _pathStack.add(_currentPath);
      _currentPath = folder.path;
    });
    _loadFiles(reset: true);
  }

  void _navigateBack() {
    if (_pathStack.isNotEmpty) {
      setState(() => _currentPath = _pathStack.removeLast());
      _loadFiles(reset: true);
    } else if (widget.onBack != null) {
      widget.onBack!();
    }
  }

  Future<void> _refresh() async {
    FileListNotifier.invalidate(_currentPath);
    await _loadFiles(reset: true);
  }

  // ── File actions ──────────────────────────────────────────────────────────

  void _showFileActions(FileItem file) {
    if (widget.readOnly) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(file.icon, color: file.iconColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        file.name,
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.cardBorder),
              ListTile(
                leading: const Icon(Icons.edit_rounded,
                    color: AppColors.textSecondary),
                title: Text(AppLocalizations.of(context)!.folderRenameTitle,
                    style: GoogleFonts.dmSans(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameFile(file);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_rounded, color: AppColors.error),
                title: Text(AppLocalizations.of(context)!.folderDeleteTitle,
                    style: GoogleFonts.dmSans(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteFile(file);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _renameFile(FileItem file) {
    final ctrl = TextEditingController(text: file.name);
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.folderRenameTitle, style: GoogleFonts.sora()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.dmSans(color: AppColors.textPrimary),
          decoration: InputDecoration(hintText: l10n.folderRenameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.buttonCancel,
                style:
                    GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref
                    .read(apiServiceProvider)
                    .renameFile(file.path, ctrl.text);
                FileListNotifier.invalidate(_currentPath);
                await _loadFiles(reset: true);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyError(e))),
                  );
                }
              }
            },
            child: Text(l10n.folderRenameButton,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _deleteFile(FileItem file) {
    final index = _items.indexOf(file);
    _softDeleteFile(file, index >= 0 ? index : _items.length);
  }

  /// Optimistically removes [file] from the list and shows an Undo SnackBar.
  /// If the user doesn't undo within 30 s the deletion is committed via the API.
  void _softDeleteFile(FileItem file, int originalIndex) {
    setState(() {
      _items.remove(file);
      if (_totalCount > 0) _totalCount -= 1;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.folderMovedToTrash(file.name)),
            duration: const Duration(seconds: 30),
            action: SnackBarAction(label: AppLocalizations.of(context)!.buttonUndo, onPressed: () {}),
          ),
        )
        .closed
        .then((reason) {
      if (!mounted) return;
      if (reason == SnackBarClosedReason.action) {
        // Restore the item to its original position.
        setState(() {
          final insertAt = originalIndex.clamp(0, _items.length);
          _items.insert(insertAt, file);
          _totalCount += 1;
        });
      } else {
        // Commit the delete via the API.
        FileListNotifier.invalidate(_currentPath);
        ref.read(apiServiceProvider).deleteFile(file.path).catchError((Object e) {
          if (mounted) {
            setState(() {
              final insertAt = originalIndex.clamp(0, _items.length);
              _items.insert(insertAt, file);
              _totalCount += 1;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.folderDeleteFailed(friendlyError(e)))),
            );
          }
        });
      }
    });
  }

  // ── Add menu (upload / new folder) ────────────────────────────────────────

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.upload_file_rounded,
                      color: AppColors.primary),
                ),
                title: Text(AppLocalizations.of(context)!.folderUploadFileTitle,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500)),
                subtitle: Text(AppLocalizations.of(context)!.folderUploadFileSubtitle,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _uploadFile();
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.create_new_folder_rounded,
                      color: AppColors.secondary),
                ),
                title: Text(AppLocalizations.of(context)!.folderNewFolderTitle,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500)),
                subtitle: Text(AppLocalizations.of(context)!.folderNewFolderSubtitle,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _createFolder();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _createFolder() {
    final ctrl = TextEditingController();
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.folderNewFolderTitle, style: GoogleFonts.sora()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.dmSans(color: AppColors.textPrimary),
          decoration: InputDecoration(hintText: l10n.folderNewFolderHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.buttonCancel,
                style:
                    GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref
                    .read(apiServiceProvider)
                    .createFolder(_currentPath, ctrl.text);
                FileListNotifier.invalidate(_currentPath);
                await _loadFiles(reset: true);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyError(e))),
                  );
                }
              }
            },
            child: Text(l10n.folderCreateButton,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Cancel an in-progress upload and remove its card.
  void _dismissUpload(String taskId) {
    _uploadSubscriptions.remove(taskId)?.cancel();
    if (mounted) {
      ref.read(uploadTasksProvider.notifier).removeTask(taskId);
    }
  }

  /// Retry a failed upload.
  void _retryUpload(UploadTask task) {
    final filePath = task.filePath;
    final destinationPath = task.destinationPath;
    if (filePath == null || destinationPath == null) return;
    _dismissUpload(task.id);
    final newTask = UploadTask(
      id: 'upload_${DateTime.now().millisecondsSinceEpoch}_${task.fileName.hashCode}',
      fileName: task.fileName,
      totalBytes: task.totalBytes,
      filePath: filePath,
      destinationPath: destinationPath,
    );
    _startUpload(newTask);
  }

  /// Wire up a stream subscription for an [UploadTask] and begin streaming.
  void _startUpload(UploadTask task) {
    final api = ref.read(apiServiceProvider);
    ref.read(uploadTasksProvider.notifier).addTask(task);
    ref.read(uploadTasksProvider.notifier).updateTask(task.id, status: UploadStatus.uploading);

    final sortedToCompleter = Completer<String?>();

    final stream = api.uploadFile(
      task.destinationPath!,
      task.fileName,
      task.totalBytes,
      filePath: task.filePath!,
      sortedToCompleter: sortedToCompleter,
    );

    final sub = stream.listen(
      (bytes) {
        if (mounted) {
          ref.read(uploadTasksProvider.notifier).updateTask(task.id, uploadedBytes: bytes);
        }
      },
      onDone: () async {
        _uploadSubscriptions.remove(task.id);
        if (!mounted) return;

        // 1. Mark done and refresh file list immediately
        ref.read(uploadTasksProvider.notifier).updateTask(task.id, status: UploadStatus.completed);
        FileListNotifier.invalidate(_currentPath);
        _loadFiles(reset: true);

        // 2. Show immediate snackbar — don't wait for sortedTo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.folderUploadedSnackbar(task.fileName))),
          );
        }

        // 3. Remove card after 2s
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) ref.read(uploadTasksProvider.notifier).removeTask(task.id);
        });

        // 4. If sortedTo arrives quickly, show a second snackbar (bonus info)
        try {
          final sortedTo = await sortedToCompleter.future
              .timeout(const Duration(seconds: 3));
          if (sortedTo != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_uploadSnackMessage(task.fileName, sortedTo))),
            );
          }
        } catch (_) {
          // sortedTo timeout — fine, already showed success snackbar
        }
      },
      onError: (e) {
        _uploadSubscriptions.remove(task.id);
        if (mounted) {
          final errorMsg = friendlyError(e);
          ref.read(uploadTasksProvider.notifier).updateTask(
            task.id,
            status: UploadStatus.failed,
            error: errorMsg,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.folderUploadFailed(errorMsg)),
              action: SnackBarAction(
                label: AppLocalizations.of(context)!.buttonRetryAction,
                onPressed: () {
                  ref.read(uploadTasksProvider.notifier).removeTask(task.id);
                  final retryTask = UploadTask(
                    id: 'retry_${DateTime.now().millisecondsSinceEpoch}_${task.fileName.hashCode}',
                    fileName: task.fileName,
                    totalBytes: task.totalBytes,
                    filePath: task.filePath,
                    destinationPath: task.destinationPath,
                  );
                  _startUpload(retryTask);
                },
              ),
            ),
          );
        }
      },
      cancelOnError: false,
    );
    _uploadSubscriptions[task.id] = sub;
  }

  /// Pick one or more files from the device and upload them to the Cubie.
  void _uploadFile() async {
    if (_isPickerOpen) return;
    if (ref.read(connectionProvider) != ConnectionStatus.connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError('Connection lost'))),
        );
      }
      return;
    }
    _isPickerOpen = true;
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      for (final pickedFile in result.files) {
        if (pickedFile.path == null) continue;
        final task = UploadTask(
          id: 'upload_${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name.hashCode}',
          fileName: pickedFile.name,
          totalBytes: pickedFile.size,
          filePath: pickedFile.path,
          destinationPath: _currentPath,
        );
        _startUpload(task);
      }
    } finally {
      _isPickerOpen = false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Map the backend sortedTo folder name to a friendly snackbar message.
  String _uploadSnackMessage(String fileName, String? sortedTo) {
    final l10n = AppLocalizations.of(context)!;
    return switch (sortedTo) {
      'Photos' => l10n.folderSortedToPhotos(fileName),
      'Videos' => l10n.folderSortedToVideos(fileName),
      'Documents' => l10n.folderSortedToDocuments(fileName),
      _ => l10n.folderUploadedSnackbar(fileName),
    };
  }

  Widget _handle() => Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.textMuted,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  bool _isNoStorageError(String error) {
    return error.contains('No external storage mounted') ||
        error.contains('503');
  }

  Widget _buildNoStorageMessage() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.usb_off_rounded,
                size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(l10n.filesNoStorageTitle,
                style: GoogleFonts.sora(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              l10n.filesNoStorageMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.filesCheckAgainButton),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploads = ref.watch(uploadTasksProvider);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            if (widget.showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  widget.title,
                  style: GoogleFonts.sora(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

            // Back / breadcrumb
            if (_pathStack.isNotEmpty || widget.onBack != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          size: 20, color: AppColors.textSecondary),
                      tooltip: AppLocalizations.of(context)!.folderGoBackTooltip,
                      onPressed: _navigateBack,
                    ),
                    Expanded(
                      child: Text(
                        _currentPath
                            .split('/')
                            .where((s) => s.isNotEmpty)
                            .last,
                        style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Upload progress cards
            if (uploads.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  children: uploads
                      .map((t) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _UploadProgressCard(
                              task: t,
                              onDismiss: () => _dismissUpload(t.id),
                              onRetry: () => _retryUpload(t),
                            ),
                          ))
                      .toList(),
                ),
              ),

            // File list
            Expanded(
              child: _initialLoading
                  ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
                  : _error != null
                      ? _isNoStorageError(_error!)
                          ? _buildNoStorageMessage()
                          : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 48, color: AppColors.error),
                      const SizedBox(height: 12),
                      Text(friendlyError(_error!),
                          style: GoogleFonts.dmSans(color: AppColors.error)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _refresh, child: Text(AppLocalizations.of(context)!.buttonRetry)),
                    ],
                  ),
                )
                      : _buildFileList(_items),
            ),
          ],
        ),

        // FAB
        if (!widget.readOnly)
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton(
              heroTag: 'folder_fab_${widget.folderPath}',
              tooltip: AppLocalizations.of(context)!.folderAddTooltip,
              onPressed: _showAddMenu,
              child:
                  const Icon(Icons.add_rounded, color: AppColors.background),
            ),
          ),
      ],
    );
  }

  Widget _buildFileList(List<FileItem> files) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_rounded,
                size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.folderEmptyTitle,
                style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary, fontSize: 15)),
            if (!widget.readOnly) ...[
              const SizedBox(height: 8),
              Text(AppLocalizations.of(context)!.folderEmptySubtitle,
                  style: GoogleFonts.dmSans(
                      color: AppColors.textMuted, fontSize: 13)),
            ],
          ],
        ),
      );
    }

    final sorted = [...files];

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
        itemCount: sorted.length + 1,
        itemBuilder: (_, i) {
          if (i == sorted.length) {
            // Show a small spinner while fetching the next page, so the layout
            // doesn't shift (24 px matches the task requirement).
            if (_loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
              );
            }
            final canLoadMore = sorted.length < _totalCount;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: canLoadMore ? _loadMore : null,
                  child: Text(canLoadMore
                      ? 'Load more (${sorted.length}/$_totalCount)'
                      : 'All items loaded ($_totalCount)'),
                ),
              ),
            );
          }
          final file = sorted[i];
          final tile = FileListTile(
            file: file,
            readOnly: widget.readOnly,
            onTap: file.isDirectory
                ? () => _navigateInto(file)
                : () => context.push('/file-preview', extra: file),
            onLongPress:
                widget.readOnly ? null : () => _showFileActions(file),
          ).animate().fadeIn(delay: (40 * i).ms);
          if (widget.readOnly) return tile;
          return Dismissible(
            key: ValueKey(file.path),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
            ),
            onDismissed: (_) => _softDeleteFile(file, i),
            child: tile,
          );
        },
      ),
    );
  }
}

// ─── Upload progress card ───────────────────────────────────────────────────

class _UploadProgressCard extends StatelessWidget {
  final UploadTask task;
  final VoidCallback onDismiss;
  final VoidCallback onRetry;

  const _UploadProgressCard({
    required this.task,
    required this.onDismiss,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == UploadStatus.completed;
    final isFail = task.status == UploadStatus.failed;
    final isUploading = task.status == UploadStatus.uploading;

    return AppCard(
      padding: const EdgeInsets.all(12),
      glowing: isUploading,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isDone
                  ? Icons.check_circle_rounded
                  : isFail
                      ? Icons.error_rounded
                      : Icons.upload_rounded,
              color: isDone
                  ? AppColors.success
                  : isFail
                      ? AppColors.error
                      : AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (isFail)
                  Text(
                    task.error ?? 'Upload failed',
                    style: GoogleFonts.dmSans(
                      color: AppColors.error,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      backgroundColor: AppColors.cardBorder,
                      valueColor: AlwaysStoppedAnimation(
                        isDone ? AppColors.success : AppColors.primary,
                      ),
                      minHeight: 4,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (!isFail)
            Text(
              '${(task.progress * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.dmSans(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (isFail && task.filePath != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: AppColors.primary,
              ),
              child: Text('Retry', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          // Dismiss (completed/failed) or Cancel (uploading) button
          IconButton(
            icon: Icon(
              isUploading ? Icons.close_rounded : Icons.clear_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: isUploading ? 'Cancel upload' : 'Dismiss',
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
