import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api/vigia_api.dart';
import '../data/models/bot_telegram.dart';
import '../data/models/estadisticas.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/estado_carga.dart';
import '../widgets/formato.dart';
import '../widgets/lista_centrada.dart';

/// "Gestionar Bot de Telegram": si el bot responde, qué alertas recibe cada
/// canal (público, privado e interno) y cómo van los envíos. El staff puede
/// mandar un mensaje de prueba a cada canal. El token y los chats se
/// configuran en el servidor (.env), nunca desde la app.
class BotTelegramScreen extends StatefulWidget {
  const BotTelegramScreen({super.key});

  static const titulo = 'Gestionar Bot de Telegram';

  @override
  State<BotTelegramScreen> createState() => _BotTelegramScreenState();
}

/// Forma del estado del bot para el skeleton de carga.
final _ejemplo = EstadoBot(
  bot: 'Bot de Vigía',
  tokenConfigurado: true,
  canales: [
    for (final (canal, nombre) in const [
      ('telegram_publico', 'Telegram público'),
      ('telegram_privado', 'Telegram privado'),
      ('telegram_interno', 'Telegram interno'),
    ])
      CanalBot(
        canal: canal,
        nombre: nombre,
        configurado: true,
        alertas: const ['validacion_manual'],
        enviados7d: 10,
        fallidos7d: 0,
        ultimoEnvio: DateTime(2026, 11, 25),
      ),
  ],
  recientes: [
    for (var i = 0; i < 5; i++)
      EnvioBot(
        fechaEnvio: DateTime(2026, 11, 25),
        canal: 'telegram_privado',
        estado: 'enviado',
        tipoAlerta: 'deteccion_satelital',
        municipio: 'Municipio',
      ),
  ],
);

class _BotTelegramScreenState extends State<BotTelegramScreen> {
  static const _estados = {'enviado': 'Enviado', 'fallido': 'Fallido', 'leido': 'Leído'};

  late Future<EstadoBot> _datos;
  String? _probando;

  @override
  void initState() {
    super.initState();
    _datos = _cargar();
  }

  Future<EstadoBot> _cargar() async {
    final access = await context.read<AuthProvider>().accessToken();
    if (!mounted) throw const ApiException('');
    return context.read<VigiaApi>().estadoBot(access);
  }

  void _recargar() {
    // FutureBuilder lo escucha en el próximo cuadro: si falla antes, sin
    // ignore() el error se reportaría como no manejado (la pantalla igual lo muestra).
    final datos = _cargar()..ignore();
    setState(() {
      _datos = datos;
    });
  }

  Future<void> _probar(String canal, String nombre) async {
    final mensajero = ScaffoldMessenger.of(context);
    setState(() => _probando = canal);
    try {
      final access = await context.read<AuthProvider>().accessToken();
      if (!mounted) return;
      await context.read<VigiaApi>().probarCanal(access, canal);
      mensajero.showSnackBar(SnackBar(content: Text('Mensaje de prueba enviado al canal $nombre.')));
    } on ApiException catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _probando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<AuthProvider>().rol == Rol.staff;
    return Scaffold(
      appBar: AppBar(
        title: const Text(BotTelegramScreen.titulo),
        actions: [IconButton(tooltip: 'Recargar', onPressed: _recargar, icon: const Icon(Icons.refresh))],
      ),
      body: EstadoCarga<EstadoBot>(
        futuro: _datos,
        mensajeError: 'No se pudo cargar el estado del bot.',
        esqueleto: _ejemplo,
        onReintentar: _recargar,
        contenido: (datos) => ListaCentrada(children: _contenido(datos, staff)),
      ),
    );
  }

  List<Widget> _contenido(EstadoBot d, bool staff) {
    final (icono, color, texto) = switch ((d.bot, d.tokenConfigurado)) {
      (final String nombre, _) => (Icons.check_circle, Theme.of(context).colorScheme.primary, 'El bot @$nombre está activo.'),
      (null, true) => (Icons.error, Theme.of(context).colorScheme.error, 'Telegram no reconoce el token del bot o no responde.'),
      (null, false) => (Icons.error, Theme.of(context).colorScheme.error, 'El bot no tiene token: las alertas no salen por Telegram.'),
    };
    final recientes = d.recientes;
    return [
      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(icono, color: color),
          title: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('El token y los canales se configuran en el servidor.'),
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, limites) {
        final columnas = limites.maxWidth >= 1000 ? 3 : (limites.maxWidth >= 640 ? 2 : 1);
        final ancho = (limites.maxWidth - 16 * (columnas - 1)) / columnas;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final c in d.canales)
              SizedBox(
                width: ancho,
                child: _Canal(
                  c,
                  probando: _probando == c.canal,
                  onProbar: staff && _probando == null ? () => _probar(c.canal, c.nombre) : null,
                  staff: staff,
                ),
              ),
          ],
        );
      }),
      const SizedBox(height: 16),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: const Text('Últimos envíos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const SizedBox(height: 8),
              if (recientes.isEmpty)
                Text('Todavía no hay envíos.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              else
                for (final n in recientes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      n.fallido ? Icons.error_outline : Icons.check,
                      color: n.fallido ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text([tiposAlerta[n.tipoAlerta] ?? n.tipoAlerta, ?n.municipio].join(' · ')),
                    subtitle: Text(
                      '${Formato.fechaHora(n.fechaEnvio)} · ${d.nombreCanal(n.canal)} · ${_estados[n.estado] ?? n.estado}',
                    ),
                  ),
            ],
          ),
        ),
      ),
    ];
  }
}

/// Tarjeta de un canal: si está configurado, qué alertas recibe y sus envíos.
class _Canal extends StatelessWidget {
  const _Canal(this.c, {required this.probando, required this.onProbar, required this.staff});

  final CanalBot c;
  final bool probando;
  final VoidCallback? onProbar;
  final bool staff;

  @override
  Widget build(BuildContext context) {
    final configurado = c.configurado;
    final ultimo = c.ultimoEnvio;
    final fallidos = c.fallidos7d;
    final secundario = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.send_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
                Chip(
                  label: Text(configurado ? 'Configurado' : 'Sin configurar'),
                  backgroundColor: configurado ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.tertiaryContainer,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Recibe:', style: secundario),
            for (final t in c.alertas) Text('• ${tiposAlerta[t] ?? t}'),
            const SizedBox(height: 8),
            Text(
              'Últimos 7 días: ${Formato.entero(c.enviados7d)} enviados'
              '${fallidos > 0 ? ' · ${Formato.entero(fallidos)} fallidos' : ''}',
              style: TextStyle(color: fallidos > 0 ? Theme.of(context).colorScheme.error : null),
            ),
            Text(
              ultimo == null ? 'Sin envíos todavía.' : 'Último envío: ${Formato.fechaHora(ultimo)}',
              style: secundario,
            ),
            if (staff) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: configurado ? onProbar : null,
                  icon: probando
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.science_outlined),
                  label: const Text('Enviar prueba'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
