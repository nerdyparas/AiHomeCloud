import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _showButton = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final session = ref.read(authSessionProvider);
    if (session != null) {
      // Already authenticated — quick check then navigate
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      final api = ref.read(apiServiceProvider);
      try {
        await api.getDeviceInfo();
        if (!mounted) return;
        context.go('/dashboard');
      } catch (_) {
        if (!mounted) return;
        context.go('/scan-network');
      }
      return;
    }

    // Not authenticated — wait for animations to finish then reveal button
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _showButton = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Illustration
              const _Illustration()
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1, 1),
                    duration: 600.ms,
                  ),

              const SizedBox(height: 48),

              // Title
              Text(
                'AiHomeCloud',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  color: AppColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              )
                  .animate(delay: 300.ms)
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
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ).animate(delay: 600.ms).fadeIn(duration: 500.ms),

              const Spacer(flex: 3),

              // CTA — appears after animations complete (~1.5 s)
              if (_showButton)
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
                          'Find My AiHomeCloud',
                          style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.3, end: 0)
              else
                const SizedBox(height: 56),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Decorative illustration ─────────────────────────────────────────────────

class _Illustration extends StatelessWidget {
  const _Illustration();

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
                  AppColors.primary.withValues(alpha: 0.15),
                  AppColors.primary.withValues(alpha: 0.03),
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
              border: Border.all(color: AppColors.cardBorder, width: 1),
            ),
          ),
          // Inner ring
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3), width: 1),
            ),
          ),
          // Centre cloud icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.cloud_rounded,
                color: AppColors.primary, size: 40),
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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 18),
      );
}
