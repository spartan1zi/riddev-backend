import 'package:flutter/material.dart';

/// RidDev Worker — elevated cards, rounded inputs, teal-forward palette (work / field).
final workerTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF00695C),
    primary: const Color(0xFF004D40),
    secondary: const Color(0xFFF57C00),
    tertiary: const Color(0xFF1565C0),
    brightness: Brightness.light,
    surface: const Color(0xFFF5F9F8),
    surfaceContainerHighest: const Color(0xFFDCE8E6),
  ),
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
    backgroundColor: const Color(0xFFF5F9F8),
    surfaceTintColor: const Color(0xFF00695C).withValues(alpha: 0.1),
  ),
  cardTheme: CardThemeData(
    elevation: 3,
    shadowColor: Colors.black.withValues(alpha: 0.12),
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
      borderSide: const BorderSide(color: Color(0xFF00695C), width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  navigationBarTheme: NavigationBarThemeData(
    elevation: 0,
    height: 72,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    indicatorColor: const Color(0xFF00695C).withValues(alpha: 0.16),
    indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const IconThemeData(color: Color(0xFF004D40), size: 26);
      }
      return IconThemeData(color: Colors.blueGrey.shade500, size: 24);
    }),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.15,
          color: Color(0xFF004D40),
        );
      }
      return TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 11,
        letterSpacing: 0.1,
        color: Colors.blueGrey.shade600,
      );
    }),
  ),
);
