import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// Renders a circular avatar for a user.
/// Falls back to the first letter of [name] when [iconEmoji] is empty.
class UserAvatar extends StatelessWidget {
  final String name;
  final String iconEmoji;
  final int colorIndex;
  final double size;
  final bool isSelected;
  final bool isLoading;

  const UserAvatar({
    super.key,
    required this.name,
    required this.colorIndex,
    this.iconEmoji = '',
    this.size = 72,
    this.isSelected = false,
    this.isLoading = false,
  });

  static const _colors = [
    Color(0xFFE8A84C),
    Color(0xFF4C9BE8),
    Color(0xFF4CE88A),
    Color(0xFFE84CA8),
    Color(0xFF9B59B6),
    Color(0xFF1ABC9C),
    Color(0xFFE74C3C),
    Color(0xFF3498DB),
  ];

  Color get _bgColor => _colors[colorIndex % _colors.length];

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _bgColor,
        shape: BoxShape.circle,
        border: isSelected ? Border.all(color: AppColors.primary, width: 3) : null,
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                )
              ]
            : null,
      ),
      child: Center(
        child: isLoading
            ? SizedBox(
                width: size * 0.35,
                height: size * 0.35,
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : iconEmoji.isNotEmpty
                ? Text(
                    iconEmoji,
                    style: TextStyle(fontSize: size * 0.44),
                  )
                : Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.sora(
                      color: Colors.white,
                      fontSize: size * 0.38,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
      ),
    );
  }
}
