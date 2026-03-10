import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  bool _processing = false;
  int? _otpExpiresAt;
  int? _otpInitialWindow;
  Timer? _countdownTimer;

  /// Called when a QR barcode is detected (or when the demo button is pressed).
  void _onQrDetected(String rawValue) {
    if (_processing) return;
    setState(() => _processing = true);

    try {
      final uri = Uri.parse(rawValue);
      if (uri.scheme != 'cubie' || uri.host != 'pair') {
        _error('Invalid QR code. Scan the code on your AiHomeCloud box.');
        return;
      }

      final payload = QrPairPayload.fromUri(uri);
      if (payload.serial.isEmpty || payload.key.isEmpty) {
        _error('QR code is missing required data.');
        return;
      }

      if (payload.expiresAt != null) {
        _startCountdown(payload.expiresAt!);
      }

      ref.read(qrPayloadProvider.notifier).state = payload;
      context.go('/discovery');
    } catch (_) {
      _error('Could not read QR code. Please try again.');
    }
  }

  void _error(String msg) {
    setState(() => _processing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _startCountdown(int expiresAt) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    _otpExpiresAt = expiresAt;
    _otpInitialWindow = max(expiresAt - now, 1);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds <= 0) {
        _countdownTimer?.cancel();
      }
      setState(() {});
    });
    setState(() {});
  }

  int get _remainingSeconds {
    if (_otpExpiresAt == null) return 0;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final diff = _otpExpiresAt! - now;
    return diff > 0 ? diff : 0;
  }

  double get _countdownProgress {
    if (_otpInitialWindow == null || _otpInitialWindow == 0) return 0;
    return (_remainingSeconds / _otpInitialWindow!).clamp(0.0, 1.0);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildCountdownWidget() {
    final remaining = Duration(seconds: _remainingSeconds);
    final isExpired = _remainingSeconds == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined,
                size: 16,
                color:
                    isExpired ? AppColors.error : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              isExpired
                ? 'Pairing code expired — please scan again'
                : 'Pairing code valid for ${_formatDuration(remaining)}',
              style: GoogleFonts.dmSans(
                color:
                    isExpired ? AppColors.error : AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: isExpired ? 0 : _countdownProgress,
          color: AppColors.error,
          backgroundColor: AppColors.surface.withValues(alpha: 0.6),
          minHeight: 4,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Injects a realistic demo QR value for emulator testing.
  void _useDemoQr() {
    _onQrDetected(
      'cubie://pair?serial=CUBIE-A5E-2024-001'
      '&key=demo_pairing_key_12345'
      '&host=cubie-CUBIE-A5E-2024-001.local',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        title: Text('Scan QR Code',
            style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),

          // ── Camera preview placeholder ────────────────────────────────────
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Real camera scanner using mobile_scanner package
                    ClipRRect(
                      borderRadius: BorderRadius.circular(23),
                      child: MobileScanner(
                        onDetect: (capture) {
                          final barcode = capture.barcodes.firstOrNull;
                          if (barcode?.rawValue != null) {
                            _onQrDetected(barcode!.rawValue!);
                          }
                        },
                      ),
                    ),

                    // Scanner-corner overlay
                    _ScannerOverlay(),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── Instructions ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Text(
                  'Point your camera at the QR code\n'
                  'on the bottom of your AiHomeCloud box',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (_otpExpiresAt != null) ...[
                  const SizedBox(height: 16),
                  _buildCountdownWidget(),
                ],
                const SizedBox(height: 24),

                // Demo button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _processing ? null : _useDemoQr,
                    icon: const Icon(Icons.bug_report_rounded, size: 18),
                    label: Text(
                      'Use Demo QR (Testing)',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Scanner corner overlay ─────────────────────────────────────────────────

class _ScannerOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const s = 32.0;
    const w = 3.0;
    const c = AppColors.primary;

    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        children: [
          _corner(
              Alignment.topLeft,
              const Border(
                  top: BorderSide(color: c, width: w),
                  left: BorderSide(color: c, width: w)),
              s),
          _corner(
              Alignment.topRight,
              const Border(
                  top: BorderSide(color: c, width: w),
                  right: BorderSide(color: c, width: w)),
              s),
          _corner(
              Alignment.bottomLeft,
              const Border(
                  bottom: BorderSide(color: c, width: w),
                  left: BorderSide(color: c, width: w)),
              s),
          _corner(
              Alignment.bottomRight,
              const Border(
                  bottom: BorderSide(color: c, width: w),
                  right: BorderSide(color: c, width: w)),
              s),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
        begin: 0.95, end: 1.05, duration: 1500.ms, curve: Curves.easeInOut);
  }

  Widget _corner(Alignment align, Border border, double size) {
    return Align(
      alignment: align,
      child: Container(
          width: size, height: size, decoration: BoxDecoration(border: border)),
    );
  }
}
