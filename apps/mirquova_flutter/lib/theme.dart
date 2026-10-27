import 'package:flutter/material.dart';

ThemeData mirquovaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF215C45),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFA4D8B8) : const Color(0xFF215C45),
        primaryContainer: dark
            ? const Color(0xFF203F31)
            : const Color(0xFFE2EDE0),
        onPrimaryContainer: dark
            ? const Color(0xFFBDE6CC)
            : const Color(0xFF163E2C),
        secondaryContainer: dark
            ? const Color(0xFF4A3C22)
            : const Color(0xFFF3E7C7),
        onSecondaryContainer: dark
            ? const Color(0xFFF2DEAA)
            : const Color(0xFF4A3C16),
        onPrimary: dark ? const Color(0xFF103827) : Colors.white,
        surface: dark ? const Color(0xFF141C18) : const Color(0xFFF6F8F4),
        secondary: dark ? const Color(0xFFE2C781) : const Color(0xFF71581A),
      );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20),
    side: BorderSide(color: scheme.outlineVariant),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      selectedLabelTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
