import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// Animated donut / arc chart showing storage usage.
/// Used amber for the "used" arc and #2A3347 for the "free" background arc.
class StorageDonutChart extends StatelessWidget {
  final double usedGB;
  final double totalGB;
  final double size;
  final double strokeWidth;

  const StorageDonutChart({
    super.key,
    required this.usedGB,
    required this.totalGB,
    this.size = 160,
    this.strokeWidth = 14,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Painted arcs
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(
              usedPercent: (usedGB / totalGB).clamp(0.0, 1.0),
              strokeWidth: strokeWidth,
              usedColor: AppColors.primary,
              freeColor: const Color(0xFF2A3347),
            ),
          ),
          // Centre label
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                usedGB.toStringAsFixed(1),
                style: GoogleFonts.sora(
                  color: AppColors.textPrimary,
                  fontSize: size * 0.17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'of ${totalGB.toStringAsFixed(0)} GB',
                style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary,
                  fontSize: size * 0.085,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double usedPercent;
  final double strokeWidth;
  final Color usedColor;
  final Color freeColor;

  _DonutPainter({
    required this.usedPercent,
    required this.strokeWidth,
    required this.usedColor,
    required this.freeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // Background ring (free space)
    final bgPaint = Paint()
      ..color = freeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, bgPaint);

    if (usedPercent <= 0) return;

    final sweep = 2 * pi * usedPercent;
    const start = -pi / 2; // 12-o'clock

    // Amber glow behind the arc
    final glowPaint = Paint()
      ..color = usedColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawArc(rect, start, sweep, false, glowPaint);

    // Used arc
    final usedPaint = Paint()
      ..color = usedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, usedPaint);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.usedPercent != usedPercent;
}
