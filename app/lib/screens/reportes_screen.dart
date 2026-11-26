import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/api/vigia_api.dart';
import '../data/models/reporte.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/fondo_vigia.dart';
import '../widgets/esqueleto.dart';
import '../widgets/formato.dart';
import 'nuevo_reporte_screen.dart';

/// "Gestionar Reportar Focos de Incendios" del mapa de navegación.
/// Ciudadano: crea reportes y ve los suyos. Administrador: valida o rechaza
/// los de su jurisdicción. Staff: solo lectura. La API aplica los permisos;
/// aquí solo se decide qué botones mostrar.
class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  static const titulo = 'Gestionar Reportar Focos de Incendios';

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  late Future<List<Reporte>> _reportes;
  // Reporte que se está validando o rechazando: sus botones se desactivan
  // para que un doble toque no mande dos veces la decisión.
  int? _resolviendo;

  @override
  void initState() {
    super.initState();
    _reportes = _cargar();
  }

  Future<List<Reporte>> _cargar() async {
    final access = await context.read<AuthProvider>().accessToken();
    if (!mounted) return const [];
    return context.read<VigiaApi>().listarReportes(access);
  }

  void _recargar() {
    // FutureBuilder lo escucha en el próximo cuadro: si falla antes, sin
    // ignore() el error se reportaría como no manejado (la pantalla igual lo muestra).
    final reportes = _cargar()..ignore();
    setState(() {
      _reportes = reportes;
    });
  }

  Future<void> _nuevo() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NuevoReporteScreen()),
    );
    if (creado == true) _recargar();
  }

  Future<void> _resolver(Reporte reporte, {required bool validar}) async {
    final mensajero = ScaffoldMessenger.of(context);
    setState(() => _resolviendo = reporte.id);
    try {
      final access = await context.read<AuthProvider>().accessToken();
      if (!mounted) return;
      await context.read<VigiaApi>().resolverReporte(access, reporte.id, validar: validar);
      mensajero.showSnackBar(SnackBar(content: Text('Reporte #${reporte.id} ${validar ? 'validado' : 'rechazado'}.')));
    } on ApiException catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
    if (!mounted) return;
    _resolviendo = null;
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final rol = context.watch<AuthProvider>().rol;

    return Scaffold(
      appBar: AppBar(title: const Text(ReportesScreen.titulo)),
      floatingActionButton: rol == Rol.ciudadano
          ? FloatingActionButton.extended(
              onPressed: _nuevo,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Nuevo reporte'),
            )
          : null,
      body: FondoVigia(child: RefreshIndicator(
        onRefresh: () async {
          _recargar();
          await _reportes;
        },
        child: FutureBuilder<List<Reporte>>(
          future: _reportes,
          builder: (context, snap) => switch (snap) {
            AsyncSnapshot(hasError: true, :final error) => _Mensaje(
                error is ApiException ? error.mensaje : 'No se pudieron cargar los reportes.',
                color: Theme.of(context).colorScheme.error,
              ),
            AsyncSnapshot(hasData: true, :final data) when data!.isEmpty => _Mensaje(
                rol == Rol.ciudadano
                    ? 'Todavía no has reportado ningún incendio.'
                    : 'No hay reportes ciudadanos en tu jurisdicción.',
              ),
            AsyncSnapshot(hasData: true, :final data) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  for (final r in data!)
                    _TarjetaReporte(
                      r,
                      onResolver: rol == Rol.administrador && r.estado == EstadoReporte.pendiente
                          ? (validar) => _resolver(r, validar: validar)
                          : null,
                      bloqueado: _resolviendo != null,
                    ),
                ],
              ),
            _ => Esqueleto(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    for (var i = 0; i < 4; i++)
                      _TarjetaReporte(
                        Reporte(
                          id: i,
                          ciudadano: 'ciudadano',
                          ubicacionIncendio: const LatLng(6.15, -75.37),
                          estado: EstadoReporte.pendiente,
                          fechaCreacion: DateTime(2026, 11, 25),
                          descripcion: 'Descripción del reporte de ejemplo para el skeleton.',
                        ),
                      ),
                  ],
                ),
              ),
          },
        ),
      )),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje(this.texto, {this.color});

  final String texto;

  /// Por defecto, el color de texto secundario del tema.
  final Color? color;

  // ListView para que RefreshIndicator funcione también sin datos.
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: [Text(texto, textAlign: TextAlign.center, style: TextStyle(color: color ?? Theme.of(context).colorScheme.onSurfaceVariant))],
      );
}

