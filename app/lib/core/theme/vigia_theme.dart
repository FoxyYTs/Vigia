import 'package:flutter/material.dart';

/// Paleta del design system "Vigía — Alertas ambientales" (Stitch, ver
/// app/design/README.md). Todos los pares texto/fondo cumplen WCAG AA
/// (contraste ≥ 4.5:1).
class VigiaColors {
  const VigiaColors._();

  static const bosque = Color(0xFF1B5E3A); // primario (app bar, botones)
  static const bosqueOscuro = Color(0xFF004526);
  static const bosqueClaro = Color(0xFFAEF2C2);
  static const fuego = Color(0xFFB4410F); // acento de alerta
  static const fuegoClaro = Color(0xFFFFDBCF);
  static const superficie = Color(0xFFF4F6F3);
  static const borde = Color(0xFFD5DBD3);
  static const texto = Color(0xFF1A1F1C);
  static const textoSecundario = Color(0xFF404942);
  static const error = Color(0xFFB3261E);

  /// Color de cada fuente satelital en el mapa (siempre acompañado de la
  /// leyenda: el color nunca es la única señal).
  static const firms = Color(0xFFD9531E);
  static const inpe = Color(0xFF7B1E5A);
}

ThemeData construirTemaVigia() {
  final esquema = ColorScheme.fromSeed(
    seedColor: VigiaColors.bosque,
    primary: VigiaColors.bosque,
    onPrimary: Colors.white,
    secondary: VigiaColors.fuego,
    onSecondary: Colors.white,
    error: VigiaColors.error,
    surface: Colors.white,
    onSurface: VigiaColors.texto,
  );

  const radio = BorderRadius.all(Radius.circular(8));

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: VigiaColors.superficie,
    appBarTheme: const AppBarTheme(
      backgroundColor: VigiaColors.bosque,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radio,
        side: BorderSide(color: VigiaColors.borde),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radio),
      enabledBorder: OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: Color(0xFF707971)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: VigiaColors.bosque, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: VigiaColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: VigiaColors.error, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VigiaColors.bosque,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        shape: const RoundedRectangleBorder(borderRadius: radio),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VigiaColors.bosque,
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: VigiaColors.borde),
        shape: const RoundedRectangleBorder(borderRadius: radio),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: radio),
      side: BorderSide(color: VigiaColors.borde),
    ),
  );
}
