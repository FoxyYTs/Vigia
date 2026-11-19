import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/nuevo_reporte_screen.dart';
import 'package:vigia_app/screens/reportes_screen.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

/// PNG de 1×1: la vista previa necesita una imagen decodificable.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

Map<String, Object?> _reporte(int id, String estado) => {
      'id': id,
      'ciudadano': 'ana',
      'miniatura_url': null,
      'descripcion': 'Humo en la ladera',
      'ubicacion_usuario': null,
      'ubicacion_incendio': {'latitud': 6.25, 'longitud': -75.56},
      'distancia_reportada_km': 1.2,
      'estado': estado,
      'validado_por': null,
      'fecha_creacion': '2026-11-17T15:00:00Z',
      'fecha_validacion': null,
    };

/// Monta [pantalla] con sesión iniciada como [rol]; [peticiones] registra lo
/// que la app manda a la API (sin contar el login).
Future<void> _montar(
  WidgetTester t,
  Widget pantalla, {
  required String rol,
  required Future<http.Response> Function(http.BaseRequest r) manejar,
}) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await initializeDateFormatting('es_CO');

  final api = VigiaApi(
    baseUrl: Uri.parse('https://vigia.test/api/'),
    cliente: MockClient.streaming((r, cuerpo) async {
      final resp = r.url.path.endsWith('auth/token/')
          ? _json({'access': jwtFalso(rol: rol), 'refresh': 'r'})
          : await manejar(r);
      return http.StreamedResponse(Stream.value(resp.bodyBytes), resp.statusCode, headers: resp.headers);
    }),
  );
  final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
  await auth.iniciarSesion('ana', 'clave');

  await t.pumpWidget(MultiProvider(
    providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
    child: MaterialApp(
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: pantalla,
    ),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('el administrador ve los pendientes de su jurisdicción y puede validarlos', (t) async {
    final pedidas = <String>[];
    await _montar(t, const ReportesScreen(), rol: 'administrador', manejar: (r) async {
      pedidas.add('${r.method} ${r.url.path}');
      return r.method == 'POST'
          ? _json(_reporte(7, 'validado'))
          : _json({'count': 2, 'next': null, 'previous': null, 'results': [_reporte(7, 'pendiente'), _reporte(8, 'rechazado')]});
    });

    expect(find.text('Reporte #7'), findsOneWidget);
    expect(find.text('Humo en la ladera'), findsNWidgets(2));
    // Solo el pendiente tiene acciones, y el administrador no crea reportes.
    expect(find.text('Validar'), findsOneWidget);
    expect(find.text('Nuevo reporte'), findsNothing);

    await t.tap(find.text('Validar'));
    await t.pump();
    await t.pump();
    expect(pedidas, contains('POST /api/reportes/7/validar/'));
    expect(find.text('Reporte #7 validado.'), findsOneWidget);
  });

  testWidgets('el ciudadano ve sus reportes y el botón para crear uno, sin acciones de validación', (t) async {
    await _montar(t, const ReportesScreen(), rol: 'ciudadano',
        manejar: (_) async => _json({'count': 1, 'next': null, 'previous': null, 'results': [_reporte(3, 'pendiente')]}));

    expect(find.text('Reporte #3'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Nuevo reporte'), findsOneWidget);
    expect(find.text('Validar'), findsNothing);
  });

  testWidgets('el nuevo reporte exige foto y envía foto, ubicación del ciudadano y pin en multipart', (t) async {
    http.MultipartRequest? enviada;
    await _montar(
      t,
      NuevoReporteScreen(
        tomarFoto: () async => _png,
        ubicar: () async => const LatLng(6.25, -75.56),
      ),
      rol: 'ciudadano',
      manejar: (r) async {
        enviada = r as http.MultipartRequest;
        return _json(_reporte(9, 'pendiente'), 201);
      },
    );

    final enviar = find.widgetWithText(FilledButton, 'Enviar reporte');
    expect(t.widget<FilledButton>(enviar).onPressed, isNull, reason: 'sin foto no se puede enviar');

    await t.tap(find.text('Tomar foto'));
    await t.pump();
    await t.enterText(find.byType(TextField), '  Llamas cerca de la vía ');
    await t.tap(enviar);
    await t.pump();
    await t.pump();

    expect(enviada!.url.path, '/api/reportes/');
    expect(enviada!.fields, {
      'latitud_usuario': '6.25',
      'longitud_usuario': '-75.56',
      // Sin tocar el mapa, el pin arranca en la ubicación del ciudadano.
      'latitud_incendio': '6.25',
      'longitud_incendio': '-75.56',
      'descripcion': 'Llamas cerca de la vía',
    });
    expect(enviada!.files.single.field, 'foto');
    expect(enviada!.headers['Authorization'], startsWith('Bearer '));
  });

  testWidgets('el error de validación de la API se muestra en el formulario', (t) async {
    await _montar(
      t,
      NuevoReporteScreen(
        tomarFoto: () async => _png,
        ubicar: () async => const LatLng(6.25, -75.56),
      ),
      rol: 'ciudadano',
      manejar: (_) async => _json({'latitud_incendio': ['El incendio debe estar en Colombia.']}, 400),
    );

    await t.tap(find.text('Tomar foto'));
    await t.pump();
    await t.tap(find.text('Enviar reporte'));
    await t.pump();
    await t.pump();

    expect(find.text('El incendio debe estar en Colombia.'), findsOneWidget);
  });

  testWidgets('mientras se valida, los botones esperan (sin doble envío)', (t) async {
    final pedidas = <String>[];
    final respuesta = Completer<http.Response>();
    await _montar(t, const ReportesScreen(), rol: 'administrador', manejar: (r) {
      if (r.method == 'POST') {
        pedidas.add(r.url.path);
        return respuesta.future;
      }
      return Future.value(_json({'count': 1, 'next': null, 'previous': null, 'results': [_reporte(7, 'pendiente')]}));
    });

    await t.tap(find.text('Validar'));
    await t.pump();
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Validar')).onPressed, isNull);
    await t.tap(find.text('Validar'));
    await t.pump();
    expect(pedidas, hasLength(1));

    respuesta.complete(_json(_reporte(7, 'validado')));
    await t.pump();
    await t.pump();
  });

  testWidgets('si la cámara no abre, lo explica; el mapa da crédito a OpenStreetMap', (t) async {
    await _montar(
      t,
      NuevoReporteScreen(
        tomarFoto: () async => throw Exception('permiso negado'),
        ubicar: () async => const LatLng(6.25, -75.56),
      ),
      rol: 'ciudadano',
      manejar: (_) async => _json({}),
    );

    await t.tap(find.text('Tomar foto'));
    await t.pump();
    expect(find.textContaining('No se pudo abrir la cámara'), findsOneWidget);
    expect(find.byType(RichAttributionWidget), findsOneWidget);
  });
}
