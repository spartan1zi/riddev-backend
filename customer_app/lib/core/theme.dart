import 'package:flutter/material.dart';

/// RidDev customer app — depth via elevation, rounded shapes, and a warm/trust palette.
final riddevTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF1565C0),
    primary: const Color(0xFF0D47A1),
    secondary: const Color(0xFF00838F),
    tertiary: const Color(0xFF6A1B9A),
    brightness: Brightness.light,
    surface: const Color(0xFFF8FAFC),
    surfaceContainerHighest: const Color(0xFFE2E8F0),
  ),
  fontFamily: null,
  textTheme: const TextTheme(
    headlineLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    headlineMedium: TextStyle(fontWeight: FontWeight.w700),
    titleLarge: TextStyle(fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(height: 1.45),
  ),
  appBarTheme: AppBarTheme(
    centerTitle: true,
    elevation: 0,
    scrolledUnderElevation: 2,
    backgroundColor: const Color(0xFFF8FAFC),
    surfaceTintColor: const Color(0xFF1565C0).withOpacity(0.08),
  ),
  cardTheme: CardThemeData(
    elevation: 3,
    shadowColor: Colors.black.withOpacity(0.12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    clipBehavior: Clip.antiAlias,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  searchBarTheme: SearchBarThemeData(
    elevation: WidgetStateProperty.all(2),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);
