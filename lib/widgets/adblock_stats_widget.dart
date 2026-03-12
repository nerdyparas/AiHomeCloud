import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AdBlockStatsWidget
//
// Displays AdGuard Home ad-blocking statistics inside the Network card.
// Shows: shield icon, "Ads blocked today" count, and total blocked.
// Silently hides itself when AdGuard is disabled or unreachable.
// ═══════════════════════════════════════════════════════════════════════════════

class AdBlockStatsWidget extends ConsumerWidget {
  const AdBlockStatsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adGuardStatsSilentProvider);

    return statsAsync.when(
      // Hide loading state — no skeleton here, card already shows network rows
      loading: () => const SizedBox.shrink(),
      // Silently suppress errors — AdGuard may not be enabled on every device
      error: (_, __) => const SizedBox.shrink(),
      data: (stats) {
        if (stats == null) return const SizedBox.shrink();

        final blockedToday = stats['blocked_today'] as int? ?? 0;
        final totalBlocked = stats['total_blocked'] as int? ??
            stats['num_blocked_filtering_all_time'] as int? ??
            0;
        final dnsQueries = stats['dns_queries'] as int? ?? 0;

        // Hide the widget entirely when AdGuard has no data yet
        if (blockedToday == 0 && dnsQueries == 0) return const SizedBox.shrink();

        return _AdBlockStatsContent(
          blockedToday: blockedToday,
          totalBlocked: totalBlocked,
        ).animate().fadeIn(duration: 350.ms);
      },
    );
  }
}

// ── Internal display widget (purely presentational) ─────────────────────────

class _AdBlockStatsContent extends StatelessWidget {
  final int blockedToday;
  final int totalBlocked;

  const _AdBlockStatsContent({
    required this.blockedToday,
    required this.totalBlocked,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Consistent inner padding aligning with network card divider rows
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          // Shield icon with green tinted background
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: AppColors.success,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),

          // Stats column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row: value is emphasised
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    children: [
                      TextSpan(
                        text: _formatCount(blockedToday),
                        style: GoogleFonts.sora(
                          color: AppColors.success,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: '  Ads blocked today'),
                    ],
                  ),
                ),
                // Secondary line: total all-time (hidden when zero)
                if (totalBlocked > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Total blocked: ${_formatCount(totalBlocked)}',
                    style: GoogleFonts.dmSans(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Protection active indicator dot
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  /// Format large numbers as e.g. "1.4K" or "2.1M".
  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
