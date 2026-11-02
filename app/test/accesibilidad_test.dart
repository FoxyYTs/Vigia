/// Pautas de accesibilidad automáticas (WCAG 2.2 AA, Ley 1618 de 2013): áreas
/// táctiles de al menos 48 px, controles con etiqueta y contraste de texto.
library;

import 'dart:convert';

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

Future<void> _cumplePautas(WidgetTester t, Widget pantalla) async {
  final semantica = t.ensureSemantics();
  await t.pumpWidget(MultiProvider(
    providers: [
      Provider.value(value: _api),
      ChangeNotifierProvider(create: (_) => AuthProvider(api: _api, almacen: AlmacenTokensMemoria())),
      ChangeNotifierProvider(create: (_) => PrediccionProvider(api: _api)),
      ChangeNotifierProvider(create: (_) => HistoricoProvider(api: _api)),
    ],
    child: MaterialApp(theme: construirTemaVigia(), home: pantalla),
  ));
  await t.pumpAndSettle();
  await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(t, meetsGuideline(textContrastGuideline));
  semantica.dispose();
}

void main() {
  testWidgets('inicio de sesión', (t) => _cumplePautas(t, const LoginScreen()));

  testWidgets('paneles de predicción e histórico', (t) => _cumplePautas(
        t,
        const Scaffold(body: SingleChildScrollView(child: Column(children: [PanelPrediccion(), PanelHistorico()]))),
      ));

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
