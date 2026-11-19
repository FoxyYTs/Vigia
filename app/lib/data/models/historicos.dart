/// DTO de `/api/historico/resumen/` (apps/historico/views.py).
class ResumenHistoricos {
  const ResumenHistoricos({
    required this.ungrdTotal,
    required this.ungrdSinMunicipio,
    required this.ungrdDesde,
    required this.ungrdHasta,
    required this.ungrdPorAnio,
    required this.ideamPorAnio,
    required this.firmsTotal,
    required this.firmsPorAnio,
  });

  final int ungrdTotal;
  final int ungrdSinMunicipio;
  final DateTime? ungrdDesde;
  final DateTime? ungrdHasta;

  /// (año, [incendios, hectáreas]).
  final List<(int, List<num?>)> ungrdPorAnio;

  /// (año, [municipios, hectáreas]).
  final List<(int, List<num?>)> ideamPorAnio;
  final int firmsTotal;

  /// (año, [detecciones]).
  final List<(int, List<num?>)> firmsPorAnio;

  factory ResumenHistoricos.fromJson(Map<String, dynamic> json) {
    final ungrd = json['ungrd'] as Map<String, dynamic>;
    final ideam = json['ideam'] as Map<String, dynamic>;
    final firms = json['firms'] as Map<String, dynamic>;
    DateTime? fecha(Object? v) => v == null ? null : DateTime.parse(v as String);
    List<(int, List<num?>)> filas(Map<String, dynamic> fuente, List<String> campos) => [
          for (final f in (fuente['por_anio'] as List).cast<Map<String, dynamic>>())
            (f['anio'] as int, [for (final c in campos) f[c] as num?]),
        ];
    return ResumenHistoricos(
      ungrdTotal: ungrd['total'] as int,
      ungrdSinMunicipio: ungrd['sin_municipio'] as int,
      ungrdDesde: fecha(ungrd['desde']),
      ungrdHasta: fecha(ungrd['hasta']),
      ungrdPorAnio: filas(ungrd, ['cantidad', 'hectareas']),
      ideamPorAnio: filas(ideam, ['municipios', 'hectareas']),
      firmsTotal: firms['total'] as int,
      firmsPorAnio: filas(firms, ['cantidad']),
    );
  }
}
