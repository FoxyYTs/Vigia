import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/login_screen.dart';
import 'package:vigia_app/screens/rutas.dart';

import '../helpers/jwt_falso.dart';

class _Escenario {
  _Escenario(MockClientHandler manejador) {
    api = VigiaApi(
      baseUrl: Uri.parse('https://vigia.test/api/'),
      cliente: MockClient((r) {
        llamadas++;
        return manejador(r);
      }),
    );
    auth = AuthProvider(api: api, almacen: almacen);
  }

  late final VigiaApi api;
  late final AuthProvider auth;
  final almacen = AlmacenTokensMemoria();
  int llamadas = 0;

  Widget app() => MultiProvider(
        providers: [
          Provider.value(value: api),
          ChangeNotifierProvider.value(value: auth),
        ],
        child: MaterialApp(
          initialRoute: Rutas.login,
          routes: {
            Rutas.mapa: (_) => const Scaffold(body: Text('pantalla-mapa')),
            Rutas.login: (_) => const LoginScreen(),
            Rutas.panel: (_) => const Scaffold(body: Text('pantalla-panel')),
          },
        ),
      );
}

Future<void> _escribir(WidgetTester t, {String usuario = '', String password = ''}) async {
  await t.enterText(find.byKey(const Key('campo-usuario')), usuario);
  await t.enterText(find.byKey(const Key('campo-password')), password);
  await t.tap(find.byKey(const Key('boton-ingresar')));
  await t.pumpAndSettle();
}

/// Ventana de escritorio: muestra el panel de marca y el formulario.
void _escritorio(WidgetTester t) {
  t.view.physicalSize = const Size(1280, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('campos vacíos: muestra los dos errores y no llama a la API', (t) async {
    final e = _Escenario((_) async => http.Response('{}', 200));
    _escritorio(t);
    await t.pumpWidget(e.app());

    await _escribir(t);

    expect(find.text('Escribe tu nombre de usuario.'), findsOneWidget);
    expect(find.text('Escribe tu contraseña.'), findsOneWidget);
    expect(e.llamadas, 0);
  });

  testWidgets('usuario con caracteres no permitidos se rechaza en el cliente', (t) async {
    final e = _Escenario((_) async => http.Response('{}', 200));
    _escritorio(t);
    await t.pumpWidget(e.app());

    await _escribir(t, usuario: 'ana pérez!', password: 'x');

    expect(find.textContaining('solo admite letras, números'), findsOneWidget);
    expect(e.llamadas, 0);
  });

  testWidgets('credenciales incorrectas: mensaje amable y se limpia la contraseña', (t) async {
    final e = _Escenario((_) async => http.Response(jsonEncode({'detail': 'x'}), 401));
    _escritorio(t);
    await t.pumpWidget(e.app());

    await _escribir(t, usuario: 'ana', password: 'mala');

    expect(find.byKey(const Key('error-login')), findsOneWidget);
    expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
    final password = t.widget<TextField>(
      find.descendant(of: find.byKey(const Key('campo-password')), matching: find.byType(TextField)),
    );
    expect(password.controller!.text, isEmpty);
    expect(e.auth.autenticado, isFalse);
  });

  testWidgets('login correcto: guarda la sesión y abre el panel', (t) async {
    final e = _Escenario(
      (_) async => http.Response(jsonEncode({'access': jwtFalso(username: 'ana'), 'refresh': 'r'}), 200),
    );
    _escritorio(t);
    await t.pumpWidget(e.app());

    await _escribir(t, usuario: ' ana ', password: 'buena');

    expect(e.auth.autenticado, isTrue);
    expect(e.auth.username, 'ana');
    expect(await e.almacen.leer(), isNotNull);
    expect(find.text('pantalla-panel'), findsOneWidget);
  });

  testWidgets('el registro aparece como próximo incremento, sin acción', (t) async {
    final e = _Escenario((_) async => http.Response('{}', 200));
    _escritorio(t);
    await t.pumpWidget(e.app());

    final registro = find.byKey(const Key('registro-proximo'));
    expect(registro, findsOneWidget);
    expect(find.descendant(of: registro, matching: find.text('Próximo incremento')), findsOneWidget);
    expect(find.descendant(of: registro, matching: find.byType(ButtonStyleButton)), findsNothing);
  });

  testWidgets('el botón de mostrar contraseña tiene etiqueta accesible', (t) async {
    final e = _Escenario((_) async => http.Response('{}', 200));
    _escritorio(t);
    await t.pumpWidget(e.app());

    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
    await t.tap(find.byTooltip('Mostrar contraseña'));
    await t.pump();
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
  });
}
