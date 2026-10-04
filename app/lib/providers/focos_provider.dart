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

  int contarPorFuente(FuenteSatelital f) => _focos.where((x) => x.fuente == f).length;

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
      final resto = await Future.wait([for (var n = 2; n <= paginas; n++) pagina(n)]);
      if (consulta != _consulta) return;

      _focos = [...primera.focos, for (final p in resto) ...p.focos];
      _total = primera.total;
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

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
