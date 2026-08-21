import "package:flutter/material.dart";

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static ColorScheme offBlackScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFFFFFF),
      surfaceTint: Color(0xFFFFFFFF),
      onPrimary: Color(0xFF000000),
      primaryContainer: Color(0xFF1E2638),
      onPrimaryContainer: Color(0xFFFFFFFF),
      secondary: Color(0xFFE5E7EB),
      onSecondary: Color(0xFF000000),
      secondaryContainer: Color(0xFF1E2638),
      onSecondaryContainer: Color(0xFFFFFFFF),
      tertiary: Color(0xFFD1D5DB),
      onTertiary: Color(0xFF000000),
      tertiaryContainer: Color(0xFF1E2638),
      onTertiaryContainer: Color(0xFFFFFFFF),
      error: Color(0xFFFF5252),
      onError: Color(0xFF000000),
      errorContainer: Color(0xFF3E1418),
      onErrorContainer: Color(0xFFFF5252),
      surface: Color(0xFF121622),
      onSurface: Color(0xFFFFFFFF),
      onSurfaceVariant: Color(0xFF9CA3AF),
      outline: Color(0xFF1F2636),
      outlineVariant: Color(0xFF2A3448),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFFFFFFF),
      inversePrimary: Color(0xFF0B0C10),
    );
  }

  ThemeData dark() {
    final scheme = offBlackScheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B0C10),
      canvasColor: const Color(0xFF0B0C10),
      cardColor: const Color(0xFF121622),
      dialogBackgroundColor: const Color(0xFF121622),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF10131B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1A202C),
        selectedColor: Colors.white,
        secondarySelectedColor: Colors.white,
        labelStyle: const TextStyle(color: Colors.white),
        secondaryLabelStyle: const TextStyle(color: Colors.black),
      ),
    );
  }

  ThemeData light() => dark();
}
