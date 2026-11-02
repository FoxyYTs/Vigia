import 'dart:convert';

/// Rol que viaja en el claim `rol` del JWT (Usuario.Rol en el backend).
/// Solo decide qué ve la interfaz: la autorización real la hace la API.
enum Rol {
  ciudadano('ciudadano', 'Ciudadano'),
  administrador('administrador', 'Administrador'),
  staff('staff', 'Staff'),
  desconocido('', 'Sin rol');

  const Rol(this.valorApi, this.etiqueta);

  final String valorApi;
  final String etiqueta;

  static Rol desdeApi(String? valor) =>
      values.firstWhere((r) => r.valorApi == valor, orElse: () => Rol.desconocido);
}

/// Par de tokens de simplejwt.
class Tokens {
  const Tokens({required this.access, required this.refresh});

  final String access;
  final String refresh;

  factory Tokens.fromJson(Map<String, dynamic> json) =>
      Tokens(access: json['access'] as String, refresh: json['refresh'] as String);
}

/// Datos que la app lee del payload del JWT (sin verificar la firma: eso lo
/// hace el backend en cada petición).
class ClaimsJwt {
  const ClaimsJwt({required this.username, required this.rol, required this.expira});

  final String username;
  final Rol rol;
  final DateTime expira;

  bool get vencido => DateTime.now().isAfter(expira.subtract(const Duration(seconds: 30)));

  static ClaimsJwt? decodificar(String token) {
    final partes = token.split('.');
    if (partes.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))))
          as Map<String, dynamic>;
      return ClaimsJwt(
        username: payload['username'] as String? ?? '',
        rol: Rol.desdeApi(payload['rol'] as String?),
        expira: DateTime.fromMillisecondsSinceEpoch((payload['exp'] as int) * 1000),
      );
    } catch (_) {
      return null;
    }
  }
}

/// DTO de `UsuarioSerializer` (`GET /api/auth/yo/`).
class Usuario {
  const Usuario({
    required this.id,
    required this.username,
    required this.email,
    required this.rol,
    this.municipioResidencia,
    this.entidad,
  });

  final int id;
  final String username;
  final String email;
  final Rol rol;
  final int? municipioResidencia;
  final int? entidad;

  factory Usuario.fromJson(Map<String, dynamic> json) => Usuario(
        id: json['id'] as int,
        username: json['username'] as String,
        email: json['email'] as String? ?? '',
        rol: Rol.desdeApi(json['rol'] as String?),
        municipioResidencia: json['municipio_residencia'] as int?,
        entidad: json['entidad'] as int?,
      );
}
