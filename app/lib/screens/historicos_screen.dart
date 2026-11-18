import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/formato.dart';

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
  late Future<Map<String, dynamic>> _datos;
  bool _actualizando = false;

  @override
  void initState() {
    super.initState();
    _datos = _cargar();
  }

  Future<Map<String, dynamic>> _cargar() async {
    final access = await context.read<AuthProvider>().accessToken();
    if (!mounted) throw const ApiException('');
    return context.read<VigiaApi>().resumenHistoricos(access);
  }

  void _recargar() {
    final datos = _cargar();
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
      body: FutureBuilder<Map<String, dynamic>>(
        future: _datos,
        builder: (context, snap) => switch (snap) {
          AsyncSnapshot(hasError: true, :final error) => Center(
              child: Text(
                error is ApiException ? error.mensaje : 'No se pudo cargar el resumen de los históricos.',
                style: const TextStyle(color: VigiaColors.error),
              ),
            ),
          AsyncSnapshot(connectionState: ConnectionState.done, hasData: true, :final data) => ListView(
              // Centrado y con ancho máximo en pantallas anchas.
              padding:
                  EdgeInsets.symmetric(vertical: 16, horizontal: max(16, (MediaQuery.sizeOf(context).width - 1500) / 2)),
              children: [
                // Una tarjeta por fuente, lado a lado cuando caben (3, 2 o 1 columnas).
                LayoutBuilder(builder: (context, limites) {
                  final columnas = limites.maxWidth >= 1200 ? 3 : (limites.maxWidth >= 760 ? 2 : 1);
                  final ancho = (limites.maxWidth - 16 * (columnas - 1)) / columnas;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [for (final f in _fuentes(data!, staff)) SizedBox(width: ancho, child: f)],
                  );
                }),
              ],
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  List<Widget> _fuentes(Map<String, dynamic> d, bool staff) {
    final ungrd = d['ungrd'] as Map<String, dynamic>;
    final ideam = d['ideam'] as Map<String, dynamic>;
    final firms = d['firms'] as Map<String, dynamic>;
    String? fecha(Object? v) => v == null ? null : Formato.fecha(DateTime.parse(v as String));
    final desde = fecha(ungrd['desde']), hasta = fecha(ungrd['hasta']);
    return [
      _Fuente(
        icono: Icons.local_fire_department_outlined,
        titulo: 'Incendios reportados (UNGRD)',
        detalle: 'Incendios forestales reportados a la UNGRD, por municipio (datos.gov.co).',
        resumen: [
          '${Formato.entero(ungrd['total'] as int)} incendios',
          if (desde != null) 'del $desde al $hasta',
          if (ungrd['sin_municipio'] as int > 0) '${Formato.entero(ungrd['sin_municipio'] as int)} sin municipio',
        ],
        columnas: const ['Incendios', 'Hectáreas'],
        filas: [
          for (final f in ungrd['por_anio'] as List) (f['anio'] as int, [f['cantidad'] as num, f['hectareas'] as num?]),
        ],
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
        filas: [
          for (final f in ideam['por_anio'] as List) (f['anio'] as int, [f['municipios'] as num, f['hectareas'] as num?]),
        ],
      ),
      _Fuente(
        icono: Icons.satellite_alt_outlined,
        titulo: 'Detecciones históricas (NASA FIRMS)',
        detalle: 'Archivo de puntos de calor de NASA FIRMS, que alimenta el modelo de recurrencia. '
            'Desde la puesta en marcha se completa solo con la ingesta en tiempo real.',
        resumen: ['${Formato.entero(firms['total'] as int)} detecciones'],
        columnas: const ['Detecciones'],
        filas: [
          for (final f in firms['por_anio'] as List) (f['anio'] as int, [f['cantidad'] as num]),
        ],
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
