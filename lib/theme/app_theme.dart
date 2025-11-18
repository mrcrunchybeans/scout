// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ---------------------------
/// Brand palette (tweak here)
/// ---------------------------
class BrandColors {
  // Brand Colors
  static const brandTeal = Color(0xFF00CBA9);
  static const brandTealDark = Color(0xFF009B84);
  static const brandBlue = Color(0xFF3B82F6);

  // Common UI Colors
  static const ink = Color(0xFF1F2F32);
  static const inkMuted = Color(0xFF5A6C71);
  static const offWhite = Color(0xFFF9FAFB);
  static const white = Color(0xFFFFFFFF);
  static const outline = Color(0xFFDDE6E9);

  // Dark Theme UI Colors (Logically Inverted)
  static const surfaceDark = Color(0xFF1A1C1B);
  static const backgroundDark = Color(0xFF0D1214);
  static const cardDark = Color(0xFF1E2628);
  static const inputDark = Color(0xFF283235);
  static const outlineDark = Color(0xFF4C5D61);
}

/// Helper: subtle drop shadow for cards
const _softShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x0A000000), // 4% black, much softer
    blurRadius: 10,
    offset: Offset(0, 4),
  ),
];

/// A ThemeExtension for shared card shadows.
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

/// All theme data consolidated in one class.
class BrandTheme {
  final _textTheme = GoogleFonts.interTextTheme();

  final ColorScheme lightColorScheme = ColorScheme.fromSeed(
    seedColor: BrandColors.brandTeal,
    brightness: Brightness.light,
  ).copyWith(
    primary: BrandColors.brandTeal,
    onPrimary: BrandColors.white,
    primaryContainer: BrandColors.brandTeal.withValues(alpha:0.1),
    onPrimaryContainer: BrandColors.brandTealDark,
    secondary: BrandColors.brandBlue,
    onSecondary: BrandColors.white,
    surface: BrandColors.white,
    onSurface: BrandColors.ink,
    background: BrandColors.offWhite,
    onBackground: BrandColors.ink,
    outline: BrandColors.outline,
  );

  final ColorScheme darkColorScheme = ColorScheme.fromSeed(
    seedColor: BrandColors.brandTeal,
    brightness: Brightness.dark,
  ).copyWith(
    primary: BrandColors.brandTeal,
    onPrimary: BrandColors.white,
    primaryContainer: BrandColors.brandTeal.withValues(alpha:0.2),
    onPrimaryContainer: Colors.black,
    secondary: BrandColors.brandBlue,
    onSecondary: BrandColors.white,
    surface: BrandColors.surfaceDark,
    onSurface: BrandColors.offWhite,
    background: BrandColors.backgroundDark,
    onBackground: BrandColors.offWhite,
    outline: BrandColors.outlineDark,
  );

  late final _lightTheme = _baseTheme(lightColorScheme).copyWith(
    textTheme: _textTheme.copyWith(
      bodyMedium: _textTheme.bodyMedium?.copyWith(
        color: BrandColors.inkMuted,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: lightColorScheme.surface,
      foregroundColor: lightColorScheme.onSurface,
      titleTextStyle: _textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: lightColorScheme.onSurface,
      ),
    ),
    extensions: const <ThemeExtension<dynamic>>[
      _CardShadow(shadow: _softShadow),
    ],
  );

  late final _darkTheme = _baseTheme(darkColorScheme).copyWith(
    textTheme: _textTheme.copyWith(
      bodyLarge: _textTheme.bodyLarge?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      bodyMedium: _textTheme.bodyMedium?.copyWith(
        color: darkColorScheme.onSurface.withValues(alpha:0.7),
      ),
      bodySmall: _textTheme.bodySmall?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      titleLarge: _textTheme.titleLarge?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      titleMedium: _textTheme.titleMedium?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      titleSmall: _textTheme.titleSmall?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      headlineLarge: _textTheme.headlineLarge?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      headlineMedium: _textTheme.headlineMedium?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      headlineSmall: _textTheme.headlineSmall?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      labelLarge: _textTheme.labelLarge?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      labelMedium: _textTheme.labelMedium?.copyWith(
        color: darkColorScheme.onSurface,
      ),
      labelSmall: _textTheme.labelSmall?.copyWith(
        color: darkColorScheme.onSurface,
      ),
    ),
    scaffoldBackgroundColor: darkColorScheme.background,
    cardTheme: CardThemeData(
      color: BrandColors.cardDark,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: darkColorScheme.surface,
      foregroundColor: darkColorScheme.onSurface,
      titleTextStyle: _textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: darkColorScheme.onSurface,
      ),
    ),
    extensions: const <ThemeExtension<dynamic>>[
      _CardShadow(shadow: []),
    ],
  );

  ThemeData get lightTheme => _lightTheme;
  ThemeData get darkTheme => _darkTheme;

  ThemeData _baseTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(width: 1.5, color: scheme.primary),
        ),
        labelStyle: TextStyle(color: scheme.onSurface),
        hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha:0.7)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.primary.withValues(alpha:0.5);
            }
            return scheme.primary;
          }),
          foregroundColor: WidgetStateProperty.all(scheme.onPrimary),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          textStyle: WidgetStateProperty.all(
            GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

// How to use it:
// MaterialApp(
//   theme: BrandTheme().lightTheme,
//   darkTheme: BrandTheme().darkTheme,
//   themeMode: ThemeMode.system,
// );