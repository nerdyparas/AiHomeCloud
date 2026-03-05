import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  int? _expiresAtSeconds;
  Timer? _countdownTimer;
  bool _fingerprintDialogVisible = false;
  @override
  void initState() {
    super.initState();
    _expiresAtSeconds = ref.read(qrPayloadProvider)?.expiresAt;
    ref.listen<QrPairPayload?>(qrPayloadProvider, (prev, next) {
      final nextExpires = next?.expiresAt;
      if (nextExpires != _expiresAtSeconds) {
        setState(() {
          _expiresAtSeconds = nextExpires;
        });
      }
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_expiresAtSeconds == null) return;
      if (_timeRemaining == Duration.zero) {
        _countdownTimer?.cancel();
      }
      setState(() {});
    });
    _startDiscovery();
  }

  void _startDiscovery() {
    final payload = ref.read(qrPayloadProvider);
    if (payload == null) {
      // Guard: go back if no QR data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/qr-scan');
      });
      return;
    }
    ref
        .read(discoveryNotifierProvider.notifier)
        .startDiscovery(payload.serial, payload.key);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoveryNotifierProvider);

    // Auto-navigate on success
    ref.listen<DiscoveryState>(discoveryNotifierProvider, (prev, next) {
      if (next.pendingFingerprint != null &&
          next.pendingFingerprint != prev?.pendingFingerprint) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showFingerprintDialog(next.pendingFingerprint!);
          }
        });
      }

      if (next.status == DiscoveryStatus.found &&
          next.pendingFingerprint == null) {
        Future.delayed(const Duration(seconds: 1), () {
          // ignore: use_build_context_synchronously
          if (mounted) context.go('/setup');
        });
      }
    });

    return Scaffold(
      backgroundColor: CubieColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Animated radar / success / error
              _StatusAnimation(status: state.status),

              const SizedBox(height: 48),

              // Title
              Text(
                _title(state.status),
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  color: CubieColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ).animate().fadeIn(duration: 300.ms),

              const SizedBox(height: 16),

              if (_expiresAtSeconds != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 16, color: CubieColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      _timeRemaining == Duration.zero
                          ? 'OTP expired — scan again'
                          : 'OTP expires in ${_formatDuration(_timeRemaining)}',
                      style: GoogleFonts.dmSans(
                        color: _timeRemaining == Duration.zero
                            ? CubieColors.error
                            : CubieColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],

              // Live status message
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  state.statusMessage,
                  key: ValueKey(state.statusMessage),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // Retry / rescan on failure
              if (state.status == DiscoveryStatus.failed) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      ref.read(discoveryNotifierProvider.notifier).reset();
                      _startDiscovery();
                    },
                    child: Text('Retry',
                        style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/qr-scan'),
                  child: Text('Scan Again',
                      style:
                          GoogleFonts.dmSans(color: CubieColors.textSecondary)),
                ),
              ],

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  String _title(DiscoveryStatus s) => switch (s) {
        DiscoveryStatus.idle ||
        DiscoveryStatus.searching =>
          'Finding Your CubieCloud',
        DiscoveryStatus.found => 'Device Found!',
        DiscoveryStatus.failed => 'Connection Failed',
      };

  Duration get _timeRemaining {
    if (_expiresAtSeconds == null) return Duration.zero;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final diff = _expiresAtSeconds! - now;
    return diff > 0 ? Duration(seconds: diff) : Duration.zero;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showFingerprintDialog(String fingerprint) {
    if (_fingerprintDialogVisible) return;
    _fingerprintDialogVisible = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Verify Server Certificate', style: GoogleFonts.sora()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fingerprint (SHA-256):',
                style: GoogleFonts.dmSans(fontSize: 13)),
            const SizedBox(height: 8),
            SelectableText(
              fingerprint.toUpperCase(),
              style: GoogleFonts.dmSans(
                color: CubieColors.textSecondary,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Trusting this certificate locks the device to the pinned fingerprint.',
              style: GoogleFonts.dmSans(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _handleFingerprintRejected();
            },
            child: Text('Cancel', style: GoogleFonts.dmSans()),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _handleFingerprintTrust(fingerprint);
            },
            child: Text('Trust Certificate', style: GoogleFonts.dmSans()),
          ),
        ],
      ),
    ).whenComplete(() {
      _fingerprintDialogVisible = false;
    });
  }

  Future<void> _handleFingerprintTrust(String fingerprint) async {
    await ref
        .read(discoveryNotifierProvider.notifier)
        .trustFingerprint(fingerprint);
  }

  void _handleFingerprintRejected() {
    ref.read(discoveryNotifierProvider.notifier).reset();
    if (mounted) {
      context.go('/qr-scan');
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}

// ─── Animated status indicator ──────────────────────────────────────────────

class _StatusAnimation extends StatelessWidget {
  final DiscoveryStatus status;
  const _StatusAnimation({required this.status});

  @override
  Widget build(BuildContext context) {
    final colour = switch (status) {
      DiscoveryStatus.found => CubieColors.success,
      DiscoveryStatus.failed => CubieColors.error,
      _ => CubieColors.primary,
    };

    final icon = switch (status) {
      DiscoveryStatus.found => Icons.check_circle_rounded,
      DiscoveryStatus.failed => Icons.error_rounded,
      _ => Icons.radar_rounded,
    };

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulsing rings while searching
          if (status == DiscoveryStatus.searching) ...[
            _ring(160, colour, 0),
            _ring(120, colour, 500),
          ],

          // Centre icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colour.withOpacity(0.15),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colour.withOpacity(0.2),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(icon, color: colour, size: 40),
          ).animate().fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _ring(double size, Color c, int delayMs) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.withOpacity(0.15), width: 1),
      ),
    )
        .animate(onPlay: (ctrl) => ctrl.repeat(), delay: delayMs.ms)
        .scaleXY(begin: 0.6, end: 1.2, duration: 2.seconds)
        .fadeOut(begin: 0.6, duration: 2.seconds);
  }
}
