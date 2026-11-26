import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/focos_provider.dart';
import '../providers/preferencias_provider.dart';
import '../data/models/foco.dart';
import '../widgets/detalle_foco.dart';
import '../widgets/formato.dart';
import '../widgets/mapa_focos.dart';
import '../widgets/panel_filtros.dart';
import '../widgets/vigia_marca.dart';
import 'rutas.dart';

/// "Mapa Interactivo": pantalla pública (no pide sesión) con los focos
/// satelitales sobre Colombia.
class MapaScreen extends StatefulWidget {
  const MapaScreen({super.key});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

final _temaMapa = construirTemaVigia();

class _MapaScreenState extends State<MapaScreen> {
  final _mapa = MapController();
  // Misma instancia en cada build: los cambios de FocosProvider que redibujan
  // esta pantalla (selección, carga) no reconstruyen el mapa.
  late final _mapaFocos = MapaFocos(controller: _mapa);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<FocosProvider>();
      if (p.corte == null && !p.cargando) p.inicializar();
    });
  }

  void _zoom(double delta) => _mapa.move(_mapa.camera.center, _mapa.camera.zoom + delta);

  /// Alternativa textual al mapa (WCAG 1.1.1 y 2.1.1): los focos como lista
  /// navegable con teclado y lector de pantalla. Elegir uno lo selecciona y
  /// centra el mapa en él.
  void _abrirLista(FocosProvider p) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (contexto) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: ListaFocos(
            focos: p.focos,
            onElegir: (foco) {
              Navigator.pop(contexto);
              p.seleccionar(foco);
              _mapa.move(foco.posicion, 10);
            },
          ),
        ),
      );

  void _centrar() => _mapa.fitCamera(
        CameraFit.bounds(bounds: limitesColombia, padding: const EdgeInsets.all(24)),
      );

  void _abrirFiltros() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: const PanelFiltros(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width >= 900;
    final p = context.watch<FocosProvider>();

    // El mapa es siempre claro: lo que flota encima (botones, contador,
    // avisos, detalle del foco) usa el tema claro aunque la app esté en oscuro.
    final areaMapa = Theme(
      data: _temaMapa,
      child: Stack(
      children: [
        _mapaFocos,
        if (p.cargando)
          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
        // Controles accesibles por teclado y lector de pantalla (#33): el mapa
        // solo se manejaba con gestos y tocando círculos de 4–10 px.
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              BotonBrujula(mapa: _mapa),
              _BotonMapa(icono: Icons.center_focus_strong, texto: 'Centrar en Colombia', onPressed: _centrar),
              const SizedBox(height: 8),
              _BotonMapa(icono: Icons.add, texto: 'Acercar', onPressed: () => _zoom(1)),
              const SizedBox(height: 8),
              _BotonMapa(icono: Icons.remove, texto: 'Alejar', onPressed: () => _zoom(-1)),
              const SizedBox(height: 8),
              _BotonMapa(icono: Icons.list_alt, texto: 'Lista de focos', onPressed: () => _abrirLista(p)),
            ],
          ),
        ),
        if (!ancho)
          Positioned(top: 12, left: 12, child: _ChipContador(total: p.total, cargando: p.cargando)),
        // right: 72 deja libre la columna de botones del mapa (48 px + márgenes).
        if (p.error != null)
          Positioned(top: 60, left: 12, right: 72, child: _AvisoError(p.error!, onReintentar: p.cargar)),
        if (!p.cargando && p.error == null && p.corte != null && p.total == 0)
          const Positioned(top: 60, left: 12, right: 72, child: _AvisoVacio()),
        if (p.seleccionado != null)
          Positioned(
            right: 12,
            bottom: ancho ? null : 12,
            top: ancho ? 64 : null,
            left: ancho ? null : 12,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DetalleFoco(foco: p.seleccionado!, onCerrar: () => p.seleccionar(null)),
            ),
          ),
      ],
    ),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: Row(
          children: [
            const VigiaMarca(tamano: 36),
            if (ancho) ...[
              const SizedBox(width: 16),
              Container(width: 1, height: 28, color: Colors.white30),
              const SizedBox(width: 16),
            ],
            if (ancho)
              const Text('Mapa Interactivo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: const [_SelectorTema(), SizedBox(width: 4), _AccionesSesion(), SizedBox(width: 12)],
      ),
      floatingActionButton: ancho || p.seleccionado != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _abrirFiltros,
              icon: const Icon(Icons.tune),
              label: const Text('Filtros'),
              backgroundColor: VigiaColors.bosque,
              foregroundColor: Colors.white,
            ),
      body: ancho
          ? Row(
              children: [
                SizedBox(
                  width: 340,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                    ),
                    child: PanelFiltros(),
                  ),
                ),
                Expanded(child: areaMapa),
              ],
            )
          : areaMapa,
    );
  }
}

