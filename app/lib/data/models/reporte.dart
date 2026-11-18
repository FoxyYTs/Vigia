import 'package:latlong2/latlong.dart';

/// Valores de `ReporteCiudadano.Estado` en el backend.
enum EstadoReporte {
  pendiente('pendiente', 'Pendiente'),
  validado('validado', 'Validado'),
  rechazado('rechazado', 'Rechazado');

  const EstadoReporte(this.valorApi, this.etiqueta);

  final String valorApi;
  final String etiqueta;

  static EstadoReporte desdeApi(String? valor) =>
      values.firstWhere((e) => e.valorApi == valor, orElse: () => pendiente);
}

/// DTO de `ReporteCiudadanoSerializer` (apps/reportes/serializers.py).
class Reporte {
  const Reporte({
    required this.id,
    required this.ciudadano,
    required this.ubicacionIncendio,
    required this.estado,
    required this.fechaCreacion,
    this.descripcion = '',
    this.miniaturaUrl,
    this.distanciaKm,
  });

  final int id;
  final String ciudadano;
  final LatLng ubicacionIncendio;
  final EstadoReporte estado;
  final DateTime fechaCreacion;
  final String descripcion;

  /// Nula cuando la foto ya se borró por retención.
  final String? miniaturaUrl;

  /// Distancia entre el ciudadano y el incendio; nula si la cuenta se eliminó.
  final double? distanciaKm;

  factory Reporte.fromJson(Map<String, dynamic> json) {
    final ubicacion = json['ubicacion_incendio'] as Map<String, dynamic>;
    return Reporte(
      id: json['id'] as int,
      ciudadano: json['ciudadano'] as String? ?? '',
      ubicacionIncendio: LatLng((ubicacion['latitud'] as num).toDouble(), (ubicacion['longitud'] as num).toDouble()),
      estado: EstadoReporte.desdeApi(json['estado'] as String?),
      fechaCreacion: DateTime.parse(json['fecha_creacion'] as String),
      descripcion: json['descripcion'] as String? ?? '',
      miniaturaUrl: json['miniatura_url'] as String?,
      distanciaKm: (json['distancia_reportada_km'] as num?)?.toDouble(),
    );
  }
}
