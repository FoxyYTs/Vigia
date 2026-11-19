import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/panel_screen.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

/// Abre el panel; las demás rutas muestran su nombre, para comprobar la navegación.
Future<AuthProvider> _abrirPanel(WidgetTester t, String rol, {http.Response? perfil, double ancho = 1280}) async {
  t.view.physicalSize = Size(ancho, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);

  final api = VigiaApi(
    baseUrl: Uri.parse('https://vigia.test/api/'),
    cliente: MockClient((r) async => r.url.path.endsWith('auth/token/')
        ? _json({'access': jwtFalso(username: 'ana', rol: rol), 'refresh': 'r'})
        : perfil ?? _json({'id': 1, 'username': 'ana', 'email': 'ana@vigia.test', 'rol': rol})),
  );
  final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
  await auth.iniciarSesion('ana', 'clave');

  await t.pumpWidget(MultiProvider(
    providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
    child: MaterialApp(
      key: UniqueKey(),
      home: const PanelScreen(),
      onGenerateRoute: (ajustes) => MaterialPageRoute(builder: (_) => Text('RUTA ${ajustes.name}')),
    ),
  ));
  await t.pumpAndSettle();
  return auth;
}

const _gestion = [
  'Gestionar Permisos',
  'Gestionar Estadísticas',
  'Gestionar Históricos',
  'Gestionar Informes',
  'Gestionar Bot de Telegram',
];

void main() {
  testWidgets('el ciudadano solo ve los bloques que puede usar', (t) async {
    await _abrirPanel(t, 'ciudadano');

    expect(find.text('Gestionar Usuario'), findsOneWidget);
    expect(find.text('Gestionar Reportar Focos de Incendios'), findsOneWidget);
    for (final bloque in _gestion) {
      expect(find.text(bloque), findsNothing, reason: bloque);
    }
    expect(find.text('ana@vigia.test'), findsOneWidget);
  });

  testWidgets('el administrador ve los bloques del mapa de navegación, incluido Gestionar Permisos', (t) async {
    await _abrirPanel(t, 'administrador');

    for (final bloque in ['Gestionar Usuario', 'Gestionar Reportar Focos de Incendios', ..._gestion]) {
      expect(find.text(bloque), findsOneWidget, reason: bloque);
    }
    // Perfil real en Gestionar Usuario.
    expect(find.text('ana@vigia.test'), findsOneWidget);
  });

  testWidgets('cada bloque abre su pantalla, incluida la subpágina de permisos', (t) async {
    for (final (bloque, ruta) in [('Gestionar Informes', '/informes'), ('Gestionar Permisos', '/permisos')]) {
      await _abrirPanel(t, 'staff');
      await t.tap(find.text(bloque));
      await t.pumpAndSettle();
      expect(find.text('RUTA $ruta'), findsOneWidget, reason: bloque);
    }
  });

  testWidgets('cerrar sesión vuelve al mapa sin sesión', (t) async {
    final auth = await _abrirPanel(t, 'ciudadano');
    await t.tap(find.text('Cerrar sesión'));
    await t.pumpAndSettle();
    expect(auth.estado, EstadoSesion.anonima);
    expect(find.text('Sesión cerrada.'), findsOneWidget);
  });

  testWidgets('si el perfil no carga, lo dice', (t) async {
    await _abrirPanel(t, 'ciudadano', perfil: _json({'detail': 'x'}, 500));
    expect(find.text('El servidor de Vigía tuvo un problema. Inténtalo más tarde.'), findsOneWidget);
  });

  testWidgets('en el celular la barra usa íconos con tooltip y no se desborda', (t) async {
    await _abrirPanel(t, 'ciudadano', ancho: 360);
    expect(find.byTooltip('Mapa Interactivo'), findsOneWidget);
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
