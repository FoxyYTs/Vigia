/// Pautas de accesibilidad automáticas (WCAG 2.2 AA, Ley 1618 de 2013): áreas
/// táctiles de al menos 48 px, controles con etiqueta y contraste de texto.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/core/theme/vigia_theme.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/models/foco.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/providers/historico_provider.dart';
import 'package:vigia_app/providers/prediccion_provider.dart';
import 'package:vigia_app/screens/login_screen.dart';
import 'package:vigia_app/screens/mapa_screen.dart';
import 'package:vigia_app/widgets/panel_filtros.dart';

final _api = VigiaApi(
  baseUrl: Uri.parse('https://vigia.test/api/'),
  cliente: MockClient((_) async => http.Response(jsonEncode({'meses': []}), 200)),
);

Future<void> _cumplePautas(WidgetTester t, Widget pantalla, {Brightness brillo = Brightness.light}) async {
  final semantica = t.ensureSemantics();
  await t.pumpWidget(MultiProvider(
    providers: [
      Provider.value(value: _api),
      ChangeNotifierProvider(create: (_) => AuthProvider(api: _api, almacen: AlmacenTokensMemoria())),
      ChangeNotifierProvider(create: (_) => PrediccionProvider(api: _api)),
      ChangeNotifierProvider(create: (_) => HistoricoProvider(api: _api)),
    ],
    child: MaterialApp(theme: construirTemaVigia(brillo: brillo), home: pantalla),
  ));
  await t.pumpAndSettle();
  await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(t, meetsGuideline(textContrastGuideline));
  semantica.dispose();
}

void main() {
  for (final brillo in Brightness.values) {
    testWidgets('inicio de sesión (${brillo.name})', (t) => _cumplePautas(t, const LoginScreen(), brillo: brillo));

    testWidgets('paneles de predicción e histórico (${brillo.name})', (t) => _cumplePautas(
          t,
          const Scaffold(body: SingleChildScrollView(child: Column(children: [PanelPrediccion(), PanelHistorico()]))),
          brillo: brillo,
        ));
  }

  // textContrastGuideline solo mira el texto pintado; aquí van los pares del
  // esquema que usan las pantallas, en los dos temas (texto ≥ 4,5:1).
  for (final brillo in Brightness.values) {
    test('contraste del esquema ${brillo.name}', () {
      final tema = construirTemaVigia(brillo: brillo);
      final c = tema.colorScheme;
      double contraste(Color a, Color b) {
        final (la, lb) = (a.computeLuminance(), b.computeLuminance());
        return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
      }

      for (final fondo in [c.surface, tema.scaffoldBackgroundColor, tema.cardTheme.color!]) {
        for (final texto in [c.onSurface, c.onSurfaceVariant, c.primary, c.secondary, c.error]) {
          expect(contraste(texto, fondo), greaterThanOrEqualTo(4.5), reason: '$texto sobre $fondo');
        }
        expect(contraste(c.outline, fondo), greaterThanOrEqualTo(3), reason: 'bordes de los campos');
      }
      for (final (texto, fondo) in [
        (c.onPrimary, c.primary),
        (c.onPrimaryContainer, c.primaryContainer),
        (c.onErrorContainer, c.errorContainer),
        (c.onTertiaryContainer, c.tertiaryContainer),
      ]) {
        expect(contraste(texto, fondo), greaterThanOrEqualTo(4.5), reason: '$texto sobre $fondo');
      }
      // Íconos y leyendas de cada fuente: componente gráfico, basta 3:1.
      for (final f in FuenteSatelital.values) {
        expect(contraste(colorFuente(f, brillo), c.surface), greaterThanOrEqualTo(3), reason: '$f');
      }
      // Barra de progreso de Estadísticas: componente gráfico, basta 3:1.
      expect(contraste(c.secondary, c.tertiaryContainer), greaterThanOrEqualTo(3));
    });
  }

  testWidgets('lista de focos (alternativa al mapa)', (t) async {
    final foco = Foco(
      id: 1,
      fuente: FuenteSatelital.nasaFirms,
      posicion: const LatLng(6.15, -75.37),
      fechaHora: DateTime.utc(2026, 11, 1, 12),
      confianza: 'n',
    );
    Foco? elegido;
    await _cumplePautas(t, Scaffold(body: ListaFocos(focos: [foco], onElegir: (f) => elegido = f)));
    await t.tap(find.textContaining('NASA FIRMS'));
    expect(elegido, foco);
  });
}
