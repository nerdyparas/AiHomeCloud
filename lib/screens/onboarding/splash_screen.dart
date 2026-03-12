import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../services/network_scanner.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _scanning = false;
  bool _scanComplete = false;
  bool _contentShifted = false;
  List<DiscoveredHost> _hosts = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final session = ref.read(authSessionProvider);
    if (session != null) {
      // Already authenticated — quick check then navigate to user picker
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      final api = ref.read(apiServiceProvider);
      try {
        await api.getDeviceInfo();
        if (!mounted) return;
        context.go('/user-picker', extra: session.host);
      } catch (_) {
        if (!mounted) return;
        context.go('/scan-network');
      }
      return;
    }

    // Not authenticated — wait 2s then shift content up and start scanning
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _contentShifted = true);

    // Start scan after animation starts
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _scanComplete = false;
      _hosts = [];
      _error = null;
    });

    final scanner = NetworkScanner.instance;
    final localIp = await scanner.getLocalIp();
    if (!mounted) return;

    if (localIp == null) {
      setState(() {
        _scanning = false;
        _scanComplete = true;
        _error = 'Could not detect local network. Make sure you are connected to Wi-Fi.';
      });
      return;
    }

    final stream = scanner.scanNetwork(onProgress: (_, __) {});
    await for (final host in stream) {
      if (!mounted) return;
      setState(() => _hosts.add(host));
    }

    if (mounted) {
      setState(() {
        _scanning = false;
        _scanComplete = true;
      });
    }
  }

  Future<void> _selectDevice(DiscoveredHost host) async {
    try {
      final api = ref.read(apiServiceProvider);
      final names = await api.fetchUserNames(host.ip);
      if (!mounted) return;
      if (names.isEmpty) {
        context.go('/profile-creation', extra: {'ip': host.ip, 'isAddingUser': false});
      } else {
        context.go('/user-picker', extra: host.ip);
      }
    } catch (_) {
      if (!mounted) return;
      context.go('/user-picker', extra: host.ip);
    }
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
              Expanded(
                flex: 2,
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  alignment: _contentShifted
                      ? const Alignment(0, -0.8)
                      : Alignment.center,
                  child: _heroContent(),
                ),
              ),
              if (_contentShifted)
                Expanded(
                  flex: 3,
                  child: _scanContent(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Illustration()
            .animate()
            .fadeIn(duration: 600.ms)
            .scale(
              begin: const Offset(0.8, 0.8),
              end: const Offset(1, 1),
              duration: 600.ms,
            ),
        const SizedBox(height: 48),
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
      ],
    );
  }

  Widget _scanContent() {
    return Column(
      children: [
        const SizedBox(height: 8),
        if (_scanning) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              backgroundColor: AppColors.card,
              color: AppColors.primary,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scanning for your AiHomeCloud…',
            style: GoogleFonts.dmSans(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: _hosts.isNotEmpty
              ? ListView(
                  children: _hosts
                      .map((h) => _DeviceTile(
                            host: h,
                            onTap: () => _selectDevice(h),
                          )
                              .animate()
                              .fadeIn(duration: 300.ms)
                              .slideX(begin: 0.05, end: 0))
                      .toList(),
                )
              : const SizedBox(),
        ),
        if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(color: AppColors.error, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _startScan,
            child: Text('Try again',
                style: GoogleFonts.dmSans(color: AppColors.primary, fontSize: 14)),
          ),
          const SizedBox(height: 16),
        ] else if (_scanComplete && _hosts.isEmpty) ...[
          Text(
            'No device found on this network',
            style: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _startScan,
            child: Text('Try again',
                style: GoogleFonts.dmSans(color: AppColors.primary, fontSize: 14)),
          ),
          const SizedBox(height: 16),
        ],
      ],
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

// ─── Device tile (shown during scan) ────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final DiscoveredHost host;
  final VoidCallback? onTap;

  const _DeviceTile({required this.host, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        host.deviceName ?? 'AiHomeCloud',
                        style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        host.ip,
                        style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
