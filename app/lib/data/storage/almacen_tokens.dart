import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/usuario.dart';

/// Dónde se guardan los tokens JWT. Es una abstracción para que los tests
/// usen [AlmacenTokensMemoria] sin depender de los plugins de la plataforma.
abstract class AlmacenTokens {
  Future<Tokens?> leer();
  Future<void> guardar(Tokens tokens);
  Future<void> borrar();
}

/// Keystore en Android; en web, `localStorage` cifrado con WebCrypto
/// (flutter_secure_storage_web).
class AlmacenTokensSeguro implements AlmacenTokens {
  AlmacenTokensSeguro([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _claveAccess = 'vigia_access';
  static const _claveRefresh = 'vigia_refresh';

  final FlutterSecureStorage _storage;

  @override
  Future<Tokens?> leer() async {
    try {
      final access = await _storage.read(key: _claveAccess);
      final refresh = await _storage.read(key: _claveRefresh);
      if (access == null || refresh == null) return null;
      return Tokens(access: access, refresh: refresh);
    } catch (_) {
      // Almacén corrupto o clave de cifrado perdida: se trata como sin sesión.
      await borrar();
      return null;
    }
  }

  @override
  Future<void> guardar(Tokens tokens) async {
    await _storage.write(key: _claveAccess, value: tokens.access);
    await _storage.write(key: _claveRefresh, value: tokens.refresh);
  }

  @override
  Future<void> borrar() async {
    await _storage.delete(key: _claveAccess);
    await _storage.delete(key: _claveRefresh);
  }
}

class AlmacenTokensMemoria implements AlmacenTokens {
  Tokens? _tokens;

  @override
  Future<Tokens?> leer() async => _tokens;

  @override
  Future<void> guardar(Tokens tokens) async => _tokens = tokens;

  @override
  Future<void> borrar() async => _tokens = null;
}
