import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/models/foco.dart';
import '../providers/focos_provider.dart';
import 'panel_filtros.dart' show colorFuente;

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
            userAgentPackageName: 'com.foxyyts.vigia.vigia_app',
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
            source: Text('OpenStreetMap contributors · NASA FIRMS · INPE'),
          ),
        ],
      ),
    );
  }
}
