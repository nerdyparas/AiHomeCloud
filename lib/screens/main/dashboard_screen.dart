import 'dart:async';

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
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _activeQuery = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceInfoProvider);
    final statsAsync = ref.watch(systemStatsStreamProvider);
    final storageAsync = ref.watch(storageDevicesProvider);
    final session = ref.watch(authSessionProvider);
    final userName = (session?.username.isNotEmpty ?? false)
      ? session!.username
      : 'User';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Top bar: avatar only ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.go('/user-picker',
                          extra: session?.host ?? ''),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                            style: GoogleFonts.sora(
                              color: AppColors.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 400.ms),
              ),
            ),

            // ── Hero status card ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _HeroStatusCard(
                  deviceAsync: deviceAsync,
                  statsAsync: statsAsync,
                ),
              ),
            ),

            // ── Search bar ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _buildSearchBar(),
              ),
            ),

            // ── Content: search results OR normal dashboard ───────────────────
            if (_activeQuery.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _DocSearchResults(query: _activeQuery),
              ),
            ] else ...[

            // ── Ad Blocking badge (hidden if AdGuard not enabled) ──────────
            const _AdBlockingBadge(),

            // ── Storage section title ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Text('Storage',
                        style: GoogleFonts.sora(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.push('/storage-explorer'),
                      child: Row(
                        children: [
                          Text('Manage',
                              style: GoogleFonts.dmSans(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
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
                      return _emptyStorageCard();
                    }

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
                            color: AppColors.primary)),
                  ),
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
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),

            // ── System compact row ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: statsAsync.when(
                  data: (s) => _SystemCompactCard(stats: s).animate().fadeIn(delay: 200.ms),
                  loading: () => const SizedBox(height: 52),
                  error: (e, __) => AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(friendlyError(e),
                              style: GoogleFonts.dmSans(
                                  color: AppColors.error, fontSize: 13)),
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

            // ── Section title: Network ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Text('Network',
                    style: GoogleFonts.sora(
                        color: AppColors.textPrimary,
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

            ], // else: normal dashboard content
          ],
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearchChanged,
      style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search documents…',
        hintStyle: GoogleFonts.dmSans(
            color: AppColors.textMuted, fontSize: 14),
        prefixIcon: const Icon(
            Icons.search_rounded, color: AppColors.textMuted, size: 20),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded,
                    color: AppColors.textMuted, size: 20),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearchChanged('');
                },
              )
            : null,
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
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
// NETWORK STATUS CARD — WiFi, LAN, Bluetooth connectivity
// ═══════════════════════════════════════════════════════════════════════════════

