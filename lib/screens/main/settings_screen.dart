import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/cubie_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _checkingUpdate = false;
  Map<String, dynamic>? _updateInfo;

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceInfoProvider);
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      backgroundColor: CubieColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 16),
            Text('Settings',
                    style: GoogleFonts.sora(
                        color: CubieColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700))
                .animate()
                .fadeIn(duration: 400.ms),

            // ── Device info ─────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Device'),
            const SizedBox(height: 12),
            deviceAsync.when(
              data: (d) => CubieCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _row('Name', d.name,
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_rounded,
                              size: 18, color: CubieColors.textMuted),
                          onPressed: () => _editName(d.name),
                        )),
                    _divider(),
                    _row('Serial', d.serial),
                    _divider(),
                    _row('IP Address', d.ip),
                    _divider(),
                    _row('Firmware', d.firmwareVersion),
                  ],
                ),
              ).animate().fadeIn(delay: 100.ms),
              loading: () => const CubieCard(
                  child: SizedBox(
                      height: 160,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: CubieColors.primary)))),
              error: (e, _) => CubieCard(child: Text('Error: $e')),
            ),

            // ── OTA update ──────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Firmware Update'),
            const SizedBox(height: 12),
            CubieCard(
              child: _updateInfo != null ? _updateAvailable() : _checkButton(),
            ).animate().fadeIn(delay: 200.ms),

            // ── Services ────────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Services'),
            const SizedBox(height: 12),
            servicesAsync.when(
              data: (services) => CubieCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (int i = 0; i < services.length; i++) ...[
                      _ServiceToggle(
                        service: services[i],
                        onToggle: (v) async {
                          await ref
                              .read(apiServiceProvider)
                              .toggleService(services[i].id, v);
                          ref.invalidate(servicesProvider);
                        },
                      ),
                      if (i < services.length - 1) _divider(),
                    ],
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms),
              loading: () => const CubieCard(
                  child: SizedBox(
                      height: 200,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: CubieColors.primary)))),
              error: (e, _) => CubieCard(child: Text('Error: $e')),
            ),

            // ── Account ─────────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Account'),
            const SizedBox(height: 12),
            CubieCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_rounded,
                        color: CubieColors.textSecondary, size: 20),
                    title: Text('Change PIN',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textPrimary, fontSize: 14)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: CubieColors.textMuted, size: 20),
                    onTap: _changePin,
                  ),
                  _divider(),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded,
                        color: CubieColors.error, size: 20),
                    title: Text('Logout',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.error, fontSize: 14)),
                    onTap: _confirmLogout,
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms),

            // ── Footer ──────────────────────────────────────────────────────
            const SizedBox(height: 32),
            Center(
              child: Text('CubieCloud v1.0.0',
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textMuted, fontSize: 12)),
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
          color: CubieColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5));

  Widget _row(String label, String value, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 13)),
            const Spacer(),
            Text(value,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _divider() => const Divider(
      height: 1, indent: 16, endIndent: 16, color: CubieColors.cardBorder);

  // ── OTA ────────────────────────────────────────────────────────────────────

  Widget _checkButton() => SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _checkingUpdate
              ? null
              : () async {
                  setState(() => _checkingUpdate = true);
                  final info = await ref
                      .read(apiServiceProvider)
                      .checkFirmwareUpdate();
                  setState(() {
                    _updateInfo = info;
                    _checkingUpdate = false;
                  });
                },
          icon: _checkingUpdate
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: CubieColors.primary))
              : const Icon(Icons.system_update_rounded, size: 18),
          label: Text(
            _checkingUpdate ? 'Checking…' : 'Check for Updates',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
          ),
        ),
      );

  Widget _updateAvailable() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: CubieColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('v${_updateInfo!['latest_version']} available',
                    style: GoogleFonts.dmSans(
                        color: CubieColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              Text('${_updateInfo!['size_mb']} MB',
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text(_updateInfo!['changelog'] as String,
              style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary,
                  fontSize: 13,
                  height: 1.5)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await ref.read(apiServiceProvider).triggerOtaUpdate();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Update started. Device will reboot automatically.')));
                }
              },
              child: Text('Install Update',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      );

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _editName(String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Device Name', style: GoogleFonts.sora()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Enter device name'),
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
                  .read(apiServiceProvider)
                  .updateDeviceName(ctrl.text);
              ref.invalidate(deviceInfoProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Save',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
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
              style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Current PIN',
                prefixIcon: Icon(Icons.lock_open_rounded,
                    color: CubieColors.textMuted),
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
                style:
                    GoogleFonts.dmSans(color: CubieColors.textSecondary)),
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
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
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

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Logout?', style: GoogleFonts.sora()),
        content: Text(
          'You will need to pair your device again to use the app.',
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
            style:
                ElevatedButton.styleFrom(backgroundColor: CubieColors.error),
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

// ─── Service toggle row ─────────────────────────────────────────────────────

class _ServiceToggle extends StatefulWidget {
  final ServiceInfo service;
  final ValueChanged<bool> onToggle;
  const _ServiceToggle({required this.service, required this.onToggle});

  @override
  State<_ServiceToggle> createState() => _ServiceToggleState();
}

class _ServiceToggleState extends State<_ServiceToggle> {
  late bool _on;

  @override
  void initState() {
    super.initState();
    _on = widget.service.isEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (_on ? CubieColors.primary : CubieColors.textMuted)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.service.icon,
                color: _on ? CubieColors.primary : CubieColors.textMuted,
                size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.service.name,
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                Text(widget.service.description,
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: _on,
            onChanged: (v) {
              setState(() => _on = v);
              widget.onToggle(v);
            },
          ),
        ],
      ),
    );
  }
}
