import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/cubie_card.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/storage_donut_chart.dart';

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
    final userName = ref.watch(currentUserNameProvider) ?? 'User';

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
                    // Avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: CubieColors.primary.withValues(alpha: 0.15),
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

            // ── Storage card ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: statsAsync.when(
                  data: (s) => CubieCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.storage_rounded,
                                color: CubieColors.primary, size: 20),
                            const SizedBox(width: 8),
                            Text('Storage',
                                style: GoogleFonts.sora(
                                    color: CubieColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            StorageDonutChart(
                              usedGB: s.storage.usedGB,
                              totalGB: s.storage.totalGB,
                              size: 130,
                              strokeWidth: 12,
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _legendRow(
                                      'Used',
                                      '${s.storage.usedGB.toStringAsFixed(1)} GB',
                                      CubieColors.primary),
                                  const SizedBox(height: 12),
                                  _legendRow(
                                      'Free',
                                      '${s.storage.freeGB.toStringAsFixed(1)} GB',
                                      const Color(0xFF2A3347)),
                                  const SizedBox(height: 12),
                                  _legendRow(
                                      'Total',
                                      '${s.storage.totalGB.toStringAsFixed(0)} GB',
                                      CubieColors.textSecondary),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 500.ms, delay: 100.ms),
                  loading: () => const CubieCard(
                    child: SizedBox(
                        height: 170,
                        child: Center(
                            child: CircularProgressIndicator(
                                color: CubieColors.primary))),
                  ),
                  error: (e, _) => CubieCard(
                    child: SizedBox(
                        height: 170,
                        child: Center(
                            child: Text('Error: $e',
                                style: const TextStyle(
                                    color: CubieColors.error)))),
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

            // ── Stat tiles grid ─────────────────────────────────────────────
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
                error: (_, __) =>
                    const SliverToBoxAdapter(child: SizedBox.shrink()),
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

            // ── Network speed card ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                            width: 1, height: 40, color: CubieColors.cardBorder),
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
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _legendRow(String label, String value, Color dot) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: dot, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: GoogleFonts.dmSans(
                color: CubieColors.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: GoogleFonts.dmSans(
                color: CubieColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
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
