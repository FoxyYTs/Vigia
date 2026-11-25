import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/models/foco.dart';
import '../providers/focos_provider.dart';
import '../providers/historico_provider.dart';
import '../providers/prediccion_provider.dart';
import 'agrupar_focos.dart';
import 'formato.dart';
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

  @override
  void dispose() {
    _hit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // select y no watch: seleccionar un foco solo redibuja _AnilloSeleccion.
    final focos = context.select<FocosProvider, List<Foco>>((p) => p.focos);
    final zonas = context.watch<PrediccionProvider>().zonas;
    final historico = _poligonosHistoricos(context.watch<HistoricoProvider>());

    final teselas = TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.vigia.foxyyts',
    );

    return Semantics(
      label: 'Mapa de Colombia con ${focos.length} focos de calor. '
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
          onTap: (_, _) => context.read<FocosProvider>().seleccionar(null),
        ),
        children: [
          // OSM no tiene teselas oscuras: se invierten los colores de toda la
          // capa (por tesela quedaban líneas claras entre ellas).
          if (Theme.of(context).brightness == Brightness.dark)
            darkModeTilesContainerBuilder(context, teselas)
          else
            teselas,
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
                if (valores != null && valores.isNotEmpty) context.read<FocosProvider>().seleccionar(valores.first);
              },
              child: _CapaFocos(focos: focos, hit: _hit),
            ),
          ),
          const _AnilloSeleccion(),
          // Plegable: en pantallas angostas la línea completa se cortaba.
          RichAttributionWidget(
            alignment: AttributionAlignment.bottomLeft,
            // El botón de flutter_map es negro fijo y no se ve en modo oscuro.
            openButton: (context, abrir) => IconButton(
              tooltip: 'Fuentes y atribuciones',
              onPressed: abrir,
              icon: Icon(Icons.info_outlined, color: Theme.of(context).colorScheme.onSurface),
            ),
            attributions: const [
              TextSourceAttribution('OpenStreetMap contributors'),
              TextSourceAttribution('NASA FIRMS', prependCopyright: false),
              TextSourceAttribution('INPE', prependCopyright: false),
              TextSourceAttribution('UNGRD', prependCopyright: false),
              TextSourceAttribution('IDEAM (CC BY-SA)', prependCopyright: false),
              TextSourceAttribution('geoBoundaries/DANE (CC BY)', prependCopyright: false),
              TextSourceAttribution('Modelo Vigía', prependCopyright: false),
            ],
          ),
        ],
      ),
    );
  }
}

double _radio(Foco f) {
  final frp = f.brilloFrp;
  if (frp == null || frp <= 0) return 4;
  // Redondeado a 0,5 px: CircleLayer dibuja en un solo lote los de igual radio.
  return ((4 + math.min(6, math.log(frp + 1) * 1.4)) * 2).roundToDouble() / 2;
}

/// Focos sueltos como círculos y, con zoom menor a [zoomSinAgrupar], las
/// celdas con al menos [tamanoMinimoGrupo] focos agrupadas en un círculo con el conteo (#94).
class _CapaFocos extends StatefulWidget {
  const _CapaFocos({required this.focos, required this.hit});

  final List<Foco> focos;
  final LayerHitNotifier<Foco> hit;

  @override
  State<_CapaFocos> createState() => _CapaFocosState();
}

class _CapaFocosState extends State<_CapaFocos> {
  List<Foco>? _focosPrevios;
  int? _zoomPrevio;
  List<CircleMarker<Foco>> _sueltos = const [];
  List<Marker> _grupos = const [];

  /// Solo se reagrupa al cambiar la lista o el zoom entero, no en cada frame
  /// del arrastre.
  void _agrupar(int zoom) {
    if (identical(widget.focos, _focosPrevios) && zoom == _zoomPrevio) return;
    _focosPrevios = widget.focos;
    _zoomPrevio = zoom;
    final grupos = zoom >= zoomSinAgrupar ? const <GrupoFocos>[] : agruparFocos(widget.focos, zoom);
    final agrupados = Set<Foco>.identity()..addAll([for (final g in grupos) if (g.focos.length >= tamanoMinimoGrupo) ...g.focos]);
    _sueltos = [
      // Los más antiguos primero: los recientes quedan dibujados encima.
      for (final f in widget.focos.reversed)
        if (!agrupados.contains(f))
          CircleMarker<Foco>(
            point: f.posicion,
            radius: _radio(f),
            // Opaco: con transparencia, CircleLayer pinta cada borde con su
            // propio drawCircle (5000 llamadas) en vez de un lote de drawPoints.
            color: colorFuente(f.fuente),
            borderColor: Colors.white,
            borderStrokeWidth: 0.8,
            hitValue: f,
          ),
    ];
    _grupos = [
      for (final g in grupos)
        if (g.focos.length >= tamanoMinimoGrupo) _MarcaGrupo.marker(g),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _agrupar(MapCamera.of(context).zoom.floor());
    return Stack(
      children: [
        RepaintBoundary(child: CircleLayer<Foco>(hitNotifier: widget.hit, circles: _sueltos)),
        if (_grupos.isNotEmpty) MarkerLayer(markers: _grupos),
      ],
    );
  }
}

/// Círculo con el número de focos del grupo; tocarlo acerca el mapa a ellos.
class _MarcaGrupo extends StatelessWidget {
  const _MarcaGrupo(this.grupo);

  final GrupoFocos grupo;

  static Marker marker(GrupoFocos g) {
    final lado = 30 + math.min(18.0, math.log(g.focos.length) * 4).toDouble();
    return Marker(point: g.centro, width: lado, height: lado, child: _MarcaGrupo(g));
  }

  @override
  Widget build(BuildContext context) {
    final n = grupo.focos.length;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${Formato.entero(n)} focos. Toca para acercar.',
      child: GestureDetector(
        onTap: () => MapController.of(context).fitCamera(
          CameraFit.bounds(bounds: grupo.limites, padding: const EdgeInsets.all(48), maxZoom: zoomSinAgrupar + 1),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: colorFuente(grupo.fuentePrincipal), width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
          ),
          child: Center(
            child: Text(
              n >= 1000 ? '${(n / 1000).round()} mil' : '$n',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1F1C)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anillo sobre el foco seleccionado, en su propia capa para que seleccionar
/// no reconstruya ni repinte los miles de círculos.
class _AnilloSeleccion extends StatelessWidget {
  const _AnilloSeleccion();

  @override
  Widget build(BuildContext context) {
    final seleccionado = context.select<FocosProvider, Foco?>((p) => p.seleccionado);
    if (seleccionado == null) return const SizedBox.shrink();
    return CircleLayer(
      circles: [
        CircleMarker(
          point: seleccionado.posicion,
          radius: _radio(seleccionado) + 6,
          color: Colors.transparent,
          borderColor: Theme.of(context).colorScheme.onSurface,
          borderStrokeWidth: 2.5,
        ),
      ],
    );
  }
}
