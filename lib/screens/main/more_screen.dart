import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../models/models.dart';
import '../../providers.dart';
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 16),

            // â”€â”€ Screen title â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Text('More',
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
            _sectionLabel('Sharing'),
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
                          title: Text('TV & Computer Sharing',
                              style: GoogleFonts.dmSans(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          subtitle: Text('Not available',
                              style: GoogleFonts.dmSans(
                                  color: AppColors.textMuted, fontSize: 12)),
                          trailing: const Icon(Icons.info_outline_rounded,
                              color: AppColors.textMuted, size: 18),
                        );
                      }

                      return ListTile(
                        leading:
                            _iconBox(Icons.tv_rounded, AppColors.secondary),
                        title: Text('TV & Computer Sharing',
                            style: GoogleFonts.dmSans(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        subtitle: Text(
                            media.isEnabled
                                ? 'DLNA + SMB active'
                                : 'Stream to TVs and computers',
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
                      title: Text('TV & Computer Sharing',
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
                      title: Text('TV & Computer Sharing',
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
                      title: Text('Telegram Bot',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text('Send files from anywhere',
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
            _sectionLabel('Privacy & Security'),
            const SizedBox(height: 8),

            // â”€â”€ 3. PRIVACY & SECURITY CARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            const SizedBox(height: 4),

            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [

                  // Server Certificate
                  ListTile(
                    leading: _iconBox(
                        Icons.verified_user_rounded, AppColors.success),
                    title: Text('Server Certificate',
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      fingerprint != null
                          ? fingerprint.toUpperCase()
                          : 'Not pinned yet',
                      style: GoogleFonts.dmSans(
                          color: fingerprint != null
                              ? AppColors.textSecondary
                              : AppColors.textMuted,
                          fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                    onTap: () => _verifyServerCertificate(fingerprint),
                  ),

                  _divider(),

                  // Trash
                  const _TrashCard(),
                ],
              ),
            ).animate().fadeIn(delay: 120.ms),

            const SizedBox(height: 8),
            _sectionLabel('Family & Storage'),
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
                    title: 'Family Members',
                    subtitle: 'Manage users and storage',
                    onTap: () => context.go('/family'),
                  ),

                  _divider(),

                  // Storage Drive
                  _navTile(
                    icon: Icons.storage_rounded,
                    color: AppColors.secondary,
                    title: 'Storage Drive',
                    subtitle: 'Manage drives and storage',
                    onTap: () => context.push('/storage-explorer'),
                  ),

                  // Device (admin only)
                  if (isAdmin) ...[
                    _divider(),
                    _navTile(
                      icon: Icons.developer_board_rounded,
                      color: AppColors.textSecondary,
                      title: 'Device',
                      subtitle: 'Device info and name',
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
                'AiHomeCloud v1.0.0',
                style: GoogleFonts.dmSans(
                    color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Your personal home cloud',
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
                    Text('Log Out',
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
                    label: Text('Restart',
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
                    label: Text('Shut Down',
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

  Future<void> _verifyServerCertificate(String? storedFingerprint) async {
    final api = ref.read(apiServiceProvider);
    String? serverFingerprint;
    String message;

    try {
      serverFingerprint = await api.fetchServerFingerprint();
      if (serverFingerprint == null) {
        message = 'Unable to fetch the fingerprint from the device.';
      } else if (storedFingerprint == null) {
        message = 'Fingerprint retrieved from the current device.';
      } else if (storedFingerprint == serverFingerprint) {
        message = 'Stored fingerprint matches the server certificate.';
      } else {
        message = 'Stored fingerprint differs from the server certificate.';
      }
    } catch (e) {
      message = 'Failed to verify fingerprint: ${friendlyError(e)}';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Server Certificate', style: GoogleFonts.sora()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stored fingerprint:', style: GoogleFonts.dmSans(fontSize: 12)),
            SelectableText(
              storedFingerprint?.toUpperCase() ?? 'Not set',
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text('Server fingerprint:', style: GoogleFonts.dmSans(fontSize: 12)),
            SelectableText(
              serverFingerprint?.toUpperCase() ?? 'Unavailable',
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Text(message,
                style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: GoogleFonts.dmSans()),
          ),
          if (serverFingerprint != null)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await persistServerFingerprint(ref, serverFingerprint!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Fingerprint pinned to certificate.')));
                }
              },
              child: Text('Trust Fingerprint', style: GoogleFonts.dmSans()),
            ),
        ],
      ),
    );
  }

  void _changePin() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change my PIN', style: GoogleFonts.sora()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: GoogleFonts.dmSans(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Current PIN',
                prefixIcon:
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
              decoration: const InputDecoration(
                hintText: 'New PIN',
                prefixIcon:
                    Icon(Icons.lock_rounded, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
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
                      const SnackBar(content: Text('PIN changed successfully')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                }
              }
            },
            child: Text('Change',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _confirmReboot() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restart AiHomeCloud?', style: GoogleFonts.sora()),
        content: Text(
          'The device will restart and come back online in about a minute.',
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.pop(ctx);
              _performReboot();
            },
            child: Text('Restart',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _performReboot() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restarting AiHomeCloudâ€¦')),
    );
    try {
      await ref.read(apiServiceProvider).rebootDevice();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AiHomeCloud is restarting.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restart failed: ${friendlyError(e)}')),
        );
      }
    }
  }

  void _confirmShutdown() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Shut Down AiHomeCloud?', style: GoogleFonts.sora()),
        content: Text(
          'This will stop all active services, cancel file transfers, '
          'and safely power off the device. You will need physical access '
          'to turn it back on.',
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              _performShutdown();
            },
            child: Text('Shut Down',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _performShutdown() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shutting down AiHomeCloudâ€¦')),
    );
    try {
      await ref.read(apiServiceProvider).shutdownDevice();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AiHomeCloud is powering off.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shutdown failed: ${friendlyError(e)}')),
        );
      }
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Log Out?', style: GoogleFonts.sora()),
        content: Text(
          'You will need to pair your device again to use the app.',
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
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
            child: Text('Log Out',
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
                        Text('Edit name, icon and PIN',
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
            title: Text('Change PIN',
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

// â”€â”€â”€ Trash card (Privacy section) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _TrashCard extends ConsumerStatefulWidget {
  const _TrashCard();

  @override
  ConsumerState<_TrashCard> createState() => _TrashCardState();
}

class _TrashCardState extends ConsumerState<_TrashCard> {
  bool _clearing = false;

  Future<void> _emptyTrash(List<TrashItem> items) async {
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
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
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
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trashAsync = ref.watch(trashItemsProvider);
    final items = trashAsync.valueOrNull ?? [];
    final totalMB =
        items.fold(0, (sum, i) => sum + i.sizeBytes) ~/ (1024 * 1024);

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppColors.error, size: 18),
      ),
      title: Text('Trash',
          style: GoogleFonts.dmSans(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(
          items.isEmpty
              ? 'Empty'
              : '${items.length} item${items.length > 1 ? 's' : ''} Â· $totalMB MB',
          style: GoogleFonts.dmSans(
              color: AppColors.textSecondary, fontSize: 12)),
      trailing: items.isEmpty
          ? null
          : _clearing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.error),
                )
              : TextButton(
                  onPressed: () => _emptyTrash(items),
                  child: Text('Empty',
                      style: GoogleFonts.dmSans(
                          color: AppColors.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
    );
  }
}

