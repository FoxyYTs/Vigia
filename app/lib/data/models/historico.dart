import 'package:latlong2/latlong.dart';

/// Indicadores de la capa "Histórico" (`/api/historico/capa/`).
enum IndicadorHistorico {
  incendiosUngrd('incendios_ungrd', 'Incendios reportados', 'UNGRD', 'incendios'),
  deforestacionIdeam('deforestacion_ideam', 'Deforestación', 'IDEAM', 'ha');

  const IndicadorHistorico(this.valorApi, this.etiqueta, this.fuente, this.unidad);

  final String valorApi;
  final String etiqueta;
  final String fuente;
  final String unidad;
}

/// Municipio de `/api/municipios/geometria/`: anillos exteriores de su
/// MultiPolygon, ya simplificados a ~1 km por el backend.
class MunicipioGeo {
  const MunicipioGeo({required this.codigoDane, required this.nombre, required this.departamento, required this.anillos});

  final String codigoDane;
  final String nombre;
  final String departamento;
  final List<List<LatLng>> anillos;

  factory MunicipioGeo.fromFeature(Map<String, dynamic> f) {
    final props = f['properties'] as Map<String, dynamic>;
    return MunicipioGeo(
      codigoDane: props['codigo_dane'] as String,
      nombre: props['nombre'] as String,
      departamento: props['departamento'] as String,
      anillos: [
        for (final poligono in f['geometry']['coordinates'] as List)
          [for (final p in (poligono as List)[0] as List) LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())],
      ],
    );
  }
}
