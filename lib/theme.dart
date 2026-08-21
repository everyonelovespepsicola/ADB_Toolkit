import "package:flutter/material.dart";

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static ColorScheme offWhiteScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF000000),
      surfaceTint: Color(0xFF000000),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFE5E7EB),
      onPrimaryContainer: Color(0xFF000000),
      secondary: Color(0xFF111827),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE5E7EB),
      onSecondaryContainer: Color(0xFF000000),
      tertiary: Color(0xFF1F2937),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFE5E7EB),
      onTertiaryContainer: Color(0xFF000000),
      error: Color(0xFFFF5252),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFEBEE),
      onErrorContainer: Color(0xFFDC2626),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF000000),
      onSurfaceVariant: Color(0xFF4B5563),
      outline: Color(0xFFD1D5DB),
      outlineVariant: Color(0xFFE5E7EB),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF111827),
      inversePrimary: Color(0xFFFFFFFF),
    );
  }

  ThemeData light() {
    final scheme = offWhiteScheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF3F4F6),
      canvasColor: const Color(0xFFF3F4F6),
      cardColor: const Color(0xFFFFFFFF),
      dialogBackgroundColor: const Color(0xFFFFFFFF),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFE5E7EB),
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE5E7EB),
        selectedColor: Colors.black,
        secondarySelectedColor: Colors.black,
        labelStyle: const TextStyle(color: Colors.black),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
      ),
    );
  }

  ThemeData dark() => light(); // Enforce clean Black on Off-White theme
}
