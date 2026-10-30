import 'package:flutter/material.dart';

ThemeData mirquovaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  const primary = Color(0xFF3478F6);
  const primaryBright = Color(0xFF4C9BFF);
  const cyan = Color(0xFF22D3EE);
  const violet = Color(0xFF8B5CF6);
  final background = dark ? const Color(0xFF080D18) : const Color(0xFFF3F6FB);
  final surface = dark ? const Color(0xFF0E1728) : const Color(0xFFFFFFFF);
  final raised = dark ? const Color(0xFF142138) : const Color(0xFFF7F9FC);
  final hover = dark ? const Color(0xFF1A2B45) : const Color(0xFFE7EEF8);
  final border = dark ? const Color(0xFF22334D) : const Color(0xFFD5DEEB);
  final textPrimary = dark ? const Color(0xFFF4F7FC) : const Color(0xFF0E1728);
  final textSecondary = dark
      ? const Color(0xFFA7B4C8)
      : const Color(0xFF3E4E68);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xFF16325A) : const Color(0xFFE5EEFF),
    onPrimaryContainer: textPrimary,
    secondary: cyan,
    onSecondary: const Color(0xFF042028),
    secondaryContainer: dark
        ? const Color(0xFF12343C)
        : const Color(0xFFD9F7FB),
    onSecondaryContainer: dark
        ? const Color(0xFFD7F8FD)
        : const Color(0xFF08343A),
    tertiary: violet,
    onTertiary: Colors.white,
    tertiaryContainer: dark ? const Color(0xFF2C2154) : const Color(0xFFEDE7FF),
    onTertiaryContainer: textPrimary,
    error: const Color(0xFFF16B78),
    onError: const Color(0xFF2A0A10),
    surface: background,
    onSurface: textPrimary,
    onSurfaceVariant: textSecondary,
    outline: border,
    outlineVariant: border,
    surfaceContainerLowest: raised,
    surfaceContainerLow: surface,
    surfaceContainer: raised,
    surfaceContainerHigh: hover,
    surfaceContainerHighest: hover,
    shadow: Colors.black,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: BorderSide(color: border),
  );
  final base =
      (dark ? Typography.material2021().white : Typography.material2021().black)
          .apply(
            fontFamily: 'Roboto',
            bodyColor: textSecondary,
            displayColor: textPrimary,
          );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    fontFamily: 'Roboto',
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    textTheme: base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: textPrimary,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.4),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded,
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: hover,
      contentTextStyle: TextStyle(color: textPrimary, fontFamily: 'Roboto'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF0E1728) : Colors.white,
      labelStyle: TextStyle(color: textSecondary),
      hintStyle: TextStyle(
        color: dark ? const Color(0xFF71819A) : const Color(0xFF71819A),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryBright, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: primary.withValues(alpha: 0.38),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: primaryBright,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return border;
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.standard,
        side: WidgetStatePropertyAll(BorderSide(color: border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
  );
}