class _TarjetaReporte extends StatelessWidget {
  const _TarjetaReporte(this.reporte, {this.onResolver, this.bloqueado = false});

  final Reporte reporte;
  final void Function(bool validar)? onResolver;

  /// Hay una validación o un rechazo en curso: los botones esperan.
  final bool bloqueado;

  @override
  Widget build(BuildContext context) {
    final r = reporte;
    final p = r.ubicacionIncendio;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Miniatura(r.miniaturaUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Reporte #${r.id}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                          _EtiquetaEstado(r.estado),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(Formato.fechaHora(r.fechaCreacion),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                      Text('${Formato.coordenada(p.latitude, latitud: true)}, ${Formato.coordenada(p.longitude, latitud: false)}',
                          style: const TextStyle(fontSize: 13)),
                      if (r.distanciaKm != null)
                        Text('A ${r.distanciaKm!.toStringAsFixed(1)} km de quien reportó',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                      if (r.descripcion.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(r.descripcion),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (onResolver != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: bloqueado ? null : () => onResolver!(false),
                      icon: const Icon(Icons.close),
                      label: const Text('Rechazar'),
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: bloqueado ? null : () => onResolver!(true),
                      icon: const Icon(Icons.check),
                      label: const Text('Validar'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EtiquetaEstado extends StatelessWidget {
  const _EtiquetaEstado(this.estado);

  final EstadoReporte estado;

  @override
  Widget build(BuildContext context) {
    final (fondo, texto) = switch (estado) {
      EstadoReporte.pendiente => (Theme.of(context).scaffoldBackgroundColor, Theme.of(context).colorScheme.onSurfaceVariant),
      EstadoReporte.validado => (Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.onPrimaryContainer),
      EstadoReporte.rechazado => (Theme.of(context).colorScheme.errorContainer, Theme.of(context).colorScheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(6)),
      child: Text(estado.etiqueta, style: TextStyle(fontSize: 12, color: texto, fontWeight: FontWeight.w600)),
    );
  }
}

class _Miniatura extends StatefulWidget {
  const _Miniatura(this.url);

  final String? url;

  @override
  State<_Miniatura> createState() => _MiniaturaState();
}

class _MiniaturaState extends State<_Miniatura> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    final url = widget.url;
    if (url != null) {
      final api = context.read<VigiaApi>();
      _bytes = context.read<AuthProvider>().accessToken().then((access) => api.descargarFoto(access, url));
    }
  }

  @override
  Widget build(BuildContext context) {
    const lado = 72.0;
    Widget sinFoto(IconData icono) => Container(
          width: lado,
          height: lado,
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Icon(icono, color: Theme.of(context).colorScheme.onSurfaceVariant),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: _bytes == null
          ? Semantics(label: 'Foto eliminada por retención', child: sinFoto(Icons.hide_image_outlined))
          : FutureBuilder<Uint8List>(
              future: _bytes,
              builder: (context, snap) => snap.hasData
                  ? Image.memory(snap.data!, width: lado, height: lado, fit: BoxFit.cover,
                      semanticLabel: 'Foto del incendio reportado')
                  : sinFoto(snap.hasError ? Icons.broken_image_outlined : Icons.image_outlined),
            ),
    );
  }
}