class _NetworkStatusCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netAsync = ref.watch(networkStatusProvider);
    return netAsync.when(
      data: (n) => AppCard(
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
            const Divider(color: AppColors.cardBorder, height: 1),
            _netStatusRow(
              icon: Icons.lan_rounded,
              label: n.lanConnected ? 'Ethernet: Connected' : 'Ethernet: Disconnected',
              subtitle: n.lanConnected
                  ? [n.lanIp, n.lanSpeed].whereType<String>().join(' • ')
                  : null,
              connected: n.lanConnected,
              enabled: true,
            ),
            const Divider(color: AppColors.cardBorder, height: 1),
            _netStatusRow(
              icon: Icons.bluetooth_rounded,
              label: n.bluetoothEnabled ? 'Bluetooth: On' : 'Bluetooth: Off',
              connected: n.bluetoothEnabled,
              enabled: n.bluetoothEnabled,
            ),
            const Divider(color: AppColors.cardBorder, height: 1),
            Consumer(
              builder: (context, ref, _) {
                final statsAsync = ref.watch(systemStatsStreamProvider);
                return statsAsync.when(
                  data: (s) => Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
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
                            width: 1, height: 36, color: AppColors.cardBorder),
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
      loading: () => const SizedBox(
        height: 60,
        child: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      ),
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
        Text(value,
            style: GoogleFonts.sora(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        Text(label,
            style: GoogleFonts.dmSans(
                color: AppColors.textSecondary, fontSize: 11)),
      ],
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
        ? AppColors.success
        : enabled
            ? AppColors.textSecondary
            : AppColors.textMuted;
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
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(subtitle,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary, fontSize: 11)),
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

// ═══════════════════════════════════════════════════════════════════════════════
// DOCUMENT SEARCH RESULTS
// ═══════════════════════════════════════════════════════════════════════════════

class _DocSearchResults extends ConsumerWidget {
  final String query;
  const _DocSearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(docSearchResultsProvider(query));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: resultsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
        ),
        error: (e, _) => AppCard(
          child: Text(friendlyError(e),
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (results) {
          if (results.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_off_rounded,
                      color: AppColors.textMuted, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No documents found for "$query"',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              for (int i = 0; i < results.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SearchResultTile(result: results[i])
                      .animate()
                      .fadeIn(delay: (50 * i).ms)
                      .slideY(begin: 0.05, end: 0),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  const _SearchResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final file = result.toFileItem();
    return AppCard(
      onTap: () => context.push('/file-preview', extra: file),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: file.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(file.icon, color: file.iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.filename,
                  style: GoogleFonts.dmSans(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${result.addedBy}  •  ${_formatDate(result.addedAt)}',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays < 1) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AD BLOCKING BADGE — compact stats row, hidden if AdGuard not enabled
// ═══════════════════════════════════════════════════════════════════════════════

class _AdBlockingBadge extends ConsumerWidget {
  const _AdBlockingBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adGuardStatsSilentProvider);
    return statsAsync.when(
      data: (stats) {
        if (stats == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
        final blocked = stats['blocked_today'] as int? ?? 0;
        if (blocked == 0 && (stats['dns_queries'] as int? ?? 0) == 0) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        final formatted = _formatCount(blocked);
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: AppCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.shield_rounded,
                        color: AppColors.success, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.dmSans(
                            color: AppColors.textSecondary, fontSize: 13),
                        children: [
                          TextSpan(
                            text: '$formatted ads',
                            style: GoogleFonts.dmSans(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: ' blocked today'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HERO STATUS CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _HeroStatusCard extends StatelessWidget {
  final AsyncValue<CubieDevice> deviceAsync;
  final AsyncValue<SystemStats> statsAsync;

  const _HeroStatusCard({
    required this.deviceAsync,
    required this.statsAsync,
  });

  @override
  Widget build(BuildContext context) {
    final stats = statsAsync.valueOrNull;
    final device = deviceAsync.valueOrNull;

    final cpuHigh = (stats?.cpuPercent ?? 0) >= 80;
    final ramHigh = (stats?.ramPercent ?? 0) >= 85;
    final tempHigh = (stats?.tempCelsius ?? 0) >= 65;
    final allGood = !cpuHigh && !ramHigh && !tempHigh;

    final statusColor = allGood ? AppColors.success : AppColors.error;
    final statusText = allGood
        ? 'Everything is running fine'
        : [
            if (cpuHigh) 'CPU high',
            if (ramHigh) 'RAM high',
            if (tempHigh) 'Temperature high',
          ].join('  ·  ');

    final uptimePart = stats != null ? _formatUptime(stats.uptime) : '—';
    final tempPart = stats != null
        ? '${stats.tempCelsius.toStringAsFixed(0)}°C'
        : '—';
    const connPart = 'LAN';

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
                Text(
                  device?.name ?? 'AiHomeCloud',
                  style: GoogleFonts.sora(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusText,
                  style: GoogleFonts.dmSans(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Uptime $uptimePart  ·  $tempPart  ·  $connPart',
                  style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary,
                    fontSize: 12,
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

String _formatUptime(Duration d) {
  final days = d.inDays;
  final hrs = d.inHours.remainder(24);
  final mins = d.inMinutes.remainder(60);
  if (days > 0) return '${days}d ${hrs}h';
  if (hrs > 0) return '${hrs}h ${mins}m';
  return '${mins}m';
}

// ═══════════════════════════════════════════════════════════════════════════════
// SYSTEM COMPACT CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _SystemCompactCard extends StatelessWidget {
  final SystemStats stats;
  const _SystemCompactCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cpuOk = stats.cpuPercent < 80;
    final ramOk = stats.ramPercent < 85;
    final tempOk = stats.tempCelsius < 65;

    return AppCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.memory_rounded,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary, fontSize: 13),
                children: [
                  _statSpan(
                      'CPU ${stats.cpuPercent.toStringAsFixed(0)}%', cpuOk),
                  _sep(),
                  _statSpan(
                      'RAM ${stats.ramPercent.toStringAsFixed(0)}%', ramOk),
                  _sep(),
                  _statSpan(
                      '${stats.tempCelsius.toStringAsFixed(0)}°C', tempOk),
                  _sep(),
                  TextSpan(
                    text: _formatUptime(stats.uptime),
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }

  InlineSpan _statSpan(String text, bool ok) => TextSpan(
        text: text,
        style: GoogleFonts.dmSans(
          color: ok ? AppColors.textPrimary : AppColors.error,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );

  InlineSpan _sep() => TextSpan(
        text: '  ·  ',
        style: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 13),
      );
}
