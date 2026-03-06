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
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    final session = ref.read(authSessionProvider);
    if (session != null) {
      // Try reaching the saved device; if unreachable show scan page
      final api = ref.read(apiServiceProvider);
      try {
        await api.getDeviceInfo();
        if (!mounted) return;
        context.go('/dashboard');
      } catch (_) {
        if (!mounted) return;
        context.go('/scan-network');
      }
    } else {
      context.go('/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CubieColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: CubieColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: CubieColors.primary.withOpacity(0.2),
                    blurRadius: 32,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.cloud_rounded,
                color: CubieColors.primary,
                size: 44,
              ),
            )
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1.0, 1.0),
                  duration: 600.ms,
                  curve: Curves.easeOutBack,
                ),

            const SizedBox(height: 24),

            // App name
            Text(
              'CubieCloud',
              style: GoogleFonts.sora(
                color: CubieColors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w700,
              ),
            )
                .animate(delay: 300.ms)
                .fadeIn(duration: 500.ms)
                .slideY(
                    begin: 0.3,
                    end: 0,
                    duration: 500.ms,
                    curve: Curves.easeOut),

            const SizedBox(height: 8),

            // Tagline
            Text(
              'Your home, your cloud',
              style: GoogleFonts.dmSans(
                color: CubieColors.textSecondary,
                fontSize: 16,
              ),
            ).animate(delay: 600.ms).fadeIn(duration: 500.ms),
          ],
        ),
      ),
    );
  }
}
