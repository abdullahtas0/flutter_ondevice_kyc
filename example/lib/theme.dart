import 'package:flutter/material.dart';

const ink = Color(0xFFF2F0E8);
const muted = Color(0xFF8C9386);
const stage = Color(0xFF070807);
const panel = Color(0xFF1A1E1B);
const line = Color(0xFF2C332C);
const lockGreen = Color(0xFF3DDC97);
const lockDeep = Color(0xFF146B45);
const holdAmber = Color(0xFFD7A441);

ThemeData buildKycTheme() {
  const scheme = ColorScheme.dark(
    surface: Color(0xFF121410),
    primary: lockGreen,
    onPrimary: Color(0xFF062116),
    secondary: holdAmber,
    onSecondary: Color(0xFF1C1404),
    error: holdAmber,
    onSurface: ink,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: scheme.surface,
    colorScheme: scheme,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: ink, height: 1.35),
      bodySmall: TextStyle(color: muted, height: 1.35),
      titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      labelStyle: const TextStyle(color: muted),
      hintStyle: const TextStyle(color: muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: lockGreen),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: lockDeep,
        foregroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
  );
}

const mrzStyle = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['Courier', 'monospace'],
  fontSize: 13,
  height: 1.4,
  color: ink,
);
