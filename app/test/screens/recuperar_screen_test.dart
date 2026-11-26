import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/screens/recuperar_screen.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

Future<List<http.Request>> _montar(WidgetTester t, {http.Response Function(http.Request)? confirmar}) async {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pedidas = <http.Request>[];
  final api = VigiaApi(
    baseUrl: Uri.parse('https://vigia.test/api/'),
    cliente: MockClient((r) async {
      pedidas.add(r);
      if (r.url.path.endsWith('auth/recuperar/confirmar/')) return confirmar?.call(r) ?? _json({'detail': 'ok'});
      return _json({'detail': 'ok'});
    }),
  );
  await t.pumpWidget(
    Provider.value(
      value: api,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecuperarScreen())),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
  return pedidas;
}

Future<void> _pedirCodigo(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('campo-correo')), 'ana@correo.co');
  await t.tap(find.byKey(const Key('boton-recuperar-enviar')));
  await t.pumpAndSettle();
}

Future<void> _llenarCodigo(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('campo-codigo')), '123456');
  await t.enterText(find.byKey(const Key('campo-nueva')), 'clave-nueva-77');
  await t.enterText(find.byKey(const Key('campo-confirmacion')), 'clave-nueva-77');
  await t.tap(find.byKey(const Key('boton-recuperar-enviar')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('pide el código y cambia la contraseña en la misma pantalla', (t) async {
    final pedidas = await _montar(t);
    await _pedirCodigo(t);
    expect(jsonDecode(pedidas.single.body), {'email': 'ana@correo.co'});
    expect(find.textContaining('te llegó un código'), findsOneWidget);

    await _llenarCodigo(t);
    expect(pedidas.last.url.path, endsWith('auth/recuperar/confirmar/'));
    expect(jsonDecode(pedidas.last.body), {'email': 'ana@correo.co', 'codigo': '123456', 'password': 'clave-nueva-77'});
    expect(find.byType(RecuperarScreen), findsNothing); // volvió al login
    expect(find.textContaining('Contraseña actualizada'), findsOneWidget);
  });

  testWidgets('un código errado muestra el mensaje del servidor y se queda', (t) async {
    await _montar(
      t,
      confirmar: (_) => _json({
        'codigo': ['El código no es válido o ya venció. Pide uno nuevo.'],
      }, 400),
    );
    await _pedirCodigo(t);
    await _llenarCodigo(t);
    expect(find.text('El código no es válido o ya venció. Pide uno nuevo.'), findsOneWidget);
    expect(find.byType(RecuperarScreen), findsOneWidget);
  });

  testWidgets('el código solo acepta 6 dígitos', (t) async {
    final pedidas = await _montar(t);
    await _pedirCodigo(t);
    await t.enterText(find.byKey(const Key('campo-codigo')), '12ab3');
    await t.tap(find.byKey(const Key('boton-recuperar-enviar')));
    await t.pumpAndSettle();
    expect(find.text('El código tiene 6 dígitos.'), findsOneWidget);
    expect(pedidas, hasLength(1));
  });
}
