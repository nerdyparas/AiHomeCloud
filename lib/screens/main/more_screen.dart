import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/cubie_card.dart';

/// Tab 4 — More: a hub for sharing, security, storage, network, and account.
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
    final fingerprint = ref.watch(certFingerprintProvider);
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      backgroundColor: CubieColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 16),
            Text('More',
                    style: GoogleFonts.sora(
                        color: CubieColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700))
                .animate()
                .fadeIn(duration: 400.ms),

            // ── Sharing & Streaming ──────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Sharing & Streaming'),
            const SizedBox(height: 12),

            // Smart TV Streaming toggle (DLNA service)
            servicesAsync.when(
              data: (services) {
                final dlna = services.cast<ServiceInfo?>().firstWhere(
                    (s) => s?.id == 'dlna',
                    orElse: () => null);
                if (dlna == null) {
                  return CubieCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: _iconBox(Icons.tv_rounded, CubieColors.secondary),
                      title: Text('Smart TV Streaming',
                          style: GoogleFonts.dmSans(
                              color: CubieColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text('Not available',
                          style: GoogleFonts.dmSans(
                              color: CubieColors.textMuted, fontSize: 12)),
                      trailing: const Icon(Icons.info_outline_rounded,
                          color: CubieColors.textMuted, size: 18),
                    ),
                  ).animate().fadeIn(delay: 50.ms);
                }
                return CubieCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: _iconBox(Icons.tv_rounded, CubieColors.secondary),
                    title: Text('Smart TV Streaming',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    subtitle: Text(
                        dlna.isEnabled
                            ? 'Streaming to nearby TVs'
                            : 'Stream media to your Smart TV',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textSecondary, fontSize: 12)),
                    trailing: Switch(
                      value: dlna.isEnabled,
                      onChanged: (v) async {
                        try {
                          await ref
                              .read(apiServiceProvider)
                              .toggleService(dlna.id, v);
                          ref.invalidate(servicesProvider);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(friendlyError(e))),
                            );
                          }
                        }
                      },
                      activeColor: CubieColors.primary,
                    ),
                  ),
                ).animate().fadeIn(delay: 50.ms);
              },
              loading: () => CubieCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: _iconBox(Icons.tv_rounded, CubieColors.secondary),
                  title: Text('Smart TV Streaming',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  trailing: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: CubieColors.primary),
                  ),
                ),
              ),
              error: (e, _) => CubieCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading:
                      _iconBox(Icons.tv_rounded, CubieColors.textSecondary),
                  title: Text('Smart TV Streaming',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textPrimary, fontSize: 14)),
                  subtitle: Text(friendlyError(e),
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textMuted, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: CubieColors.primary, size: 20),
                    onPressed: () => ref.invalidate(servicesProvider),
                  ),
                ),
              ),
            ),

            // ── Ad Blocking ──────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Ad Blocking'),
            const SizedBox(height: 12),
            _AdBlockingCard(isAdmin: isAdmin)
                .animate()
                .fadeIn(delay: 80.ms),

            // ── Telegram Bot (admin only) ─────────────────────────────────
            if (isAdmin) ...[
              const SizedBox(height: 24),
              _sectionLabel('Telegram Bot'),
              const SizedBox(height: 12),
              CubieCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading:
                      _iconBox(Icons.smart_toy_rounded, CubieColors.primary),
                  title: Text('Telegram Bot',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  subtitle: Text('Find documents via Telegram',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: CubieColors.textMuted, size: 20),
                  onTap: () => context.push('/telegram-setup'),
                ),
              ).animate().fadeIn(delay: 100.ms),
            ],
            // ── Trash ────────────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Trash'),
            const SizedBox(height: 12),
            const _TrashCard().animate().fadeIn(delay: 110.ms),
            // ── Security ─────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Security'),
            const SizedBox(height: 12),
            CubieCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.verified_user_rounded,
                        color: CubieColors.primary, size: 20),
                    title: Text('Verify Server Certificate',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textPrimary, fontSize: 14)),
                    subtitle: Text(
                      fingerprint != null
                          ? fingerprint.toUpperCase()
                          : 'Not pinned yet',
                      style: GoogleFonts.dmSans(
                          color: fingerprint != null
                              ? CubieColors.textSecondary
                              : CubieColors.textMuted,
                          fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: CubieColors.textMuted, size: 20),
                    onTap: () => _verifyServerCertificate(fingerprint),
                  ),
                  _divider(),
                  ListTile(
                    leading: _iconBox(
                        Icons.lock_rounded, CubieColors.textSecondary),
                    title: Text('Change my PIN',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: CubieColors.textMuted, size: 20),
                    onTap: _changePin,
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 120.ms),

            // ── Storage & Network ─────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Storage & Network'),
            const SizedBox(height: 12),
            CubieCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _navTile(
                    icon: Icons.storage_rounded,
                    color: CubieColors.secondary,
                    title: 'Storage Drive',
                    subtitle: 'Manage drives and storage',
                    onTap: () => context.push('/storage-explorer'),
                  ),
                  _divider(),
                  _navTile(
                    icon: Icons.wifi_rounded,
                    color: CubieColors.primary,
                    title: 'Network',
                    subtitle: 'Wi-Fi, Hotspot, Ethernet',
                    onTap: () => context.push('/settings/network'),
                  ),
                  if (isAdmin) ...[
                    _divider(),
                    _navTile(
                      icon: Icons.developer_board_rounded,
                      color: CubieColors.textSecondary,
                      title: 'Device',
                      subtitle: 'Device info and name',
                      onTap: () => context.push('/settings/device'),
                    ),
                  ],
                ],
              ),
            ).animate().fadeIn(delay: 140.ms),

            // ── About ─────────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('About'),
            const SizedBox(height: 12),
            CubieCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: CubieColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.home_rounded,
                            color: CubieColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AiHomeCloud',
                              style: GoogleFonts.sora(
                                  color: CubieColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          Text('v1.0.0',
                              style: GoogleFonts.dmSans(
                                  color: CubieColors.textSecondary,
                                  fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your personal home NAS — files, family, and streaming in one place.',
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textSecondary,
                        fontSize: 12,
                        height: 1.5),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 160.ms),

            // ── Danger zone ───────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Account'),
            const SizedBox(height: 12),
            CubieCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout_rounded,
                        color: CubieColors.error, size: 20),
                    title: Text('Log Out',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.error, fontSize: 14)),
                    onTap: _confirmLogout,
                  ),
                  if (isAdmin) ...[
                    _divider(),
                    ListTile(
                      leading: const Icon(Icons.power_settings_new_rounded,
                          color: CubieColors.error, size: 20),
                      title: Text('Shut Down AiHomeCloud',
                          style: GoogleFonts.dmSans(
                              color: CubieColors.error, fontSize: 14)),
                      subtitle: Text('Stop all services and power off',
                          style: GoogleFonts.dmSans(
                              color: CubieColors.textMuted, fontSize: 12)),
                      onTap: _confirmShutdown,
                    ),
                  ],
                ],
              ),
            ).animate().fadeIn(delay: 180.ms),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(text,
      style: GoogleFonts.sora(
          color: CubieColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5));

  Widget _divider() => const Divider(
      height: 1, indent: 16, endIndent: 16, color: CubieColors.cardBorder);

  Widget _iconBox(IconData icon, Color color) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
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
                color: CubieColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: GoogleFonts.dmSans(
                color: CubieColors.textSecondary, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: CubieColors.textMuted, size: 20),
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
            Text('Stored fingerprint:', style: GoogleFonts.dmSans(fontSize: 12)),
            SelectableText(
              storedFingerprint?.toUpperCase() ?? 'Not set',
              style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text('Server fingerprint:', style: GoogleFonts.dmSans(fontSize: 12)),
            SelectableText(
              serverFingerprint?.toUpperCase() ?? 'Unavailable',
              style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Text(message,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 12)),
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
              style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Current PIN',
                prefixIcon:
                    Icon(Icons.lock_open_rounded, color: CubieColors.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'New PIN',
                prefixIcon:
                    Icon(Icons.lock_rounded, color: CubieColors.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: CubieColors.textSecondary)),
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

  void _confirmShutdown() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Shut Down AiHomeCloud?', style: GoogleFonts.sora()),
        content: Text(
          'This will stop all active services, cancel file transfers, '
          'and safely power off the device. You will need physical access '
          'to turn it back on.',
          style: GoogleFonts.dmSans(color: CubieColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CubieColors.error),
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
      const SnackBar(content: Text('Shutting down AiHomeCloud…')),
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
          style: GoogleFonts.dmSans(color: CubieColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CubieColors.error),
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

// ─── Ad Blocking card ────────────────────────────────────────────────────────

class _AdBlockingCard extends ConsumerStatefulWidget {
  final bool isAdmin;
  const _AdBlockingCard({required this.isAdmin});

  @override
  ConsumerState<_AdBlockingCard> createState() => _AdBlockingCardState();
}

class _AdBlockingCardState extends ConsumerState<_AdBlockingCard> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      final stats = await ref.read(apiServiceProvider).getAdGuardStats();
      if (mounted) setState(() { _stats = stats; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _unavailable = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return CubieCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CubieColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.shield_rounded, color: CubieColors.primary, size: 18),
          ),
          title: Text('Ad Blocking',
              style: GoogleFonts.dmSans(
                  color: CubieColors.textPrimary, fontSize: 14)),
          trailing: const SizedBox(
            width: 20,
            height: 20,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: CubieColors.primary),
          ),
        ),
      );
    }

    if (_unavailable || _stats == null) {
      return CubieCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CubieColors.textMuted.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield_outlined,
                color: CubieColors.textMuted, size: 18),
          ),
          title: Text('Ad Blocking',
              style: GoogleFonts.dmSans(
                  color: CubieColors.textPrimary, fontSize: 14)),
          subtitle: Text('Not configured — run install-adguard.sh on your Cubie',
              style:
                  GoogleFonts.dmSans(color: CubieColors.textMuted, fontSize: 12)),
          trailing: IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: CubieColors.primary, size: 20),
            onPressed: _load,
          ),
        ),
      );
    }

    final blocked = _stats!['blocked_today'] as int? ?? 0;
    final queries = _stats!['dns_queries'] as int? ?? 0;
    final percent = _stats!['blocked_percent'] as double? ?? 0.0;
    final topBlocked =
        (_stats!['top_blocked'] as List<dynamic>? ?? []).cast<String>();

    return CubieCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CubieColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield_rounded,
                    color: CubieColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ad Blocking',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    Text(
                        '$blocked of $queries queries blocked today (${percent.toStringAsFixed(0)}%)',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),

          if (topBlocked.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Top blocked:',
                style: GoogleFonts.dmSans(
                    color: CubieColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: topBlocked.take(5).map((domain) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: CubieColors.cardBorder.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(domain,
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary, fontSize: 11)),
                );
              }).toList(),
            ),
          ],

          // Pause / toggle row
          const SizedBox(height: 12),
          Row(
            children: [
              _PauseButton(minutes: 5),
              const SizedBox(width: 8),
              _PauseButton(minutes: 30),
              const SizedBox(width: 8),
              _PauseButton(minutes: 60),
              if (widget.isAdmin) ...[
                const Spacer(),
                Text('Enable',
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 4),
                Switch(
                  value: _stats!['protection_enabled'] as bool? ?? true,
                  onChanged: (v) => _toggle(v),
                  activeColor: CubieColors.primary,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(bool enabled) async {
    try {
      await ref.read(apiServiceProvider).toggleAdGuard(enabled);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }
}

class _PauseButton extends ConsumerWidget {
  final int minutes;
  const _PauseButton({required this.minutes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = minutes >= 60 ? '1h' : '${minutes}m';
    return OutlinedButton(
      onPressed: () async {
        try {
          await ref.read(apiServiceProvider).pauseAdGuard(minutes);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ad Blocking paused for $label')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(e))));
        }
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: Text('Pause $label'),
    );
  }
}

// ─── Trash card ──────────────────────────────────────────────────────────────

class _TrashCard extends ConsumerWidget {
  const _TrashCard();

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(trashItemsProvider);
    return trashAsync.when(
      data: (items) {
        final totalBytes =
            items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
        final sizeLabel = totalBytes > 0 ? _formatSize(totalBytes) : '0 B';
        return CubieCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: CubieColors.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: CubieColors.error, size: 18),
            ),
            title: Text('Trash',
                style: GoogleFonts.dmSans(
                    color: CubieColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            subtitle: Text('Trash: $sizeLabel',
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 12)),
            trailing: items.isEmpty
                ? null
                : TextButton(
                    onPressed: () =>
                        _confirmEmptyTrash(context, ref, items),
                    style: TextButton.styleFrom(
                        foregroundColor: CubieColors.error),
                    child: Text('Empty',
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
          ),
        );
      },
      loading: () => CubieCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CubieColors.textMuted.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: CubieColors.textMuted, size: 18),
          ),
          title: Text('Trash',
              style: GoogleFonts.dmSans(
                  color: CubieColors.textPrimary, fontSize: 14)),
          trailing: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: CubieColors.primary),
          ),
        ),
      ),
      error: (e, _) => CubieCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CubieColors.textMuted.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: CubieColors.textMuted, size: 18),
          ),
          title: Text('Trash',
              style: GoogleFonts.dmSans(
                  color: CubieColors.textPrimary, fontSize: 14)),
          subtitle: Text(friendlyError(e),
              style: GoogleFonts.dmSans(
                  color: CubieColors.textMuted, fontSize: 12)),
          trailing: IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: CubieColors.primary, size: 20),
            onPressed: () => ref.invalidate(trashItemsProvider),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmEmptyTrash(
    BuildContext context,
    WidgetRef ref,
    List<TrashItem> items,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Empty Trash?', style: GoogleFonts.sora()),
        content: Text(
          'This will permanently delete ${items.length} '
          'item${items.length == 1 ? '' : 's'}. This cannot be undone.',
          style: GoogleFonts.dmSans(color: CubieColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style:
                    GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: CubieColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Empty Trash',
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiServiceProvider);
      for (final item in items) {
        await api.permanentDeleteTrashItem(item.id);
      }
      ref.invalidate(trashItemsProvider);
      messenger
          .showSnackBar(const SnackBar(content: Text('Trash emptied.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Failed: ${friendlyError(e)}')));
    }
  }
}
