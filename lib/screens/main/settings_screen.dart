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
    final networkAsync = ref.watch(networkStatusProvider);
    final fingerprint = ref.watch(certFingerprintProvider);

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

            // ── Network ─────────────────────────────────────────────────────
            const SizedBox(height: 24),
            _sectionLabel('Network'),
            const SizedBox(height: 12),
            networkAsync.when(
              data: (n) => CubieCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // WiFi toggle
                    _NetworkToggleRow(
                      icon: Icons.wifi_rounded,
                      label: 'Wi-Fi',
                      subtitle: n.wifiConnected
                          ? n.wifiSsid ?? 'Connected'
                          : (n.wifiEnabled ? 'Not connected' : 'Off'),
                      value: n.wifiEnabled,
                      onChanged: (v) async {
                        await ref.read(apiServiceProvider).toggleWifi(v);
                        ref.invalidate(networkStatusProvider);
                      },
                    ),
                    _divider(),
                    // Hotspot toggle
                    _NetworkToggleRow(
                      icon: Icons.wifi_tethering_rounded,
                      label: 'Hotspot',
                      subtitle:
                          n.hotspotEnabled ? n.hotspotSsid ?? 'Active' : 'Off',
                      value: n.hotspotEnabled,
                      onChanged: (v) async {
                        await ref.read(apiServiceProvider).toggleHotspot(v);
                        ref.invalidate(networkStatusProvider);
                      },
                    ),
                    _divider(),
                    // Bluetooth toggle
                    _NetworkToggleRow(
                      icon: Icons.bluetooth_rounded,
                      label: 'Bluetooth',
                      subtitle: n.bluetoothEnabled ? 'On' : 'Off',
                      value: n.bluetoothEnabled,
                      onChanged: (v) async {
                        await ref.read(apiServiceProvider).toggleBluetooth(v);
                        ref.invalidate(networkStatusProvider);
                      },
                    ),
                    _divider(),
                    // LAN status (read-only)
                    _LanStatusRow(
                      connected: n.lanConnected,
                      ip: n.lanIp,
                      speed: n.lanSpeed,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 50.ms),
              loading: () => const CubieCard(
                  child: SizedBox(
                      height: 200,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: CubieColors.primary)))),
              error: (e, _) => CubieCard(
                  child: Text(friendlyError(e),
                      style: const TextStyle(color: CubieColors.error))),
            ),

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
              error: (e, _) => CubieCard(child: Text(friendlyError(e))),
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
              error: (e, _) => CubieCard(child: Text(friendlyError(e))),
            ),

            const SizedBox(height: 24),
            _sectionLabel('Security'),
            const SizedBox(height: 12),
            CubieCard(
              child: ListTile(
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
            ).animate().fadeIn(delay: 350.ms),

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
                  final info =
                      await ref.read(apiServiceProvider).checkFirmwareUpdate();
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
                  color: CubieColors.success.withOpacity(0.15),
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
                  color: CubieColors.textSecondary, fontSize: 13, height: 1.5)),
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
                  color: CubieColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text('Server fingerprint:',
                style: GoogleFonts.dmSans(fontSize: 12)),
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
                style: GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(apiServiceProvider).updateDeviceName(ctrl.text);
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
                  .withOpacity(0.12),
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

// ─── Network toggle row ─────────────────────────────────────────────────────

class _NetworkToggleRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  const _NetworkToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_NetworkToggleRow> createState() => _NetworkToggleRowState();
}

class _NetworkToggleRowState extends State<_NetworkToggleRow> {
  late bool _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _on = widget.value;
  }

  @override
  void didUpdateWidget(covariant _NetworkToggleRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _on = widget.value;
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
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon,
                color: _on ? CubieColors.primary : CubieColors.textMuted,
                size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label,
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                Text(widget.subtitle,
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: CubieColors.primary),
            )
          else
            Switch(
              value: _on,
              onChanged: (v) async {
                setState(() {
                  _on = v;
                  _busy = true;
                });
                try {
                  await widget.onChanged(v);
                } catch (e) {
                  if (mounted) {
                    setState(() => _on = !v);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
            ),
        ],
      ),
    );
  }
}

// ─── LAN status row (read-only with safety note) ────────────────────────────

class _LanStatusRow extends StatelessWidget {
  final bool connected;
  final String? ip;
  final String? speed;

  const _LanStatusRow({
    required this.connected,
    this.ip,
    this.speed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      (connected ? CubieColors.success : CubieColors.textMuted)
                          .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.settings_ethernet_rounded,
                    color:
                        connected ? CubieColors.success : CubieColors.textMuted,
                    size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ethernet',
                        style: GoogleFonts.dmSans(
                            color: CubieColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    Text(
                      connected
                          ? '${ip ?? "No IP"}'
                              '${speed != null ? "  •  $speed" : ""}'
                          : 'Cable not connected',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      (connected ? CubieColors.success : CubieColors.textMuted)
                          .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  connected ? 'Connected' : 'Disconnected',
                  style: GoogleFonts.dmSans(
                      color: connected
                          ? CubieColors.success
                          : CubieColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          // Safety note (2E.5)
          if (connected)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: CubieColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Changing the LAN IP may make this device unreachable.',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textMuted,
                          fontSize: 11,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
