import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/models/usuario.dart';
import 'package:vigia_app/data/storage/almacen_tokens.dart';
import 'package:vigia_app/main.dart';
import 'package:vigia_app/providers/auth_provider.dart';
import 'package:vigia_app/screens/login_screen.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(cuerpo)), status, headers: {'content-type': 'application/json'});

/// Backend falso: `auth/token/refresh/` responde [refresco]; registra las rutas pedidas.
VigiaApi _api(http.Response Function() refresco, {List<String>? pedidas}) => VigiaApi(
      baseUrl: Uri.parse('https://vigia.test/api/'),
      cliente: MockClient((r) async {
        pedidas?.add(r.url.path);
        return refresco();
      }),
    );

Future<AlmacenTokensMemoria> _almacenCon(String access, [String refresh = 'r1']) async {
  final almacen = AlmacenTokensMemoria();
  await almacen.guardar(Tokens(access: access, refresh: refresh));
  return almacen;
}

void main() {
  final vencido = jwtFalso(vence: const Duration(minutes: -5));

  group('restaurar', () {
    test('con access vigente no llama a la API', () async {
      final pedidas = <String>[];
      final auth = AuthProvider(api: _api(() => _json({}), pedidas: pedidas), almacen: await _almacenCon(jwtFalso()));

      await auth.restaurar();

      expect(auth.estado, EstadoSesion.autenticada);
      expect(pedidas, isEmpty);
    });

    test('con access vencido y refresh válido renueva y queda autenticada', () async {
      final nuevo = jwtFalso(username: 'ana', rol: 'administrador');
      final almacen = await _almacenCon(vencido);
      final auth = AuthProvider(api: _api(() => _json({'access': nuevo})), almacen: almacen);

      await auth.restaurar();

      expect(auth.estado, EstadoSesion.autenticada);
      expect(auth.rol, Rol.administrador);
      expect((await almacen.leer())!.access, nuevo);
    });

    test('con refresh vencido (401) queda anónima y borra el almacén', () async {
      final almacen = await _almacenCon(vencido);
      final auth = AuthProvider(api: _api(() => _json({'detail': 'token expirado'}, 401)), almacen: almacen);

      await auth.restaurar();

      expect(auth.estado, EstadoSesion.anonima);
      expect(await almacen.leer(), isNull);
    });

    test('sin sesión guardada queda anónima', () async {
      final auth = AuthProvider(api: _api(() => _json({})), almacen: AlmacenTokensMemoria());
      await auth.restaurar();
      expect(auth.estado, EstadoSesion.anonima);
    });
  });

  group('accessToken', () {
    // El servidor devuelve primero un access ya vencido (queda guardado tal cual),
    // así la siguiente llamada a accessToken() tiene que renovar.
    Future<(AuthProvider, AlmacenTokensMemoria)> sesionPorVencer(http.Response segundaRespuesta) async {
      final respuestas = [_json({'access': vencido}), segundaRespuesta];
      final almacen = await _almacenCon(vencido);
      final auth = AuthProvider(api: _api(() => respuestas.removeAt(0)), almacen: almacen);
      await auth.restaurar();
      return (auth, almacen);
    }

    test('renueva el access vencido y lo guarda', () async {
      final nuevo = jwtFalso();
      final (auth, almacen) = await sesionPorVencer(_json({'access': nuevo}));

      expect(await auth.accessToken(), nuevo);
      expect((await almacen.leer())!.access, nuevo);
    });

    test('si renovar devuelve 401 cierra la sesión y propaga el error', () async {
      final (auth, almacen) = await sesionPorVencer(_json({'detail': 'x'}, 401));

      await expectLater(auth.accessToken(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
      expect(auth.estado, EstadoSesion.anonima);
      expect(await almacen.leer(), isNull);
    });

    test('sin sesión lanza 401 sin llamar a la API', () async {
      final pedidas = <String>[];
      final auth = AuthProvider(api: _api(() => _json({}), pedidas: pedidas), almacen: AlmacenTokensMemoria());
      await expectLater(auth.accessToken(), throwsA(isA<ApiException>()));
      expect(pedidas, isEmpty);
    });
  });

  test('cerrarSesion borra los tokens y notifica', () async {
    final almacen = await _almacenCon(jwtFalso());
    final auth = AuthProvider(api: _api(() => _json({})), almacen: almacen);
    await auth.restaurar();
    var avisos = 0;
    auth.addListener(() => avisos++);

    await auth.cerrarSesion();

    expect(auth.estado, EstadoSesion.anonima);
    expect(auth.username, isEmpty);
    expect(await almacen.leer(), isNull);
    expect(avisos, 1);
  });

  group('RequiereSesion', () {
    Future<void> montar(WidgetTester t, AuthProvider auth, VigiaApi api) => t.pumpWidget(MultiProvider(
          providers: [Provider.value(value: api), ChangeNotifierProvider.value(value: auth)],
          child: const MaterialApp(home: RequiereSesion(child: Text('PANEL'))),
        ));

    testWidgets('sin sesión muestra el login en vez del panel', (t) async {
      final api = _api(() => _json({}));
      final auth = AuthProvider(api: api, almacen: AlmacenTokensMemoria());
      await auth.restaurar();

      await montar(t, auth, api);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('PANEL'), findsNothing);
    });

    testWidgets('con sesión muestra el panel', (t) async {
      final api = _api(() => _json({}));
      final auth = AuthProvider(api: api, almacen: await _almacenCon(jwtFalso()));
      await auth.restaurar();

      await montar(t, auth, api);

      expect(find.text('PANEL'), findsOneWidget);
    });

    testWidgets('mientras verifica muestra un indicador de carga', (t) async {
      final api = _api(() => _json({}));
      await montar(t, AuthProvider(api: api, almacen: AlmacenTokensMemoria()), api);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('rotación y revocación', () {
    test('al renovar se guarda el refresh nuevo que entrega el servidor', () async {
      final almacen = await _almacenCon(vencido, 'r-viejo');
      final auth = AuthProvider(api: _api(() => _json({'access': jwtFalso(), 'refresh': 'r-nuevo'})), almacen: almacen);

      await auth.restaurar();

      expect((await almacen.leer())!.refresh, 'r-nuevo');
    });

    test('sin conexión al restaurar se conserva la sesión', () async {
      final almacen = await _almacenCon(vencido);
      final api = VigiaApi(
        baseUrl: Uri.parse('https://vigia.test/api/'),
        cliente: MockClient((_) async => throw http.ClientException('sin red')),
      );
      final auth = AuthProvider(api: api, almacen: almacen);

      await auth.restaurar();

      expect(auth.estado, EstadoSesion.autenticada);
      expect(await almacen.leer(), isNotNull);
    });

    test('un error de red al pedir el token no cierra la sesión', () async {
      var caido = false;
      final almacen = await _almacenCon(vencido);
      final api = VigiaApi(
        baseUrl: Uri.parse('https://vigia.test/api/'),
        cliente: MockClient((_) async {
          if (caido) throw http.ClientException('sin red');
          return _json({'access': vencido, 'refresh': 'r2'});
        }),
      );
      final auth = AuthProvider(api: api, almacen: almacen);
      await auth.restaurar();
      caido = true;

      await expectLater(auth.accessToken(), throwsA(isA<ApiException>()));
      expect(auth.estado, EstadoSesion.autenticada);
    });

    test('dos llamadas simultáneas renuevan una sola vez', () async {
      var renovaciones = 0;
      final respuestas = [_json({'access': vencido, 'refresh': 'r1'})];
      final almacen = await _almacenCon(vencido);
      final auth = AuthProvider(
        api: _api(() {
          renovaciones++;
          return respuestas.isNotEmpty ? respuestas.removeAt(0) : _json({'access': jwtFalso(), 'refresh': 'r2'});
        }),
        almacen: almacen,
      );
      await auth.restaurar();
      renovaciones = 0;

      await Future.wait([auth.accessToken(), auth.accessToken()]);

      expect(renovaciones, 1);
    });

    test('cerrar sesión revoca el refresh en el servidor', () async {
      final pedidas = <String>[];
      final auth = AuthProvider(api: _api(() => _json({}), pedidas: pedidas), almacen: await _almacenCon(jwtFalso()));
      await auth.restaurar();

      await auth.cerrarSesion();

      expect(pedidas.last, endsWith('auth/logout/'));
    });
  });
}
