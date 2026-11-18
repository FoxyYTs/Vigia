import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/proximo_incremento.dart';
import '../widgets/vigia_marca.dart';
import 'estadisticas_screen.dart';
import 'informes_screen.dart';
import 'reportes_screen.dart';
import 'rutas.dart';

/// Bloques "Gestionar X" que cuelgan de "Iniciar Sesión" en el mapa de
/// navegación. "Gestionar Usuario" (perfil de `/api/auth/yo/`), "Reportar
/// Focos", "Estadísticas" e "Informes" ya funcionan; los demás se habilitan
/// en los incrementos siguientes. El ciudadano solo ve los bloques que puede
/// usar: los de gestión son para administradores y staff.
class PanelScreen extends StatelessWidget {
  const PanelScreen({super.key});

  static const _bloques = [
    (Icons.add_a_photo_outlined, ReportesScreen.titulo, 'Reporte con foto tomada en el momento y ubicación del incendio.', Rutas.reportes, false),
    (Icons.query_stats, EstadisticasScreen.titulo, 'Estadísticas de incidentes por región y periodo.', Rutas.estadisticas, true),
    (Icons.history, 'Gestionar Históricos', 'Históricos de deforestación (IDEAM, UNGRD) e incendios (FIRMS).', null, true),
    (Icons.description_outlined, InformesScreen.titulo, 'Informes de apoyo a la decisión en CSV, Excel y PDF.', Rutas.informes, true),
    (Icons.send_outlined, 'Gestionar Bot de Telegram', 'Canales público, privado e interno de alertas.', null, true),
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
                      for (final (icono, titulo, detalle, ruta, gestion) in _bloques)
                        if (!gestion || auth.rol.gestiona)
                          SizedBox(width: 340, child: _Bloque(icono, titulo, detalle, ruta)),
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
                // Única subpágina del mapa de navegación:
                // Gestionar Usuario → Gestionar Permisos.
                if (context.watch<AuthProvider>().rol.gestiona) ...[
                  const Divider(height: 32),
                  const Row(
                    children: [
                      Icon(Icons.admin_panel_settings_outlined, color: VigiaColors.textoSecundario),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Gestionar Permisos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            Text('Roles y permisos de los usuarios de cada entidad.',
                                style: TextStyle(color: VigiaColors.textoSecundario, fontSize: 13)),
                          ],
                        ),
                      ),
                      ProximoIncremento(),
                    ],
                  ),
                ],
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

/// Bloque "Gestionar X": abre su pantalla si ya tiene [ruta]; si no, queda
/// rotulado como próximo incremento.
class _Bloque extends StatelessWidget {
  const _Bloque(this.icono, this.titulo, this.detalle, this.ruta);

  final IconData icono;
  final String titulo;
  final String detalle;
  final String? ruta;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: ruta == null ? null : () => Navigator.of(context).pushNamed(ruta!),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icono, color: ruta == null ? VigiaColors.textoSecundario : VigiaColors.bosque),
                    const Spacer(),
                    if (ruta == null) const ProximoIncremento() else const Icon(Icons.arrow_forward),
                  ],
                ),
                const SizedBox(height: 12),
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(detalle, style: const TextStyle(color: VigiaColors.textoSecundario, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
}
