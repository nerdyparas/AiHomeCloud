import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../services/api_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/user_avatar.dart';

class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyAsync = ref.watch(familyUsersProvider);
    final l10n = AppLocalizations.of(context)!;

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
                      child: Text(l10n.familyTitle,
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
                child: Text(l10n.familySubtitle,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 14)),
              ),
            ),

            // ── Member list ─────────────────────────────────────────────────
            familyAsync.when(
              data: (users) {
                final session = ref.read(authSessionProvider);
                final currentUserIsAdmin = session?.isAdmin ?? false;
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final u = users[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MemberCard(
                            user: u,
                            index: i,
                            isCurrentUserAdmin: currentUserIsAdmin,
                            onTap: () => context.push('/folder-view', extra: {
                              'title': l10n.familyMemberFiles(u.name),
                              'folderPath':
                                  '${AppConstants.personalBasePath}${u.name.toLowerCase()}/',
                              'readOnly': true,
                            }),
                            onRemove: (currentUserIsAdmin && !u.isAdmin)
                                ? () => _confirmRemove(context, ref, u)
                                : null,
                            onRoleToggle: currentUserIsAdmin
                                ? () => _confirmRoleChange(context, ref, u)
                                : null,
                          )
                              .animate()
                              .fadeIn(delay: (100 * i).ms)
                              .slideX(begin: 0.05, end: 0),
                        );
                      },
                      childCount: users.length,
                    ),
                  ),
                );
              },
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
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.familyAddMemberTitle, style: GoogleFonts.sora()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.dmSans(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: l10n.familyNameHint,
            prefixIcon: const
                Icon(Icons.person_rounded, color: AppColors.textMuted),
          ),
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
              if (ctrl.text.trim().isNotEmpty) {
                try {
                  await ref
                      .read(apiServiceProvider)
                      .addFamilyUser(ctrl.text.trim());
                  ref.invalidate(familyUsersProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(friendlyError(e))),
                    );
                  }
                }
              }
            },
            child: Text(l10n.buttonAdd,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Role change confirmation ─────────────────────────────────────────────

  void _confirmRoleChange(BuildContext context, WidgetRef ref, FamilyUser user) {
    final l10n = AppLocalizations.of(context)!;
    final makeAdmin = !user.isAdmin;
    final action = makeAdmin ? l10n.familyMakeAdminTitle : l10n.familyRemoveAdminTitle;
    final body = makeAdmin
        ? l10n.familyMakeAdminDescription(user.name)
        : l10n.familyRemoveAdminDescription(user.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action, style: GoogleFonts.sora()),
        content: Text(body,
            style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.buttonCancel,
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(apiServiceProvider)
                    .setUserRole(user.id, isAdmin: makeAdmin);
                ref.invalidate(familyUsersProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyError(e))),
                  );
                }
              }
            },
            child: Text(action,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Remove confirmation ───────────────────────────────────────────────────

  void _confirmRemove(BuildContext context, WidgetRef ref, FamilyUser user) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.familyRemoveTitle(user.name), style: GoogleFonts.sora()),
        content: Text(
          l10n.familyRemoveWarning,
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.buttonCancel,
                style:
                    GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
            onPressed: () async {
              try {
                await ref
                    .read(apiServiceProvider)
                    .removeFamilyUser(user.id);
                ref.invalidate(familyUsersProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(friendlyError(e))),
                  );
                }
              }
            },
            child: Text(l10n.buttonRemove,
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
  final int index;
  final bool isCurrentUserAdmin;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onRoleToggle;

  const _MemberCard({
    required this.user,
    required this.index,
    required this.isCurrentUserAdmin,
    this.onTap,
    this.onRemove,
    this.onRoleToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppCard(
      onTap: onTap,
      onLongPress: onRoleToggle != null
          ? () => _showRoleMenu(context)
          : null,
      child: Row(
        children: [
          // Avatar
          UserAvatar(
            name: user.name,
            iconEmoji: user.iconEmoji,
            colorIndex: index,
            size: 48,
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
                        child: Text(l10n.familyAdminBadge,
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
                    l10n.familyStorageUsed(user.folderSizeGB.toStringAsFixed(1)),
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

  void _showRoleMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = user.isAdmin ? l10n.familyRemoveAdminTitle : l10n.familyMakeAdminTitle;
    final icon = user.isAdmin
        ? Icons.admin_panel_settings_outlined
        : Icons.admin_panel_settings_rounded;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(icon, color: AppColors.primary),
              title: Text(label,
                  style: GoogleFonts.dmSans(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(user.name,
                  style:
                      GoogleFonts.dmSans(color: AppColors.textSecondary)),
              onTap: () {
                Navigator.pop(context);
                onRoleToggle?.call();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
