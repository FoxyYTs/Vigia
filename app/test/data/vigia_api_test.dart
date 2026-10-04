import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigia_app/config/app_config.dart';
import 'package:vigia_app/data/api/vigia_api.dart';
import 'package:vigia_app/data/models/foco.dart';
import 'package:vigia_app/data/models/usuario.dart';

import '../helpers/jwt_falso.dart';

http.Response _json(Object cuerpo, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(cuerpo)),
      status,
      headers: {'content-type': 'application/json'},
    );

VigiaApi _api(MockClientHandler manejador) =>
    VigiaApi(baseUrl: Uri.parse('https://vigia.test/api/'), cliente: MockClient(manejador));

void main() {
  group('AppConfig', () {
    test('agrega la barra final a la URL base', () {
      expect(AppConfig.normalizarBase('https://x.co/api').toString(), 'https://x.co/api/');
      expect(AppConfig.normalizarBase('https://x.co/api/').toString(), 'https://x.co/api/');
    });
  });

  group('iniciarSesion', () {
    test('envía usuario y contraseña a auth/token/ y devuelve los tokens', () async {
      late http.Request enviada;
      final access = jwtFalso(username: 'ana', rol: 'administrador');
      final api = _api((r) async {
        enviada = r;
        return _json({'access': access, 'refresh': 'r1'});
      });

      final tokens = await api.iniciarSesion('ana', 'secreta');

      expect(enviada.method, 'POST');
      expect(enviada.url.toString(), 'https://vigia.test/api/auth/token/');
      expect(jsonDecode(enviada.body), {'username': 'ana', 'password': 'secreta'});
      expect(tokens.access, access);
      expect(tokens.refresh, 'r1');
      final claims = ClaimsJwt.decodificar(tokens.access)!;
      expect(claims.username, 'ana');
      expect(claims.rol, Rol.administrador);
      expect(claims.vencido, isFalse);
    });

    test('credenciales incorrectas (401) dan un mensaje en español', () async {
      final api = _api((_) async => _json({'detail': 'No active account'}, 401));
      expect(
        () => api.iniciarSesion('ana', 'mala'),
        throwsA(isA<ApiException>()
            .having((e) => e.mensaje, 'mensaje', 'Usuario o contraseña incorrectos.')
            .having((e) => e.status, 'status', 401)),
      );
    });

    test('el límite de intentos (429) se explica al usuario', () async {
      final api = _api((_) async => _json({'detail': 'throttled'}, 429));
      expect(
        () => api.iniciarSesion('ana', 'x'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('Demasiados intentos'))),
      );
    });

    test('sin conexión da un mensaje de conectividad, no una excepción cruda', () async {
      final api = _api((_) async => throw http.ClientException('Connection refused'));
      expect(
        () => api.iniciarSesion('ana', 'x'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('No se pudo conectar'))),
      );
    });

    test('un error 500 no expone el cuerpo de la respuesta', () async {
      final api = _api((_) async => http.Response('<html>Traceback (most recent call last)</html>', 500));
      expect(
        () => api.iniciarSesion('ana', 'x'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', isNot(contains('Traceback')))),
      );
    });
  });

  group('focos', () {
    test('listarFocos manda el rango en UTC, la fuente y la paginación', () async {
      late Uri pedida;
      final api = _api((r) async {
        pedida = r.url;
        return _json({
          'count': 1,
          'next': null,
          'previous': null,
          'results': [
            {
              'id': 7,
              'fuente': 'INPE_QUEIMADAS',
              'latitud': 4.5,
              'longitud': -71.2,
              'fecha_hora': '2026-09-23T14:00:00-05:00',
              'confianza': '',
              'brillo_frp': null,
              'satelite': 'AQUA_M-T',
            },
          ],
        });
      });

      final pagina = await api.listarFocos(
        desde: DateTime.utc(2026, 9, 22),
        hasta: DateTime.utc(2026, 9, 24),
        fuente: FuenteSatelital.inpeQueimadas,
        pagina: 2,
      );

      expect(pedida.path, '/api/focos/');
      expect(pedida.queryParameters, {
        'desde': '2026-09-22T00:00:00.000Z',
        'hasta': '2026-09-24T00:00:00.000Z',
        'fuente': 'INPE_QUEIMADAS',
        'page': '2',
        'page_size': '500',
      });
      expect(pagina.total, 1);
      final foco = pagina.focos.single;
      expect(foco.fuente, FuenteSatelital.inpeQueimadas);
      expect(foco.posicion.latitude, 4.5);
      expect(foco.fechaHora, DateTime.utc(2026, 9, 23, 19));
      expect(foco.confianzaLegible, 'No reportada');
    });

    test('un filtro inválido (400) muestra el primer mensaje de DRF', () async {
      final api = _api((_) async => _json({'desde': ['El rango máximo es de 31 días.']}, 400));
      expect(
        () => api.listarFocos(desde: DateTime(2026), hasta: DateTime(2026, 6)),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'El rango máximo es de 31 días.')),
      );
    });

    test('fechaUltimoFoco devuelve null si no hay focos', () async {
      final api = _api((_) async => _json({'fecha_hora': null}));
      expect(await api.fechaUltimoFoco(), isNull);
    });
  });

  test('obtenerPerfil manda el token como Bearer', () async {
    late http.Request enviada;
    final api = _api((r) async {
      enviada = r;
      return _json({'id': 1, 'username': 'ana', 'email': 'a@b.co', 'rol': 'staff'});
    });

    final usuario = await api.obtenerPerfil('tok');

    expect(enviada.headers['Authorization'], 'Bearer tok');
    expect(usuario.rol, Rol.staff);
  });
}
