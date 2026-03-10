import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../providers.dart';
import '../../widgets/app_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final fingerprint = ref.watch(certFingerprintProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 16),
            Text('Settings',
                    style: GoogleFonts.sora(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700))
                .animate()
                .fadeIn(duration: 400.ms),

            // ── Categories ──────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('General'),
            const SizedBox(height: 12),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _categoryTile(
                    icon: Icons.wifi_rounded,
                    title: 'Network',
                    subtitle: 'Wi-Fi, Hotspot, Bluetooth, Ethernet',
                    onTap: () => context.push('/settings/network'),
                  ),
                  _divider(),
                  _categoryTile(
                    icon: Icons.developer_board_rounded,
                    title: 'Device',
                    subtitle: 'Info, name',
                    onTap: () => context.push('/settings/device'),
                  ),
                  _divider(),
                  _categoryTile(
                    icon: Icons.apps_rounded,
                    title: 'Services',
                    subtitle: 'Manage NAS services',
                    onTap: () => context.push('/settings/services'),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 50.ms),

            // ── Security ────────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Security'),
            const SizedBox(height: 12),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.verified_user_rounded,
                        color: AppColors.primary, size: 20),
                    title: Text('Verify Server Certificate',
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary, fontSize: 14)),
                    subtitle: Text(
                      fingerprint != null
                          ? fingerprint.toUpperCase()
                          : 'Not pinned yet',
                      style: GoogleFonts.dmSans(
                          color: fingerprint != null
                              ? AppColors.textSecondary
                              : AppColors.textMuted,
                          fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                    onTap: () => _verifyServerCertificate(fingerprint),
                  ),
                  _divider(),
                  ListTile(
                    leading: const Icon(Icons.lock_rounded,
                        color: AppColors.textSecondary, size: 20),
                    title: Text('Change PIN',
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary, fontSize: 14)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                    onTap: _changePin,
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 100.ms),

            // ── Account ─────────────────────────────────────────────────────
            const SizedBox(height: 24),
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.logout_rounded,
                    color: AppColors.error, size: 20),
                title: Text('Logout',
                    style: GoogleFonts.dmSans(
                        color: AppColors.error, fontSize: 14)),
                onTap: _confirmLogout,
              ),
            ).animate().fadeIn(delay: 150.ms),

            // ── Power ───────────────────────────────────────────────────────
            const SizedBox(height: 16),
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.power_settings_new_rounded,
                    color: AppColors.error, size: 20),
                title: Text('Turn Off Cubie',
                    style: GoogleFonts.dmSans(
                        color: AppColors.error, fontSize: 14)),
                subtitle: Text('Stop all services and power off',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textMuted, fontSize: 12)),
                onTap: _confirmShutdown,
              ),
            ).animate().fadeIn(delay: 200.ms),

            // ── Footer ──────────────────────────────────────────────────────
            const SizedBox(height: 32),
            Center(
              child: Text('AiHomeCloud v1.0.0',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textMuted, fontSize: 12)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(text,
      style: GoogleFonts.sora(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5));

  Widget _divider() => const Divider(
      height: 1, indent: 16, endIndent: 16, color: AppColors.cardBorder);

  Widget _categoryTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
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

  // ── Dialogs ───────────────────────────────────────────────────────────────

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
            Text('Stored fingerprint:',
                style: GoogleFonts.dmSans(fontSize: 12)),
            SelectableText(
              storedFingerprint?.toUpperCase() ?? 'Not set',
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text('Server fingerprint:',
                style: GoogleFonts.dmSans(fontSize: 12)),
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
        title: Text('Change PIN', style: GoogleFonts.sora()),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('PIN changed successfully')));
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

  void _confirmShutdown() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Turn Off Cubie?', style: GoogleFonts.sora()),
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
            child: Text('Turn Off',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _performShutdown() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shutting down Cubie…')),
    );
    try {
      await ref.read(apiServiceProvider).shutdownDevice();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cubie is powering off.')),
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
        title: Text('Logout?', style: GoogleFonts.sora()),
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
            child: Text('Logout',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
