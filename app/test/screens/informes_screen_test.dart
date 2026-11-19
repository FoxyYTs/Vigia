import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/informes_screen.dart';

import '../helpers/jwt_falso.dart';

typedef _Guardado = ({Uint8List bytes, String nombre, String tipo});

Future<(List<Uri>, List<_Guardado>)> _montar(WidgetTester t, {http.Response? respuesta, bool falla = false}) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pedidas = <Uri>[];
  final guardados = <_Guardado>[];
  final api = VigiaApi(
    baseUrl: Uri.parse('https://vigia.test/api/'),
    cliente: MockClient((r) async {
      if (r.url.path.endsWith('auth/token/')) {
        return http.Response('{"access": "${jwtFalso(rol: 'administrador')}", "refresh": "r"}', 200);
      }
      pedidas.add(r.url);
      return respuesta ??
          http.Response.bytes([37, 80, 68, 70], 200, headers: {
            'content-type': 'application/pdf',
            'content-disposition': 'attachment; filename="vigia-2026-10-20_2026-11-18.pdf"',
          });
    }),
  );
  final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
  await auth.iniciarSesion('ana', 'clave');
  await t.pumpWidget(MultiProvider(
    providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
    child: MaterialApp(
      home: InformesScreen(guardar: (bytes, nombre, tipo) async {
        if (falla) throw Exception('gesto vencido');
        guardados.add((bytes: bytes, nombre: nombre, tipo: tipo));
      }),
    ),
  ));
  return (pedidas, guardados);
}

void main() {
  testWidgets('descarga el PDF con el nombre que da el backend', (t) async {
    final (pedidas, guardados) = await _montar(t);
    await t.tap(find.text('Descargar PDF'));
    await t.pumpAndSettle();

    expect(pedidas.single.queryParameters['formato'], 'pdf');
    expect(guardados.single.nombre, 'vigia-2026-10-20_2026-11-18.pdf');
    expect(guardados.single.tipo, 'application/pdf');
    expect(guardados.single.bytes, [37, 80, 68, 70]);
  });

  testWidgets('el CSV pide el conjunto elegido', (t) async {
    final (pedidas, _) = await _montar(t);
    await t.tap(find.text('Detecciones satelitales'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reportes ciudadanos').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Descargar CSV'));
    await t.pumpAndSettle();

    expect(pedidas.single.queryParameters, containsPair('conjunto', 'reportes'));
    expect(pedidas.single.queryParameters, containsPair('formato', 'csv'));
  });

  testWidgets('con un año solo se puede descargar el PDF', (t) async {
    await _montar(t);
    await t.tap(find.text('1 año'));
    await t.pump();

    FilledButton boton(String texto) => t.widget<FilledButton>(find.widgetWithText(FilledButton, texto));
    expect(boton('Descargar Excel').onPressed, isNull);
    expect(boton('Descargar CSV').onPressed, isNull);
    expect(boton('Descargar PDF').onPressed, isNotNull);
  });

  testWidgets('el error de la API se muestra y no se guarda nada', (t) async {
    final (_, guardados) = await _montar(
      t,
      respuesta: http.Response.bytes(utf8.encode('{"desde": ["El detalle en CSV o Excel admite hasta 92 días."]}'), 400),
    );
    await t.tap(find.text('Descargar Excel'));
    await t.pumpAndSettle();

    expect(find.text('El detalle en CSV o Excel admite hasta 92 días.'), findsOneWidget);
    expect(guardados, isEmpty);
  });

  testWidgets('si la hoja de compartir falla, lo avisa y se puede reintentar', (t) async {
    await _montar(t, falla: true);
    await t.pumpAndSettle();
    await t.tap(find.text('Descargar PDF'));
    await t.pumpAndSettle();
    expect(find.text('No se pudo guardar el archivo. Inténtalo de nuevo.'), findsOneWidget);
    expect(find.text('Descargar PDF'), findsOneWidget);
  });
}
