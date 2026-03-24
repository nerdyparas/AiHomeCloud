import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../services/api_service.dart';
import '../../widgets/app_card.dart';

/// Tab 4 â€” More: a hub for sharing, security, storage, network, and account.
/// Replaces the old 5-tab Settings screen and consolidates all settings here.
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final isAdmin = session?.isAdmin ?? false;
    final userName = session?.username ?? 'User';
    final fingerprint = ref.watch(certFingerprintProvider);
    final servicesAsync = ref.watch(servicesProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 16),

            // â”€â”€ Screen title â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Text(l10n.moreScreenTitle,
                    style: GoogleFonts.sora(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700))
                .animate()
                .fadeIn(duration: 400.ms),

            const SizedBox(height: 20),

            // â”€â”€ 1. PROFILE CARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            _ProfileCard(
              userName: userName,
              onChangePinTap: _changePin,
              onProfileTap: () => context.push('/profile-edit'),
            ).animate().fadeIn(delay: 50.ms),

            const SizedBox(height: 8),
            _sectionLabel(l10n.moreSectionSharing),
            const SizedBox(height: 8),

            // â”€â”€ 2. SHARING CARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [

                  // TV & Computer Sharing â€” toggle row
                  servicesAsync.when(
                    data: (services) {
                      final media = services.cast<ServiceInfo?>().firstWhere(
                          (s) => s?.id == 'media',
                          orElse: () => null);

                      if (media == null) {
                        return ListTile(
                          leading: _iconBox(
                              Icons.tv_rounded, AppColors.secondary),
                          title: Text(l10n.moreServiceTvComputer,
                              style: GoogleFonts.dmSans(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          subtitle: Text(l10n.moreServiceNotAvailable,
                              style: GoogleFonts.dmSans(
                                  color: AppColors.textMuted, fontSize: 12)),
                          trailing: const Icon(Icons.info_outline_rounded,
                              color: AppColors.textMuted, size: 18),
                        );
                      }

                      return ListTile(
                        leading:
                            _iconBox(Icons.tv_rounded, AppColors.secondary),
                        title: Text(l10n.moreServiceTvComputer,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        subtitle: Text(
                            media.isEnabled
                                ? l10n.moreServiceTvSubtitleActive
                                : l10n.moreServiceTvSubtitleInactive,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textSecondary, fontSize: 12)),
                        trailing: Switch(
                          value: media.isEnabled,
                          onChanged: (v) {
                            final messenger = ScaffoldMessenger.of(context);
                            ref.read(servicesProvider.notifier).toggle(
                              media.id,
                              v,
                              onError: (msg) {
                                if (mounted) {
                                  messenger.showSnackBar(SnackBar(
                                    content: Text(friendlyError(
                                        Exception(msg))),
                                  ));
                                }
                              },
                            );
                          },
                          activeThumbColor: AppColors.primary,
                        ),
                      );
                    },
                    loading: () => ListTile(
                      leading:
                          _iconBox(Icons.tv_rounded, AppColors.secondary),
                      title: Text(l10n.moreServiceTvComputer,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary, fontSize: 14)),
                      trailing: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      ),
                    ),
                    error: (e, _) => ListTile(
                      leading: _iconBox(
                          Icons.tv_rounded, AppColors.textSecondary),
                      title: Text(l10n.moreServiceTvComputer,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary, fontSize: 14)),
                      subtitle: Text(friendlyError(e),
                          style: GoogleFonts.dmSans(
                              color: AppColors.textMuted, fontSize: 12)),
                      trailing: GestureDetector(
                        onTap: () => ref.read(servicesProvider.notifier).load(),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFE8A84C),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Telegram Bot (admin only)
                  if (isAdmin) ...[
                    _divider(),
                    ListTile(
                      leading:
                          _iconBox(Icons.send_rounded, AppColors.primary),
                      title: Text(l10n.moreTelegramBot,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text(l10n.moreTelegramSubtitle,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textMuted, size: 20),
                      onTap: () => context.push('/telegram-setup'),
                    ),
                  ],
                ],
              ),
            ).animate().fadeIn(delay: 80.ms),

            const SizedBox(height: 8),
            _sectionLabel(l10n.moreSectionPrivacySecurity),
            const SizedBox(height: 8),

            // â”€â”€ 3. PRIVACY & SECURITY CARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            const SizedBox(height: 4),

            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [

                  // Auto Backup
                  Builder(builder: (context) {
                    final backupAsync = ref.watch(backupStatusProvider);
                    final subtitle = backupAsync.valueOrNull?.statusSubtitle ?? 'Not set up';
                    return ListTile(
                      leading: _iconBox(Icons.cloud_upload_rounded, AppColors.primary),
                      title: Text('Auto Backup',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text(subtitle,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textMuted, size: 20),
                      onTap: () => context.push('/auto-backup'),
                    );
                  }),

                  _divider(),

                  // Server Certificate — demoted to small text link
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: GestureDetector(
                      onTap: _showCertDialog,
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 13,
                              color: fingerprint != null
                                  ? AppColors.success
                                  : AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            l10n.moreCertTitle,
                            style: GoogleFonts.dmSans(
                                color: fingerprint != null
                                    ? AppColors.textSecondary
                                    : AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.textMuted),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            fingerprint != null ? l10n.moreCertPinned : l10n.moreCertNotPinned,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 120.ms),

            const SizedBox(height: 8),
            _sectionLabel(l10n.moreSectionFamilyStorage),
            const SizedBox(height: 8),

            // â”€â”€ 4. FAMILY & STORAGE CARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [

                  // Family Members
                  _navTile(
                    icon: Icons.people_rounded,
                    color: const Color(0xFFE8A84C),
                    title: l10n.moreFamilyMembers,
                    subtitle: l10n.moreFamilyMembersSubtitle,
                    onTap: () => context.go('/family'),
                  ),

                  _divider(),

                  // Storage Drive
                  _navTile(
                    icon: Icons.storage_rounded,
                    color: AppColors.secondary,
                    title: l10n.moreStorageDrive,
                    subtitle: l10n.moreStorageDriveSubtitle,
                    onTap: () => context.push('/storage-explorer'),
                  ),

                  // Device (admin only)
                  if (isAdmin) ...[
                    _divider(),
                    _navTile(
                      icon: Icons.developer_board_rounded,
                      color: AppColors.textSecondary,
                      title: l10n.moreDeviceTitle,
                      subtitle: l10n.moreDeviceSubtitle,
                      onTap: () => context.push('/settings/device'),
                    ),
                  ],
                ],
              ),
            ).animate().fadeIn(delay: 140.ms),

            // â”€â”€ 5. FOOTER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            const SizedBox(height: 32),

            Center(
              child: Text(
                l10n.moreAppVersion,
                style: GoogleFonts.dmSans(
                    color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                l10n.moreTagline,
                style: GoogleFonts.dmSans(
                    color: AppColors.textMuted, fontSize: 11),
              ),
            ),

            const SizedBox(height: 24),

            // Log Out
            Center(
              child: GestureDetector(
                onTap: _confirmLogout,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout_rounded,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 6),
                    Text(l10n.moreLogOut,
                        style: GoogleFonts.dmSans(
                            color: AppColors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),

            // Restart and Shutdown (admin only)
            if (isAdmin) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _confirmReboot,
                    icon: const Icon(Icons.restart_alt_rounded,
                        color: AppColors.primary, size: 16),
                    label: Text(l10n.moreRestart,
                        style: GoogleFonts.dmSans(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: _confirmShutdown,
                    icon: const Icon(Icons.power_settings_new_rounded,
                        color: AppColors.error, size: 16),
                    label: Text(l10n.moreShutDown,
                        style: GoogleFonts.dmSans(
                            color: AppColors.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Shared widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _sectionLabel(String text) => Text(text,
      style: GoogleFonts.sora(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5));

  Widget _divider() => const Divider(
      height: 1, indent: 16, endIndent: 16, color: AppColors.cardBorder);

  Widget _iconBox(IconData icon, Color color) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      );

  Widget _navTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: _iconBox(icon, color),
        title: Text(title,
            style: GoogleFonts.dmSans(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: GoogleFonts.dmSans(
                color: AppColors.textSecondary, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.textMuted, size: 20),
        onTap: onTap,
      );

  // â”€â”€ Dialogs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showCertDialog() {
    final stored = ref.read(certFingerprintProvider);
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.moreCertTitle, style: GoogleFonts.sora()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.moreCertFingerprintLabel,
                style: GoogleFonts.dmSans(fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(
              stored?.toUpperCase() ?? l10n.moreCertNotPinnedYet,
              style: GoogleFonts.dmSans(
                  color: stored != null
                      ? AppColors.textSecondary
                      : AppColors.textMuted,
                  fontSize: 12),
            ),
            if (stored != null) ...[  
              const SizedBox(height: 10),
              Text(
                l10n.moreCertFingerprintDescription,
                style: GoogleFonts.dmSans(
                    color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.buttonClose, style: GoogleFonts.dmSans()),
          ),
        ],
      ),
    );
  }

  void _changePin() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.moreProfileChangePinTitle, style: GoogleFonts.sora()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: GoogleFonts.dmSans(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.settingsCurrentPinHint,
                prefixIcon: const
                    Icon(Icons.lock_open_rounded, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: GoogleFonts.dmSans(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.settingsNewPinHint,
                prefixIcon: const
                    Icon(Icons.lock_rounded, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.buttonCancel,
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref
                    .read(apiServiceProvider)
                    .changePin(oldCtrl.text, newCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.settingsPinChangedSuccess)));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                }
              }
            },
            child: Text(l10n.buttonChange,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _confirmReboot() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.moreRestartDialogTitle, style: GoogleFonts.sora()),
        content: Text(
          l10n.moreRestartDialogMessage,
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.buttonCancel,
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.pop(ctx);
              _performReboot();
            },
            child: Text(l10n.moreRestartButton,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _performReboot() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.moreRestartingSnackbar)),
    );
    try {
      await ref.read(apiServiceProvider).rebootDevice();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.moreRestartStartedSnackbar)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.moreRestartFailedSnackbar(friendlyError(e)))),
        );
      }
    }
  }

  void _confirmShutdown() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.moreShutdownDialogTitle, style: GoogleFonts.sora()),
        content: Text(
          l10n.moreShutdownDialogMessage,
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.buttonCancel,
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              _performShutdown();
            },
            child: Text(l10n.moreShutdownButton,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _performShutdown() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.moreShutdownStartedSnackbar)),
    );
    try {
      await ref.read(apiServiceProvider).shutdownDevice();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.moreShutdownCompleteSnackbar)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  void _confirmLogout() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsLogoutDialogTitle, style: GoogleFonts.sora()),
        content: Text(
          l10n.settingsLogoutWarning,
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.buttonCancel,
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              await ref.read(apiServiceProvider).logout();
              final prefs = ref.read(sharedPreferencesProvider);
              await prefs.clear();
              ref.read(isSetupDoneProvider.notifier).state = false;
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) context.go('/');
            },
            child: Text(l10n.moreLogOut,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€ Profile card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ProfileCard extends StatelessWidget {
  final String userName;
  final VoidCallback onChangePinTap;
  final VoidCallback? onProfileTap;

  const _ProfileCard({
    required this.userName,
    required this.onChangePinTap,
    this.onProfileTap,
  });

  static const _avatarColors = [
    Color(0xFFE8A84C),
    Color(0xFF4C9BE8),
    Color(0xFF4CE88A),
    Color(0xFFE84CA8),
    Color(0xFF9B59B6),
    Color(0xFF1ABC9C),
  ];

  Color get _avatarColor => _avatarColors[
      userName.isNotEmpty ? userName.codeUnitAt(0) % _avatarColors.length : 0];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          GestureDetector(
            onTap: onProfileTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _avatarColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        userName.isNotEmpty
                            ? userName[0].toUpperCase()
                            : 'U',
                        style: GoogleFonts.sora(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userName,
                            style: GoogleFonts.sora(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(l10n.moreProfileEditSubtitle,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 20),
                ],
              ),
            ),
          ),
          const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: AppColors.cardBorder),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_rounded,
                  color: AppColors.textSecondary, size: 18),
            ),
            title: Text(l10n.settingsChangePin,
                style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 20),
            onTap: onChangePinTap,
          ),
        ],
      ),
    );
  }
}
