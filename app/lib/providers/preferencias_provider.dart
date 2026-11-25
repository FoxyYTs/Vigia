import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preferencias de la interfaz que se recuerdan entre sesiones: el tema y si
/// el mapa agrupa los focos. Sin almacén (pruebas) viven solo en memoria.
class PreferenciasProvider extends ChangeNotifier {
  PreferenciasProvider({this._almacen});

  static const _claveTema = 'vigia_tema';
  static const _claveAgrupar = 'vigia_agrupar_focos';

  final FlutterSecureStorage? _almacen;

  ThemeMode _tema = ThemeMode.system;
  bool _agruparFocos = true;

  ThemeMode get tema => _tema;
  bool get agruparFocos => _agruparFocos;

  Future<void> cargar() async {
    try {
      final tema = await _almacen?.read(key: _claveTema);
      final agrupar = await _almacen?.read(key: _claveAgrupar);
      _tema = ThemeMode.values.asNameMap()[tema] ?? ThemeMode.system;
      _agruparFocos = agrupar != 'false';
      notifyListeners();
    } catch (_) {
      // Almacén ilegible: se quedan los valores por defecto.
    }
  }

  void cambiarTema(ThemeMode tema) {
    if (tema == _tema) return;
    _tema = tema;
    notifyListeners();
    _guardar(_claveTema, tema.name);
  }

  void cambiarAgruparFocos(bool agrupar) {
    if (agrupar == _agruparFocos) return;
    _agruparFocos = agrupar;
    notifyListeners();
    _guardar(_claveAgrupar, '$agrupar');
  }

  // Si no se puede guardar, la preferencia igual aplica en esta sesión.
  void _guardar(String clave, String valor) => _almacen?.write(key: clave, value: valor).catchError((_) {});
}
