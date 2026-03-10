import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/cubie_card.dart';

/// Tab 2 — storage file explorer (Google Files / My Computer style).
/// Shows available USB/NVMe drives and quick-access folders.
class MyFolderScreen extends ConsumerStatefulWidget {
  const MyFolderScreen({super.key});

  @override
  ConsumerState<MyFolderScreen> createState() => _MyFolderScreenState();
}

class _MyFolderScreenState extends ConsumerState<MyFolderScreen> {
  List<StorageRoot>? _roots;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roots = await ref.read(apiServiceProvider).getStorageRoots();
      if (mounted) setState(() { _roots = roots; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  String get _userName {
    final session = ref.watch(authSessionProvider);
    return (session?.username.isNotEmpty ?? false) ? session!.username : 'user';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRoots,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              // ── Title ─────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text('My Files',
                      style: GoogleFonts.sora(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                ).animate().fadeIn(duration: 400.ms),
              ),

              // ── Storage Drives ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Text('Storage Drives',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),

              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  ),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: AppCard(
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(_error!,
                                style: GoogleFonts.dmSans(
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded,
                                color: AppColors.primary, size: 20),
                            onPressed: _loadRoots,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_roots == null || _roots!.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: AppCard(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.textMuted.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.usb_off_rounded,
                                color: AppColors.textMuted, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('No storage connected',
                                    style: GoogleFonts.dmSans(
                                        color: AppColors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text('Connect a USB drive or NVMe SSD',
                                    style: GoogleFonts.dmSans(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final root = _roots![index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 5),
                        child: _DriveCard(
                          root: root,
                          onTap: () => context.push('/folder-view', extra: {
                            'title': root.name,
                            'folderPath': '${root.path}/',
                            'readOnly': false,
                          }),
                        ).animate()
                          .fadeIn(delay: (100 * index).ms)
                          .slideY(begin: 0.05, end: 0),
                      );
                    },
                    childCount: _roots!.length,
                  ),
                ),

              // ── Quick Access ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Text('Quick Access',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                  child: AppCard(
                    onTap: () => context.push('/folder-view', extra: {
                      'title': 'Personal',
                      'folderPath': '${AppConstants.personalBasePath}$_userName/',
                      'readOnly': false,
                    }),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_rounded,
                              color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Personal',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('Your private files',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textMuted, size: 18),
                      ],
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05, end: 0),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                  child: AppCard(
                    onTap: () => context.push('/folder-view', extra: {
                      'title': 'Shared',
                      'folderPath': AppConstants.sharedPath,
                      'readOnly': false,
                    }),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.folder_shared_rounded,
                              color: AppColors.secondary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Shared',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('Family shared files',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textMuted, size: 18),
                      ],
                    ),
                  ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05, end: 0),
                ),
              ),

              // Bottom padding
              const SliverToBoxAdapter(
                child: SizedBox(height: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card showing a storage drive.
class _DriveCard extends StatelessWidget {
  final StorageRoot root;
  final VoidCallback onTap;
  const _DriveCard({required this.root, required this.onTap});

  Color get _color => switch (root.transport) {
        'usb' => const Color(0xFF4C9BE8),
        'nvme' => const Color(0xFFE8A84C),
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(root.icon, color: _color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(root.name,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${root.typeLabel}  •  ${root.sizeDisplay}',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }
}
