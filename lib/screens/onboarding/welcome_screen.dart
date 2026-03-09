import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CubieColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Illustration
              _Illustration()
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1, 1),
                      duration: 600.ms),

              const SizedBox(height: 48),

              // Title
              Text(
                'Welcome to\nAiHomeCloud',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  color: CubieColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.2, end: 0),

              const SizedBox(height: 16),

              // Subtitle
              Text(
                'Your personal home cloud. Store photos, videos, '
                'and files — all on your own device.\n'
                'No subscriptions, no limits.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ).animate(delay: 400.ms).fadeIn(duration: 500.ms),

              const Spacer(flex: 3),

              // CTA
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => context.go('/scan-network'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_find_rounded, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Find My Cubie',
                        style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              )
                  .animate(delay: 600.ms)
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.3, end: 0),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Decorative illustration ────────────────────────────────────────────────

class _Illustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Gradient glow
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  CubieColors.primary.withOpacity(0.15),
                  CubieColors.primary.withOpacity(0.03),
                  Colors.transparent,
                ],
                radius: 0.8,
              ),
            ),
          ),
          // Outer ring
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: CubieColors.cardBorder, width: 1),
            ),
          ),
          // Inner ring
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: CubieColors.primary.withOpacity(0.3), width: 1),
            ),
          ),
          // Centre cloud icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: CubieColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: CubieColors.primary.withOpacity(0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: CubieColors.primary.withOpacity(0.2),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.cloud_rounded,
                color: CubieColors.primary, size: 40),
          ),
          // Orbiting device icons
          Positioned(
              top: 20,
              right: 30,
              child: _bubble(Icons.phone_android_rounded)),
          Positioned(
              bottom: 25, left: 20, child: _bubble(Icons.laptop_rounded)),
          Positioned(top: 40, left: 15, child: _bubble(Icons.tv_rounded)),
        ],
      ),
    );
  }

  Widget _bubble(IconData icon) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: CubieColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CubieColors.cardBorder),
        ),
        child: Icon(icon, color: CubieColors.textSecondary, size: 18),
      );
}
