import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/models/foco.dart';
import '../providers/focos_provider.dart';
import '../providers/historico_provider.dart';
import '../providers/prediccion_provider.dart';
import 'panel_filtros.dart' show colorFuente, colorPuntaje, coloresHistorico;

/// Rectángulo que contiene el territorio continental e insular de Colombia.
final limitesColombia = LatLngBounds(const LatLng(-4.3, -79.2), const LatLng(13.6, -66.8));

/// Mapa base de OpenStreetMap con los focos como
/// círculos. Tocar un círculo lo selecciona en [FocosProvider].
class MapaFocos extends StatefulWidget {
  const MapaFocos({super.key, required this.controller});

  final MapController controller;

  @override
  State<MapaFocos> createState() => _MapaFocosState();
}

class _MapaFocosState extends State<MapaFocos> {
  final LayerHitNotifier<Foco> _hit = ValueNotifier(null);

  List<Foco>? _focosPrevios;
  List<CircleMarker<Foco>> _circulos = const [];
  int? _versionHistorico;
  List<Polygon> _municipios = const [];

  List<Polygon> _poligonosHistoricos(HistoricoProvider h) {
    if (h.version != _versionHistorico) {
      _versionHistorico = h.version;
      final colores = coloresHistorico(h.indicador);
      _municipios = [
        for (final (m, clase) in h.coloreados)
          for (final anillo in m.anillos) Polygon(points: anillo, color: colores[clase].withValues(alpha: 0.6)),
      ];
    }
    return _municipios;
  }

  static double _radio(Foco f) {
    final frp = f.brilloFrp;
    if (frp == null || frp <= 0) return 4;
    return 4 + math.min(6, math.log(frp + 1) * 1.4);
  }

  /// Los círculos solo se reconstruyen cuando cambia la lista de focos (no
  /// en cada selección), para que el mapa siga fluido con miles de puntos.
  List<CircleMarker<Foco>> _circulosDe(List<Foco> focos) {
    if (!identical(focos, _focosPrevios)) {
      _focosPrevios = focos;
      _circulos = [
        // Los más antiguos primero: los recientes quedan dibujados encima.
        for (final f in focos.reversed)
          CircleMarker<Foco>(
            point: f.posicion,
            radius: _radio(f),
            color: colorFuente(f.fuente).withValues(alpha: 0.78),
            borderColor: Colors.white,
            borderStrokeWidth: 0.8,
            hitValue: f,
          ),
      ];
    }
    return _circulos;
  }

  @override
  void dispose() {
    _hit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FocosProvider>();
    final zonas = context.watch<PrediccionProvider>().zonas;
    final historico = _poligonosHistoricos(context.watch<HistoricoProvider>());
    final seleccionado = p.seleccionado;

    return Semantics(
      label: 'Mapa de Colombia con ${p.focos.length} focos de calor. '
          'Usa el panel de filtros para cambiar el rango y la fuente.',
      child: FlutterMap(
        mapController: widget.controller,
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(bounds: limitesColombia, padding: const EdgeInsets.all(24)),
          minZoom: 4,
          maxZoom: 16,
          cameraConstraint: CameraConstraint.containCenter(
            bounds: LatLngBounds(const LatLng(-15, -90), const LatLng(20, -55)),
          ),
          onTap: (_, _) => p.seleccionar(null),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.vigia.foxyyts',
          ),
          if (historico.isNotEmpty) PolygonLayer(polygons: historico),
          // Debajo de los focos: la predicción es contexto, los focos son lo observado.
          if (zonas.isNotEmpty)
            PolygonLayer(
              polygons: [
                for (final z in zonas)
                  Polygon(points: z.contorno, color: colorPuntaje(z.puntaje).withValues(alpha: 0.45)),
              ],
            ),
          MouseRegion(
            hitTestBehavior: HitTestBehavior.deferToChild,
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                final valores = _hit.value?.hitValues;
                if (valores != null && valores.isNotEmpty) p.seleccionar(valores.first);
              },
              child: CircleLayer<Foco>(
                hitNotifier: _hit,
                circles: _circulosDe(p.focos),
              ),
            ),
          ),
          if (seleccionado != null)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: seleccionado.posicion,
                  radius: _radio(seleccionado) + 6,
                  color: Colors.transparent,
                  borderColor: const Color(0xFF1A1F1C),
                  borderStrokeWidth: 2.5,
                ),
              ],
            ),
          const SimpleAttributionWidget(
            source: Text('© OpenStreetMap contributors · NASA FIRMS · INPE · UNGRD · IDEAM (CC BY-SA) · geoBoundaries/DANE (CC BY) · Modelo Vigía'),
          ),
        ],
      ),
    );
  }
}
