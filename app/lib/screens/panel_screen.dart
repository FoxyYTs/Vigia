import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/vigia_marca.dart';
import 'rutas.dart';

/// Bloques "Gestionar X" que cuelgan de "Iniciar Sesión" en el mapa de
/// navegación. En este incremento solo "Gestionar Usuario" muestra datos
/// reales (el perfil de `/api/auth/yo/`); los demás se habilitan en los
/// incrementos siguientes del cronograma.
class PanelScreen extends StatelessWidget {
  const PanelScreen({super.key});

  static const _bloques = [
    (Icons.add_a_photo_outlined, 'Gestionar Reportar Focos de Incendios', 'Reporte con foto tomada en el momento y ubicación del incendio.'),
    (Icons.query_stats, 'Gestionar Estadísticas', 'Estadísticas de incidentes por región y periodo.'),
    (Icons.history, 'Gestionar Históricos', 'Históricos de deforestación (IDEAM, UNGRD) e incendios (FIRMS).'),
    (Icons.description_outlined, 'Gestionar Informes', 'Informes de apoyo a la decisión en CSV, Excel y PDF.'),
    (Icons.send_outlined, 'Gestionar Bot de Telegram', 'Canales público, privado e interno de alertas.'),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const VigiaMarca(tamano: 36),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(Rutas.mapa, (_) => false),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Mapa Interactivo'),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: VigiaColors.bosque),
            onPressed: () async {
              await context.read<AuthProvider>().cerrarSesion();
              if (!context.mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil(Rutas.mapa, (_) => false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sesión cerrada.')),
              );
            },
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text('Hola, ${auth.username}',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  Text('Sesión iniciada como ${auth.rol.etiqueta.toLowerCase()}.',
                      style: const TextStyle(color: VigiaColors.textoSecundario)),
                  const SizedBox(height: 24),
                  const _GestionarUsuario(),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final (icono, titulo, detalle) in _bloques)
                        SizedBox(width: 340, child: _BloquePendiente(icono, titulo, detalle)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GestionarUsuario extends StatefulWidget {
  const _GestionarUsuario();

  @override
  State<_GestionarUsuario> createState() => _GestionarUsuarioState();
}

class _GestionarUsuarioState extends State<_GestionarUsuario> {
  late Future<Usuario> _perfil;

  @override
  void initState() {
    super.initState();
    _perfil = _cargar();
  }

  Future<Usuario> _cargar() async {
    final auth = context.read<AuthProvider>();
    final api = context.read<VigiaApi>();
    return api.obtenerPerfil(await auth.accessToken());
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<Usuario>(
          future: _perfil,
          builder: (context, snap) {
            final contenido = switch (snap) {
              AsyncSnapshot(hasError: true, :final error) => Text(
                  error is ApiException ? error.mensaje : 'No se pudo cargar el perfil.',
                  style: const TextStyle(color: VigiaColors.error),
                ),
              AsyncSnapshot(hasData: true, :final data) => Wrap(
                  spacing: 32,
                  runSpacing: 12,
                  children: [
                    _Dato('Usuario', data!.username),
                    _Dato('Correo', data.email.isEmpty ? 'Sin correo' : data.email),
                    _Dato('Rol', data.rol.etiqueta),
                  ],
                ),
              _ => const LinearProgressIndicator(),
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.manage_accounts_outlined, color: VigiaColors.bosque),
                    SizedBox(width: 10),
                    Text('Gestionar Usuario', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 16),
                contenido,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(fontSize: 12, color: VigiaColors.textoSecundario)),
          Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      );
}

class _BloquePendiente extends StatelessWidget {
  const _BloquePendiente(this.icono, this.titulo, this.detalle);

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icono, color: VigiaColors.textoSecundario),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: VigiaColors.superficie,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: VigiaColors.borde),
                    ),
                    child: const Text('Próximo incremento',
                        style: TextStyle(fontSize: 11, color: VigiaColors.textoSecundario)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(detalle, style: const TextStyle(color: VigiaColors.textoSecundario, fontSize: 13)),
            ],
          ),
        ),
      );
}
