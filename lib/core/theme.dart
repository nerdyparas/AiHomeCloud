import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Design System Colors ──────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  static const background = Color(0xFF0D0F14);
  static const surface = Color(0xFF161B25);
  static const card = Color(0xFF1E2533);
  static const cardBorder = Color(0xFF2A3347);

  static const primary = Color(0xFFE8A84C); // warm amber
  static const secondary = Color(0xFF4C9BE8); // blue

  static const textPrimary = Color(0xFFF0F2F7);
  static const textSecondary = Color(0xFF7A8499);
  static const textMuted = Color(0xFF3E4A62);

  static const error = Color(0xFFE85C5C);
  static const success = Color(0xFF4CE88A);
  static const pink = Color(0xFFE84CA8);
}

// ─── App-wide Border Radii ─────────────────────────────────────────────────────

class CubieRadii {
  CubieRadii._();
  static const double card = 16;
  static const double button = 14;
  static const double input = 12;
}

// ─── Full Dark Theme ───────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark();

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.background,
        onSecondary: AppColors.background,
        onSurface: AppColors.textPrimary,
        onError: AppColors.textPrimary,
      ),

      // ── Typography ──
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.sora(color: AppColors.textPrimary),
        displayMedium: GoogleFonts.sora(color: AppColors.textPrimary),
        displaySmall: GoogleFonts.sora(color: AppColors.textPrimary),
        headlineLarge: GoogleFonts.sora(color: AppColors.textPrimary),
        headlineMedium: GoogleFonts.sora(color: AppColors.textPrimary),
        headlineSmall: GoogleFonts.sora(color: AppColors.textPrimary),
        titleLarge: GoogleFonts.sora(
            color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.sora(
            color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.sora(
            color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.dmSans(color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.dmSans(color: AppColors.textPrimary),
        bodySmall: GoogleFonts.dmSans(color: AppColors.textSecondary),
        labelLarge: GoogleFonts.dmSans(
            color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        labelMedium: GoogleFonts.dmSans(color: AppColors.textSecondary),
        labelSmall: GoogleFonts.dmSans(color: AppColors.textMuted),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CubieRadii.card),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
      ),

      // ── Elevated Button ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CubieRadii.button)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle:
              GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),

      // ── Outlined Button ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CubieRadii.button)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle:
              GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),

      // ── Text Button ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle:
              GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // ── Input Fields ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted),
        labelStyle: GoogleFonts.dmSans(color: AppColors.textSecondary),
        counterStyle: GoogleFonts.dmSans(color: AppColors.textMuted),
      ),

      // ── NavigationBar (bottom) ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textMuted,
          );
        }),
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sora(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: AppColors.cardBorder,
        thickness: 1,
        space: 1,
      ),

      // ── FAB ──
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CubieRadii.button)),
      ),

      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.card,
        contentTextStyle: GoogleFonts.dmSans(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CubieRadii.card),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        titleTextStyle: GoogleFonts.sora(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── BottomSheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withValues(alpha: 0.3);
          }
          return AppColors.surface;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          return AppColors.cardBorder;
        }),
      ),

      // ── Progress Indicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.cardBorder,
      ),
    );
  }
}
