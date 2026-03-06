import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../core/error_utils.dart';
import '../../../providers.dart';
import '../../../widgets/cubie_card.dart';

class NetworkSettingsScreen extends ConsumerWidget {
  const NetworkSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networkAsync = ref.watch(networkStatusProvider);

    return Scaffold(
      backgroundColor: CubieColors.background,
      appBar: AppBar(
        backgroundColor: CubieColors.background,
        title: Text('Network',
            style: GoogleFonts.sora(
                color: CubieColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_rounded, color: CubieColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: networkAsync.when(
        data: (n) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 12),
            CubieCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
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
                    onTap: n.wifiEnabled
                        ? () => context.push('/wifi-settings')
                        : null,
                  ),
                  _divider(),
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
                  _LanStatusRow(
                    connected: n.lanConnected,
                    ip: n.lanIp,
                    speed: n.lanSpeed,
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 24),
          ],
        ),
        loading: () => const Center(
            child:
                CircularProgressIndicator(color: CubieColors.primary)),
        error: (e, _) => Center(
            child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(friendlyError(e),
              style: const TextStyle(color: CubieColors.error)),
        )),
      ),
    );
  }

  static Widget _divider() => const Divider(
      height: 1, indent: 16, endIndent: 16, color: CubieColors.cardBorder);
}

// ─── Network toggle row ─────────────────────────────────────────────────────

class _NetworkToggleRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;
  final VoidCallback? onTap;

  const _NetworkToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.onTap,
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
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(widget.subtitle,
                            style: GoogleFonts.dmSans(
                                color: CubieColors.textSecondary,
                                fontSize: 12)),
                      ),
                      if (widget.onTap != null)
                        const Icon(Icons.chevron_right_rounded,
                            color: CubieColors.textMuted, size: 18),
                    ],
                  ),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(friendlyError(e))));
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ─── LAN status row ─────────────────────────────────────────────────────────

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
