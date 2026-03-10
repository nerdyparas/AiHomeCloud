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
import '../../widgets/app_card.dart';

class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyAsync = ref.watch(familyUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Family',
                          style: GoogleFonts.sora(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700)),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.person_add_rounded,
                            color: AppColors.primary, size: 20),
                        onPressed: () =>
                            _showAddDialog(context, ref),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 400.ms),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text('Manage family members and their storage',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 14)),
              ),
            ),

            // ── Member list ─────────────────────────────────────────────────
            familyAsync.when(
              data: (users) => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final u = users[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MemberCard(
                          user: u,
                          onTap: () => context.push('/folder-view', extra: {
                            'title': "${u.name}'s Files",
                            'folderPath':
                                '${AppConstants.personalBasePath}${u.name.toLowerCase()}/',
                            'readOnly': true,
                          }),
                          onRemove: u.isAdmin
                              ? null
                              : () => _confirmRemove(context, ref, u),
                        )
                            .animate()
                            .fadeIn(delay: (100 * i).ms)
                            .slideX(begin: 0.05, end: 0),
                      );
                    },
                    childCount: users.length,
                  ),
                ),
              ),
              loading: () => const SliverFillRemaining(
                child: Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary)),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(
                    child: Text(friendlyError(e),
                        style: const TextStyle(color: AppColors.error))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add member dialog ─────────────────────────────────────────────────────

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Family Member', style: GoogleFonts.sora()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.dmSans(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Name',
            prefixIcon:
                Icon(Icons.person_rounded, color: AppColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                await ref
                    .read(apiServiceProvider)
                    .addFamilyUser(ctrl.text.trim());
                ref.invalidate(familyUsersProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: Text('Add',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Remove confirmation ───────────────────────────────────────────────────

  void _confirmRemove(BuildContext context, WidgetRef ref, FamilyUser user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${user.name}?', style: GoogleFonts.sora()),
        content: Text(
          'This will remove their account and all their files. '
          'This action cannot be undone.',
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              await ref
                  .read(apiServiceProvider)
                  .removeFamilyUser(user.id);
              ref.invalidate(familyUsersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Remove',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Family member card ─────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final FamilyUser user;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _MemberCard({required this.user, this.onTap, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: user.avatarColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                user.name[0].toUpperCase(),
                style: GoogleFonts.sora(
                    color: user.avatarColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(user.name,
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    if (user.isAdmin) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Admin',
                            style: GoogleFonts.dmSans(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                    '${user.folderSizeGB.toStringAsFixed(1)} GB used',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.error, size: 20),
              onPressed: onRemove,
            ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 20),
        ],
      ),
    );
  }
}
