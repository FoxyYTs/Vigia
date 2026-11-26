import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api/vigia_api.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/estado_carga.dart';
import '../widgets/lista_centrada.dart';

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
  bool _abriendo = false;
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
    // FutureBuilder lo escucha en el próximo cuadro: si falla antes, sin
    // ignore() el error se reportaría como no manejado (la pantalla igual lo muestra).
    final usuarios = _cargar()..ignore();
    setState(() {
      _usuarios = usuarios;
    });
  }

  Future<void> _editar(Map<String, dynamic> usuario) async {
    // Las entidades tardan en llegar: sin esto, varios toques abrían varios diálogos.
    if (_abriendo) return;
    final mensajero = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    final api = context.read<VigiaApi>();
    setState(() => _abriendo = true);
    try {
      final entidades = await api.entidades(await auth.accessToken());
      if (!mounted) return;
      setState(() => _abriendo = false);
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
    } finally {
      if (mounted && _abriendo) setState(() => _abriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final staff = auth.rol == Rol.staff;
    return Scaffold(
      appBar: AppBar(title: const Text(PermisosScreen.titulo)),
      body: ListaCentrada(
        maximo: ListaCentrada.lectura,
        children: [
          if (!staff)
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Administradores de tu entidad. Los permisos los cambia el staff de Vigía.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                    onSelected: (_) {
                      _rol = r;
                      _recargar();
                    },
                  ),
            ],
          ),
          const SizedBox(height: 16),
          EstadoCarga<List<Map<String, dynamic>>>(
            futuro: _usuarios,
            mensajeError: 'No se pudieron cargar los usuarios.',
            esqueleto: [
              for (var i = 0; i < 6; i++)
                {
                  'id': i,
                  'username': 'usuario_ejemplo',
                  'email': 'usuario@correo.co',
                  'rol': 'ciudadano',
                  'entidad': null,
                  'entidad_nombre': null,
                  'nombre': '',
                  'is_active': true,
                },
            ],
            onReintentar: _recargar,
            contenido: (usuarios) => usuarios.isEmpty
                ? Text('Ningún usuario coincide.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                : Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final u in usuarios)
                          _Usuario(
                            u,
                            // Ni a sí mismo: el backend también lo rechaza.
                            onEditar: staff && u['username'] != auth.username ? () => _editar(u) : null,
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

class _Usuario extends StatelessWidget {
  const _Usuario(this.u, {required this.onEditar});

  final Map<String, dynamic> u;
  final VoidCallback? onEditar;

  @override
  Widget build(BuildContext context) {
    final activo = u['is_active'] as bool;
    final email = u['email'] as String;
    return ListTile(
      leading: Icon(Icons.person_outline, color: activo ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
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
        // Con el teclado abierto o letra grande, el contenido se desplaza.
        scrollable: true,
        title: Text('Permisos de ${widget.usuario['username']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Al cambiar el rol se cerrarán sus sesiones abiertas.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
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
