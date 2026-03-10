import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';

/// Shown when no devices are found on the LAN.  Guides the user to connect
/// their phone to the AiHomeCloud Wi-Fi hotspot so they can then enter
/// home Wi-Fi credentials on the next screen.
class HotspotConnectScreen extends StatelessWidget {
  const HotspotConnectScreen({super.key});

  static const _ssid = 'AiHomeCloud';
  static const _password = 'aihomecloud123';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.go('/scan-network'),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Connect to AiHomeCloud',
                      style: GoogleFonts.sora(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 8),

              Expanded(
                child: ListView(
                  children: [
                    // ── Explanation ────────────────────────────────────
                    Text(
                      'Your AiHomeCloud is not on this network yet.\n'
                      'It has started a Wi-Fi hotspot. Connect your phone '
                      'to it, then continue to set up your home Wi-Fi.',
                      style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'If your AiHomeCloud has a QR code sticker, scan it '
                      'with your phone camera to connect automatically.',
                      style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Step indicator ─────────────────────────────────
                    _stepBadge('Step 1 of 2 — Connect to hotspot'),

                    const SizedBox(height: 20),

                    // ── Wi-Fi icon ────────────────────────────────────
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.wifi_tethering_rounded,
                          color: AppColors.primary,
                          size: 40,
                        ),
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                    const SizedBox(height: 24),

                    // ── Manual Credentials ────────────────────────────
                    _credentialCard(
                      context,
                      icon: Icons.wifi_rounded,
                      label: 'Network Name (SSID)',
                      value: _ssid,
                    ),
                    const SizedBox(height: 10),
                    _credentialCard(
                      context,
                      icon: Icons.lock_outline_rounded,
                      label: 'Password',
                      value: _password,
                    ),

                    const SizedBox(height: 20),

                    // ── Open WiFi Settings ────────────────────────────
                    OutlinedButton.icon(
                      onPressed: _openWifiSettings,
                      icon: const Icon(Icons.settings_rounded, size: 18),
                      label: Text(
                        'Open Wi-Fi Settings',
                        style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.cardBorder),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Continue Button ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.go('/wifi-setup'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      "I'm Connected — Continue",
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: GoogleFonts.dmSans(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _credentialCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            color: AppColors.textSecondary,
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static void _openWifiSettings() {
    // Launch Android Wi-Fi settings via platform channel.
    const platform = MethodChannel('com.aihomecloud/system');
    platform.invokeMethod<void>('openWifiSettings').catchError((_) {
      // Silently ignore — user can navigate manually.
    });
  }
}
