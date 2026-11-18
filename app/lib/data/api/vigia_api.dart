import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/estadisticas.dart';
import '../models/foco.dart';
import '../models/historico.dart';
import '../models/reporte.dart';
import '../models/usuario.dart';
import '../models/zona.dart';

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

  /// Renueva la sesión. El backend rota el refresh (y revoca el anterior):
  /// hay que guardar el que devuelve, no el que se mandó.
  Future<Tokens> renovarSesion(String refresh) async {
    final json = await _enviar(
      () => _cliente.post(
        baseUrl.resolve('auth/token/refresh/'),
        headers: _cabeceras(),
        body: jsonEncode({'refresh': refresh}),
      ),
      mensaje401: 'Tu sesión expiró. Inicia sesión de nuevo.',
    );
    return Tokens(access: json['access'] as String, refresh: json['refresh'] as String? ?? refresh);
  }

  /// Revoca el refresh en el servidor: aunque alguien lo haya copiado, deja de servir.
  Future<void> revocarSesion(String refresh) => _enviar(
        () => _cliente.post(
          baseUrl.resolve('auth/logout/'),
          headers: _cabeceras(),
          body: jsonEncode({'refresh': refresh}),
        ),
      );

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

  // ---------------------------------------------------------- prediccion --

  Future<MesesPrediccion> mesesPrediccion() async {
    final json = await _enviar(
      () => _cliente.get(baseUrl.resolve('zonas-recurrentes/meses/'), headers: _cabeceras()),
    );
    return MesesPrediccion.fromJson(json);
  }

  /// Zonas del [mes] ("AAAA-MM") con puntaje de al menos [minPuntaje].
  Future<PaginaZonas> listarZonas({
    required String mes,
    double minPuntaje = 0,
    int pagina = 1,
    int tamanoPagina = tamanoPaginaMaximo,
  }) async {
    final uri = baseUrl.resolve('zonas-recurrentes/').replace(queryParameters: {
      'mes': mes,
      'min_puntaje': '$minPuntaje',
      'page': '$pagina',
      'page_size': '$tamanoPagina',
    });
    final json = await _enviar(() => _cliente.get(uri, headers: _cabeceras()));
    return PaginaZonas.fromJson(json);
  }

  // ----------------------------------------------------------- historico --

  Future<List<MunicipioGeo>> geometriaMunicipios() async {
    final json = await _enviar(() => _cliente.get(baseUrl.resolve('municipios/geometria/'), headers: _cabeceras()));
    return [for (final f in json['features'] as List) MunicipioGeo.fromFeature(f as Map<String, dynamic>)];
  }

  /// Años con datos de cada indicador.
  Future<Map<IndicadorHistorico, List<int>>> disponibilidadHistorica() async {
    final json = await _enviar(
      () => _cliente.get(baseUrl.resolve('historico/capa/disponible/'), headers: _cabeceras()),
    );
    return {
      for (final i in IndicadorHistorico.values)
        i: [for (final a in (json[i.valorApi] as List? ?? const [])) a as int],
    };
  }

  /// Valor del [indicador] en [anio] por código DANE.
  Future<Map<String, double>> capaHistorica(IndicadorHistorico indicador, int anio) async {
    final uri = baseUrl.resolve('historico/capa/').replace(
      queryParameters: {'indicador': indicador.valorApi, 'anio': '$anio'},
    );
    final lista = await _enviarLista(() => _cliente.get(uri, headers: _cabeceras()));
    return {for (final f in lista) f['codigo_dane'] as String: (f['valor'] as num).toDouble()};
  }

  // ------------------------------------------------------------ reportes --

  /// Crea un reporte ciudadano (multipart). [foto] son los bytes JPEG de la
  /// cámara; el backend la re-codifica sin EXIF y genera la miniatura.
  Future<Reporte> crearReporte(
    String access, {
    required List<int> foto,
    required LatLng ubicacionUsuario,
    required LatLng ubicacionIncendio,
    String descripcion = '',
  }) async {
    final peticion = http.MultipartRequest('POST', baseUrl.resolve('reportes/'))
      ..headers.addAll({'Accept': 'application/json', 'Authorization': 'Bearer $access'})
      ..fields.addAll({
        'latitud_usuario': '${ubicacionUsuario.latitude}',
        'longitud_usuario': '${ubicacionUsuario.longitude}',
        'latitud_incendio': '${ubicacionIncendio.latitude}',
        'longitud_incendio': '${ubicacionIncendio.longitude}',
        'descripcion': descripcion,
      })
      ..files.add(http.MultipartFile.fromBytes('foto', foto, filename: 'reporte.jpg'));
    final json = await _enviar(() async => http.Response.fromStream(await _cliente.send(peticion)));
    return Reporte.fromJson(json);
  }

  /// Ciudadano: los suyos. Administrador: los de su jurisdicción. Staff: todos.
  Future<List<Reporte>> listarReportes(String access, {EstadoReporte? estado}) async {
    final uri = baseUrl.resolve('reportes/').replace(queryParameters: {
      if (estado != null) 'estado': estado.valorApi,
      'page_size': '$tamanoPaginaMaximo',
    });
    final json = await _enviar(() => _cliente.get(uri, headers: _cabeceras(access)));
    return [for (final r in json['results'] as List) Reporte.fromJson(r as Map<String, dynamic>)];
  }

  /// Valida o rechaza un reporte pendiente (solo administradores).
  Future<Reporte> resolverReporte(String access, int id, {required bool validar}) async {
    final json = await _enviar(
      () => _cliente.post(
        baseUrl.resolve('reportes/$id/${validar ? 'validar' : 'rechazar'}/'),
        headers: _cabeceras(access),
      ),
    );
    return Reporte.fromJson(json);
  }

  /// La foto está protegida por sesión: se descarga con el token en vez de
  /// pasar la URL a `Image.network`, que en web no manda cabeceras.
  /// Solo se usa la ruta de [url]: detrás de Nginx/Cloudflare el backend la
  /// arma con otro host o esquema, y la API siempre vive en [baseUrl].
  Future<Uint8List> descargarFoto(String access, String url) async {
    final ruta = Uri.parse(url);
    final http.Response respuesta;
    try {
      respuesta = await _cliente.get(baseUrl.replace(path: ruta.path, query: ruta.query), headers: {'Authorization': 'Bearer $access'}).timeout(timeout);
    } on Exception {
      throw const ApiException('No se pudo descargar la foto.');
    }
    if (respuesta.statusCode != 200) {
      throw ApiException('La foto ya no está disponible.', status: respuesta.statusCode);
    }
    return respuesta.bodyBytes;
  }

  // --------------------------------------------------------- estadisticas --

  /// Focos, alertas y reportes de [desde] a [hasta] (ambos inclusivos).
  Future<Estadisticas> estadisticas(String access, {required DateTime desde, required DateTime hasta}) async {
    String dia(DateTime d) => d.toIso8601String().substring(0, 10);
    final uri = baseUrl.resolve('estadisticas/').replace(queryParameters: {'desde': dia(desde), 'hasta': dia(hasta)});
    return Estadisticas.fromJson(await _enviar(() => _cliente.get(uri, headers: _cabeceras(access))));
  }

  /// Informe de [desde] a [hasta] como archivo: `csv` (detalle de
  /// [conjunto]), `xlsx` (resumen y detalle) o `pdf` (resumen).
  Future<({Uint8List bytes, String nombre})> descargarInforme(
    String access, {
    required String formato,
    required DateTime desde,
    required DateTime hasta,
    String conjunto = 'focos',
  }) async {
    String dia(DateTime d) => d.toIso8601String().substring(0, 10);
    final uri = baseUrl.resolve('informes/').replace(queryParameters: {
      'formato': formato,
      'conjunto': conjunto,
      'desde': dia(desde),
      'hasta': dia(hasta),
    });
    // Un Excel de 92 días puede tardar varios segundos en generarse.
    final r = await _ejecutar(() => _cliente.get(uri, headers: {'Authorization': 'Bearer $access'}), timeout * 4);
    if (r.statusCode != 200) {
      throw _error(r.statusCode, _decodificar(r), 'Tu sesión expiró. Inicia sesión de nuevo.');
    }
    final nombre = RegExp(r'filename="([^"]+)"').firstMatch(r.headers['content-disposition'] ?? '')?.group(1);
    return (bytes: r.bodyBytes, nombre: nombre ?? 'vigia-informe.$formato');
  }

  // ------------------------------------------------------------ historicos --

  /// Qué hay cargado de cada fuente histórica (UNGRD, IDEAM y FIRMS), por año.
  Future<Map<String, dynamic>> resumenHistoricos(String access) =>
      _enviar(() => _cliente.get(baseUrl.resolve('historico/resumen/'), headers: _cabeceras(access)));

  /// Encola la descarga de los incendios nuevos de la UNGRD (solo staff).
  Future<void> sincronizarUngrd(String access) =>
      _enviar(() => _cliente.post(baseUrl.resolve('historico/ungrd/sincronizar/'), headers: _cabeceras(access)));

  // ---------------------------------------------------------- bot telegram --

  /// Estado del bot y de sus tres canales (sin token ni ids de chat).
  Future<Map<String, dynamic>> estadoBot(String access) =>
      _enviar(() => _cliente.get(baseUrl.resolve('bot-telegram/'), headers: _cabeceras(access)));

  /// Mensaje de prueba al [canal] (`telegram_publico|privado|interno`; solo staff).
  Future<void> probarCanal(String access, String canal) => _enviar(() => _cliente.post(
        baseUrl.resolve('bot-telegram/probar/'),
        headers: _cabeceras(access),
        body: jsonEncode({'canal': canal}),
      ));

  // ------------------------------------------------------------ internos --

  Map<String, String> _cabeceras([String? access]) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (access != null) 'Authorization': 'Bearer $access',
      };

  Future<Map<String, dynamic>> _enviar(
    Future<http.Response> Function() peticion, {
    String mensaje401 = 'Necesitas iniciar sesión para continuar.',
  }) =>
      _pedir<Map<String, dynamic>>(peticion, mensaje401: mensaje401);

  /// Para los endpoints que responden una lista JSON en vez de un objeto.
  Future<List<dynamic>> _enviarLista(Future<http.Response> Function() peticion) =>
      _pedir<List<dynamic>>(peticion, mensaje401: 'Necesitas iniciar sesión para continuar.');

  Future<T> _pedir<T>(
    Future<http.Response> Function() peticion, {
    required String mensaje401,
  }) async {
    final respuesta = await _ejecutar(peticion);
    final cuerpo = _decodificar(respuesta);
    final status = respuesta.statusCode;
    if (status >= 200 && status < 300 && cuerpo is T) return cuerpo;
    throw _error(status, cuerpo, mensaje401);
  }

  Future<http.Response> _ejecutar(Future<http.Response> Function() peticion, [Duration? limite]) async {
    try {
      return await peticion().timeout(limite ?? timeout);
    } on TimeoutException {
      throw const ApiException('El servidor tardó demasiado en responder. Inténtalo de nuevo.');
    } on http.ClientException {
      throw const ApiException(
        'No se pudo conectar con el servidor de Vigía. Revisa tu conexión a internet.',
      );
    }
  }

  ApiException _error(int status, Object? cuerpo, String mensaje401) {
    return ApiException(
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
