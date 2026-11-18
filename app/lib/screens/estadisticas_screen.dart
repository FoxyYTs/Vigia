import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../data/models/estadisticas.dart';
import '../data/models/foco.dart';
import '../data/models/reporte.dart';
import '../providers/auth_provider.dart';
import '../widgets/formato.dart';

/// "Gestionar Estadísticas" (UC7): incidentes por región y periodo, para
/// administradores y staff. La API limita al administrador a su jurisdicción.
class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});

  static const titulo = 'Gestionar Estadísticas';

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  static const _periodos = [7, 30, 90, 365];
  static const _tipos = {
    'deteccion_satelital': 'Detección satelital',
    'coincidencia_geografica': 'Coincidencia geográfica',
    'acumulacion_reportes': 'Acumulación de reportes',
    'validacion_manual': 'Validación manual',
  };

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
    return context.read<VigiaApi>().estadisticas(access, desde: hoy.subtract(Duration(days: _dias - 1)), hasta: hoy);
  }

  void _cambiarPeriodo(int dias) {
    _dias = dias;
    final datos = _cargar();
    setState(() {
      _datos = datos;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(EstadisticasScreen.titulo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _periodos)
                ChoiceChip(
                  label: Text(d == 365 ? '1 año' : '$d días'),
                  selected: _dias == d,
                  onSelected: (_) => _cambiarPeriodo(d),
                  selectedColor: VigiaColors.bosqueClaro,
                ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<Estadisticas>(
            future: _datos,
            builder: (context, snap) => switch (snap) {
              AsyncSnapshot(hasError: true, :final error) => Text(
                  error is ApiException ? error.mensaje : 'No se pudieron cargar las estadísticas.',
                  style: const TextStyle(color: VigiaColors.error),
                ),
              AsyncSnapshot(connectionState: ConnectionState.done, hasData: true, :final data) => _Contenido(data!),
              _ => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Del ${Formato.fecha(e.desde)} al ${Formato.fecha(e.hasta)} · '
          '${e.nacional ? 'Todo el país' : 'Jurisdicción de tu entidad'}',
          style: const TextStyle(color: VigiaColors.textoSecundario),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Total('Detecciones satelitales', e.focos, Icons.local_fire_department_outlined),
            _Total('Alertas', e.alertas, Icons.notifications_active_outlined),
            _Total('Reportes ciudadanos', e.reportes, Icons.add_a_photo_outlined),
          ],
        ),
        _Seccion('Detecciones por día', [_Barras(e.focosPorDia)]),
        _Seccion('Detecciones por departamento', [
          for (final c in e.focosPorDepartamento.take(10))
            _Fila(c.clave ?? 'Fuera de los municipios cargados', c.cantidad, e.focos),
        ]),
        _Seccion('Detecciones por fuente', [
          for (final c in e.focosPorFuente) _Fila(fuente(c.clave), c.cantidad, e.focos),
        ]),
        _Seccion('Alertas por disparador', [
          for (final c in e.alertasPorTipo)
            _Fila(_EstadisticasScreenState._tipos[c.clave] ?? c.clave ?? '', c.cantidad, e.alertas),
        ]),
        _Seccion('Reportes por estado', [
          for (final c in e.reportesPorEstado) _Fila(EstadoReporte.desdeApi(c.clave).etiqueta, c.cantidad, e.reportes),
        ]),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.etiqueta, this.valor, this.icono);

  final String etiqueta;
  final int valor;
  final IconData icono;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icono, color: VigiaColors.bosque),
                const SizedBox(height: 8),
                Text(Formato.entero(valor), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                Text(etiqueta, style: const TextStyle(color: VigiaColors.textoSecundario)),
              ],
            ),
          ),
        ),
      );
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo, this.hijos);

  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            if (hijos.isEmpty)
              const Text('Sin datos en el periodo.', style: TextStyle(color: VigiaColors.textoSecundario))
            else
              ...hijos,
          ],
        ),
      );
}

/// Etiqueta, barra proporcional al [total] y cantidad.
class _Fila extends StatelessWidget {
  const _Fila(this.etiqueta, this.cantidad, this.total);

  final String etiqueta;
  final int cantidad;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(etiqueta)),
            Expanded(
              flex: 3,
              // La barra es decorativa: el lector de pantalla lee etiqueta y cantidad.
              child: ExcludeSemantics(
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : cantidad / total,
                  minHeight: 10,
                  color: VigiaColors.fuego,
                  backgroundColor: VigiaColors.superficie,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            SizedBox(width: 64, child: Text(Formato.entero(cantidad), textAlign: TextAlign.end)),
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
    if (maximo == 0) return const Text('Sin detecciones.', style: TextStyle(color: VigiaColors.textoSecundario));
    final pico = dias.firstWhere((d) => d.cantidad == maximo);
    return Semantics(
      label: 'Máximo de ${Formato.entero(maximo)} detecciones el ${Formato.fecha(DateTime.parse(pico.clave!))}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in dias)
                    Expanded(
                      child: Tooltip(
                        message: '${Formato.fecha(DateTime.parse(d.clave!))}: ${Formato.entero(d.cantidad)}',
                        child: Container(
                          height: 120 * d.cantidad / maximo,
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          color: VigiaColors.fuego,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Máximo: ${Formato.entero(maximo)} el ${Formato.fecha(DateTime.parse(pico.clave!))}',
              style: const TextStyle(color: VigiaColors.textoSecundario, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
