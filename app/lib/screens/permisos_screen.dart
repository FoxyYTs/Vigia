import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/vigia_theme.dart';
import '../data/api/vigia_api.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';

/// "Gestionar Permisos" (subpágina de Gestionar Usuario): el staff cambia el
/// rol, la entidad y si la cuenta está activa; el administrador solo consulta
/// a los administradores de su entidad.
class PermisosScreen extends StatefulWidget {
  const PermisosScreen({super.key});

  static const titulo = 'Gestionar Permisos';

  @override
  State<PermisosScreen> createState() => _PermisosScreenState();
}

class _PermisosScreenState extends State<PermisosScreen> {
  final _buscar = TextEditingController();
  Rol? _rol;
  late Future<List<Map<String, dynamic>>> _usuarios;

  @override
  void initState() {
    super.initState();
    _usuarios = _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _cargar() async {
    final access = await context.read<AuthProvider>().accessToken();
    if (!mounted) throw const ApiException('');
    return context.read<VigiaApi>().usuarios(access, buscar: _buscar.text.trim(), rol: _rol?.valorApi);
  }

  void _recargar() {
    final usuarios = _cargar();
    setState(() {
      _usuarios = usuarios;
    });
  }

  Future<void> _editar(Map<String, dynamic> usuario) async {
    final mensajero = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    final api = context.read<VigiaApi>();
    try {
      final entidades = await api.entidades(await auth.accessToken());
      if (!mounted) return;
      final cambios = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (_) => _EditarUsuario(usuario: usuario, entidades: entidades),
      );
      if (cambios == null) return;
      await api.actualizarUsuario(await auth.accessToken(), usuario['id'] as int, cambios);
      mensajero.showSnackBar(SnackBar(content: Text('Permisos de ${usuario['username']} actualizados.')));
      if (mounted) _recargar();
    } on ApiException catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final staff = auth.rol == Rol.staff;
    return Scaffold(
      appBar: AppBar(title: const Text(PermisosScreen.titulo)),
      body: ListView(
        // Centrado y con ancho máximo en pantallas anchas.
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: max(16, (MediaQuery.sizeOf(context).width - 1000) / 2)),
        children: [
          if (!staff)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Administradores de tu entidad. Los permisos los cambia el staff de Vigía.',
                  style: TextStyle(color: VigiaColors.textoSecundario)),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _buscar,
                  decoration: InputDecoration(
                    labelText: 'Buscar por usuario o correo',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(tooltip: 'Buscar', onPressed: _recargar, icon: const Icon(Icons.arrow_forward)),
                  ),
                  onSubmitted: (_) => _recargar(),
                ),
              ),
              if (staff)
                for (final r in [null, Rol.ciudadano, Rol.administrador, Rol.staff])
                  ChoiceChip(
                    label: Text(r?.etiqueta ?? 'Todos'),
                    selected: _rol == r,
                    selectedColor: VigiaColors.bosqueClaro,
                    onSelected: (_) {
                      _rol = r;
                      _recargar();
                    },
                  ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _usuarios,
            builder: (context, snap) => switch (snap) {
              AsyncSnapshot(hasError: true, :final error) => Text(
                  error is ApiException ? error.mensaje : 'No se pudieron cargar los usuarios.',
                  style: const TextStyle(color: VigiaColors.error),
                ),
              AsyncSnapshot(connectionState: ConnectionState.done, hasData: true, :final data) when data!.isEmpty =>
                const Text('Ningún usuario coincide.', style: TextStyle(color: VigiaColors.textoSecundario)),
              AsyncSnapshot(connectionState: ConnectionState.done, hasData: true, :final data) => Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final u in data!)
                        _Usuario(
                          u,
                          // Ni a sí mismo: el backend también lo rechaza.
                          onEditar: staff && u['username'] != auth.username ? () => _editar(u) : null,
                        ),
                    ],
                  ),
                ),
              _ => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            },
          ),
        ],
      ),
    );
  }
}

