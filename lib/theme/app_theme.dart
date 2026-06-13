import 'package:flutter/material.dart';

class AppTheme {
  static final _brown = Colors.brown.shade500;

  // Light theme
  static final lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _brown,
      brightness: Brightness.light,
    ),
    // Use system fonts for better performance
    fontFamily: 'Roboto',
  );

  // Dark theme (default)
  static final darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _brown,
      brightness: Brightness.dark,
    ),
    // Use system fonts for better performance
    fontFamily: 'Roboto',
  );
}