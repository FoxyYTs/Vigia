import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/foco.dart';
import '../models/usuario.dart';

/// Error de la API ya traducido a un mensaje que se le puede mostrar al
/// usuario. Nunca incluye tokens ni contraseñas.
class ApiException implements Exception {
  const ApiException(this.mensaje, {this.status});

  final String mensaje;
  final int? status;

  bool get noAutorizado => status == 401;

  @override
  String toString() => 'ApiException($status): $mensaje';
}

/// Cliente HTTP de la API REST de Vigía (contrato en el README del repo).
///
/// Recibe el [http.Client] por constructor para poder probarlo con
/// `MockClient` sin red.
class VigiaApi {
  VigiaApi({required this.baseUrl, http.Client? cliente, this.timeout = const Duration(seconds: 20)})
      : _cliente = cliente ?? http.Client();

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _cliente;

  /// Tamaño máximo de página que acepta `PaginacionEstandar` del backend.
  static const int tamanoPaginaMaximo = 500;

  // ---------------------------------------------------------------- auth --

  Future<Tokens> iniciarSesion(String username, String password) async {
    final json = await _enviar(
      () => _cliente.post(
        baseUrl.resolve('auth/token/'),
        headers: _cabeceras(),
        body: jsonEncode({'username': username, 'password': password}),
      ),
      mensaje401: 'Usuario o contraseña incorrectos.',
    );
    return Tokens.fromJson(json);
  }

  Future<String> refrescarAcceso(String refresh) async {
    final json = await _enviar(
      () => _cliente.post(
        baseUrl.resolve('auth/token/refresh/'),
        headers: _cabeceras(),
        body: jsonEncode({'refresh': refresh}),
      ),
      mensaje401: 'Tu sesión expiró. Inicia sesión de nuevo.',
    );
    return json['access'] as String;
  }

  Future<Usuario> obtenerPerfil(String access) async {
    final json = await _enviar(
      () => _cliente.get(baseUrl.resolve('auth/yo/'), headers: _cabeceras(access)),
      mensaje401: 'Tu sesión expiró. Inicia sesión de nuevo.',
    );
    return Usuario.fromJson(json);
  }

  // --------------------------------------------------------------- focos --

  Future<PaginaFocos> listarFocos({
    required DateTime desde,
    required DateTime hasta,
    FuenteSatelital? fuente,
    int pagina = 1,
    int tamanoPagina = tamanoPaginaMaximo,
  }) async {
    final uri = baseUrl.resolve('focos/').replace(queryParameters: {
      'desde': desde.toUtc().toIso8601String(),
      'hasta': hasta.toUtc().toIso8601String(),
      if (fuente != null) 'fuente': fuente.valorApi,
      'page': '$pagina',
      'page_size': '$tamanoPagina',
    });
    final json = await _enviar(() => _cliente.get(uri, headers: _cabeceras()));
    return PaginaFocos.fromJson(json);
  }

  /// Fecha del foco más reciente cargado en la base de datos, o `null`.
  Future<DateTime?> fechaUltimoFoco() async {
    final json = await _enviar(
      () => _cliente.get(baseUrl.resolve('focos/ultimo/'), headers: _cabeceras()),
    );
    final valor = json['fecha_hora'] as String?;
    return valor == null ? null : DateTime.parse(valor);
  }

  // ------------------------------------------------------------ internos --

  Map<String, String> _cabeceras([String? access]) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (access != null) 'Authorization': 'Bearer $access',
      };

  Future<Map<String, dynamic>> _enviar(
    Future<http.Response> Function() peticion, {
    String mensaje401 = 'Necesitas iniciar sesión para continuar.',
  }) async {
    final http.Response respuesta;
    try {
      respuesta = await peticion().timeout(timeout);
    } on TimeoutException {
      throw const ApiException('El servidor tardó demasiado en responder. Inténtalo de nuevo.');
    } on http.ClientException {
      throw const ApiException(
        'No se pudo conectar con el servidor de Vigía. Revisa tu conexión a internet.',
      );
    }

    final cuerpo = _decodificar(respuesta);
    final status = respuesta.statusCode;
    if (status >= 200 && status < 300 && cuerpo is Map<String, dynamic>) return cuerpo;

    throw ApiException(
      switch (status) {
        401 => mensaje401,
        403 => 'No tienes permiso para realizar esta acción.',
        404 => 'El recurso solicitado no existe.',
        429 => 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.',
        400 => _primerError(cuerpo) ?? 'Revisa los datos enviados.',
        >= 500 => 'El servidor de Vigía tuvo un problema. Inténtalo más tarde.',
        _ => 'Respuesta inesperada del servidor (código $status).',
      },
      status: status,
    );
  }

  Object? _decodificar(http.Response r) {
    if (r.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// DRF devuelve `{"campo": ["mensaje"]}` o `{"campo": "mensaje"}`.
  String? _primerError(Object? cuerpo) {
    if (cuerpo is! Map || cuerpo.isEmpty) return null;
    final valor = cuerpo.values.first;
    if (valor is List && valor.isNotEmpty) return '${valor.first}';
    if (valor is String) return valor;
    return null;
  }
}
