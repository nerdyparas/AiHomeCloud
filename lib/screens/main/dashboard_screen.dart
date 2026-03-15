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

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceInfoProvider);
    final statsAsync  = ref.watch(systemStatsStreamProvider);
    final storageAsync = ref.watch(storageDevicesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── 1. SYSTEM STATUS CARD ────────────────────────────────────────
            // Shows overall health only — no hardware metrics in this card.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _HeroStatusCard(
                  deviceAsync: deviceAsync,
                  statsAsync: statsAsync,
                ),
              ),
            ),

              // ── 3. STORAGE SECTION ───────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      Text(
                        'Storage',
                        style: GoogleFonts.sora(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => context.push('/storage-explorer'),
                        child: Row(
                          children: [
                            Text(
                              'Manage',
                              style: GoogleFonts.dmSans(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_ios_rounded,
                                color: AppColors.primary, size: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Storage cards (shows up to 2 external/NAS devices)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: storageAsync.when(
                    data: (devices) {
                      final visible = devices
                          .where((d) => !d.isOsDisk)
                          .toList()
                        ..sort((a, b) {
                          if (a.isNasActive && !b.isNasActive) return -1;
                          if (!a.isNasActive && b.isNasActive) return 1;
                          return 0;
                        });

                      if (visible.isEmpty) return _emptyStorageCard();

                      final show = visible.take(2).toList();
                      final moreCount = visible.length - show.length;

                      return Column(
                        children: [
                          for (int i = 0; i < show.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _StorageDeviceTile(
                                device: show[i],
                                usedGB: show[i].isNasActive
                                    ? statsAsync.value?.storage.usedGB
                                    : null,
                                totalGB: show[i].isNasActive
                                    ? statsAsync.value?.storage.totalGB
                                    : null,
                              )
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
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                    loading: () => _StorageSkeletonCard(),
                    error: (e, _) => AppCard(
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(friendlyError(e),
                                style: const TextStyle(color: AppColors.error)),
                          ),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(storageDevicesProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── 4. SYSTEM COMPACT ROW ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Text(
                    'System',
                    style: GoogleFonts.sora(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              // ── System compact row ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: statsAsync.when(
                    data: (s) =>
                        _SystemCompactCard(stats: s).animate().fadeIn(delay: 200.ms),
                    loading: () => _SystemSkeletonCard(),
                    error: (e, __) => AppCard(
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              friendlyError(e),
                              style: GoogleFonts.dmSans(
                                  color: AppColors.error, fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(systemStatsStreamProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── 5 & 6. NETWORK SECTION ────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Text(
                    'Network',
                    style: GoogleFonts.sora(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: _NetworkStatusCard(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyStorageCard() {
    return GestureDetector(
      onTap: () => context.push('/storage-explorer'),
      child: AppCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.usb_rounded,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No storage drive',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Connect a USB drive to get started',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.textMuted, size: 14),
          ],
        ),
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════════
// STORAGE DEVICE TILE (Google Files style)
// ═══════════════════════════════════════════════════════════════════════════════

class _StorageDeviceTile extends StatelessWidget {
  final StorageDevice device;
  final double? usedGB;
  final double? totalGB;

  const _StorageDeviceTile({
    required this.device,
    this.usedGB,
    this.totalGB,
  });

  @override
  Widget build(BuildContext context) {
    final usedFraction = (usedGB != null && totalGB != null && totalGB! > 0)
        ? (usedGB! / totalGB!).clamp(0.0, 1.0)
        : null;

    final freeGB = (usedGB != null && totalGB != null)
        ? (totalGB! - usedGB!).clamp(0.0, totalGB!)
        : null;

    // Bar colour shifts to amber above 80%, red above 95%
    final barColor = usedFraction == null
        ? AppColors.primary
        : usedFraction >= 0.95
            ? AppColors.error
            : usedFraction >= 0.80
                ? const Color(0xFFE8A84C)
                : AppColors.primary;

    return AppCard(
      glowing: device.isNasActive,
      onTap: () => context.push('/storage-explorer'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: icon + name + status badge + chevron ────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(device.icon, color: _color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.label ?? device.model ?? device.name,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.typeLabel,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
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
                  color: AppColors.textMuted, size: 18),
            ],
          ),

          // ── Storage bar (only when stats available) ───────────────────────
          if (usedFraction != null) ...[
            const SizedBox(height: 14),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: usedFraction,
                minHeight: 6,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),

            const SizedBox(height: 6),

            // Used / Free text
            Row(
              children: [
                Text(
                  '${usedGB!.toStringAsFixed(1)} GB used',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${freeGB!.toStringAsFixed(1)} GB free',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ] else ...[
            // No stats yet — show total size as before
            const SizedBox(height: 4),
            Text(
              device.sizeDisplay,
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Color get _color => switch (device.transport) {
        'usb' => AppColors.primary,
        'nvme' => AppColors.secondary,
        _ => AppColors.textSecondary,
      };

  String get _statusText {
    if (device.isNasActive) return 'Active';
    if (device.mounted) return 'Activated';
    if (device.fstype == null) return 'Not ready yet';
    return 'Ready';
  }

  Color get _statusColor {
    if (device.isNasActive) return AppColors.success;
    if (device.mounted) return AppColors.secondary;
    if (device.fstype == null) return AppColors.primary;
    return AppColors.textSecondary;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NETWORK STATUS CARD
//
// Rows: WiFi | Ethernet | Bluetooth
// Below rows: upload / download speed indicators (live from WebSocket)
// ═══════════════════════════════════════════════════════════════════════════════

class _NetworkStatusCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netAsync = ref.watch(networkStatusProvider);

    return netAsync.when(
      data: (n) => AppCard(
        child: Column(
          children: [
            // WiFi row
            _netStatusRow(
              icon: Icons.wifi_rounded,
              label: 'WiFi',
              status: n.wifiConnected
                  ? (n.wifiSsid ?? 'Connected')
                  : n.wifiEnabled
                      ? 'Not connected'
                      : 'Off',
              subtitle: n.wifiConnected ? n.wifiIp : null,
              connected: n.wifiConnected,
              enabled: n.wifiEnabled,
            ),
            const Divider(color: AppColors.cardBorder, height: 1),

            // Ethernet row
            _netStatusRow(
              icon: Icons.lan_rounded,
              label: 'Ethernet',
              status: n.lanConnected ? 'Connected' : 'Disconnected',
              subtitle: n.lanConnected
                  ? [n.lanIp, n.lanSpeed].whereType<String>().join(' • ')
                  : null,
              connected: n.lanConnected,
              enabled: true,
            ),
            const Divider(color: AppColors.cardBorder, height: 1),

            // Bluetooth row
            _netStatusRow(
              icon: Icons.bluetooth_rounded,
              label: 'Bluetooth',
              status: n.bluetoothEnabled ? 'On' : 'Off',
              connected: n.bluetoothEnabled,
              enabled: n.bluetoothEnabled,
            ),
            const Divider(color: AppColors.cardBorder, height: 1),

            // Real-time upload / download speeds from WebSocket stream
            Consumer(
              builder: (context, ref, _) {
                final statsAsync = ref.watch(systemStatsStreamProvider);
                return statsAsync.when(
                  data: (s) => Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _speedCol(
                            Icons.arrow_upward_rounded,
                            'Upload',
                            '${s.networkUpMbps.toStringAsFixed(1)} Mbps',
                            AppColors.success,
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 36,
                            color: AppColors.cardBorder),
                        Expanded(
                          child: _speedCol(
                            Icons.arrow_downward_rounded,
                            'Download',
                            '${s.networkDownMbps.toStringAsFixed(1)} Mbps',
                            AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  loading: () => const SizedBox(height: 44),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),

          ],
        ),
      ).animate().fadeIn(delay: 550.ms),
      loading: () => _NetworkSkeletonCard(),
      error: (e, _) => AppCard(
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Unable to load network status: ${friendlyError(e)}',
                style: GoogleFonts.dmSans(
                    color: AppColors.error, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speedCol(IconData icon, String label, String value, Color c) {
    return Column(
      children: [
        Icon(icon, color: c, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.sora(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.dmSans(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _netStatusRow({
    required IconData icon,
    required String label,
    required String status,
    String? subtitle,
    required bool connected,
    required bool enabled,
  }) {
    final dotColor = connected
        ? AppColors.success
        : enabled
            ? AppColors.textSecondary
            : AppColors.textMuted;
    final iconColor = connected
        ? AppColors.success
        : enabled
            ? AppColors.textSecondary
            : AppColors.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label bold + status inline, e.g. "Ethernet  Connected"
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: label,
                        style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: '  $status',
                        style: GoogleFonts.dmSans(
                          color: connected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Status indicator dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HERO STATUS CARD
//
// Shows overall system health — green when all metrics are nominal, red when
// any threshold is exceeded.  Hardware metrics (CPU %, temp, uptime) are
// intentionally absent here; they live in the System Metrics card below.
// ═══════════════════════════════════════════════════════════════════════════════

class _HeroStatusCard extends StatelessWidget {
  final AsyncValue<AhcDevice> deviceAsync;
  final AsyncValue<SystemStats> statsAsync;

  const _HeroStatusCard({
    required this.deviceAsync,
    required this.statsAsync,
  });

  @override
  Widget build(BuildContext context) {
    final stats  = statsAsync.valueOrNull;
    final device = deviceAsync.valueOrNull;

    final cpuHigh  = (stats?.cpuPercent    ?? 0) >= 80;
    final ramHigh  = (stats?.ramPercent    ?? 0) >= 85;
    final tempHigh = (stats?.tempCelsius   ?? 0) >= 65;
    final allGood  = !cpuHigh && !ramHigh && !tempHigh;

    final statusColor = allGood ? AppColors.success : AppColors.error;
    final statusText  = allGood
        ? 'Everything running smoothly'
        : [
            if (cpuHigh)  'CPU high',
            if (ramHigh)  'RAM high',
            if (tempHigh) 'Temperature high',
          ].join('  ·  ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allGood
              ? AppColors.success.withValues(alpha: 0.35)
              : AppColors.error.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.06),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          // Glowing status dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Device / app name
                Text(
                  device?.name ?? 'AiHomeCloud',
                  style: GoogleFonts.sora(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                // Health summary text
                Text(
                  statusText,
                  style: GoogleFonts.dmSans(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),

              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SYSTEM COMPACT CARD — V1 DESIGN (LOCKED)
//
// DO NOT MODIFY this widget without explicit user confirmation.
// Small circular progress rings (44px) + chip icon + single labels.
// ═══════════════════════════════════════════════════════════════════════════════

class _SystemCompactCard extends StatelessWidget {
  final SystemStats stats;
  const _SystemCompactCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cpu = stats.cpuPercent.clamp(0, 100).toDouble();
    final ram = stats.ramPercent.clamp(0, 100).toDouble();
    final temp = stats.tempCelsius;
    final uptimeHours = stats.uptime.inHours;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.card,
            AppColors.surface.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.memory_rounded,
              color: AppColors.primary,
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _SystemMetricIndicator(
                    value: '${cpu.toStringAsFixed(0)}%',
                    label: 'CPU',
                    progress: cpu / 100,
                    color: AppColors.success,
                  ),
                ),
                const _SystemMetricDivider(),
                Expanded(
                  child: _SystemMetricIndicator(
                    value: '${ram.toStringAsFixed(0)}%',
                    label: 'RAM',
                    progress: ram / 100,
                    color: AppColors.secondary,
                  ),
                ),
                const _SystemMetricDivider(),
                Expanded(
                  child: _SystemMetricIndicator(
                    value: '${temp.toStringAsFixed(0)}°',
                    label: 'TEMP',
                    progress: (temp / 100).clamp(0.0, 1.0),
                    color: AppColors.primary,
                  ),
                ),
                const _SystemMetricDivider(),
                Expanded(
                  child: _SystemMetricIndicator(
                    value: '${uptimeHours}h',
                    label: 'UPTIME',
                    progress: (uptimeHours / 24).clamp(0.0, 1.0),
                    color: AppColors.textSecondary,
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

class _SystemMetricIndicator extends StatelessWidget {
  final String value;
  final String label;
  final double progress;
  final Color color;

  const _SystemMetricIndicator({
    required this.value,
    required this.label,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                strokeWidth: 3.5,
                backgroundColor: AppColors.cardBorder.withValues(alpha: 0.7),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
              Text(
                value,
                style: GoogleFonts.dmSans(
                  color: AppColors.textPrimary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: GoogleFonts.dmSans(
            color: AppColors.textSecondary.withValues(alpha: 0.85),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _SystemMetricDivider extends StatelessWidget {
  const _SystemMetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.cardBorder.withValues(alpha: 0.55),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SKELETON / SHIMMER PLACEHOLDERS
// ═══════════════════════════════════════════════════════════════════════════════

class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;

  const _SkeletonBar({
    required this.width,
    this.height = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _StorageSkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          // Icon placeholder
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SkeletonBar(width: 100, height: 14),
                const SizedBox(height: 8),
                const _SkeletonBar(width: 60, height: 10),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 6,
                    color: AppColors.surface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          duration: 1200.ms,
          color: AppColors.cardBorder.withValues(alpha: 0.3),
        );
  }
}

class _SystemSkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.card,
            AppColors.surface.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Row(
        children: [
          // Chip icon placeholder
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 14),
          // 4 metric circle placeholders
          for (int i = 0; i < 4; i++) ...[
            if (i > 0) const _SystemMetricDivider(),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.cardBorder.withValues(alpha: 0.7),
                        width: 3.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  const _SkeletonBar(width: 28, height: 10),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          duration: 1200.ms,
          color: AppColors.cardBorder.withValues(alpha: 0.3),
        );
  }
}

class _NetworkSkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0)
              const Divider(color: AppColors.cardBorder, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const _SkeletonBar(width: 70, height: 13),
                  const Spacer(),
                  const _SkeletonBar(width: 90, height: 11),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          duration: 1200.ms,
          color: AppColors.cardBorder.withValues(alpha: 0.3),
        );
  }
}
