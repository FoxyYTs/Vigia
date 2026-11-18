import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../data/models/estadisticas.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/formato.dart';

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

class _BotTelegramScreenState extends State<BotTelegramScreen> {
  static const _estados = {'enviado': 'Enviado', 'fallido': 'Fallido', 'leido': 'Leído'};

  late Future<Map<String, dynamic>> _datos;
  String? _probando;

  @override
  void initState() {
    super.initState();
    _datos = _cargar();
  }

  Future<Map<String, dynamic>> _cargar() async {
    final access = await context.read<AuthProvider>().accessToken();
    if (!mounted) throw const ApiException('');
    return context.read<VigiaApi>().estadoBot(access);
  }

  void _recargar() {
    final datos = _cargar();
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
      body: FutureBuilder<Map<String, dynamic>>(
        future: _datos,
        builder: (context, snap) => switch (snap) {
          AsyncSnapshot(hasError: true, :final error) => Center(
              child: Text(
                error is ApiException ? error.mensaje : 'No se pudo cargar el estado del bot.',
                style: const TextStyle(color: VigiaColors.error),
              ),
            ),
          AsyncSnapshot(connectionState: ConnectionState.done, hasData: true, :final data) => ListView(
              // Centrado y con ancho máximo en pantallas anchas.
              padding:
                  EdgeInsets.symmetric(vertical: 16, horizontal: max(16, (MediaQuery.sizeOf(context).width - 1500) / 2)),
              children: _contenido(data!, staff),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  List<Widget> _contenido(Map<String, dynamic> d, bool staff) {
    final bot = d['bot'] as String?;
    final (icono, color, texto) = switch ((bot, d['token_configurado'] as bool)) {
      (final String nombre, _) => (Icons.check_circle, VigiaColors.bosque, 'El bot @$nombre está activo.'),
      (null, true) => (Icons.error, VigiaColors.error, 'Telegram no reconoce el token del bot o no responde.'),
      (null, false) => (Icons.error, VigiaColors.error, 'El bot no tiene token: las alertas no salen por Telegram.'),
    };
    final recientes = d['recientes'] as List;
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
            for (final c in d['canales'] as List)
              SizedBox(
                width: ancho,
                child: _Canal(
                  c as Map<String, dynamic>,
                  probando: _probando == c['canal'],
                  onProbar: staff && _probando == null ? () => _probar(c['canal'] as String, c['nombre'] as String) : null,
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
                const Text('Todavía no hay envíos.', style: TextStyle(color: VigiaColors.textoSecundario))
              else
                for (final n in recientes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      n['estado'] == 'fallido' ? Icons.error_outline : Icons.check,
                      color: n['estado'] == 'fallido' ? VigiaColors.error : VigiaColors.bosque,
                    ),
                    title: Text(
                      [tiposAlerta[n['tipo_alerta']] ?? n['tipo_alerta'], ?n['municipio'] as String?].join(' · '),
                    ),
                    subtitle: Text(
                      '${Formato.fechaHora(DateTime.parse(n['fecha_envio'] as String))} · '
                      '${_nombreCanal(d, n['canal'] as String)} · ${_estados[n['estado']] ?? n['estado']}',
                    ),
                  ),
            ],
          ),
        ),
      ),
    ];
  }

  static String _nombreCanal(Map<String, dynamic> d, String canal) =>
      (d['canales'] as List).firstWhere((c) => c['canal'] == canal, orElse: () => {'nombre': canal})['nombre']
          as String;
}

/// Tarjeta de un canal: si está configurado, qué alertas recibe y sus envíos.
class _Canal extends StatelessWidget {
  const _Canal(this.c, {required this.probando, required this.onProbar, required this.staff});

  final Map<String, dynamic> c;
  final bool probando;
  final VoidCallback? onProbar;
  final bool staff;

  @override
  Widget build(BuildContext context) {
    final configurado = c['configurado'] as bool;
    final ultimo = c['ultimo_envio'] as String?;
    final fallidos = c['fallidos_7d'] as int;
    const secundario = TextStyle(color: VigiaColors.textoSecundario);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.send_outlined, color: VigiaColors.bosque),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(c['nombre'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
                Chip(
                  label: Text(configurado ? 'Configurado' : 'Sin configurar'),
                  backgroundColor: configurado ? VigiaColors.bosqueClaro : VigiaColors.fuegoClaro,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Recibe:', style: secundario),
            for (final t in c['alertas'] as List) Text('• ${tiposAlerta[t] ?? t}'),
            const SizedBox(height: 8),
            Text(
              'Últimos 7 días: ${Formato.entero(c['enviados_7d'] as int)} enviados'
              '${fallidos > 0 ? ' · ${Formato.entero(fallidos)} fallidos' : ''}',
              style: TextStyle(color: fallidos > 0 ? VigiaColors.error : null),
            ),
            Text(
              ultimo == null ? 'Sin envíos todavía.' : 'Último envío: ${Formato.fechaHora(DateTime.parse(ultimo))}',
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
