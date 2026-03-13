import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/error_utils.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/folder_view.dart';

/// Tab 2 — Files explorer with two root entries: personal folder and Shared.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});
  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  // null = root view, non-null = inside a folder
  String? _currentPath;
  String? _currentTitle;
  bool _trashOpen = false;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _activeQuery = value.trim());
    });
  }

  void _openFolder(String path, String title) {
    setState(() {
      _currentPath = path;
      _currentTitle = title;
      _trashOpen = false;
    });
  }

  void _goBack() {
    setState(() {
      _currentPath = null;
      _currentTitle = null;
      _trashOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Trash screen
    if (_trashOpen) {
      return _TrashScreen(onBack: _goBack);
    }

    if (_currentPath != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goBack();
        },
        child: FolderView(
          title: _currentTitle ?? 'Files',
          folderPath: _currentPath!,
          readOnly: false,
          showHeader: true,
          onBack: _goBack,
        ),
      );
    }

    // Root view: show 4 folder entries
    final session = ref.watch(authSessionProvider);
    final username = session?.username ?? 'My Files';
    final personalPath = '${AppConstants.personalBasePath}$username/';
    const familyPath = AppConstants.familyPath;
    const entertainmentPath = AppConstants.entertainmentPath;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text('Files',
                style: GoogleFonts.sora(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                )),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _buildSearchBar(),
            ),
            if (_activeQuery.isNotEmpty)
              Expanded(
                child: SingleChildScrollView(
                  child: _DocSearchResults(query: _activeQuery),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _FolderCard(
                      name: username,
                      icon: Icons.person_rounded,
                      color: AppColors.primary,
                      subtitle: 'Your private files',
                      onTap: () => _openFolder(personalPath, username),
                    ),
                    const SizedBox(height: 12),
                    _FolderCard(
                      name: 'Family',
                      icon: Icons.people_rounded,
                      color: const Color(0xFF4CE88A),
                      subtitle: 'Shared with everyone',
                      onTap: () => _openFolder(familyPath, 'Family'),
                    ),
                    const SizedBox(height: 12),
                    _FolderCard(
                      name: 'Entertainment',
                      icon: Icons.movie_rounded,
                      color: const Color(0xFFE84CA8),
                      subtitle: 'Movies, series, music',
                      onTap: () => _openFolder(entertainmentPath, 'Entertainment'),
                    ),
                    const SizedBox(height: 12),
                    _FolderCard(
                      name: 'Trash',
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.error,
                      subtitle: 'Recently deleted files',
                      onTap: () => setState(() => _trashOpen = true),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearchChanged,
      style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search documents…',
        hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: const Icon(
            Icons.search_rounded, color: AppColors.textMuted, size: 20),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded,
                    color: AppColors.textMuted, size: 20),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearchChanged('');
                },
              )
            : null,
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final String subtitle;
  final VoidCallback onTap;

  const _FolderCard({
    required this.name,
    required this.icon,
    required this.color,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(name,
          style: GoogleFonts.dmSans(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          )),
        subtitle: Text(subtitle,
          style: GoogleFonts.dmSans(
            color: AppColors.textMuted,
            fontSize: 12,
          )),
        trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Document search results
// ---------------------------------------------------------------------------

class _DocSearchResults extends ConsumerWidget {
  final String query;
  const _DocSearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(docSearchResultsProvider(query));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: resultsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
        ),
        error: (e, _) => AppCard(
          child: Text(friendlyError(e),
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (results) {
          if (results.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_off_rounded,
                      color: AppColors.textMuted, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No documents found for "$query"',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              for (int i = 0; i < results.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SearchResultTile(result: results[i])
                      .animate()
                      .fadeIn(delay: (50 * i).ms)
                      .slideY(begin: 0.05, end: 0),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  const _SearchResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final file = result.toFileItem();
    return AppCard(
      onTap: () => context.push('/file-preview', extra: file),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: file.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(file.icon, color: file.iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.filename,
                  style: GoogleFonts.dmSans(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${result.addedBy}  •  ${_formatDate(result.addedAt)}',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays < 1) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ---------------------------------------------------------------------------
// Trash screen
// ---------------------------------------------------------------------------

class _TrashScreen extends ConsumerWidget {
  final VoidCallback onBack;
  const _TrashScreen({required this.onBack});

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _restore(
      BuildContext context, WidgetRef ref, TrashItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiServiceProvider).restoreTrashItem(item.id);
      ref.invalidate(trashItemsProvider);
      messenger.showSnackBar(
          SnackBar(content: Text('Restored: ${item.filename}')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Restore failed: ${friendlyError(e)}')));
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, TrashItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete permanently?', style: GoogleFonts.sora()),
        content: Text(
          '${item.filename} will be permanently deleted. This cannot be undone.',
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiServiceProvider).permanentDeleteTrashItem(item.id);
      ref.invalidate(trashItemsProvider);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Delete failed: ${friendlyError(e)}')));
    }
  }

  Future<void> _emptyTrash(
      BuildContext context, WidgetRef ref, List<TrashItem> items) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Empty Trash?', style: GoogleFonts.sora()),
        content: Text(
          'This will permanently delete ${items.length} '
          'item${items.length == 1 ? '' : 's'}. This cannot be undone.',
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Empty Trash',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiServiceProvider);
      for (final item in items) {
        await api.permanentDeleteTrashItem(item.id);
      }
      ref.invalidate(trashItemsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Trash emptied.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Failed: ${friendlyError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(trashItemsProvider);
    final autoDeleteAsync = ref.watch(trashAutoDeleteProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded,
                          color: AppColors.textPrimary),
                      onPressed: onBack,
                    ),
                    Text(
                      'Trash',
                      style: GoogleFonts.sora(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              // Auto-delete toggle
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: autoDeleteAsync.when(
                    data: (enabled) => SwitchListTile(
                      value: enabled,
                      activeColor: AppColors.primary,
                      onChanged: (val) async {
                        try {
                          await ref
                              .read(apiServiceProvider)
                              .setTrashAutoDelete(val);
                          ref.invalidate(trashAutoDeleteProvider);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Could not save: ${friendlyError(e)}'),
                          ));
                        }
                      },
                      title: Text(
                        'Auto-delete after 30 days',
                        style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        enabled
                            ? 'Items older than 30 days are permanently deleted'
                            : 'Files stay in trash until manually deleted',
                        style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                    error: (_, __) => ListTile(
                      title: Text('Auto-delete after 30 days',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary, fontSize: 14)),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh_rounded,
                            color: AppColors.primary),
                        onPressed: () => ref.invalidate(trashAutoDeleteProvider),
                      ),
                    ),
                  ),
                ),
              ),
              // Items list
              Expanded(
                child: trashAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.delete_outline_rounded,
                                color: AppColors.textMuted, size: 56),
                            const SizedBox(height: 12),
                            Text('Trash is empty',
                                style: GoogleFonts.dmSans(
                                    color: AppColors.textMuted, fontSize: 15)),
                          ],
                        ),
                      );
                    }
                    final total =
                        items.fold<int>(0, (s, e) => s + e.sizeBytes);
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${items.length} item${items.length == 1 ? '' : 's'}'
                                ' \u2022 ${_fmt(total)}',
                                style: GoogleFonts.dmSans(
                                    color: AppColors.textSecondary,
                                    fontSize: 12),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                    foregroundColor: AppColors.error),
                                onPressed: () =>
                                    _emptyTrash(context, ref, items),
                                child: Text('Empty All',
                                    style: GoogleFonts.dmSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, i) => _TrashItemTile(
                              item: items[i],
                              onRestore: () => _restore(context, ref, items[i]),
                              onDelete: () => _delete(context, ref, items[i]),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  error: (e, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(friendlyError(e),
                            style: GoogleFonts.dmSans(
                                color: AppColors.textMuted, fontSize: 14)),
                        const SizedBox(height: 8),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          color: AppColors.primary,
                          onPressed: () => ref.invalidate(trashItemsProvider),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrashItemTile extends StatelessWidget {
  final TrashItem item;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _TrashItemTile({
    required this.item,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final daysAgo = DateTime.now().difference(item.deletedAt).inDays;
    final daysLeft = 30 - daysAgo;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.insert_drive_file_rounded,
                color: AppColors.error, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.formattedSize} \u2022 ${daysAgo}d ago'
                  '${daysLeft > 0 ? ' \u2022 ${daysLeft}d left' : ' \u2022 expires soon'}',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restore_rounded,
                color: AppColors.primary, size: 20),
            tooltip: 'Restore',
            onPressed: onRestore,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_rounded,
                color: AppColors.error, size: 20),
            tooltip: 'Delete permanently',
            onPressed: onDelete,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
