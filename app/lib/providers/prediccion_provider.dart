import 'package:flutter/foundation.dart';

import '../data/api/vigia_api.dart';
import '../data/models/zona.dart';

/// Capa de predicción del Mapa Interactivo: zonas de incendio recurrente
/// del modelo para uno de los 3 meses que predice la corrida más reciente.
///
/// Solo se piden las celdas con puntaje ≥ [puntajeMinimo]: el resto casi
/// nunca tiene fuego y dibujar las ~9.300 celdas pesaría en web.
class PrediccionProvider extends ChangeNotifier {
  PrediccionProvider({required this._api, this.puntajeMinimo = 0.3});

  final VigiaApi _api;
  final double puntajeMinimo;

  bool _visible = false;
  List<String> _meses = const [];
  DateTime? _fechaModelo;
  String? _mes;
  List<ZonaRecurrente> _zonas = const [];
  bool _cargando = false;
  String? _error;
  int _consulta = 0; // descarta respuestas de consultas ya reemplazadas

  bool get visible => _visible;
  List<String> get meses => _meses;
  DateTime? get fechaModelo => _fechaModelo;
  String? get mes => _mes;
  List<ZonaRecurrente> get zonas => _visible ? _zonas : const [];
  bool get cargando => _cargando;
  String? get error => _error;

  Future<void> mostrar(bool visible) async {
    _visible = visible;
    notifyListeners();
    if (visible && _mes == null) await _cargarMeses();
  }

  Future<void> cambiarMes(String mes) async {
    if (mes == _mes) return;
    _mes = mes;
    await _cargarZonas();
  }

  Future<void> _cargarMeses() async {
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      final disponibles = await _api.mesesPrediccion();
      _meses = disponibles.meses;
      _fechaModelo = disponibles.fechaEjecucion;
    } on ApiException catch (e) {
      _error = e.mensaje;
    }
    if (_meses.isEmpty) {
      _error ??= 'El modelo todavía no tiene predicciones.';
      _cargando = false;
      notifyListeners();
      return;
    }
    _mes = _meses.first;
    await _cargarZonas();
  }

  Future<void> _cargarZonas() async {
    final mes = _mes!;
    final consulta = ++_consulta;
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      Future<PaginaZonas> pagina(int n) => _api.listarZonas(mes: mes, minPuntaje: puntajeMinimo, pagina: n);
      final primera = await pagina(1);
      final paginas = (primera.total / VigiaApi.tamanoPaginaMaximo).ceil();
      final resto = await Future.wait([for (var n = 2; n <= paginas; n++) pagina(n)]);
      if (consulta != _consulta) return;
      _zonas = [...primera.zonas, for (final p in resto) ...p.zonas];
    } on ApiException catch (e) {
      if (consulta != _consulta) return;
      _error = e.mensaje;
    } finally {
      if (consulta == _consulta) {
        _cargando = false;
        notifyListeners();
      }
    }
  }
}
