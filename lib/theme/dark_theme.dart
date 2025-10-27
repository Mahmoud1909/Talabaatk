// lib/themes/dark_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color kPrimaryColor = Color(0xFF25AA50);

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: kPrimaryColor,

  // ColorScheme respects primary and secondary shades for material widgets
  colorScheme: ColorScheme.fromSeed(
    seedColor: kPrimaryColor,
    brightness: Brightness.dark,
    secondary: Colors.deepOrangeAccent,
  ).copyWith(primary: kPrimaryColor),

  // Scaffold and surfaces
  scaffoldBackgroundColor: const Color(0xFF0B0B0B),
  canvasColor: const Color(0xFF0B0B0B),
  cardColor: const Color(0xFF121212),
  dialogBackgroundColor: const Color(0xFF141414),

  // App bar styling: keep status bar behind battery same tint as app bar
  appBarTheme: const AppBarTheme(
    backgroundColor: kPrimaryColor,
    foregroundColor: Colors.white,
    elevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: kPrimaryColor, // status bar behind battery
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  ),

  // Buttons
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimaryColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: kPrimaryColor,
      side: BorderSide(color: kPrimaryColor.withOpacity(0.85)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),

  // Dividers and shadows
  dividerColor: Colors.grey.shade800,
  shadowColor: Colors.black.withOpacity(0.6),

  // Typography: use the material 2021 palette for dark text
  textTheme: Typography.material2021().white.copyWith(
    bodyLarge: Typography.material2021().white.bodyLarge?.copyWith(color: Colors.white),
    bodyMedium:
    Typography.material2021().white.bodyMedium?.copyWith(color: Colors.white70),
    titleLarge:
    Typography.material2021().white.titleLarge?.copyWith(color: Colors.white),
  ),

  // Input, chip, and card defaults for consistent look
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF1B1B1B),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
  ),

  cardTheme: const CardThemeData(
    color: Color(0xFF121212),
    elevation: 3,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  ),


  // Keep splash effects subtle on dark
  splashFactory: InkRipple.splashFactory,
  visualDensity: VisualDensity.adaptivePlatformDensity,
  useMaterial3: false,
);
