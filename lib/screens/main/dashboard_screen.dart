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
import '../../widgets/stat_tile.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _uptime(Duration d) {
    final days = d.inDays;
    final hrs = d.inHours.remainder(24);
    final mins = d.inMinutes.remainder(60);
    if (days > 0) return '${days}d ${hrs}h';
    if (hrs > 0) return '${hrs}h ${mins}m';
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceAsync = ref.watch(deviceInfoProvider);
    final statsAsync = ref.watch(systemStatsStreamProvider);
    final storageAsync = ref.watch(storageDevicesProvider);
    final session = ref.watch(authSessionProvider);
    final userName = (session?.username.isNotEmpty ?? false)
      ? session!.username
      : 'User';

    return Scaffold(
      backgroundColor: CubieColors.background,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hey, $userName 👋',
                            style: GoogleFonts.sora(
                              color: CubieColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          deviceAsync.when(
                            data: (d) => Text(d.name,
                                style: GoogleFonts.dmSans(
                                    color: CubieColors.textSecondary,
                                    fontSize: 14)),
                            loading: () => Text('Loading…',
                                style: GoogleFonts.dmSans(
                                    color: CubieColors.textMuted,
                                    fontSize: 14)),
                            error: (_, __) => Text('Device error',
                                style: GoogleFonts.dmSans(
                                    color: CubieColors.error, fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: CubieColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          userName.isNotEmpty
                              ? userName[0].toUpperCase()
                              : 'U',
                          style: GoogleFonts.sora(
                            color: CubieColors.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 400.ms),
              ),
            ),

            // ── SD-only warning banner (2C.7) ───────────────────────────────
            SliverToBoxAdapter(
              child: storageAsync.when(
                data: (devices) {
                  final hasActive =
                      devices.any((d) => d.isNasActive && !d.isOsDisk);
                  if (hasActive) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CubieColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: CubieColors.primary.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: CubieColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No external storage active — files are on the SD card. '
                              'Connect a USB drive or NVMe SSD for better performance.',
                              style: GoogleFonts.dmSans(
                                  color: CubieColors.primary,
                                  fontSize: 12,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms).shimmer(
                          duration: 1500.ms,
                          color: CubieColors.primary.withOpacity(0.1),
                        ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // ── Storage section title ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Text('Storage',
                        style: GoogleFonts.sora(
                            color: CubieColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.push('/storage-explorer'),
                      child: Row(
                        children: [
                          Text('Manage',
                              style: GoogleFonts.dmSans(
                                  color: CubieColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: CubieColors.primary, size: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Storage device cards (Google Files style, max 2) ────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: storageAsync.when(
                  data: (devices) {
                    // Show external devices first, then NAS active, up to 2
                    final visible = devices
                        .where((d) => !d.isOsDisk)
                        .toList()
                      ..sort((a, b) {
                        if (a.isNasActive && !b.isNasActive) return -1;
                        if (!a.isNasActive && b.isNasActive) return 1;
                        return 0;
                      });

                    if (visible.isEmpty) {
                      return _emptyStorageCard(context);
                    }

                    final show = visible.take(2).toList();
                    final moreCount = visible.length - show.length;

                    return Column(
                      children: [
                        for (int i = 0; i < show.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _StorageDeviceTile(device: show[i])
                                .animate()
                                .fadeIn(delay: (100 * i).ms)
                                .slideY(begin: 0.05, end: 0),
                          ),
                        if (moreCount > 0)
                          GestureDetector(
                            onTap: () => context.push('/storage-explorer'),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+$moreCount more device${moreCount > 1 ? 's' : ''}',
                                style: GoogleFonts.dmSans(
                                    color: CubieColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const SizedBox(
                    height: 80,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: CubieColors.primary)),
                  ),
                  error: (e, _) => CubieCard(
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: CubieColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(friendlyError(e),
                              style: const TextStyle(color: CubieColors.error)),
                        ),
                        TextButton(
                          onPressed: () => ref.invalidate(storageDevicesProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Section title: System ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Text('System',
                    style: GoogleFonts.sora(
                        color: CubieColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),

            // ── Compact stat tiles (2x2 grid) ──────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: statsAsync.when(
                data: (s) => SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.45,
                  children: [
                    StatTile(
                      label: 'CPU',
                      value: s.cpuPercent.toStringAsFixed(0),
                      unit: '%',
                      icon: Icons.memory_rounded,
                      accentColor: CubieColors.primary,
                    ).animate().fadeIn(delay: 200.ms),
                    StatTile(
                      label: 'Memory',
                      value: s.ramPercent.toStringAsFixed(0),
                      unit: '%',
                      icon: Icons.developer_board_rounded,
                      accentColor: CubieColors.secondary,
                    ).animate().fadeIn(delay: 300.ms),
                    StatTile(
                      label: 'Temperature',
                      value: s.tempCelsius.toStringAsFixed(0),
                      unit: '°C',
                      icon: Icons.thermostat_rounded,
                      accentColor: s.tempCelsius > 60
                          ? CubieColors.error
                          : CubieColors.success,
                    ).animate().fadeIn(delay: 400.ms),
                    StatTile(
                      label: 'Uptime',
                      value: _uptime(s.uptime),
                      icon: Icons.schedule_rounded,
                      accentColor: CubieColors.textSecondary,
                    ).animate().fadeIn(delay: 500.ms),
                  ],
                ),
                loading: () => const SliverToBoxAdapter(
                  child: SizedBox(
                      height: 200,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: CubieColors.primary))),
                ),
                error: (e, __) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: CubieCard(
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: CubieColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Unable to load system stats: ${friendlyError(e)}',
                              style: GoogleFonts.dmSans(
                                  color: CubieColors.error, fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref.invalidate(systemStatsStreamProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Section title: Network ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Text('Network',
                    style: GoogleFonts.sora(
                        color: CubieColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),

            // ── Network connectivity status ─────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _NetworkStatusCard(),
              ),
            ),

            // ── Network speed card ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: statsAsync.when(
                  data: (s) => CubieCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: _netCol(
                              Icons.arrow_upward_rounded,
                              'Upload',
                              '${s.networkUpMbps.toStringAsFixed(1)} Mbps',
                              CubieColors.success),
                        ),
                        Container(
                            width: 1,
                            height: 40,
                            color: CubieColors.cardBorder),
                        Expanded(
                          child: _netCol(
                              Icons.arrow_downward_rounded,
                              'Download',
                              '${s.networkDownMbps.toStringAsFixed(1)} Mbps',
                              CubieColors.secondary),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 600.ms),
                  loading: () => const SizedBox(height: 80),
                  error: (e, __) => CubieCard(
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: CubieColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Unable to load network speed: ${friendlyError(e)}',
                            style: GoogleFonts.dmSans(
                                color: CubieColors.error, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref.invalidate(systemStatsStreamProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _emptyStorageCard(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/storage-explorer'),
      child: CubieCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CubieColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.usb_rounded,
                  color: CubieColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No external storage',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Tap to manage storage devices',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: CubieColors.textMuted, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _netCol(IconData icon, String label, String value, Color c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.sora(
                  color: CubieColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          Text(label,
              style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STORAGE DEVICE TILE (Google Files style)
// ═══════════════════════════════════════════════════════════════════════════════

class _StorageDeviceTile extends StatelessWidget {
  final StorageDevice device;
  const _StorageDeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    return CubieCard(
      glowing: device.isNasActive,
      onTap: () => context.push('/storage-explorer'),
      child: Row(
        children: [
          // Device icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(device.icon, color: _color, size: 22),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.label ?? device.model ?? device.name,
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${device.typeLabel}  •  ${device.sizeDisplay}',
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_statusText,
                style: GoogleFonts.dmSans(
                    color: _statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),

          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded,
              color: CubieColors.textMuted, size: 18),
        ],
      ),
    );
  }

  Color get _color => switch (device.transport) {
        'usb' => CubieColors.primary,
        'nvme' => CubieColors.secondary,
        _ => CubieColors.textSecondary,
      };

  String get _statusText {
    if (device.isNasActive) return 'Active';
    if (device.mounted) return 'Activated';
    if (device.fstype == null) return 'Unformatted';
    return 'Ready';
  }

  Color get _statusColor {
    if (device.isNasActive) return CubieColors.success;
    if (device.mounted) return CubieColors.secondary;
    if (device.fstype == null) return CubieColors.primary;
    return CubieColors.textSecondary;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NETWORK STATUS CARD — WiFi, LAN, Bluetooth connectivity
// ═══════════════════════════════════════════════════════════════════════════════

class _NetworkStatusCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netAsync = ref.watch(networkStatusProvider);
    return netAsync.when(
      data: (n) => CubieCard(
        child: Column(
          children: [
            _netStatusRow(
              icon: Icons.wifi_rounded,
              label: n.wifiConnected
                  ? 'WiFi: ${n.wifiSsid ?? "Connected"}'
                  : n.wifiEnabled
                      ? 'WiFi: Not connected'
                      : 'WiFi: Off',
              subtitle: n.wifiIp,
              connected: n.wifiConnected,
              enabled: n.wifiEnabled,
            ),
            Divider(color: CubieColors.cardBorder, height: 1),
            _netStatusRow(
              icon: Icons.lan_rounded,
              label: n.lanConnected ? 'Ethernet: Connected' : 'Ethernet: Disconnected',
              subtitle: n.lanConnected
                  ? [n.lanIp, n.lanSpeed].whereType<String>().join(' • ')
                  : null,
              connected: n.lanConnected,
              enabled: true,
            ),
            Divider(color: CubieColors.cardBorder, height: 1),
            _netStatusRow(
              icon: Icons.bluetooth_rounded,
              label: n.bluetoothEnabled ? 'Bluetooth: On' : 'Bluetooth: Off',
              connected: n.bluetoothEnabled,
              enabled: n.bluetoothEnabled,
            ),
          ],
        ),
      ).animate().fadeIn(delay: 550.ms),
      loading: () => const SizedBox(
        height: 60,
        child: Center(
            child: CircularProgressIndicator(color: CubieColors.primary)),
      ),
      error: (e, _) => CubieCard(
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: CubieColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Unable to load network status: ${friendlyError(e)}',
                style: GoogleFonts.dmSans(
                    color: CubieColors.error, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _netStatusRow({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool connected,
    required bool enabled,
  }) {
    final color = connected
        ? CubieColors.success
        : enabled
            ? CubieColors.textSecondary
            : CubieColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.dmSans(
                        color: CubieColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(subtitle,
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
