import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/estadisticas_screen.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

const _respuesta = {
  'desde': '2026-10-20',
  'hasta': '2026-11-18',
  'nacional': false,
  'focos': {
    'total': 2006,
    'por_fuente': [
      {'clave': 'INPE_QUEIMADAS', 'cantidad': 1452},
      {'clave': 'NASA_FIRMS', 'cantidad': 554},
    ],
    'por_departamento': [
      {'clave': 'Vichada', 'cantidad': 1029},
      {'clave': null, 'cantidad': 3},
    ],
    'por_dia': [
      {'dia': '2026-11-17', 'cantidad': 1325},
      {'dia': '2026-11-18', 'cantidad': 681},
    ],
  },
  'alertas': {
    'total': 1,
    'por_tipo': [
      {'clave': 'validacion_manual', 'cantidad': 1},
    ],
    'por_departamento': [],
  },
  'reportes': {'total': 0, 'por_estado': []},
};

Future<List<Uri>> _montar(WidgetTester t, {required String rol, http.Response? respuesta}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pedidas = <Uri>[];
  final api = VigiaApi(
    baseUrl: Uri.parse('https://vigia.test/api/'),
    cliente: MockClient((r) async {
      if (r.url.path.endsWith('auth/token/')) return _json({'access': jwtFalso(rol: rol), 'refresh': 'r'});
      pedidas.add(r.url);
      return respuesta ?? _json(_respuesta);
    }),
  );
  final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
  await auth.iniciarSesion('ana', 'clave');
  await t.pumpWidget(MultiProvider(
    providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
    child: const MaterialApp(home: EstadisticasScreen()),
  ));
  await t.pumpAndSettle();
  return pedidas;
}

void main() {
  testWidgets('muestra totales, desgloses con etiquetas legibles y la jurisdicción', (t) async {
    final pedidas = await _montar(t, rol: 'administrador');

    expect(pedidas.single.queryParameters.keys, containsAll(['desde', 'hasta']));
    expect(find.textContaining('Jurisdicción de tu entidad'), findsOneWidget);
    expect(find.text('2.006'), findsOneWidget);
    expect(find.text('INPE QUEIMADAS'), findsOneWidget);
    expect(find.text('Vichada'), findsOneWidget);
    expect(find.text('Fuera de los municipios cargados'), findsOneWidget);
    expect(find.text('Validación manual'), findsOneWidget);
    expect(find.text('Máximo: 1.325 el 17/11/2026'), findsOneWidget);
    // Sin reportes: la sección lo dice en vez de quedar vacía.
    expect(find.text('Sin datos en el periodo.'), findsOneWidget);
  });

  testWidgets('cambiar el periodo vuelve a consultar con el nuevo rango', (t) async {
    final pedidas = await _montar(t, rol: 'staff');
    await t.tap(find.text('7 días'));
    await t.pumpAndSettle();

    expect(pedidas, hasLength(2));
    final desde = DateTime.parse(pedidas.last.queryParameters['desde']!);
    final hasta = DateTime.parse(pedidas.last.queryParameters['hasta']!);
    expect(hasta.difference(desde).inDays, 6);
  });

  testWidgets('un ciudadano ve el mensaje de permiso de la API', (t) async {
    final pedidas = await _montar(t, rol: 'ciudadano', respuesta: _json({'detail': 'No.'}, 403));
    expect(find.text('No tienes permiso para realizar esta acción.'), findsOneWidget);
    // El error ofrece reintentar la misma consulta.
    await t.tap(find.text('Reintentar'));
    await t.pumpAndSettle();
    expect(pedidas, hasLength(2));
  });
}
