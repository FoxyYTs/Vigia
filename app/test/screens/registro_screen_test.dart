import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/registro_screen.dart';
import 'package:vigia_app/screens/rutas.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

const _municipios = [
  {'id': 1, 'nombre': 'Rionegro', 'departamento': 'Antioquia', 'codigo_dane': '05615'},
  {'id': 2, 'nombre': 'Medellín', 'departamento': 'Antioquia', 'codigo_dane': '05001'},
  {'id': 3, 'nombre': 'Pore', 'departamento': 'Casanare', 'codigo_dane': '85263'},
];

Future<(List<http.Request>, AuthProvider, List<int>)> _montar(
  WidgetTester t, {
  http.Response Function(http.Request)? registro,
}) async {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pedidas = <http.Request>[];
  final politica = <int>[];
  final api = VigiaApi(
    baseUrl: Uri.parse('https://vigia.test/api/'),
    cliente: MockClient((r) async {
      pedidas.add(r);
      if (r.url.path.endsWith('municipios/')) return _json(_municipios);
      if (r.url.path.endsWith('auth/registro/')) return registro?.call(r) ?? _json({'id': 9}, 201);
      if (r.url.path.endsWith('auth/token/')) return _json({'access': jwtFalso(username: 'nuevo'), 'refresh': 'r'});
      return _json({});
    }),
  );
  final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
  await t.pumpWidget(MultiProvider(
    providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
    child: MaterialApp(
      home: RegistroScreen(abrirPolitica: () async => politica.add(1)),
      routes: {Rutas.panel: (_) => const Scaffold(body: Text('pantalla-panel'))},
    ),
  ));
  await t.pumpAndSettle();
  return (pedidas, auth, politica);
}

Future<void> _llenar(WidgetTester t, {String confirmacion = 'clave-segura-9'}) async {
  final campos = find.byType(TextFormField);
  await t.enterText(campos.at(0), 'nuevo');
  await t.enterText(campos.at(1), 'nuevo@correo.co');
  await t.enterText(campos.at(2), 'clave-segura-9');
  await t.enterText(campos.at(3), confirmacion);
}

void main() {
  testWidgets('valida el formulario y exige aceptar la política', (t) async {
    final (pedidas, _, _) = await _montar(t);

    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();
    expect(find.text('Escribe tu nombre de usuario.'), findsOneWidget);
    expect(find.text('Escribe un correo válido.'), findsOneWidget);

    await _llenar(t, confirmacion: 'otra-clave');
    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);

    await _llenar(t);
    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();
    expect(find.text('Debes aceptar la política de tratamiento de datos.'), findsOneWidget);
    expect(pedidas.where((r) => r.url.path.endsWith('registro/')), isEmpty);
  });

  testWidgets('registra con el municipio elegido, inicia sesión y abre el panel', (t) async {
    final (pedidas, auth, politica) = await _montar(t);

    await _llenar(t);
    await t.tap(find.text('Departamento (opcional)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Antioquia').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Municipio'));
    await t.pumpAndSettle();
    await t.tap(find.text('Rionegro').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Leer la política de datos'));
    await t.tap(find.byType(Checkbox));
    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();

    final registro = pedidas.firstWhere((r) => r.url.path.endsWith('auth/registro/'));
    expect(jsonDecode(registro.body), {
      'username': 'nuevo',
      'email': 'nuevo@correo.co',
      'password': 'clave-segura-9',
      'municipio_residencia': 1,
      'acepto_politica': true,
    });
    expect(politica, [1]);
    expect(auth.username, 'nuevo');
    expect(find.text('pantalla-panel'), findsOneWidget);
  });

  testWidgets('muestra el primer error de la API (p. ej. usuario repetido)', (t) async {
    await _montar(t, registro: (_) => _json({'username': ['Ya existe un usuario con este nombre.']}, 400));

    await _llenar(t);
    await t.tap(find.byType(Checkbox));
    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();
    expect(find.text('Ya existe un usuario con este nombre.'), findsOneWidget);
  });
}
