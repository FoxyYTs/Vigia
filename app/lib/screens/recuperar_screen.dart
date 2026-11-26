import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/api/vigia_api.dart';
import '../widgets/lista_centrada.dart';

/// "Recuperar contraseña" (rama de Iniciar Sesión): primero se pide un código
/// de 6 dígitos al correo de la cuenta y luego se escribe con la contraseña
/// nueva, en la misma pantalla (sin enlaces que saquen de la app).
class RecuperarScreen extends StatefulWidget {
  const RecuperarScreen({super.key});

  @override
  State<RecuperarScreen> createState() => _RecuperarScreenState();
}

class _RecuperarScreenState extends State<RecuperarScreen> {
  final _formKey = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _codigo = TextEditingController();
  final _contrasena = TextEditingController();
  final _confirmacion = TextEditingController();

  bool _codigoPedido = false;
  bool _ocultar = true;
  bool _enviando = false;
  String? _error;
  String? _aviso;

  static final _patronCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    for (final c in [_correo, _codigo, _contrasena, _confirmacion]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _ejecutar(Future<void> Function(VigiaApi api) accion) async {
    if (_enviando || !_formKey.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await accion(context.read<VigiaApi>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _pedirCodigo() => _ejecutar((api) async {
    await api.solicitarCodigoRecuperacion(_correo.text.trim());
    if (!mounted) return;
    setState(() {
      _codigoPedido = true;
      _aviso =
          'Si ${_correo.text.trim()} está registrado, te llegó un código de 6 dígitos. '
          'Vence en 15 minutos; revisa también la carpeta de spam.';
    });
  });

  Future<void> _cambiar() => _ejecutar((api) async {
    await api.restablecerContrasena(
      correo: _correo.text.trim(),
      codigo: _codigo.text.trim(),
      contrasena: _contrasena.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Contraseña actualizada. Ya puedes iniciar sesión.')));
    Navigator.of(context).pop();
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final secundario = TextStyle(color: tema.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: ListaCentrada(
        maximo: 560,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        _codigoPedido ? 'Escribe el código' : '¿Olvidaste tu contraseña?',
                        style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _aviso ?? 'Escribe el correo de tu cuenta y te enviaremos un código para crear una nueva.',
                        style: secundario,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(_error!, style: TextStyle(color: tema.colorScheme.error)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      key: const Key('campo-correo'),
                      controller: _correo,
                      enabled: !_codigoPedido,
                      decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      validator: (v) => _patronCorreo.hasMatch(v?.trim() ?? '') ? null : 'Escribe un correo válido.',
                      onFieldSubmitted: (_) => _codigoPedido ? null : _pedirCodigo(),
                    ),
                    if (_codigoPedido) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('campo-codigo'),
                        controller: _codigo,
                        decoration: const InputDecoration(
                          labelText: 'Código de 6 dígitos',
                          prefixIcon: Icon(Icons.pin_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        autofillHints: const [AutofillHints.oneTimeCode],
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v ?? '').length == 6 ? null : 'El código tiene 6 dígitos.',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('campo-nueva'),
                        controller: _contrasena,
                        obscureText: _ocultar,
                        decoration: InputDecoration(
                          labelText: 'Contraseña nueva',
                          helperText: 'Mínimo 8 caracteres, que no sea solo números ni parecida a tu usuario.',
                          helperMaxLines: 2,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                            icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _ocultar = !_ocultar),
                          ),
                        ),
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            (v ?? '').length < 8 ? 'La contraseña debe tener al menos 8 caracteres.' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('campo-confirmacion'),
                        controller: _confirmacion,
                        obscureText: _ocultar,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        textInputAction: TextInputAction.done,
                        validator: (v) => v == _contrasena.text ? null : 'Las contraseñas no coinciden.',
                        onFieldSubmitted: (_) => _cambiar(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('boton-recuperar-enviar'),
                      onPressed: _enviando ? null : (_codigoPedido ? _cambiar : _pedirCodigo),
                      child: Text(switch ((_enviando, _codigoPedido)) {
                        (true, _) => 'Enviando…',
                        (false, false) => 'Enviar código',
                        (false, true) => 'Cambiar contraseña',
                      }),
                    ),
                    if (_codigoPedido)
                      TextButton(
                        onPressed: _enviando
                            ? null
                            : () => setState(() {
                                _codigoPedido = false;
                                _aviso = _error = null;
                                _codigo.clear();
                              }),
                        child: const Text('Usar otro correo o pedir un código nuevo'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
