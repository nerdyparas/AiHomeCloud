import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Design System Colors ──────────────────────────────────────────────────────

class CubieColors {
  CubieColors._();

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

class CubieTheme {
  CubieTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark();

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: CubieColors.background,
      colorScheme: const ColorScheme.dark(
        primary: CubieColors.primary,
        secondary: CubieColors.secondary,
        surface: CubieColors.surface,
        error: CubieColors.error,
        onPrimary: CubieColors.background,
        onSecondary: CubieColors.background,
        onSurface: CubieColors.textPrimary,
        onError: CubieColors.textPrimary,
      ),

      // ── Typography ──
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.sora(color: CubieColors.textPrimary),
        displayMedium: GoogleFonts.sora(color: CubieColors.textPrimary),
        displaySmall: GoogleFonts.sora(color: CubieColors.textPrimary),
        headlineLarge: GoogleFonts.sora(color: CubieColors.textPrimary),
        headlineMedium: GoogleFonts.sora(color: CubieColors.textPrimary),
        headlineSmall: GoogleFonts.sora(color: CubieColors.textPrimary),
        titleLarge: GoogleFonts.sora(
            color: CubieColors.textPrimary, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.sora(
            color: CubieColors.textPrimary, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.sora(
            color: CubieColors.textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.dmSans(color: CubieColors.textPrimary),
        bodyMedium: GoogleFonts.dmSans(color: CubieColors.textPrimary),
        bodySmall: GoogleFonts.dmSans(color: CubieColors.textSecondary),
        labelLarge: GoogleFonts.dmSans(
            color: CubieColors.textPrimary, fontWeight: FontWeight.w600),
        labelMedium: GoogleFonts.dmSans(color: CubieColors.textSecondary),
        labelSmall: GoogleFonts.dmSans(color: CubieColors.textMuted),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        color: CubieColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CubieRadii.card),
          side: const BorderSide(color: CubieColors.cardBorder, width: 1),
        ),
      ),

      // ── Elevated Button ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CubieColors.primary,
          foregroundColor: CubieColors.background,
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
          foregroundColor: CubieColors.primary,
          side: const BorderSide(color: CubieColors.primary),
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
          foregroundColor: CubieColors.primary,
          textStyle:
              GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // ── Input Fields ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CubieColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          borderSide: const BorderSide(color: CubieColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          borderSide: const BorderSide(color: CubieColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          borderSide: const BorderSide(color: CubieColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          borderSide: const BorderSide(color: CubieColors.error),
        ),
        hintStyle: GoogleFonts.dmSans(color: CubieColors.textMuted),
        labelStyle: GoogleFonts.dmSans(color: CubieColors.textSecondary),
        counterStyle: GoogleFonts.dmSans(color: CubieColors.textMuted),
      ),

      // ── NavigationBar (bottom) ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CubieColors.surface,
        indicatorColor: CubieColors.primary.withOpacity(0.12),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? CubieColors.primary : CubieColors.textMuted,
          );
        }),
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: CubieColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sora(
          color: CubieColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: CubieColors.textPrimary),
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: CubieColors.cardBorder,
        thickness: 1,
        space: 1,
      ),

      // ── FAB ──
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: CubieColors.primary,
        foregroundColor: CubieColors.background,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CubieRadii.button)),
      ),

      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CubieColors.card,
        contentTextStyle: GoogleFonts.dmSans(color: CubieColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CubieRadii.input),
          side: const BorderSide(color: CubieColors.cardBorder),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: CubieColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CubieRadii.card),
          side: const BorderSide(color: CubieColors.cardBorder),
        ),
        titleTextStyle: GoogleFonts.sora(
          color: CubieColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── BottomSheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CubieColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return CubieColors.primary;
          }
          return CubieColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return CubieColors.primary.withOpacity(0.3);
          }
          return CubieColors.surface;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          return CubieColors.cardBorder;
        }),
      ),

      // ── Progress Indicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CubieColors.primary,
        linearTrackColor: CubieColors.cardBorder,
      ),
    );
  }
}
