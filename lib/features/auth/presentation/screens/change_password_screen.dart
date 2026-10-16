// Pantalla de cambio de contraseña para el Usuario con sesión activa.
//
// A diferencia del flujo de recuperación por correo (forgot/reset), esta
// pantalla la usa un Usuario YA autenticado desde su perfil para cambiar su
// contraseña conociendo la actual. Pide la contraseña actual (reautenticación
// de seguridad), la nueva y su confirmación, e invoca
// `AuthNotifier.changePassword`.
//
// La nueva contraseña debe tener al menos ocho (8) caracteres (Req 1.6/9.6).
// Los estados de carga y error se reflejan con un indicador de progreso y
// mensajes en español derivados de `Failure.mensaje` (p. ej. contraseña actual
// incorrecta o nueva demasiado corta).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/auth_providers.dart';

/// Longitud mínima de la nueva contraseña mostrada como pista (Req 9.6).
const int _passwordMinLength = 8;

/// Pantalla para que un Usuario autenticado cambie su contraseña.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla de cambio de contraseña.
  const ChangePasswordScreen({super.key});

  /// Nombre de ruta de la pantalla de cambio de contraseña.
  static const String routeName = '/change-password';

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _actualController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();

  bool _ocultarActual = true;
  bool _ocultarNueva = true;

  @override
  void dispose() {
    _actualController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  /// Valida el formulario y cambia la contraseña (Req 1.6/9.6).
  Future<void> _cambiar() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final exito = await ref
        .read(authNotifierProvider.notifier)
        .changePassword(
          currentPassword: _actualController.text,
          newPassword: _nuevaController.text,
        );

    if (!mounted) return;

    if (exito) {
      AppNotifications.exito(context, 'Tu contraseña se ha actualizado');
      Navigator.of(context).pop();
    } else {
      final error = ref.read(authNotifierProvider).error;
      AppNotifications.error(context, _mensajeDeError(error));
    }
  }

  /// Traduce un error a un mensaje legible en español.
  String _mensajeDeError(Object? error) {
    if (error is Failure) return error.mensaje;
    return 'Ha ocurrido un error. Inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authNotifierProvider);
    final cargando = estado.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar contraseña')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Introduce tu contraseña actual y la nueva contraseña.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _actualController,
                  enabled: !cargando,
                  obscureText: _ocultarActual,
                  decoration: InputDecoration(
                    labelText: 'Contraseña actual',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _ocultarActual = !_ocultarActual),
                      icon: Icon(
                        _ocultarActual
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (valor) => (valor == null || valor.isEmpty)
                      ? 'Introduce tu contraseña actual'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nuevaController,
                  enabled: !cargando,
                  obscureText: _ocultarNueva,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    helperText: 'Mínimo $_passwordMinLength caracteres',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _ocultarNueva = !_ocultarNueva),
                      icon: Icon(
                        _ocultarNueva
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
                    if (!esPasswordValida(valor)) {
                      return 'La contraseña debe tener al menos '
                          '$_passwordMinLength caracteres';
                    }
                    if (valor == _actualController.text) {
                      return 'La nueva contraseña debe ser distinta de la actual';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmarController,
                  enabled: !cargando,
                  obscureText: _ocultarNueva,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_reset_outlined),
                  ),
                  textInputAction: TextInputAction.done,
                  validator: (valor) => (valor != _nuevaController.text)
                      ? 'Las contraseñas no coinciden'
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: cargando ? null : _cambiar,
                  child: cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cambiar contraseña'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
