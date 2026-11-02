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
  Future<Tokens>? _renovando; // una sola renovación a la vez

  EstadoSesion get estado => _estado;
  bool get autenticado => _estado == EstadoSesion.autenticada;
  bool get enviando => _enviando;
  String? get error => _error;
  String get username => _claims?.username ?? '';
  Rol get rol => _claims?.rol ?? Rol.desconocido;

  /// Restaura la sesión guardada (si el access venció, intenta renovarlo
  /// con el refresh; si el servidor lo rechaza, queda como anónima). Sin
  /// conexión se conserva la sesión: renovará en la próxima llamada.
  Future<void> restaurar() async {
    final guardados = await _almacen.leer();
    if (guardados != null) {
      try {
        await _usar(await _vigentes(guardados));
        return;
      } on ApiException catch (e) {
        if (!e.noAutorizado) {
          await _usar(guardados);
          return;
        }
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
      await _usar(await _api.iniciarSesion(username.trim(), password));
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
    final refresh = _tokens?.refresh ?? (await _almacen.leer())?.refresh;
    await _almacen.borrar();
    _limpiar();
    if (refresh == null) return;
    try {
      await _api.revocarSesion(refresh);
    } on ApiException {
      // Ya se cerró en el dispositivo; si el servidor no responde, el refresh
      // vence solo en un día.
    }
  }

  /// Access token vigente para llamar endpoints protegidos.
  Future<String> accessToken() async {
    final tokens = _tokens;
    if (tokens == null) throw const ApiException('Necesitas iniciar sesión.', status: 401);
    try {
      final vigentes = await _vigentes(tokens);
      if (!identical(vigentes, tokens)) await _usar(vigentes);
      return vigentes.access;
    } on ApiException catch (e) {
      // Solo un 401 significa sesión inválida; un timeout no debe cerrarla.
      if (e.noAutorizado) await _cerrarLocal();
      rethrow;
    }
  }

  void limpiarError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Los mismos [tokens] si el access sigue vigente; si no, los renovados.
  /// Varias llamadas a la vez comparten una sola renovación: con la rotación
  /// del refresh, dos renovaciones en paralelo revocarían la sesión.
  Future<Tokens> _vigentes(Tokens tokens) {
    final claims = ClaimsJwt.decodificar(tokens.access);
    if (claims != null && !claims.vencido) return Future.value(tokens);
    return _renovando ??= _api.renovarSesion(tokens.refresh).whenComplete(() => _renovando = null);
  }

  Future<void> _cerrarLocal() async {
    await _almacen.borrar();
    _limpiar();
  }

  Future<void> _usar(Tokens tokens) async {
    final claims = ClaimsJwt.decodificar(tokens.access);
    if (claims == null) throw const ApiException('El servidor devolvió un token inválido.');
    _tokens = tokens;
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
