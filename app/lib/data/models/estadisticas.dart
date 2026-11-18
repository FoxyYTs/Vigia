/// DTO de `/api/estadisticas/` (apps/administracion/estadisticas.py).
class Estadisticas {
  const Estadisticas({
    required this.desde,
    required this.hasta,
    required this.nacional,
    required this.focos,
    required this.focosPorFuente,
    required this.focosPorDepartamento,
    required this.focosPorDia,
    required this.alertas,
    required this.alertasPorTipo,
    required this.reportes,
    required this.reportesPorEstado,
  });

  final DateTime desde;
  final DateTime hasta;

  /// `false` cuando el administrador solo ve la jurisdicción de su entidad.
  final bool nacional;
  final int focos;
  final List<Conteo> focosPorFuente;
  final List<Conteo> focosPorDepartamento;
  final List<Conteo> focosPorDia;
  final int alertas;
  final List<Conteo> alertasPorTipo;
  final int reportes;
  final List<Conteo> reportesPorEstado;

  factory Estadisticas.fromJson(Map<String, dynamic> json) {
    final focos = json['focos'] as Map<String, dynamic>;
    final alertas = json['alertas'] as Map<String, dynamic>;
    final reportes = json['reportes'] as Map<String, dynamic>;
    return Estadisticas(
      desde: DateTime.parse(json['desde'] as String),
      hasta: DateTime.parse(json['hasta'] as String),
      nacional: json['nacional'] as bool,
      focos: focos['total'] as int,
      focosPorFuente: Conteo.lista(focos['por_fuente']),
      focosPorDepartamento: Conteo.lista(focos['por_departamento']),
      focosPorDia: Conteo.lista(focos['por_dia'], campo: 'dia'),
      alertas: alertas['total'] as int,
      alertasPorTipo: Conteo.lista(alertas['por_tipo']),
      reportes: reportes['total'] as int,
      reportesPorEstado: Conteo.lista(reportes['por_estado']),
    );
  }
}

/// Una fila `{clave, cantidad}`. La clave es nula para los focos que caen
/// fuera de los municipios con polígono (mar, frontera).
class Conteo {
  const Conteo(this.clave, this.cantidad);

  final String? clave;
  final int cantidad;

  static List<Conteo> lista(Object? filas, {String campo = 'clave'}) => [
        for (final f in filas as List) Conteo((f as Map<String, dynamic>)[campo] as String?, f['cantidad'] as int),
      ];
}
