import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/historicos_screen.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

const _resumen = {
  'ungrd': {
    'total': 4210,
    'sin_municipio': 12,
    'desde': '2019-01-02',
    'hasta': '2024-12-30',
    'por_anio': [
      {'anio': 2019, 'cantidad': 1500, 'hectareas': 20500.4},
      {'anio': 2020, 'cantidad': 2710, 'hectareas': null},
    ],
  },
  'ideam': {'por_anio': []},
  'firms': {
    'total': 879000,
    'por_anio': [
      {'anio': 2018, 'cantidad': 879000},
    ],
  },
};

Future<List<http.Request>> _montar(WidgetTester t, {required String rol}) async {
  t.view.physicalSize = const Size(900, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pedidas = <http.Request>[];
  final api = VigiaApi(
    baseUrl: Uri.parse('https://vigia.test/api/'),
    cliente: MockClient((r) async {
      if (r.url.path.endsWith('auth/token/')) return _json({'access': jwtFalso(rol: rol), 'refresh': 'r'});
      pedidas.add(r);
      return r.method == 'POST' ? _json({'detail': 'ok'}, 202) : _json(_resumen);
    }),
  );
  final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
  await auth.iniciarSesion('ana', 'clave');
  await t.pumpWidget(MultiProvider(
    providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
    child: const MaterialApp(home: HistoricosScreen()),
  ));
  await t.pumpAndSettle();
  return pedidas;
}

void main() {
  testWidgets('muestra cada fuente con su tabla por año', (t) async {
    await _montar(t, rol: 'administrador');

    expect(find.text('4.210 incendios · del 02/01/2019 al 30/12/2024 · 12 sin municipio'), findsOneWidget);
    expect(find.text('20.500'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Sin datos cargados.'), findsOneWidget);
    expect(find.text('879.000 detecciones'), findsOneWidget);
    // El administrador no actualiza la UNGRD: es una fuente nacional.
    expect(find.text('Actualizar desde datos.gov.co'), findsNothing);
  });

  testWidgets('el staff encola la actualización de la UNGRD', (t) async {
    final pedidas = await _montar(t, rol: 'staff');

    await t.tap(find.text('Actualizar desde datos.gov.co'));
    await t.pumpAndSettle();

    expect(pedidas.last.method, 'POST');
    expect(pedidas.last.url.path, '/api/historico/ungrd/sincronizar/');
    expect(find.textContaining('Actualización en curso'), findsOneWidget);
  });
}
