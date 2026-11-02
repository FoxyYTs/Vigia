import 'package:flutter/foundation.dart';

import '../data/api/vigia_api.dart';
import '../data/models/historico.dart';

/// Capa "Histórico" del Mapa Interactivo: municipios coloreados por
/// incendios reportados a la UNGRD o por deforestación del IDEAM en un año.
///
/// La geometría de los municipios se pide una sola vez; al cambiar de
/// indicador o de año solo se piden los valores.
class HistoricoProvider extends ChangeNotifier {
  HistoricoProvider({required this._api});

  static const clases = 5;

  final VigiaApi _api;

  bool _visible = false;
  List<MunicipioGeo>? _municipios;
  Map<IndicadorHistorico, List<int>> _disponible = const {};
  IndicadorHistorico _indicador = IndicadorHistorico.incendiosUngrd;
  int? _anio;
  Map<String, double> _valores = const {};
  List<double> _cortes = const [];
  bool _cargando = false;
  String? _error;
  int _consulta = 0; // descarta respuestas de consultas ya reemplazadas
  int _version = 0;

  bool get visible => _visible;

  /// Cambia cada vez que cambian los colores: el mapa solo reconstruye sus
  /// polígonos entonces, no en cada selección de foco.
  int get version => _version;
  IndicadorHistorico get indicador => _indicador;
  int? get anio => _anio;
  List<int> get anios => _disponible[_indicador] ?? const [];
  bool get cargando => _cargando;
  String? get error => _error;

  /// Límites superiores de las primeras [clases] − 1 clases (cuantiles de los
  /// valores positivos). La última clase no tiene límite superior.
  List<double> get cortes => _cortes;

  /// Municipios con valor > 0 en la selección actual, con su clase (0 a 4).
  List<(MunicipioGeo, int)> get coloreados {
    final municipios = _municipios;
    if (!_visible || municipios == null) return const [];
    return [
      for (final m in municipios)
        if ((_valores[m.codigoDane] ?? 0) > 0) (m, claseDe(_valores[m.codigoDane]!)),
    ];
  }

  double? valorDe(String codigoDane) => _valores[codigoDane];

  int claseDe(double valor) {
    for (var i = 0; i < _cortes.length; i++) {
      if (valor <= _cortes[i]) return i;
    }
    return _cortes.length;
  }

  Future<void> mostrar(bool visible) async {
    _visible = visible;
    _version++;
    notifyListeners();
    if (visible && _municipios == null) await _cargarBase();
  }

  Future<void> cambiarIndicador(IndicadorHistorico indicador) async {
    if (indicador == _indicador) return;
    _indicador = indicador;
    // Cada indicador tiene sus propios años: se conserva el año si existe.
    if (!anios.contains(_anio)) _anio = anios.isEmpty ? null : anios.last;
    await _cargarValores();
  }

  Future<void> cambiarAnio(int anio) async {
    if (anio == _anio) return;
    _anio = anio;
    await _cargarValores();
  }

  Future<void> _cargarBase() async {
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      _disponible = await _api.disponibilidadHistorica();
      _municipios = await _api.geometriaMunicipios();
      _anio = anios.isEmpty ? null : anios.last;
    } on ApiException catch (e) {
      _error = e.mensaje;
      _cargando = false;
      notifyListeners();
      return;
    }
    await _cargarValores();
  }

  Future<void> _cargarValores() async {
    final anio = _anio;
    final consulta = ++_consulta;
    if (anio == null) {
      _valores = const {};
      _cortes = const [];
      _error = 'No hay datos de ${_indicador.etiqueta.toLowerCase()}.';
      _cargando = false;
      notifyListeners();
      return;
    }
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      final valores = await _api.capaHistorica(_indicador, anio);
      if (consulta != _consulta) return;
      _valores = valores;
      _cortes = cortesPorCuantiles(valores.values.where((v) => v > 0).toList(), clases);
      _version++;
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

/// Cortes de [clases] grupos con la misma cantidad de valores (cuantiles).
/// Se eliminan cortes repetidos: con pocos valores distintos (p. ej. muchos
/// municipios con 1 incendio) quedan menos clases, pero ninguna vacía.
List<double> cortesPorCuantiles(List<double> valores, int clases) {
  if (valores.isEmpty) return const [];
  final ordenados = [...valores]..sort();
  final cortes = <double>{
    for (var i = 1; i < clases; i++) ordenados[((ordenados.length * i) / clases).ceil() - 1],
  }..remove(ordenados.last);
  return cortes.toList()..sort();
}
