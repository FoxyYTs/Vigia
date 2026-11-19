import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../data/models/historicos.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/estado_carga.dart';
import '../widgets/formato.dart';
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
        onReintentar: _recargar,
        contenido: (datos) => ListaCentrada(
              children: [
                // Una tarjeta por fuente, lado a lado cuando caben (3, 2 o 1 columnas).
                LayoutBuilder(builder: (context, limites) {
                  final columnas = limites.maxWidth >= 1200 ? 3 : (limites.maxWidth >= 760 ? 2 : 1);
                  final ancho = (limites.maxWidth - 16 * (columnas - 1)) / columnas;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [for (final f in _fuentes(datos, staff)) SizedBox(width: ancho, child: f)],
                  );
                }),
              ],
            ),
      ),
    );
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
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final List<String> resumen;
  final List<String> columnas;
  final List<(int, List<num?>)> filas;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    const encabezado = TextStyle(fontWeight: FontWeight.w700, color: VigiaColors.textoSecundario, fontSize: 13);
    Widget celda(String texto, {TextStyle? estilo, bool numero = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(texto, style: estilo, textAlign: numero ? TextAlign.end : TextAlign.start),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: VigiaColors.bosque),
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
            Text(detalle, style: const TextStyle(color: VigiaColors.textoSecundario)),
            if (resumen.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(resumen.join(' · '), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 8),
            if (filas.isEmpty)
              const Text('Sin datos cargados.', style: TextStyle(color: VigiaColors.textoSecundario))
            else
              Table(
                border: const TableBorder(horizontalInside: BorderSide(color: VigiaColors.borde)),
                children: [
                  TableRow(children: [
                    celda('Año', estilo: encabezado, numero: false),
                    for (final c in columnas) celda(c, estilo: encabezado),
                  ]),
                  for (final (anio, valores) in filas)
                    TableRow(children: [
                      celda('$anio', numero: false),
                      for (final v in valores) celda(v == null ? '—' : Formato.entero(v.round())),
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
}
