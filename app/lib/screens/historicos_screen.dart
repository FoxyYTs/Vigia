import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api/vigia_api.dart';
import '../data/models/historicos.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/estado_carga.dart';
import '../widgets/formato.dart';
import '../widgets/indicador.dart';
import '../widgets/lista_centrada.dart';

/// "Gestionar Históricos": qué hay cargado de cada fuente histórica, por año.
/// El staff puede traer los incendios nuevos de la UNGRD; el IDEAM y el
/// archivo de FIRMS se cargan desde el servidor (comandos de manage.py).
class HistoricosScreen extends StatefulWidget {
  const HistoricosScreen({super.key});

  static const titulo = 'Gestionar Históricos';

  @override
  State<HistoricosScreen> createState() => _HistoricosScreenState();
}

/// Forma del resumen para el skeleton de carga.
final _ejemplo = ResumenHistoricos(
  ungrdTotal: 18000,
  ungrdSinMunicipio: 1,
  ungrdDesde: DateTime(2019),
  ungrdHasta: DateTime(2024, 12, 31),
  ungrdPorAnio: [for (var a = 2019; a <= 2024; a++) (a, [2000, 100000])],
  ideamPorAnio: [for (var a = 2019; a <= 2025; a++) (a, [500, 100000])],
  firmsTotal: 870000,
  firmsPorAnio: [for (var a = 2018; a <= 2026; a++) (a, [100000])],
);

class _HistoricosScreenState extends State<HistoricosScreen> {
  late Future<ResumenHistoricos> _datos;
  bool _actualizando = false;

  @override
  void initState() {
    super.initState();
    _datos = _cargar();
  }

  Future<ResumenHistoricos> _cargar() async {
    final access = await context.read<AuthProvider>().accessToken();
    if (!mounted) throw const ApiException('');
    return context.read<VigiaApi>().resumenHistoricos(access);
  }

  void _recargar() {
    // FutureBuilder lo escucha en el próximo cuadro: si falla antes, sin
    // ignore() el error se reportaría como no manejado (la pantalla igual lo muestra).
    final datos = _cargar()..ignore();
    setState(() {
      _datos = datos;
    });
  }

  Future<void> _actualizarUngrd() async {
    final mensajero = ScaffoldMessenger.of(context);
    setState(() => _actualizando = true);
    try {
      final access = await context.read<AuthProvider>().accessToken();
      if (!mounted) return;
      await context.read<VigiaApi>().sincronizarUngrd(access);
      mensajero.showSnackBar(const SnackBar(
        content: Text('Actualización en curso: recarga en unos minutos para ver los incendios nuevos.'),
      ));
    } on ApiException catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<AuthProvider>().rol == Rol.staff;
    return Scaffold(
      appBar: AppBar(
        title: const Text(HistoricosScreen.titulo),
        actions: [IconButton(tooltip: 'Recargar', onPressed: _recargar, icon: const Icon(Icons.refresh))],
      ),
      body: EstadoCarga<ResumenHistoricos>(
        futuro: _datos,
        mensajeError: 'No se pudo cargar el resumen de los históricos.',
        esqueleto: _ejemplo,
        onReintentar: _recargar,
        contenido: (datos) => ListaCentrada(
              children: [
                // Totales arriba y una tarjeta por fuente, lado a lado cuando caben (3, 2 o 1 columnas).
                LayoutBuilder(builder: (context, limites) {
                  final columnas = limites.maxWidth >= 1200 ? 3 : (limites.maxWidth >= 760 ? 2 : 1);
                  final ancho = (limites.maxWidth - 16 * (columnas - 1)) / columnas;
                  final totales = limites.maxWidth >= 600 ? (limites.maxWidth - 32) / 3 : limites.maxWidth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [for (final t in _totales(datos)) SizedBox(width: totales, child: t)],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [for (final f in _fuentes(datos, staff)) SizedBox(width: ancho, child: f)],
                      ),
                    ],
                  );
                }),
              ],
            ),
      ),
    );
  }

  List<Widget> _totales(ResumenHistoricos d) {
    String rango(List<(int, List<num?>)> filas) => filas.isEmpty ? '' : ', ${filas.first.$1}–${filas.last.$1}';
    final hectareas = d.ideamPorAnio.fold<num>(0, (s, f) => s + (f.$2.last ?? 0));
    return [
      Indicador('Incendios reportados (UNGRD${rango(d.ungrdPorAnio)})', d.ungrdTotal,
          Icons.local_fire_department_outlined),
      Indicador('Hectáreas deforestadas (IDEAM${rango(d.ideamPorAnio)})', hectareas.round(), Icons.forest_outlined),
      Indicador('Detecciones satelitales (FIRMS${rango(d.firmsPorAnio)})', d.firmsTotal, Icons.satellite_alt_outlined),
    ];
  }

  List<Widget> _fuentes(ResumenHistoricos d, bool staff) {
    final (desde, hasta) = (d.ungrdDesde, d.ungrdHasta);
    return [
      _Fuente(
        icono: Icons.local_fire_department_outlined,
        titulo: 'Incendios reportados (UNGRD)',
        detalle: 'Incendios forestales reportados a la UNGRD, por municipio (datos.gov.co).',
        resumen: [
          '${Formato.entero(d.ungrdTotal)} incendios',
          if (desde != null && hasta != null) 'del ${Formato.fecha(desde)} al ${Formato.fecha(hasta)}',
          if (d.ungrdSinMunicipio > 0) '${Formato.entero(d.ungrdSinMunicipio)} sin municipio',
        ],
        columnas: const ['Incendios', 'Hectáreas'],
        filas: d.ungrdPorAnio,
        accion: staff
            ? FilledButton.icon(
                onPressed: _actualizando ? null : _actualizarUngrd,
                icon: _actualizando
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: const Text('Actualizar desde datos.gov.co'),
              )
            : null,
      ),
      _Fuente(
        icono: Icons.forest_outlined,
        titulo: 'Deforestación (IDEAM)',
        detalle: 'Hectáreas deforestadas por municipio, del raster anual del IDEAM. '
            'Se carga desde el servidor cuando el IDEAM publica un año nuevo.',
        resumen: const [],
        columnas: const ['Municipios', 'Hectáreas'],
        filas: d.ideamPorAnio,
        barraPrimaria: true,
      ),
      _Fuente(
        icono: Icons.satellite_alt_outlined,
        titulo: 'Detecciones históricas (NASA FIRMS)',
        detalle: 'Archivo de puntos de calor de NASA FIRMS, que alimenta el modelo de recurrencia. '
            'Desde la puesta en marcha se completa solo con la ingesta en tiempo real.',
        resumen: ['${Formato.entero(d.firmsTotal)} detecciones'],
        columnas: const ['Detecciones'],
        filas: d.firmsPorAnio,
      ),
    ];
  }
}

