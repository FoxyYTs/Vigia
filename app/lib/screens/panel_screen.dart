import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/fondo_vigia.dart';
import '../widgets/vigia_marca.dart';
import 'bot_telegram_screen.dart';
import 'estadisticas_screen.dart';
import 'historicos_screen.dart';
import 'informes_screen.dart';
import 'permisos_screen.dart';
import 'reportes_screen.dart';
import 'rutas.dart';

/// Bloques "Gestionar X" que cuelgan de "Iniciar Sesión" en el mapa de
/// navegación. "Gestionar Usuario" (perfil de `/api/auth/yo/`), "Reportar
/// Focos", "Estadísticas", "Históricos", "Informes", "Bot de Telegram" y
/// "Gestionar Permisos" ya funcionan. El ciudadano solo ve los bloques que puede
/// usar: los de gestión son para administradores y staff.
class PanelScreen extends StatelessWidget {
  const PanelScreen({super.key});

  static const _bloques = [
    (Icons.add_a_photo_outlined, ReportesScreen.titulo, 'Reporte con foto tomada en el momento y ubicación del incendio.', Rutas.reportes, false),
    (Icons.query_stats, EstadisticasScreen.titulo, 'Estadísticas de incidentes por región y periodo.', Rutas.estadisticas, true),
    (Icons.history, HistoricosScreen.titulo, 'Históricos de deforestación (IDEAM, UNGRD) e incendios (FIRMS).', Rutas.historicos, true),
    (Icons.description_outlined, InformesScreen.titulo, 'Informes de apoyo a la decisión en CSV, Excel y PDF.', Rutas.informes, true),
    (Icons.send_outlined, BotTelegramScreen.titulo, 'Canales público, privado e interno de alertas.', Rutas.botTelegram, true),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final estrecho = MediaQuery.sizeOf(context).width < 600;
    void irAlMapa() => Navigator.of(context).pushNamedAndRemoveUntil(Rutas.mapa, (_) => false);
    Future<void> cerrarSesion() async {
      await context.read<AuthProvider>().cerrarSesion();
      if (!context.mounted) return;
      irAlMapa();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sesión cerrada.')));
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const VigiaMarca(tamano: 36),
        actions: [
          // En el celular no caben el logo y dos botones con texto: solo íconos con tooltip.
          if (estrecho) ...[
            IconButton(
              tooltip: 'Mapa Interactivo',
              color: Colors.white,
              onPressed: irAlMapa,
              icon: const Icon(Icons.map_outlined),
            ),
            IconButton(tooltip: 'Cerrar sesión', color: Colors.white, onPressed: cerrarSesion, icon: const Icon(Icons.logout)),
          ] else ...[
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: irAlMapa,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Mapa Interactivo'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              style: estiloBotonBarra(context),
              onPressed: cerrarSesion,
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ],
          const SizedBox(width: 12),
        ],
      ),
      body: FondoVigia(child: ListView(
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
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
      )),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                Row(
                  children: [
                    Icon(Icons.manage_accounts_outlined, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: const Text('Gestionar Usuario', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                contenido,
                // Play exige poder borrar desde la app la cuenta que se creó en
                // ella. Solo el ciudadano: las cuentas de gestión las maneja el staff.
                if (context.watch<AuthProvider>().rol == Rol.ciudadano) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () => _eliminarCuenta(context),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar mi cuenta'),
                  ),
                ],
                // Única subpágina del mapa de navegación:
                // Gestionar Usuario → Gestionar Permisos.
                if (context.watch<AuthProvider>().rol.gestiona) ...[
                  const Divider(height: 32),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.admin_panel_settings_outlined, color: Theme.of(context).colorScheme.primary),
                    title: const Text(PermisosScreen.titulo, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    subtitle: Text('Roles y permisos de los usuarios de cada entidad.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () => Navigator.of(context).pushNamed(Rutas.permisos),
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

Future<void> _eliminarCuenta(BuildContext context) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      scrollable: true,
      title: const Text('¿Eliminar tu cuenta?'),
      content: const Text(
        'Se borran tu usuario, tu correo y tu municipio, y se cierran tus sesiones. '
        'Tus reportes se conservan como evidencia de los incendios, pero sin tus datos, '
        'sin tu ubicación y solo con la miniatura de la foto. No se puede deshacer.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(contexto, true),
          child: const Text('Eliminar cuenta'),
        ),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return;
  final mensajero = ScaffoldMessenger.of(context);
  final navegador = Navigator.of(context);
  try {
    await context.read<AuthProvider>().eliminarCuenta();
    navegador.pushNamedAndRemoveUntil(Rutas.mapa, (_) => false);
    mensajero.showSnackBar(const SnackBar(content: Text('Tu cuenta fue eliminada.')));
  } on ApiException catch (e) {
    mensajero.showSnackBar(SnackBar(content: Text(e.mensaje)));
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
          Text(etiqueta, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      );
}

/// Bloque "Gestionar X": abre su pantalla.
class _Bloque extends StatelessWidget {
  const _Bloque(this.icono, this.titulo, this.detalle, this.ruta);

  final IconData icono;
  final String titulo;
  final String detalle;
  final String ruta;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pushNamed(ruta),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icono, color: Theme.of(context).colorScheme.primary),
                    const Spacer(),
                    const Icon(Icons.arrow_forward),
                  ],
                ),
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                const SizedBox(height: 4),
                Text(detalle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
}
