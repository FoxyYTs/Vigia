import 'package:latlong2/latlong.dart';

/// Fuentes satelitales que expone `/api/focos/` (valores de
/// `FocoIncendio.Fuente` en el backend).
enum FuenteSatelital {
  nasaFirms('NASA_FIRMS', 'NASA FIRMS'),
  inpeQueimadas('INPE_QUEIMADAS', 'INPE QUEIMADAS');

  const FuenteSatelital(this.valorApi, this.etiqueta);

  final String valorApi;
  final String etiqueta;

  static FuenteSatelital? desdeApi(String valor) {
    for (final f in values) {
      if (f.valorApi == valor) return f;
    }
    return null;
  }
}

/// DTO de `FocoIncendioSerializer` (apps/satelital/serializers.py).
class Foco {
  const Foco({
    required this.id,
    required this.fuente,
    required this.posicion,
    required this.fechaHora,
    this.confianza = '',
    this.brilloFrp,
    this.satelite = '',
  });

  final int id;
  final FuenteSatelital? fuente;
  final LatLng posicion;
  final DateTime fechaHora;
  final String confianza;
  final double? brilloFrp;
  final String satelite;

  factory Foco.fromJson(Map<String, dynamic> json) => Foco(
        id: json['id'] as int,
        fuente: FuenteSatelital.desdeApi(json['fuente'] as String? ?? ''),
        posicion: LatLng(
          (json['latitud'] as num).toDouble(),
          (json['longitud'] as num).toDouble(),
        ),
        fechaHora: DateTime.parse(json['fecha_hora'] as String),
        confianza: json['confianza'] as String? ?? '',
        brilloFrp: (json['brillo_frp'] as num?)?.toDouble(),
        satelite: json['satelite'] as String? ?? '',
      );

  /// VIIRS reporta la confianza como l/n/h; INPE no la reporta.
  String get confianzaLegible => switch (confianza.toLowerCase()) {
        'l' || 'low' => 'Baja',
        'n' || 'nominal' => 'Nominal',
        'h' || 'high' => 'Alta',
        '' => 'No reportada',
        _ => confianza,
      };
}

/// Una página de `/api/focos/` (paginación estándar de DRF).
class PaginaFocos {
  const PaginaFocos({required this.total, required this.focos, required this.haySiguiente});

  final int total;
  final List<Foco> focos;
  final bool haySiguiente;

  factory PaginaFocos.fromJson(Map<String, dynamic> json) => PaginaFocos(
        total: json['count'] as int,
        haySiguiente: json['next'] != null,
        focos: (json['results'] as List)
            .map((e) => Foco.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
