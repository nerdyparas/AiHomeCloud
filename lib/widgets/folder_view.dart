import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers.dart';
import 'cubie_card.dart';
import 'file_list_tile.dart';

/// Reusable file-browser widget embedded in My Files, Shared, and the
/// standalone FolderViewScreen.
class FolderView extends ConsumerStatefulWidget {
  final String title;
  final String folderPath;
  final bool readOnly;
  final bool showHeader;

  const FolderView({
    super.key,
    required this.title,
    required this.folderPath,
    this.readOnly = false,
    this.showHeader = true,
  });

  @override
  ConsumerState<FolderView> createState() => _FolderViewState();
}

class _FolderViewState extends ConsumerState<FolderView> {
  late String _currentPath;
  final List<String> _pathStack = [];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.folderPath;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateInto(FileItem folder) {
    setState(() {
      _pathStack.add(_currentPath);
      _currentPath = folder.path;
    });
    ref.invalidate(fileListProvider(_currentPath));
  }

  void _navigateBack() {
    if (_pathStack.isNotEmpty) {
      setState(() => _currentPath = _pathStack.removeLast());
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(fileListProvider(_currentPath));
  }

  // ── File actions ──────────────────────────────────────────────────────────

  void _showFileActions(FileItem file) {
    if (widget.readOnly) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: CubieColors.card,
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
                            color: CubieColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: CubieColors.cardBorder),
              ListTile(
                leading: const Icon(Icons.edit_rounded,
                    color: CubieColors.textSecondary),
                title: Text('Rename',
                    style: GoogleFonts.dmSans(color: CubieColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameFile(file);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_rounded, color: CubieColors.error),
                title: Text('Delete',
                    style: GoogleFonts.dmSans(color: CubieColors.error)),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename', style: GoogleFonts.sora()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
          decoration: const InputDecoration(hintText: 'New name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(mockApiServiceProvider)
                  .renameFile(file.path, ctrl.text);
              ref.invalidate(fileListProvider(_currentPath));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Rename',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _deleteFile(FileItem file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${file.name}?', style: GoogleFonts.sora()),
        content: Text(
          file.isDirectory
              ? 'This folder and all its contents will be permanently deleted.'
              : 'This file will be permanently deleted.',
          style: GoogleFonts.dmSans(color: CubieColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CubieColors.error),
            onPressed: () async {
              await ref
                  .read(mockApiServiceProvider)
                  .deleteFile(file.path);
              ref.invalidate(fileListProvider(_currentPath));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Delete',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Add menu (upload / new folder) ────────────────────────────────────────

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: CubieColors.card,
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
                    color: CubieColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.upload_file_rounded,
                      color: CubieColors.primary),
                ),
                title: Text('Upload File',
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textPrimary,
                        fontWeight: FontWeight.w500)),
                subtitle: Text('Choose from your phone',
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textSecondary, fontSize: 12)),
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
                    color: CubieColors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.create_new_folder_rounded,
                      color: CubieColors.secondary),
                ),
                title: Text('New Folder',
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textPrimary,
                        fontWeight: FontWeight.w500)),
                subtitle: Text('Create a new directory',
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textSecondary, fontSize: 12)),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New Folder', style: GoogleFonts.sora()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(mockApiServiceProvider)
                  .createFolder(_currentPath, ctrl.text);
              ref.invalidate(fileListProvider(_currentPath));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Create',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Simulates a file upload with chunked progress.
  /// TODO: Replace with real file_picker + multipart upload.
  void _uploadFile() {
    final task = UploadTask(
      id: 'upload_${DateTime.now().millisecondsSinceEpoch}',
      fileName: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      totalBytes: 5 * 1024 * 1024, // 5 MB mock file
    );

    ref.read(uploadTasksProvider.notifier).addTask(task);
    ref
        .read(uploadTasksProvider.notifier)
        .updateTask(task.id, status: UploadStatus.uploading);

    final api = ref.read(mockApiServiceProvider);
    final stream = api.uploadFile(_currentPath, task.fileName, task.totalBytes);

    stream.listen(
      (bytes) {
        ref
            .read(uploadTasksProvider.notifier)
            .updateTask(task.id, uploadedBytes: bytes);
      },
      onDone: () {
        ref
            .read(uploadTasksProvider.notifier)
            .updateTask(task.id, status: UploadStatus.completed);
        ref.invalidate(fileListProvider(_currentPath));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('${task.fileName} uploaded successfully')),
          );
        }
        // Auto-remove completed card after 3 s
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            ref.read(uploadTasksProvider.notifier).removeTask(task.id);
          }
        });
      },
      onError: (e) {
        ref.read(uploadTasksProvider.notifier).updateTask(
              task.id,
              status: UploadStatus.failed,
              error: e.toString(),
            );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _handle() => Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: CubieColors.textMuted,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(fileListProvider(_currentPath));
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
                    color: CubieColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

            // Back / breadcrumb
            if (_pathStack.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          size: 20, color: CubieColors.textSecondary),
                      onPressed: _navigateBack,
                    ),
                    Expanded(
                      child: Text(
                        _currentPath
                            .split('/')
                            .where((s) => s.isNotEmpty)
                            .last,
                        style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary,
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
                            child: _UploadProgressCard(task: t),
                          ))
                      .toList(),
                ),
              ),

            // File list
            Expanded(
              child: filesAsync.when(
                data: (files) => _buildFileList(files),
                loading: () => const Center(
                  child: CircularProgressIndicator(color: CubieColors.primary),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 48, color: CubieColors.error),
                      const SizedBox(height: 12),
                      Text('Error: $e',
                          style: GoogleFonts.dmSans(color: CubieColors.error)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _refresh, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
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
              onPressed: _showAddMenu,
              child:
                  const Icon(Icons.add_rounded, color: CubieColors.background),
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
                size: 64, color: CubieColors.textMuted),
            const SizedBox(height: 16),
            Text('This folder is empty',
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 15)),
            if (!widget.readOnly) ...[
              const SizedBox(height: 8),
              Text('Upload files or create a folder to get started',
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textMuted, fontSize: 13)),
            ],
          ],
        ),
      );
    }

    // Sort: directories first, then alphabetically
    final sorted = [...files]..sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return RefreshIndicator(
      onRefresh: _refresh,
      color: CubieColors.primary,
      backgroundColor: CubieColors.card,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final file = sorted[i];
          return FileListTile(
            file: file,
            readOnly: widget.readOnly,
            onTap: file.isDirectory ? () => _navigateInto(file) : null,
            onLongPress:
                widget.readOnly ? null : () => _showFileActions(file),
          ).animate().fadeIn(delay: (40 * i).ms);
        },
      ),
    );
  }
}

// ─── Upload progress card ───────────────────────────────────────────────────

class _UploadProgressCard extends StatelessWidget {
  final UploadTask task;
  const _UploadProgressCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == UploadStatus.completed;
    final isFail = task.status == UploadStatus.failed;

    return CubieCard(
      padding: const EdgeInsets.all(12),
      glowing: task.status == UploadStatus.uploading,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CubieColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isDone
                  ? Icons.check_circle_rounded
                  : isFail
                      ? Icons.error_rounded
                      : Icons.upload_rounded,
              color: isDone
                  ? CubieColors.success
                  : isFail
                      ? CubieColors.error
                      : CubieColors.primary,
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
                    color: CubieColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    backgroundColor: CubieColors.cardBorder,
                    valueColor: AlwaysStoppedAnimation(
                      isDone ? CubieColors.success : CubieColors.primary,
                    ),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(task.progress * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.dmSans(
              color: CubieColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
