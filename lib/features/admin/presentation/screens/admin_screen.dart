// Pantalla del panel de administración (Servicio_Administracion).
//
// Solo accesible para un Superadministrador (la pestaña que la contiene únicamente
// se muestra si el Usuario actual tiene rol de superadministrador, Req 5.3; la
// autorización crítica la refuerza además el backend vía RLS/RPC, Req 5.4).
//
// Funciones:
//   - Listado de Usuarios (Req 6.1): por cada Usuario muestra nombre y
//     apellidos, correo electrónico, Estado_Usuario (activo/suspendido con
//     color), Saldo_De_Clases y si es superadministrador.
//   - Acciones por Usuario mediante un menú:
//       * suspender / reactivar según su estado (Req 6.2, 6.3),
//       * eliminar con diálogo de confirmación (Req 6.4, 6.7),
//       * restablecer bono a 10 (Req 6.5),
//       * ajustar bono con un campo numérico 0..10 (Req 6.6),
//       * conceder superadministrador (Req 5.1, 5.2).
//
// Los `Failure` de dominio se muestran como notificaciones rojas en español
// (p. ej. MaxSuperadminsFailure o AutoeliminacionFailure); nunca se muestran trazas
// técnicas. Los estados de carga y error del listado se reflejan con un
// indicador de progreso y una vista de error con reintento.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failures.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../profile/domain/entities/profile.dart';
import '../providers/admin_providers.dart';