/// Tarjeta de una fuente: descripción, resumen y tabla por año.
class _Fuente extends StatelessWidget {
  const _Fuente({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.resumen,
    required this.columnas,
    required this.filas,
    this.accion,
    this.barraPrimaria = false,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final List<String> resumen;
  final List<String> columnas;
  final List<(int, List<num?>)> filas;
  final Widget? accion;

  /// Barra por año en el verde primario (deforestación) en vez del fuego.
  final bool barraPrimaria;

  @override
  Widget build(BuildContext context) {
    final encabezado = TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13);
    Widget celda(String texto, {TextStyle? estilo, bool numero = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(texto, style: estilo, textAlign: numero ? TextAlign.end : TextAlign.start),
        );
    final maximo = filas.fold<num>(0, (m, f) => (f.$2.last ?? 0) > m ? f.$2.last! : m);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(detalle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (resumen.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(resumen.join(' · '), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 8),
            if (filas.isEmpty)
              Text('Sin datos cargados.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else
              Table(
                border: TableBorder(horizontalInside: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: {
                  0: const IntrinsicColumnWidth(),
                  for (var i = 1; i <= columnas.length; i++) i: const IntrinsicColumnWidth(flex: 1),
                  columnas.length + 1: const FlexColumnWidth(1.4),
                },
                children: [
                  TableRow(children: [
                    celda('Año', estilo: encabezado, numero: false),
                    for (final c in columnas) celda(c, estilo: encabezado),
                    const SizedBox.shrink(),
                  ]),
                  for (final (anio, valores) in filas)
                    TableRow(children: [
                      celda('$anio', numero: false),
                      for (final v in valores) celda(v == null ? '—' : Formato.entero(v.round())),
                      _barra(context, valores.last, maximo),
                    ]),
                ],
              ),
            if (accion != null) ...[
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: accion),
            ],
          ],
        ),
      ),
    );
  }

  /// Barra del último valor de la fila contra el mayor de la tabla: muestra la
  /// tendencia de un vistazo. Decorativa: el lector de pantalla lee la cifra.
  Widget _barra(BuildContext context, num? valor, num maximo) => Padding(
        padding: const EdgeInsets.only(left: 16),
        child: ExcludeSemantics(
          child: LinearProgressIndicator(
            value: maximo == 0 ? 0 : (valor ?? 0) / maximo,
            minHeight: 8,
            color: barraPrimaria ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.secondary,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}
