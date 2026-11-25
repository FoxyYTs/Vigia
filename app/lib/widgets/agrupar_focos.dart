import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/foco.dart';

/// Desde este zoom los focos se dibujan sueltos.
const zoomSinAgrupar = 12;

/// Focos que caen en la misma celda de la pantalla.
class GrupoFocos {
  GrupoFocos(this.focos);

  final List<Foco> focos;

  LatLng get centro => LatLng(
        focos.fold(0.0, (s, f) => s + f.posicion.latitude) / focos.length,
        focos.fold(0.0, (s, f) => s + f.posicion.longitude) / focos.length,
      );

  LatLngBounds get limites => LatLngBounds.fromPoints([for (final f in focos) f.posicion]);

  /// La fuente con más focos del grupo (en empate, la del primero).
  FuenteSatelital? get fuentePrincipal {
    final conteo = <FuenteSatelital?, int>{};
    for (final f in focos) {
      conteo[f.fuente] = (conteo[f.fuente] ?? 0) + 1;
    }
    return conteo.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}

/// Agrupa [focos] en celdas de [celda] px al [zoom] entero, en el orden en que
/// aparece el primer foco de cada celda.
///
/// shortcut: rejilla fija, así dos focos vecinos a lados de una frontera de
/// celda quedan en grupos distintos; pasar a supercluster si eso molesta.
List<GrupoFocos> agruparFocos(List<Foco> focos, int zoom, {double celda = 80, Crs crs = const Epsg3857()}) {
  final escala = crs.scale(zoom.toDouble());
  final celdas = <(int, int), List<Foco>>{};
  for (final f in focos) {
    final (x, y) = crs.latLngToXY(f.posicion, escala);
    (celdas[((x / celda).floor(), (y / celda).floor())] ??= []).add(f);
  }
  return [for (final c in celdas.values) GrupoFocos(c)];
}
