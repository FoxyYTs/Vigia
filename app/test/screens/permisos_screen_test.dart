import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/permisos_screen.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

final _usuarios = [
  {
    'id': 1, 'username': 'ana', 'email': 'ana@vigia.test', 'rol': 'staff', 'entidad': null,
    'entidad_nombre': null, 'is_active': true,
  },
  {
    'id': 2, 'username': 'beto', 'email': 'beto@x.co', 'rol': 'administrador', 'entidad': 7,
    'entidad_nombre': 'Cornare', 'is_active': true,
  },
  {
    'id': 3, 'username': 'carla', 'email': '', 'rol': 'ciudadano', 'entidad': null,
    'entidad_nombre': null, 'is_active': false,
  },
];

Future<List<http.Request>> _montar(WidgetTester t, {required String rol, http.Response? Function(http.Request)? responder}) async {
  t.view.physicalSize = const Size(1200, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pedidas = <http.Request>[];
  final api = VigiaApi(
    baseUrl: Uri.parse('https://vigia.test/api/'),
    cliente: MockClient((r) async {
      if (r.url.path.endsWith('auth/token/')) {
        return _json({'access': jwtFalso(username: 'ana', rol: rol), 'refresh': 'r'});
      }
      pedidas.add(r);
      if (responder?.call(r) case final respuesta?) return respuesta;
      if (r.url.path.endsWith('entidades/')) return _json([{'id': 7, 'nombre': 'Cornare'}, {'id': 8, 'nombre': 'Corantioquia'}]);
      if (r.method == 'PATCH') return _json(_usuarios[2]);
      return _json({'count': 3, 'results': _usuarios});
    }),
  );
  final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
  await auth.iniciarSesion('ana', 'clave');
  await t.pumpWidget(MultiProvider(
    providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
    child: const MaterialApp(home: PermisosScreen()),
  ));
  await t.pumpAndSettle();
  return pedidas;
}

void main() {
  testWidgets('lista los usuarios con rol, entidad y estado', (t) async {
    await _montar(t, rol: 'staff');

    expect(find.text('Administrador · Cornare · beto@x.co'), findsOneWidget);
    expect(find.text('Ciudadano · Cuenta desactivada'), findsOneWidget);
    // El staff edita a los demás, no a sí mismo.
    expect(find.byIcon(Icons.edit), findsNWidgets(2));
    expect(find.byTooltip('Editar permisos de ana'), findsNothing);
  });

  testWidgets('busca y filtra por rol', (t) async {
    final pedidas = await _montar(t, rol: 'staff');

    await t.enterText(find.byType(TextField), 'beto');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(pedidas.last.url.queryParameters['buscar'], 'beto');

    await t.tap(find.widgetWithText(ChoiceChip, 'Administrador'));
    await t.pumpAndSettle();
    expect(pedidas.last.url.queryParameters, containsPair('rol', 'administrador'));
  });

  testWidgets('el staff reactiva una cuenta y la vuelve administradora de una entidad', (t) async {
    final pedidas = await _montar(t, rol: 'staff');

    await t.tap(find.byTooltip('Editar permisos de carla'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ciudadano').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Administrador').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Sin entidad (todo el país)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Corantioquia').last);
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();

    final patch = pedidas.firstWhere((r) => r.method == 'PATCH');
    expect(patch.url.path, '/api/usuarios/3/');
    expect(jsonDecode(patch.body), {'rol': 'administrador', 'entidad': 8, 'is_active': true});
    expect(find.text('Permisos de carla actualizados.'), findsOneWidget);
  });

  testWidgets('el administrador solo consulta', (t) async {
    await _montar(t, rol: 'administrador');

    expect(find.textContaining('Los permisos los cambia el staff'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('muestra los errores de la API', (t) async {
    await _montar(t,
        rol: 'staff',
        responder: (r) => r.method == 'PATCH' ? _json({'detail': 'x'}, 403) : null);
    await t.tap(find.byTooltip('Editar permisos de beto'));
    await t.pumpAndSettle();
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('No tienes permiso para realizar esta acción.'), findsOneWidget);
  });

  testWidgets('si la lista no carga, lo dice', (t) async {
    await _montar(t, rol: 'staff', responder: (r) => _json({'detail': 'x'}, 500));
    expect(find.text('El servidor de Vigía tuvo un problema. Inténtalo más tarde.'), findsOneWidget);
  });
}
