import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api/vigia_api.dart';
import '../data/models/estadisticas.dart';
import '../data/models/foco.dart';
import '../data/models/reporte.dart';
import '../providers/auth_provider.dart';
import '../widgets/estado_carga.dart';
import '../widgets/formato.dart';
import '../widgets/lista_centrada.dart';
import '../widgets/selector_periodo.dart';

/// "Gestionar Estadísticas" (UC7): incidentes por región y periodo, para
/// administradores y staff. La API limita al administrador a su jurisdicción.
class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});

  static const titulo = 'Gestionar Estadísticas';

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {

  int _dias = 30;
  late Future<Estadisticas> _datos;

  @override
  void initState() {
    super.initState();
    _datos = _cargar();
  }

  Future<Estadisticas> _cargar() async {
    final access = await context.read<AuthProvider>().accessToken();
    if (!mounted) throw const ApiException('');
    final hoy = DateTime.now();
    return context.read<VigiaApi>().estadisticas(
          access,
          desde: hoy.subtract(Duration(days: _dias - 1)),
          hasta: hoy,
        );
  }

  void _cambiarPeriodo(int dias) {
    _dias = dias;
    // FutureBuilder lo escucha en el próximo cuadro: si falla antes, sin
    // ignore() el error se reportaría como no manejado (la pantalla igual lo muestra).
    final datos = _cargar()..ignore();
    setState(() {
      _datos = datos;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(EstadisticasScreen.titulo),
        actions: [
          IconButton(tooltip: 'Recargar', onPressed: () => _cambiarPeriodo(_dias), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListaCentrada(
        children: [
          SelectorPeriodo(dias: _dias, onCambio: _cambiarPeriodo),
          const SizedBox(height: 16),
          EstadoCarga<Estadisticas>(
            futuro: _datos,
            mensajeError: 'No se pudieron cargar las estadísticas.',
            onReintentar: () => _cambiarPeriodo(_dias),
            contenido: _Contenido.new,
          ),
        ],
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido(this.e);

  final Estadisticas e;

  @override
  Widget build(BuildContext context) {
    String fuente(String? v) => FuenteSatelital.desdeApi(v ?? '')?.etiqueta ?? v ?? '';
    return LayoutBuilder(
      builder: (context, limites) {
        // Rejilla: totales en 3 columnas y secciones en 2 cuando hay espacio.
        double ancho(int columnas) => (limites.maxWidth - 16 * (columnas - 1)) / columnas;
        final total = ancho(limites.maxWidth >= 600 ? 3 : 1);
        final seccion = ancho(limites.maxWidth >= 760 ? 2 : 1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Del ${Formato.fecha(e.desde)} al ${Formato.fecha(e.hasta)} · '
              '${e.nacional ? 'Todo el país' : 'Jurisdicción de tu entidad'}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final (etiqueta, valor, icono) in [
                  ('Detecciones satelitales', e.focos, Icons.local_fire_department_outlined),
                  ('Alertas', e.alertas, Icons.notifications_active_outlined),
                  ('Reportes ciudadanos', e.reportes, Icons.add_a_photo_outlined),
                ])
                  SizedBox(width: total, child: _Total(etiqueta, valor, icono)),
              ],
            ),
            const SizedBox(height: 16),
            _Seccion('Detecciones por día', [_Barras(e.focosPorDia)]),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final (titulo, filas) in [
                  (
                    'Detecciones por departamento',
                    [
                      for (final c in e.focosPorDepartamento.take(10))
                        (c.clave ?? 'Fuera de los municipios cargados', c.cantidad),
                    ],
                  ),
                  ('Detecciones por fuente', [for (final c in e.focosPorFuente) (fuente(c.clave), c.cantidad)]),
                  (
                    'Alertas por disparador',
                    [
                      for (final c in e.alertasPorTipo)
                        (tiposAlerta[c.clave] ?? c.clave ?? '', c.cantidad),
                    ],
                  ),
                  (
                    'Reportes por estado',
                    [for (final c in e.reportesPorEstado) (EstadoReporte.desdeApi(c.clave).etiqueta, c.cantidad)],
                  ),
                ])
                  SizedBox(width: seccion, child: _Seccion(titulo, _Fila.lista(filas))),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.etiqueta, this.valor, this.icono);

  final String etiqueta;
  final int valor;
  final IconData icono;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(icono, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Formato.entero(valor), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                    Text(etiqueta, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo, this.hijos);

  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const SizedBox(height: 12),
              if (hijos.isEmpty)
                Text('Sin datos en el periodo.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              else
                ...hijos,
            ],
          ),
        ),
      );
}

/// Etiqueta y cantidad, con una barra proporcional al mayor de la sección.
class _Fila extends StatelessWidget {
  const _Fila(this.etiqueta, this.cantidad, this.maximo);

  final String etiqueta;
  final int cantidad;
  final int maximo;

  static List<Widget> lista(List<(String, int)> filas) {
    final maximo = filas.fold(0, (m, f) => f.$2 > m ? f.$2 : m);
    return [for (final (etiqueta, cantidad) in filas) _Fila(etiqueta, cantidad, maximo)];
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(etiqueta)),
                Text(Formato.entero(cantidad), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            // La barra es decorativa: el lector de pantalla lee etiqueta y cantidad.
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: maximo == 0 ? 0 : cantidad / maximo,
                minHeight: 6,
                color: Theme.of(context).colorScheme.secondary,
                backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      );
}

/// Columnas por día, sin librería de gráficos: el detalle exacto va en el
/// texto accesible y en los informes.
class _Barras extends StatelessWidget {
  const _Barras(this.dias);

  final List<Conteo> dias;

  @override
  Widget build(BuildContext context) {
    final maximo = dias.fold(0, (m, d) => d.cantidad > m ? d.cantidad : m);
    if (maximo == 0) return Text('Sin detecciones.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    final pico = dias.firstWhere((d) => d.cantidad == maximo);
    final secundario = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12);
    return Semantics(
      label: 'Máximo de ${Formato.entero(maximo)} detecciones el ${Formato.fecha(DateTime.parse(pico.clave!))}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Máximo: ${Formato.entero(maximo)} el ${Formato.fecha(DateTime.parse(pico.clave!))}',
              style: secundario,
            ),
            const SizedBox(height: 8),
            Container(
              height: 140,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in dias)
                    Expanded(
                      child: Tooltip(
                        message: '${Formato.fecha(DateTime.parse(d.clave!))}: ${Formato.entero(d.cantidad)}',
                        child: Container(
                          // Mínimo de 2 px para que los días con pocas detecciones se vean.
                          height: d.cantidad == 0 ? 0 : (140 * d.cantidad / maximo).clamp(2, 140),
                          margin: EdgeInsets.symmetric(horizontal: dias.length > 60 ? 0 : 1.5),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(Formato.fecha(DateTime.parse(dias.first.clave!)), style: secundario),
                Text(Formato.fecha(DateTime.parse(dias.last.clave!)), style: secundario),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
