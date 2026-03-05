import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Standard card matching the CubieCloud design system.
/// Set [glowing] to `true` for an amber glow on active elements.
class CubieCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final bool glowing;
  final VoidCallback? onTap;

  const CubieCard({
    super.key,
    required this.child,
    this.padding,
    this.glowing = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CubieColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: glowing
                ? CubieColors.primary.withOpacity(0.5)
                : CubieColors.cardBorder,
            width: 1,
          ),
          boxShadow: glowing
              ? [
                  BoxShadow(
                    color: CubieColors.primary.withOpacity(0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
  }
}
