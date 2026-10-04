import 'package:flutter/foundation.dart' show kIsWeb;

/// Configuración de la app tomada del entorno de compilación (Twelve-Factor:
/// la URL de la API no se escribe en el código).
///
/// ```bash
/// flutter build web --dart-define=API_BASE_URL=https://vigia.foxyyts.qzz.io/api/
/// ```
///
/// Si no se define:
/// - en web se usa `/api/` del mismo origen que sirve la app (Nginx sirve la
///   app y hace de proxy a Django, así que no hace falta CORS);
/// - en Android se usa el host del emulador (`10.0.2.2`), útil solo en
///   desarrollo.
class AppConfig {
  const AppConfig._();

  static const String _apiBaseUrlDefinida = String.fromEnvironment('API_BASE_URL');

  static Uri get apiBaseUrl {
    if (_apiBaseUrlDefinida.isNotEmpty) return normalizarBase(_apiBaseUrlDefinida);
    if (kIsWeb) return Uri.base.resolve('/api/');
    return Uri.parse('http://10.0.2.2:8080/api/');
  }

  /// Garantiza la barra final para que `resolve('auth/token/')` no
  /// reemplace el último segmento de la ruta.
  static Uri normalizarBase(String url) =>
      Uri.parse(url.endsWith('/') ? url : '$url/');
}