/// Tema de la app: el del sistema (por defecto), claro u oscuro.
class _SelectorTema extends StatelessWidget {
  const _SelectorTema();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PreferenciasProvider>();
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Tema',
      icon: const Icon(Icons.brightness_6_outlined, color: Colors.white),
      onSelected: p.cambiarTema,
      itemBuilder: (_) => [
        for (final (modo, etiqueta) in const [
          (ThemeMode.system, 'Según el sistema'),
          (ThemeMode.light, 'Claro'),
          (ThemeMode.dark, 'Oscuro'),
        ])
          CheckedPopupMenuItem(value: modo, checked: p.tema == modo, child: Text(etiqueta)),
      ],
    );
  }
}

class _AccionesSesion extends StatelessWidget {
  const _AccionesSesion();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final compacto = MediaQuery.sizeOf(context).width < 600;
    if (!auth.autenticado) {
      return FilledButton.icon(
        style: estiloBotonBarra(context),
        onPressed: () => Navigator.of(context).pushNamed(Rutas.login),
        icon: const Icon(Icons.login),
        label: const Text('Iniciar sesión'),
      );
    }
    return Row(
      children: [
        if (!compacto)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('${auth.username} · ${auth.rol.etiqueta}', style: const TextStyle(color: Colors.white)),
          ),
        FilledButton.icon(
          style: estiloBotonBarra(context),
          onPressed: () => Navigator.of(context).pushNamed(Rutas.panel),
          icon: const Icon(Icons.dashboard_outlined),
          label: const Text('Mi panel'),
        ),
      ],
    );
  }
}

class _BotonMapa extends StatelessWidget {
  const _BotonMapa({required this.icono, required this.texto, required this.onPressed, this.giro = 0});

  final IconData icono;
  final String texto;
  final VoidCallback onPressed;

  /// Ángulo del ícono en radianes.
  final double giro;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: IconButton(
          tooltip: texto,
          icon: Transform.rotate(angle: giro, child: Icon(icono, color: Theme.of(context).colorScheme.primary)),
          onPressed: onPressed,
        ),
      );
}

/// Brújula (#93): aparece solo con el mapa girado, apunta al norte y al
/// tocarla lo devuelve a su orientación.
class BotonBrujula extends StatelessWidget {
  const BotonBrujula({super.key, required this.mapa});

  final MapController mapa;

  @override
  Widget build(BuildContext context) => StreamBuilder<MapEvent>(
        stream: mapa.mapEventStream,
        builder: (context, evento) {
          final camara = evento.data?.camera;
          if (camara == null || (camara.rotation % 360).abs() < 0.5) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BotonMapa(
              icono: Icons.navigation,
              texto: 'Orientar al norte',
              giro: camara.rotationRad,
              onPressed: () => mapa.rotate(0),
            ),
          );
        },
      );
}

class _ChipContador extends StatelessWidget {
  const _ChipContador({required this.total, required this.cargando});

  final int total;
  final bool cargando;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department, color: Theme.of(context).colorScheme.secondary, size: 18),
              const SizedBox(width: 6),
              Text(cargando ? 'Cargando…' : '$total focos', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}

class _AvisoError extends StatelessWidget {
  const _AvisoError(this.mensaje, {required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Material(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 10),
                Expanded(child: Text(mensaje, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer))),
                TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
              ],
            ),
          ),
        ),
      );
}

class _AvisoVacio extends StatelessWidget {
  const _AvisoVacio();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                SizedBox(width: 10),
                Flexible(child: Text('No hay focos en este rango. Prueba con otra fecha o un rango más amplio.')),
              ],
            ),
          ),
        ),
      );
}


/// Focos del rango actual como lista, del más reciente al más antiguo.
class ListaFocos extends StatelessWidget {
  const ListaFocos({super.key, required this.focos, required this.onElegir});

  final List<Foco> focos;
  final ValueChanged<Foco> onElegir;

  @override
  Widget build(BuildContext context) {
    if (focos.isEmpty) {
      return const Center(child: Text('No hay focos en el rango seleccionado.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Semantics(
            header: true,
            child: Text('${Formato.entero(focos.length)} focos', style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: focos.length,
            itemBuilder: (_, i) {
              final f = focos[i];
              return ListTile(
                leading: Icon(Icons.local_fire_department, color: colorFuente(f.fuente, Theme.of(context).brightness)),
                title: Text('${f.fuente?.etiqueta ?? 'Fuente desconocida'} · ${Formato.fechaHora(f.fechaHora)}'),
                subtitle: Text(
                  '${Formato.coordenada(f.posicion.latitude, latitud: true)}, '
                  '${Formato.coordenada(f.posicion.longitude, latitud: false)} · confianza ${f.confianzaLegible.toLowerCase()}',
                ),
                onTap: () => onElegir(f),
              );
            },
          ),
        ),
      ],
    );
  }
}
