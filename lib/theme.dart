import "package:flutter/material.dart";

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static ColorScheme customXmlScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFFFFFF),
      surfaceTint: Color(0xFFFFFFFF),
      onPrimary: Color(0xFF000000),
      primaryContainer: Color(0xFF1F222B),
      onPrimaryContainer: Color(0xFFFFFFFF),
      secondary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFF000000),
      secondaryContainer: Color(0xFF1F222B),
      onSecondaryContainer: Color(0xFFFFFFFF),
      tertiary: Color(0xFFFFFFFF),
      onTertiary: Color(0xFF000000),
      tertiaryContainer: Color(0xFF1F222B),
      onTertiaryContainer: Color(0xFFFFFFFF),
      error: Color(0xFFFF5252),
      onError: Color(0xFF000000),
      errorContainer: Color(0xFF93000a),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF0B0C10),
      onSurface: Color(0xFFFFFFFF),
      onSurfaceVariant: Color(0xFFB0B8C0),
      outline: Color(0xFF1F2430),
      outlineVariant: Color(0xFF303644),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFFFFFFF),
      inversePrimary: Color(0xFF0B0C10),
    );
  }

  ThemeData dark() {
    final scheme = customXmlScheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B0C10),
      canvasColor: const Color(0xFF0B0C10),
      cardColor: const Color(0xFF0B0C10),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B0C10),
        foregroundColor: Colors.white,
      ),
    );
  }
}
