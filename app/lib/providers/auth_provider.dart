import 'package:flutter/foundation.dart';

import '../data/api/vigia_api.dart';
import '../data/models/usuario.dart';
import '../data/storage/almacen_tokens.dart';

enum EstadoSesion { verificando, anonima, autenticada }

/// Estado de la sesión JWT. Las pantallas solo leen este provider; la
/// comunicación con la API y el almacenamiento están inyectados.
class AuthProvider extends ChangeNotifier {
  AuthProvider({required this._api, required this._almacen});

  final VigiaApi _api;
  final AlmacenTokens _almacen;

  EstadoSesion _estado = EstadoSesion.verificando;
  Tokens? _tokens;
  ClaimsJwt? _claims;
  bool _enviando = false;
  String? _error;

  EstadoSesion get estado => _estado;
  bool get autenticado => _estado == EstadoSesion.autenticada;
  bool get enviando => _enviando;
  String? get error => _error;
  String get username => _claims?.username ?? '';
  Rol get rol => _claims?.rol ?? Rol.desconocido;

  /// Restaura la sesión guardada (si el access venció, intenta renovarlo
  /// con el refresh; si tampoco sirve, queda como anónima).
  Future<void> restaurar() async {
    final guardados = await _almacen.leer();
    if (guardados != null) {
      try {
        await _usar(guardados.refresh, await _accessVigente(guardados));
        return;
      } on ApiException {
        await _almacen.borrar();
      }
    }
    _limpiar();
  }

  Future<bool> iniciarSesion(String username, String password) async {
    _enviando = true;
    _error = null;
    notifyListeners();
    try {
      final tokens = await _api.iniciarSesion(username.trim(), password);
      await _usar(tokens.refresh, tokens.access);
      return true;
    } on ApiException catch (e) {
      _error = e.mensaje;
      return false;
    } finally {
      _enviando = false;
      notifyListeners();
    }
  }

  Future<void> cerrarSesion() async {
    await _almacen.borrar();
    _limpiar();
  }

  /// Access token vigente para llamar endpoints protegidos.
  Future<String> accessToken() async {
    final tokens = _tokens;
    if (tokens == null) throw const ApiException('Necesitas iniciar sesión.', status: 401);
    try {
      final access = await _accessVigente(tokens);
      if (access != tokens.access) await _usar(tokens.refresh, access);
      return access;
    } on ApiException {
      await cerrarSesion();
      rethrow;
    }
  }

  void limpiarError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<String> _accessVigente(Tokens tokens) async {
    final claims = ClaimsJwt.decodificar(tokens.access);
    if (claims != null && !claims.vencido) return tokens.access;
    return _api.refrescarAcceso(tokens.refresh);
  }

  Future<void> _usar(String refresh, String access) async {
    final claims = ClaimsJwt.decodificar(access);
    if (claims == null) throw const ApiException('El servidor devolvió un token inválido.');
    _tokens = Tokens(access: access, refresh: refresh);
    _claims = claims;
    await _almacen.guardar(_tokens!);
    _estado = EstadoSesion.autenticada;
    notifyListeners();
  }

  void _limpiar() {
    _tokens = null;
    _claims = null;
    _error = null;
    _estado = EstadoSesion.anonima;
    notifyListeners();
  }
}