class _Usuario extends StatelessWidget {
  const _Usuario(this.u, {required this.onEditar});

  final Map<String, dynamic> u;
  final VoidCallback? onEditar;

  @override
  Widget build(BuildContext context) {
    final activo = u['is_active'] as bool;
    final email = u['email'] as String;
    return ListTile(
      leading: Icon(Icons.person_outline, color: activo ? VigiaColors.bosque : VigiaColors.textoSecundario),
      title: Text(u['username'] as String, style: TextStyle(decoration: activo ? null : TextDecoration.lineThrough)),
      subtitle: Text([
        Rol.desdeApi(u['rol'] as String?).etiqueta,
        ?u['entidad_nombre'] as String?,
        if (email.isNotEmpty) email,
        if (!activo) 'Cuenta desactivada',
      ].join(' · ')),
      trailing: onEditar == null
          ? null
          : IconButton(tooltip: 'Editar permisos de ${u['username']}', onPressed: onEditar, icon: const Icon(Icons.edit)),
    );
  }
}

/// Diálogo del staff: rol, entidad (solo para administradores) y cuenta activa.
/// Devuelve los campos cambiados, o null si se cancela.
class _EditarUsuario extends StatefulWidget {
  const _EditarUsuario({required this.usuario, required this.entidades});

  final Map<String, dynamic> usuario;
  final List<Map<String, dynamic>> entidades;

  @override
  State<_EditarUsuario> createState() => _EditarUsuarioState();
}

class _EditarUsuarioState extends State<_EditarUsuario> {
  /// Valor del selector para "todo el país" (administrador sin entidad).
  static const _todoElPais = -1;

  late Rol _rol;
  int? _entidad;

  @override
  void initState() {
    super.initState();
    _rol = Rol.desdeApi(widget.usuario['rol'] as String?);
    // Quien ya es administrador conserva su alcance; al promover a alguien hay
    // que elegirlo: por defecto vería los reportes (y el GPS) de todo el país.
    if (_rol == Rol.administrador) _entidad = widget.usuario['entidad'] as int? ?? _todoElPais;
  }
  late bool _activo = widget.usuario['is_active'] as bool;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Permisos de ${widget.usuario['username']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Rol>(
                isExpanded: true,
                initialValue: _rol == Rol.desconocido ? null : _rol,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: [
                  for (final r in [Rol.ciudadano, Rol.administrador, Rol.staff])
                    DropdownMenuItem(value: r, child: Text(r.etiqueta)),
                ],
                onChanged: (r) => setState(() => _rol = r!),
              ),
              const SizedBox(height: 12),
              if (_rol == Rol.administrador)
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _entidad,
                  hint: const Text('Elige su alcance'),
                  decoration: const InputDecoration(
                    labelText: 'Entidad',
                    helperText: 'Limita lo que ve a los municipios de la entidad.',
                  ),
                  items: [
                    const DropdownMenuItem(value: _todoElPais, child: Text('Sin entidad (todo el país)')),
                    for (final e in widget.entidades)
                      DropdownMenuItem(value: e['id'] as int, child: Text(e['nombre'] as String)),
                  ],
                  onChanged: (v) => setState(() => _entidad = v),
                ),
              if (_rol.valorApi != widget.usuario['rol'])
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Al cambiar el rol se cerrarán sus sesiones abiertas.',
                      style: TextStyle(color: VigiaColors.textoSecundario, fontSize: 13)),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cuenta activa'),
                subtitle: _activo ? null : const Text('No podrá iniciar sesión y se cerrarán sus sesiones.'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: _rol == Rol.administrador && _entidad == null
                ? null
                : () => Navigator.pop(context, {
                      'rol': _rol.valorApi,
                      'entidad': _rol == Rol.administrador && _entidad != _todoElPais ? _entidad : null,
                      'is_active': _activo,
                    }),
            child: const Text('Guardar'),
          ),
        ],
      );
}
