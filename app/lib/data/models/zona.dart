import 'package:latlong2/latlong.dart';

/// DTO de `ZonaRecurrenteSerializer` (apps/prediccion/serializers.py): una
/// celda de ~11 km con la probabilidad de detecciones en su mes objetivo.
class ZonaRecurrente {
  const ZonaRecurrente({
    required this.id,
    required this.puntaje,
    required this.mesesConFuego,
    required this.contorno,
    this.municipio,
  });

  final int id;
  final double puntaje;
  final int mesesConFuego;
  final List<LatLng> contorno;
  final String? municipio;

  factory ZonaRecurrente.fromJson(Map<String, dynamic> json) {
    // MultiPolygon GeoJSON: primer polígono, anillo exterior, puntos [lon, lat].
    final anillo = (json['area']['coordinates'] as List)[0][0] as List;
    return ZonaRecurrente(
      id: json['id'] as int,
      puntaje: (json['puntaje_recurrencia'] as num).toDouble(),
      mesesConFuego: json['cantidad_incendios_historicos'] as int,
      municipio: json['municipio'] as String?,
      contorno: [
        for (final p in anillo) LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
      ],
    );
  }
}

class PaginaZonas {
  const PaginaZonas({required this.total, required this.zonas});

  final int total;
  final List<ZonaRecurrente> zonas;

  factory PaginaZonas.fromJson(Map<String, dynamic> json) => PaginaZonas(
        total: json['count'] as int,
        zonas: (json['results'] as List)
            .map((e) => ZonaRecurrente.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// `/api/zonas-recurrentes/meses/`: meses que predice la corrida más reciente.
class MesesPrediccion {
  const MesesPrediccion({required this.meses, this.fechaEjecucion});

  /// "AAAA-MM", en orden.
  final List<String> meses;
  final DateTime? fechaEjecucion;

  factory MesesPrediccion.fromJson(Map<String, dynamic> json) => MesesPrediccion(
        meses: [for (final m in json['meses'] as List) m as String],
        fechaEjecucion: json['fecha_ejecucion'] == null ? null : DateTime.parse(json['fecha_ejecucion'] as String),
      );
}
