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

/// Tema claro u oscuro con la misma marca. Las pantallas toman sus colores
/// del [ColorScheme] (no de [VigiaColors]) para servir en los dos; el claro
/// fija cada rol al color que ya usaba la app.
ThemeData construirTemaVigia({Brightness brillo = Brightness.light}) {
  final oscuro = brillo == Brightness.dark;
  final esquema = oscuro
      ? ColorScheme.fromSeed(
          seedColor: VigiaColors.bosque,
          brightness: Brightness.dark,
          secondary: const Color(0xFFFFB59B), // fuego aclarado: 4,5:1 sobre la superficie oscura
          onSecondary: const Color(0xFF5C1900),
          tertiaryContainer: const Color(0xFF7E2C05),
          onTertiaryContainer: VigiaColors.fuegoClaro,
        )
      : ColorScheme.fromSeed(
          seedColor: VigiaColors.bosque,
          primary: VigiaColors.bosque,
          onPrimary: Colors.white,
          primaryContainer: VigiaColors.bosqueClaro,
          onPrimaryContainer: VigiaColors.bosqueOscuro,
          secondary: VigiaColors.fuego,
          onSecondary: Colors.white,
          tertiaryContainer: VigiaColors.fuegoClaro,
          onTertiaryContainer: const Color(0xFF8A2A0A), // fuego oscurecido: 4,5:1 sobre fuegoClaro
          error: VigiaColors.error,
          errorContainer: const Color(0xFFFFDAD6),
          onErrorContainer: const Color(0xFF7A0E0A),
          surface: Colors.white,
          onSurface: VigiaColors.texto,
          onSurfaceVariant: VigiaColors.textoSecundario,
          outline: const Color(0xFF707971),
          outlineVariant: VigiaColors.borde,
        );
  final fondoTarjeta = oscuro ? esquema.surfaceContainer : esquema.surface;

  const radio = BorderRadius.all(Radius.circular(8));

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: oscuro ? esquema.surface : VigiaColors.superficie,
    // La barra de la marca es la misma en los dos temas (blanco sobre bosque, 7,6:1).
    appBarTheme: const AppBarTheme(
      backgroundColor: VigiaColors.bosque,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: fondoTarjeta,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radio,
        side: BorderSide(color: esquema.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fondoTarjeta,
      border: const OutlineInputBorder(borderRadius: radio),
      enabledBorder: OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: esquema.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: esquema.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: esquema.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: esquema.error, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: esquema.primary,
        foregroundColor: esquema.onPrimary,
        minimumSize: const Size(64, 48),
        shape: const RoundedRectangleBorder(borderRadius: radio),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: esquema.primary,
        minimumSize: const Size(64, 48),
        side: BorderSide(color: esquema.outlineVariant),
        shape: const RoundedRectangleBorder(borderRadius: radio),
      ),
    ),
    chipTheme: ChipThemeData(
      selectedColor: esquema.primaryContainer,
      shape: const RoundedRectangleBorder(borderRadius: radio),
      side: BorderSide(color: esquema.outlineVariant),
    ),
  );
}
