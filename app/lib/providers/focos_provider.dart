import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/api/vigia_api.dart';
import '../data/models/foco.dart';

/// Ventanas de tiempo del filtro. La API acepta como máximo 31 días.
enum Ventana {
  h24('24 h', Duration(hours: 24)),
  h48('48 h', Duration(hours: 48)),
  d7('7 días', Duration(days: 7)),
  d31('31 días', Duration(days: 31));

  const Ventana(this.etiqueta, this.duracion);

  final String etiqueta;
  final Duration duracion;
}

/// Focos del Mapa Interactivo y sus filtros.
///
/// Para que el mapa siga siendo fluido, se piden como máximo
/// [maximoFocos] puntos (páginas de 500 en paralelo); si el rango tiene más,
/// la pantalla lo indica y sugiere acotar el filtro.
class FocosProvider extends ChangeNotifier {
  FocosProvider({required this._api, this.maximoFocos = 5000});

  final VigiaApi _api;
  final int maximoFocos;

  Ventana _ventana = Ventana.h48;
  FuenteSatelital? _fuente;
  DateTime? _corte;
  DateTime? _ultimoDisponible;

  List<Foco> _focos = const [];
  int _total = 0;
  Map<FuenteSatelital, int> _totalPorFuente = const {};
  bool _cargando = false;
  String? _error;
  Foco? _seleccionado;
  int _consulta = 0; // descarta respuestas de consultas ya reemplazadas

  Ventana get ventana => _ventana;
  FuenteSatelital? get fuente => _fuente;
  DateTime? get corte => _corte;
  DateTime? get ultimoDisponible => _ultimoDisponible;
  DateTime? get desde => _corte?.subtract(_ventana.duracion);
  List<Foco> get focos => _focos;
  int get total => _total;
  bool get truncado => _focos.length < _total;
  bool get cargando => _cargando;
  String? get error => _error;
  Foco? get seleccionado => _seleccionado;

  /// Focos de la fuente en todo el rango (no solo los dibujados), para que
  /// el desglose sume lo mismo que [total].
  int contarPorFuente(FuenteSatelital f) => _totalPorFuente[f] ?? 0;

  /// Primera carga: usa como fecha de corte el foco más reciente disponible,
  /// así el mapa nunca arranca vacío por una ingesta detenida.
  Future<void> inicializar() async {
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      _ultimoDisponible = await _api.fechaUltimoFoco();
      _corte = _ultimoDisponible ?? DateTime.now();
    } on ApiException catch (e) {
      _error = e.mensaje;
      _cargando = false;
      notifyListeners();
      return;
    }
    await cargar();
  }

  void cambiarVentana(Ventana v) {
    if (v == _ventana) return;
    _ventana = v;
    cargar();
  }

  void cambiarFuente(FuenteSatelital? f) {
    if (f == _fuente) return;
    _fuente = f;
    cargar();
  }

  /// [dia] es la fecha de corte elegida en el calendario (se toma el final
  /// de ese día, o el último foco disponible si es ese mismo día).
  void cambiarCorte(DateTime dia) {
    final finDelDia = DateTime(dia.year, dia.month, dia.day, 23, 59, 59);
    final ultimo = _ultimoDisponible;
    _corte = (ultimo != null && ultimo.isBefore(finDelDia) && _mismoDia(ultimo.toLocal(), dia))
        ? ultimo
        : finDelDia;
    cargar();
  }

  void seleccionar(Foco? foco) {
    _seleccionado = foco;
    notifyListeners();
  }

  Future<void> cargar() async {
    final corte = _corte;
    if (corte == null) return inicializar();
    final consulta = ++_consulta;
    _cargando = true;
    _error = null;
    _seleccionado = null;
    notifyListeners();

    try {
      final desde = corte.subtract(_ventana.duracion);
      Future<PaginaFocos> pagina(int n) =>
          _api.listarFocos(desde: desde, hasta: corte, fuente: _fuente, pagina: n);

      final primera = await pagina(1);
      final paginas = math.min(
        (primera.total / VigiaApi.tamanoPaginaMaximo).ceil(),
        (maximoFocos / VigiaApi.tamanoPaginaMaximo).ceil(),
      );
      final resto = Future.wait([for (var n = 2; n <= paginas; n++) pagina(n)]);
      // Con truncado y sin filtro de fuente, los dibujados no bastan para el
      // desglose: se pide el total de cada fuente al servidor.
      final conteoServidor =
          (_fuente == null && primera.total > maximoFocos) ? _contarEnServidor(desde, corte) : null;
      final paginasResto = await resto;
      final totalesServidor = await conteoServidor;
      if (consulta != _consulta) return;

      _focos = [...primera.focos, for (final p in paginasResto) ...p.focos];
      _total = primera.total;
      final fuente = _fuente;
      _totalPorFuente = totalesServidor ??
          {
            for (final f in FuenteSatelital.values)
              f: fuente != null
                  ? (f == fuente ? _total : 0)
                  : _focos.where((x) => x.fuente == f).length,
          };
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

  /// `count` de cada fuente en el rango, con páginas de un solo elemento.
  Future<Map<FuenteSatelital, int>> _contarEnServidor(DateTime desde, DateTime hasta) async {
    final conteos = await Future.wait([
      for (final f in FuenteSatelital.values)
        _api.listarFocos(desde: desde, hasta: hasta, fuente: f, tamanoPagina: 1).then((p) => p.total),
    ]);
    return {for (final (i, f) in FuenteSatelital.values.indexed) f: conteos[i]};
  }

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