/// Pantalla de gestión de Usuarios para superadministradores.
class AdminScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla del panel de administración.
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  /// Muestra una notificación de ÉXITO (verde).
  void _mostrarExito(String mensaje) {
    if (!mounted) return;
    AppNotifications.exito(context, mensaje);
  }

  /// Muestra una notificación de ERROR (rojo).
  void _mostrarError(String mensaje) {
    if (!mounted) return;
    AppNotifications.error(context, mensaje);
  }

  /// Traduce un error a un mensaje legible en español (Req 5.2, 6.7, etc.).
  String _mensajeDeError(Object error) {
    if (error is Failure) return error.mensaje;
    return 'Ha ocurrido un error. Inténtalo de nuevo.';
  }

  /// Ejecuta una acción administrativa capturando los `Failure` de dominio para
  /// mostrarlos como notificación de error; en caso de éxito muestra
  /// [mensajeExito] en verde.
  Future<void> _ejecutarAccion(
    Future<void> Function() accion, {
    required String mensajeExito,
  }) async {
    try {
      await accion();
      _mostrarExito(mensajeExito);
    } on Failure catch (failure) {
      _mostrarError(failure.mensaje);
    } on Object catch (error) {
      _mostrarError(_mensajeDeError(error));
    }
  }

  /// Suspende a un Usuario (Req 6.2).
  Future<void> _suspender(Profile usuario) => _ejecutarAccion(
    () => ref.read(adminNotifierProvider.notifier).suspend(usuario.id),
    mensajeExito: 'Usuario suspendido',
  );

  /// Reactiva a un Usuario (Req 6.3).
  Future<void> _reactivar(Profile usuario) => _ejecutarAccion(
    () => ref.read(adminNotifierProvider.notifier).reactivate(usuario.id),
    mensajeExito: 'Usuario reactivado',
  );

  /// Restablece el bono de un Usuario a 10 (Req 6.5).
  Future<void> _restablecerBono(Profile usuario) => _ejecutarAccion(
    () => ref.read(adminNotifierProvider.notifier).restablecerBono(usuario.id),
    mensajeExito: 'Bono restablecido a 10 clases',
  );

  /// Concede el rol de superadministrador a un Usuario (Req 5.1, 5.2).
  Future<void> _concederSuperadmin(Profile usuario) => _ejecutarAccion(
    () => ref.read(adminNotifierProvider.notifier).grantSuperadmin(usuario.id),
    mensajeExito: 'Rol de superadministrador concedido',
  );

  /// Elimina a un Usuario tras confirmación (Req 6.4, 6.7).
  Future<void> _eliminar(Profile usuario) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text(
          '¿Seguro que quieres eliminar a ${usuario.nombre} '
          '${usuario.apellidos}? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    await _ejecutarAccion(
      () => ref.read(adminNotifierProvider.notifier).delete(usuario.id),
      mensajeExito: 'Usuario eliminado',
    );
  }

  /// Ajusta el bono de un Usuario mediante un diálogo con un campo numérico
  /// (0..10) (Req 6.6).
  Future<void> _ajustarBono(Profile usuario) async {
    final valor = await showDialog<int>(
      context: context,
      builder: (context) =>
          _AjustarBonoDialog(valorInicial: usuario.saldoClases),
    );

    if (valor == null) return;

    await _ejecutarAccion(
      () => ref
          .read(adminNotifierProvider.notifier)
          .ajustarBono(usuario.id, valor),
      mensajeExito: 'Bono ajustado a $valor clases',
    );
  }

  @override
  Widget build(BuildContext context) {
    final estadoUsuarios = ref.watch(adminNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: estadoUsuarios.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorAdmin(
          mensaje: _mensajeDeError(error),
          onReintentar: () =>
              ref.read(adminNotifierProvider.notifier).refresh(),
        ),
        data: (usuarios) {
          if (usuarios.isEmpty) {
            return const Center(child: Text('No hay usuarios registrados'));
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(adminNotifierProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: usuarios.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final usuario = usuarios[index];
                return _UsuarioTile(
                  usuario: usuario,
                  onSuspender: () => _suspender(usuario),
                  onReactivar: () => _reactivar(usuario),
                  onEliminar: () => _eliminar(usuario),
                  onRestablecerBono: () => _restablecerBono(usuario),
                  onAjustarBono: () => _ajustarBono(usuario),
                  onConcederSuperadmin: () => _concederSuperadmin(usuario),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Acciones administrativas disponibles en el menú de cada Usuario.
enum _AccionUsuario {
  suspender,
  reactivar,
  eliminar,
  restablecerBono,
  ajustarBono,
  concederSuperadmin,
}

/// Fila que resume un Usuario y ofrece el menú de acciones (Req 6.1).
class _UsuarioTile extends StatelessWidget {
  const _UsuarioTile({
    required this.usuario,
    required this.onSuspender,
    required this.onReactivar,
    required this.onEliminar,
    required this.onRestablecerBono,
    required this.onAjustarBono,
    required this.onConcederSuperadmin,
  });

  final Profile usuario;
  final VoidCallback onSuspender;
  final VoidCallback onReactivar;
  final VoidCallback onEliminar;
  final VoidCallback onRestablecerBono;
  final VoidCallback onAjustarBono;
  final VoidCallback onConcederSuperadmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundImage:
            (usuario.fotoUrl != null && usuario.fotoUrl!.isNotEmpty)
            ? NetworkImage(usuario.fotoUrl!)
            : null,
        child: (usuario.fotoUrl == null || usuario.fotoUrl!.isEmpty)
            ? const Icon(Icons.person)
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${usuario.nombre} ${usuario.apellidos}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (usuario.esSuperadmin) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Superadministrador',
              child: Icon(
                Icons.shield,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(usuario.email, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _EstadoChip(estado: usuario.estado),
              Text('Saldo: ${usuario.saldoClases}'),
            ],
          ),
        ],
      ),
      trailing: PopupMenuButton<_AccionUsuario>(
        tooltip: 'Acciones',
        onSelected: (accion) {
          switch (accion) {
            case _AccionUsuario.suspender:
              onSuspender();
            case _AccionUsuario.reactivar:
              onReactivar();
            case _AccionUsuario.eliminar:
              onEliminar();
            case _AccionUsuario.restablecerBono:
              onRestablecerBono();
            case _AccionUsuario.ajustarBono:
              onAjustarBono();
            case _AccionUsuario.concederSuperadmin:
              onConcederSuperadmin();
          }
        },
        itemBuilder: (context) => [
          // Suspender / reactivar según el estado actual (Req 6.2, 6.3).
          if (usuario.estaActivo)
            const PopupMenuItem(
              value: _AccionUsuario.suspender,
              child: ListTile(
                leading: Icon(Icons.block),
                title: Text('Suspender'),
              ),
            )
          else
            const PopupMenuItem(
              value: _AccionUsuario.reactivar,
              child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('Reactivar'),
              ),
            ),
          const PopupMenuItem(
            value: _AccionUsuario.restablecerBono,
            child: ListTile(
              leading: Icon(Icons.restart_alt),
              title: Text('Restablecer bono'),
            ),
          ),
          const PopupMenuItem(
            value: _AccionUsuario.ajustarBono,
            child: ListTile(
              leading: Icon(Icons.tune),
              title: Text('Ajustar bono'),
            ),
          ),
          // Conceder superadministrador solo si aún no lo es (Req 5.1, 5.2).
          if (!usuario.esSuperadmin)
            const PopupMenuItem(
              value: _AccionUsuario.concederSuperadmin,
              child: ListTile(
                leading: Icon(Icons.shield_outlined),
                title: Text('Conceder superadmin'),
              ),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _AccionUsuario.eliminar,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Eliminar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip que representa el Estado_Usuario con color (Req 6.1).
class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.estado});

  final EstadoUsuario estado;

  @override
  Widget build(BuildContext context) {
    final activo = estado == EstadoUsuario.activo;
    final color = activo ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        activo ? 'Activo' : 'Suspendido',
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

/// Diálogo para ajustar el bono de un Usuario con un campo numérico 0..10
/// (Req 6.6). Devuelve el valor confirmado o `null` si se cancela.
class _AjustarBonoDialog extends StatefulWidget {
  const _AjustarBonoDialog({required this.valorInicial});

  final int valorInicial;

  @override
  State<_AjustarBonoDialog> createState() => _AjustarBonoDialogState();
}

class _AjustarBonoDialogState extends State<_AjustarBonoDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.valorInicial}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Valida el campo y confirma el nuevo valor del bono (Req 6.6).
  void _confirmar() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    Navigator.of(context).pop(int.parse(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajustar bono'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Saldo de clases (0 a 10)',
            border: OutlineInputBorder(),
          ),
          validator: (valor) {
            final texto = valor?.trim() ?? '';
            final numero = int.tryParse(texto);
            if (numero == null) {
              return 'Introduce un número válido';
            }
            if (numero < 0 || numero > 10) {
              return 'El valor debe estar entre 0 y 10';
            }
            return null;
          },
          onFieldSubmitted: (_) => _confirmar(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Vista de error con opción de reintentar la carga del listado de Usuarios.
class _ErrorAdmin extends StatelessWidget {
  const _ErrorAdmin({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onReintentar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
