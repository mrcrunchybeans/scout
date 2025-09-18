import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ---------------------------
/// Brand palette (tweak here)
/// ---------------------------
class BrandColors {
  // Teal brand
  static const primary = Color(0xFF16B3A4);   // lively teal
  static const primaryDark = Color(0xFF0D7E75);
  static const primaryContainer = Color.fromARGB(255, 165, 255, 243);

  // Deep text / navigation (teal-charcoal vibe)
  static const ink = Color(0xFF0F2E2C);       // headings / strong text
  static const inkMuted = Color(0xFF3D5150);  // body

  // Slate accent & subtle outlines
  static const slate = Color(0xFF3B5B59);
  static const outline = Color(0xFFE0ECEA);

  // Backgrounds
  static const bg = Color(0xFFF6FBFA);        // app background
  static const surface = Colors.white;        // cards, sheets
}

/// Helper: subtle drop shadow for cards
const _softShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x1A000000), // 10% black
    blurRadius: 12,
    offset: Offset(0, 3),
  ),
];

/// A tiny ThemeExtension so you can fetch a shared card shadow.
class _CardShadow extends ThemeExtension<_CardShadow> {
  final List<BoxShadow> shadow;
  const _CardShadow({required this.shadow});

  @override
  _CardShadow copyWith({List<BoxShadow>? shadow}) =>
      _CardShadow(shadow: shadow ?? this.shadow);

  @override
  _CardShadow lerp(ThemeExtension<_CardShadow>? other, double t) {
    if (other is! _CardShadow) return this;
    return t < 0.5 ? this : other;
  }
}

class AppTheme {
  /// LIGHT THEME
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: BrandColors.primary,
      onPrimary: Colors.white,
      primaryContainer: BrandColors.primaryContainer,
      onPrimaryContainer: BrandColors.ink,
      surface: BrandColors.surface,
      onSurface: BrandColors.ink,
      secondary: BrandColors.slate,
      onSecondary: Colors.white,
      outline: BrandColors.outline,
      // no background/onBackground (deprecated) — use scaffoldBackgroundColor/onSurface
    );

    final baseText = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: BrandColors.bg,
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: BrandColors.ink,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(color: BrandColors.inkMuted),
        bodyMedium: baseText.bodyMedium?.copyWith(color: BrandColors.inkMuted),
        bodySmall: baseText.bodySmall?.copyWith(color: BrandColors.inkMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: BrandColors.surface,
        foregroundColor: BrandColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: BrandColors.ink,
        ),
        toolbarHeight: 64,
      ),
      // FIX: CardThemeData (not CardTheme)
      cardTheme: CardThemeData(
        color: BrandColors.surface,
        elevation: 0,
        margin: const EdgeInsets.all(0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        shadowColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 1,
        color: BrandColors.outline,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: BrandColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(width: 1, color: BrandColors.primary),
        ),
        labelStyle: TextStyle(color: BrandColors.inkMuted),
        hintStyle: TextStyle(color: BrandColors.inkMuted.withValues(alpha: 0.7)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BrandColors.primary.withValues(alpha: 0.4);
            }
            return BrandColors.primary;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(
              BorderSide(color: BrandColors.primaryDark)),
          foregroundColor:
              const WidgetStatePropertyAll(BrandColors.primaryDark),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor:
              const WidgetStatePropertyAll(BrandColors.primaryDark),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        _CardShadow(shadow: _softShadow),
      ],
    );
  }

  /// DARK THEME
  static ThemeData dark() {
    // Deep, modern Material dark palette
    const darkBg = Color(0xFF10191A);       // deep blue-charcoal
    const darkSurface = Color(0xFF182223);  // slightly lighter for cards/sheets
    const darkCard = Color(0xFF1E2A2B);
    const darkInput = Color(0xFF232F30);
    const darkOutline = Color(0xFF2D3C3C);

    // Rich, saturated dark brand colors
    const darkTeal = Color(0xFF00BFAE);
    const darkTealContainer = Color(0xFF1DE9B6);
    const darkBlue = Color(0xFF1976D2);
    const darkBlueContainer = Color(0xFF1565C0);
    const darkSlate = Color(0xFF4FC3B7);

    final scheme = ColorScheme.fromSeed(
      seedColor: darkTeal,
      brightness: Brightness.dark,
    ).copyWith(
      primary: darkTeal,
      onPrimary: Colors.white,
      primaryContainer: darkTealContainer,
      onPrimaryContainer: Colors.black,
      secondary: darkSlate,
      onSecondary: Colors.white,
      surface: darkSurface,
      onSurface: Colors.white,
      outline: darkOutline,
      // Use newer surface containers instead of deprecated surfaceVariant
      surfaceContainerHighest: darkCard,
      tertiary: darkTealContainer,
      onTertiary: Colors.black,
    );

    final baseText =
        GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: Colors.white.withValues(alpha: 0.92),
      displayColor: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBg,
      iconTheme: const IconThemeData(color: Colors.white),
      primaryIconTheme: const IconThemeData(color: Colors.white),

      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(height: 1.25),
        bodyMedium: baseText.bodyMedium?.copyWith(height: 1.25),
        bodySmall: baseText.bodySmall?.copyWith(color: Colors.white70),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        toolbarHeight: 64,
      ),

      // FIX: CardThemeData (not CardTheme)
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        margin: const EdgeInsets.all(0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        shadowColor: Colors.transparent,
      ),

      dividerTheme: const DividerThemeData(
        thickness: 1,
        space: 1,
        color: darkOutline,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInput,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkTeal, width: 1),
        ),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white54),
      ),

      chipTheme: const ChipThemeData(
        shape: StadiumBorder(),
        side: BorderSide.none,
        labelStyle: TextStyle(color: Colors.white),
        backgroundColor: darkInput,
        selectedColor: darkTealContainer,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return darkTealContainer;
            if (states.contains(WidgetState.disabled)) {
              return darkTeal.withValues(alpha: 0.4);
            }
            return darkTeal;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(BorderSide(color: darkBlue)),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return darkBlueContainer;
            if (states.contains(WidgetState.disabled)) {
              return darkBlue.withValues(alpha: 0.4);
            }
            return Colors.transparent;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          textStyle:
              WidgetStatePropertyAll(GoogleFonts.inter(fontWeight: FontWeight.w600)),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return darkBlueContainer;
            if (states.contains(WidgetState.disabled)) {
              return darkBlue.withValues(alpha: 0.4);
            }
            return darkBlue;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        iconColor: Colors.white,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkCard,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      extensions: const <ThemeExtension<dynamic>>[
        _CardShadow(shadow: _softShadow),
      ],
    );
  }
}
