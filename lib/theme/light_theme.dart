// lib/themes/light_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color kPrimaryColor = Color(0xFFFF5C01);

final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  primaryColor: kPrimaryColor,

  // ColorScheme based on primary swatch
  colorScheme: ColorScheme.fromSeed(
    seedColor: kPrimaryColor,
    brightness: Brightness.light,
    secondary: Colors.deepOrangeAccent,
  ).copyWith(primary: kPrimaryColor),

  // Scaffold and surfaces
  scaffoldBackgroundColor: Colors.white,
  canvasColor: Colors.white,
  cardColor: Colors.white,
  dialogBackgroundColor: Colors.white,

  // App bar + status bar: keep status bar behind battery same tint as app bar
  appBarTheme: const AppBarTheme(
    backgroundColor: kPrimaryColor,
    foregroundColor: Colors.white,
    elevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: kPrimaryColor,
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
      side: BorderSide(color: kPrimaryColor.withOpacity(0.95)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),

  // Dividers and shadows
  dividerColor: Colors.grey.shade300,
  shadowColor: Colors.black.withOpacity(0.06),

  // Typography: light text theme (dark text on light background)
  textTheme: Typography.material2021().black.copyWith(
    bodyLarge: Typography.material2021().black.bodyLarge?.copyWith(color: const Color(0xFF0B0B0B)),
    bodyMedium:
    Typography.material2021().black.bodyMedium?.copyWith(color: const Color(0xFF3C3C3C)),
    titleLarge:
    Typography.material2021().black.titleLarge?.copyWith(color: const Color(0xFF0B0B0B)),
  ),

  // Input and card styling
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF7F7F7),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
  ),

  cardTheme: const CardThemeData(
    color: Color(0xFFFFFFFF),
    elevation: 3,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  ),


  // Subtle ripple for light
  splashFactory: InkRipple.splashFactory,
  visualDensity: VisualDensity.adaptivePlatformDensity,
  useMaterial3: false,
);
