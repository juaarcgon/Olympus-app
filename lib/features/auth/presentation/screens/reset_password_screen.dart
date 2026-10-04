// Pantalla de establecimiento de una nueva contraseña (Servicio_Autenticacion).
//
// Se muestra cuando el Usuario abre el enlace de restablecimiento y existe una
// sesión de recuperación válida. Recoge la nueva contraseña (y su confirmación)
// e invoca `AuthNotifier.updatePasswordWithToken` (Req 9.7). La contraseña debe
// tener al menos ocho (8) caracteres, validado en el cliente y en el
// repositorio (Req 9.6).
//
// Los estados de carga y error se reflejan con un indicador de progreso y
// mensajes en español derivados de `Failure.mensaje` (p. ej. token inválido o
// caducado, contraseña demasiado corta o cuenta suspendida).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/auth_providers.dart';

/// Longitud mínima de la nueva contraseña mostrada como pista (Req 9.6).
const int _passwordMinLength = 8;

/// Pantalla para fijar una nueva contraseña en la sesión de recuperación.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla de restablecimiento de contraseña.
  const ResetPasswordScreen({super.key});

  /// Nombre de ruta de la pantalla de restablecimiento de contraseña.
  static const String routeName = '/reset-password';

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmarController = TextEditingController();
  bool _ocultarPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  /// Valida el formulario y fija la nueva contraseña (Req 9.6, 9.7).
  Future<void> _establecer() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    await ref
        .read(authNotifierProvider.notifier)
        .updatePasswordWithToken(_passwordController.text);

    if (!mounted) return;

    final estado = ref.read(authNotifierProvider);
    estado.when(
      data: (_) =>
          AppNotifications.exito(context, 'Tu contraseña se ha actualizado'),
      loading: () {},
      error: (error, _) =>
          AppNotifications.error(context, _mensajeDeError(error)),
    );
  }

  /// Traduce un error a un mensaje legible en español.
  String _mensajeDeError(Object error) {
    if (error is Failure) return error.mensaje;
    return 'Ha ocurrido un error. Inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authNotifierProvider);
    final cargando = estado.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva contraseña')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Introduce tu nueva contraseña.'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  enabled: !cargando,
                  obscureText: _ocultarPassword,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: 'Mínimo $_passwordMinLength caracteres',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _ocultarPassword = !_ocultarPassword),
                      icon: Icon(
                        _ocultarPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (valor) {
                    if (valor == null || valor.isEmpty) {
                      return 'Introduce una contraseña';
                    }
                    return esPasswordValida(valor)
                        ? null
                        : 'La contraseña debe tener al menos '
                              '$_passwordMinLength caracteres';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmarController,
                  enabled: !cargando,
                  obscureText: _ocultarPassword,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  textInputAction: TextInputAction.done,
                  validator: (valor) => (valor != _passwordController.text)
                      ? 'Las contraseñas no coinciden'
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: cargando ? null : _establecer,
                  child: cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar contraseña'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
