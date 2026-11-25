import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vigia_app/data/models/foco.dart';
import 'package:vigia_app/widgets/agrupar_focos.dart';

var _id = 0;
Foco _foco(double lat, double lon, [FuenteSatelital fuente = FuenteSatelital.nasaFirms]) => Foco(
      id: ++_id,
      fuente: fuente,
      posicion: LatLng(lat, lon),
      fechaHora: DateTime.utc(2026, 11, 25),
      confianza: '',
      brilloFrp: null,
      satelite: '',
    );

void main() {
  // Dos focos a ~1 km en Antioquia y uno en La Guajira.
  final antioquia = [_foco(6.150, -75.370), _foco(6.155, -75.375, FuenteSatelital.inpeQueimadas), _foco(6.152, -75.371)];
  final guajira = _foco(11.5, -72.9);
  final focos = [...antioquia, guajira];

  test('con zoom bajo junta los cercanos y separa los lejanos', () {
    final grupos = agruparFocos(focos, 5);
    expect(grupos.map((g) => g.focos.length), [3, 1]);
    expect(grupos.first.fuentePrincipal, FuenteSatelital.nasaFirms);
    expect(grupos.first.limites.contains(grupos.first.centro), isTrue);
  });

  test('al acercar se separan y nunca se pierde un foco', () {
    for (final zoom in [4, 8, zoomSinAgrupar, 16]) {
      expect(agruparFocos(focos, zoom).expand((g) => g.focos), unorderedEquals(focos));
    }
    expect(agruparFocos(focos, 16), hasLength(4));
  });
}
