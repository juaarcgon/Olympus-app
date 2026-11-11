// Pantalla de perfil del Usuario (Servicio_Usuarios).
//
// Muestra los datos del perfil del Usuario autenticado y permite editar los
// campos editables:
//
//   - Lectura (Req 3.1): nombre, apellidos, correo electrónico, foto y
//     Saldo_De_Clases. El saldo y el estado se muestran en SOLO LECTURA; esta
//     pantalla no ofrece ningún control para modificarlos (Req 3.3, 3.4).
//   - Edición (Req 3.2): campos de texto para nombre y apellidos, y un botón
//     basado en `image_picker` para elegir una nueva foto; un botón de guardar
//     invoca al `ProfileNotifier`.
//
// Los estados de carga y error del provider se reflejan con un indicador de
// progreso y mensajes en español; nunca se muestran trazas técnicas.

import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/notifications/push_notifications.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/screens/screens.dart';
import '../../domain/entities/profile.dart';
import '../providers/profile_providers.dart';

/// Pantalla que muestra y permite editar el perfil del Usuario autenticado.
class ProfileScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla de perfil.
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _imagePicker = ImagePicker();

  /// Foto recién seleccionada pendiente de guardar; `null` si no se cambió.
  XFile? _fotoSeleccionada;

  /// Indica si los controladores ya se inicializaron con el perfil cargado,
  /// para no sobrescribir lo que el Usuario esté escribiendo en recargas.
  bool _camposInicializados = false;

  /// Indica si hay un borrado de cuenta en curso.
  bool _eliminandoCuenta = false;

  /// Pide confirmación y elimina de forma permanente la cuenta del Usuario.
  ///
  /// Si sale bien, la sesión se cierra y la guarda de enrutado vuelve al
  /// inicio de sesión, así que el aviso se muestra en el overlay raíz, que
  /// sobrevive al cambio de pantalla.
  Future<void> _eliminarCuenta(Profile profile) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ConfirmarEliminarCuentaDialog(saldoClases: profile.saldoClases),
    );
    if (confirmado != true || !mounted) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    setState(() => _eliminandoCuenta = true);
    try {
      await ref.read(profileNotifierProvider.notifier).eliminarMiCuenta();
      if (mounted) ref.invalidate(authNotifierProvider);
      AppNotifications.exitoEnOverlay(
        overlay,
        'Tu cuenta y tus datos se han eliminado.',
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _eliminandoCuenta = false);
      AppNotifications.error(context, _mensajeDeError(error));
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidosController.dispose();
    super.dispose();
  }

  /// Rellena los campos del formulario con los valores del perfil una sola vez.
  void _inicializarCampos(Profile profile) {
    if (_camposInicializados) return;
    _nombreController.text = profile.nombre;
    _apellidosController.text = profile.apellidos;
    _camposInicializados = true;
  }

  /// Abre la galería para elegir una nueva foto de perfil (Req 3.2 / 1.7).
  Future<void> _seleccionarFoto() async {
    try {
      final foto = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (foto != null) {
        setState(() => _fotoSeleccionada = foto);
      }
    } on Object {
      if (!mounted) return;
      AppNotifications.error(context, 'No se pudo seleccionar la imagen');
    }
  }

  /// Valida el formulario y envía los cambios al `ProfileNotifier` (Req 3.2).
  Future<void> _guardar() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    await ref
        .read(profileNotifierProvider.notifier)
        .updateProfile(
          nombre: _nombreController.text.trim(),
          apellidos: _apellidosController.text.trim(),
          foto: _fotoSeleccionada,
        );

    if (!mounted) return;

    final estado = ref.read(profileNotifierProvider);
    estado.when(
      data: (_) {
        setState(() => _fotoSeleccionada = null);
        AppNotifications.exito(context, 'Perfil actualizado correctamente');
      },
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

  /// Cierra la sesión del Usuario (Req 2.4).
  ///
  /// La guarda de enrutado reacciona al cambio de sesión de Supabase para
  /// volver a la zona pública; aquí solo se delega en el `AuthNotifier`.
  Future<void> _cerrarSesion() async {
    await ref.read(authNotifierProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final estadoPerfil = ref.watch(profileNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          IconButton(
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: estadoPerfil.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorPerfil(
          mensaje: _mensajeDeError(error),
          onReintentar: () =>
              ref.read(profileNotifierProvider.notifier).refresh(),
        ),
        data: (profile) {
          _inicializarCampos(profile);
          // `isLoading` es true durante una actualización en curso (Req 3.2).
          final guardando = estadoPerfil.isLoading;
          return _FormularioPerfil(
            formKey: _formKey,
            profile: profile,
            nombreController: _nombreController,
            apellidosController: _apellidosController,
            fotoSeleccionada: _fotoSeleccionada,
            guardando: guardando || _eliminandoCuenta,
            onSeleccionarFoto: _seleccionarFoto,
            onGuardar: _guardar,
            eliminandoCuenta: _eliminandoCuenta,
            onEliminarCuenta: () => _eliminarCuenta(profile),
          );
        },
      ),
    );
  }
}

/// Vista de error con opción de reintentar la carga del perfil.
class _ErrorPerfil extends StatelessWidget {
  const _ErrorPerfil({required this.mensaje, required this.onReintentar});

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

/// Formulario de edición del perfil con la foto, los campos editables y el
/// saldo en solo lectura.
class _FormularioPerfil extends StatelessWidget {
  const _FormularioPerfil({
    required this.formKey,
    required this.profile,
    required this.nombreController,
    required this.apellidosController,
    required this.fotoSeleccionada,
    required this.guardando,
    required this.onSeleccionarFoto,
    required this.onGuardar,
    required this.eliminandoCuenta,
    required this.onEliminarCuenta,
  });

  final GlobalKey<FormState> formKey;
  final Profile profile;
  final TextEditingController nombreController;
  final TextEditingController apellidosController;
  final XFile? fotoSeleccionada;
  final bool guardando;
  final VoidCallback onSeleccionarFoto;
  final Future<void> Function() onGuardar;

  /// Indica si hay un borrado de cuenta en curso.
  final bool eliminandoCuenta;

  /// Inicia el borrado de la cuenta (con confirmación).
  final VoidCallback onEliminarCuenta;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _AvatarPerfil(
                fotoUrl: profile.fotoUrl,
                fotoSeleccionada: fotoSeleccionada,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: guardando ? null : onSeleccionarFoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Cambiar foto'),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: nombreController,
              enabled: !guardando,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (valor) => (valor == null || valor.trim().isEmpty)
                  ? 'El nombre es obligatorio'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: apellidosController,
              enabled: !guardando,
              decoration: const InputDecoration(
                labelText: 'Apellidos',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              validator: (valor) => (valor == null || valor.trim().isEmpty)
                  ? 'Los apellidos son obligatorios'
                  : null,
            ),
            const SizedBox(height: 16),
            // Correo electrónico: solo lectura (espejo de la cuenta de Auth).
            _CampoSoloLectura(
              etiqueta: 'Correo electrónico',
              valor: profile.email,
              icono: Icons.email_outlined,
            ),
            const SizedBox(height: 16),
            // Saldo de clases: SOLO LECTURA (Req 3.1, 3.3). El Usuario estándar
            // no puede modificar su saldo desde esta pantalla.
            _CampoSoloLectura(
              etiqueta: 'Saldo de clases',
              valor: '${profile.saldoClases}',
              icono: Icons.confirmation_number_outlined,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: guardando ? null : () => onGuardar(),
              child: guardando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar cambios'),
            ),
            const SizedBox(height: 12),
            // Acceso al cambio de contraseña para el Usuario autenticado que
            // conoce su contraseña actual (distinto del flujo de recuperación
            // por correo, que es para quien la ha olvidado).
            OutlinedButton.icon(
              onPressed: guardando
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    ),
              icon: const Icon(Icons.lock_reset_outlined),
              label: const Text('Cambiar contraseña'),
            ),
            const SizedBox(height: 16),
            const _EstadoNotificaciones(),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => PrivacidadScreen.abrir(context),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Privacidad y protección de datos'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            // Eliminación de la cuenta (exigida por Google Play). Al final de
            // la pantalla y con confirmación explícita para evitar accidentes.
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: guardando ? null : onEliminarCuenta,
              icon: eliminandoCuenta
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever_outlined),
              label: Text(
                eliminandoCuenta ? 'Eliminando cuenta…' : 'Eliminar mi cuenta',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo de confirmación del borrado de cuenta.
///
/// Explica qué se borra y exige escribir "ELIMINAR" para activar el botón,
/// porque la acción es irreversible. Devuelve `true` si el Usuario confirma.
class _ConfirmarEliminarCuentaDialog extends StatefulWidget {
  const _ConfirmarEliminarCuentaDialog({required this.saldoClases});

  /// Clases que le quedan en el bono, para que sepa lo que pierde.
  final int saldoClases;

  @override
  State<_ConfirmarEliminarCuentaDialog> createState() =>
      _ConfirmarEliminarCuentaDialogState();
}

class _ConfirmarEliminarCuentaDialogState
    extends State<_ConfirmarEliminarCuentaDialog> {
  static const String _palabraClave = 'ELIMINAR';

  final _controller = TextEditingController();

  bool get _confirmado =>
      _controller.text.trim().toUpperCase() == _palabraClave;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bono = switch (widget.saldoClases) {
      0 => '• Tu bono.',
      1 => '• Tu bono, con la clase que te queda.',
      final n => '• Tu bono, con las $n clases que te quedan.',
    };

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: const Text('Eliminar mi cuenta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se borrarán para siempre:'),
            const SizedBox(height: 8),
            Text(
              '• Tu cuenta y tus datos personales.\n'
              '• Tu foto de perfil.\n'
              '$bono\n'
              '• Tus reservas y tus puestos en listas de espera. Las plazas que '
              'tengas en clases futuras pasarán a la siguiente persona de la '
              'lista.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Esta acción no se puede deshacer.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Escribe $_palabraClave para confirmar',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _confirmado ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Eliminar cuenta'),
        ),
      ],
    );
  }
}

/// Avatar circular que muestra la foto seleccionada pendiente de guardar, en su
/// defecto la foto actual del perfil, o un icono genérico.
class _AvatarPerfil extends StatelessWidget {
  const _AvatarPerfil({required this.fotoUrl, required this.fotoSeleccionada});

  final String? fotoUrl;
  final XFile? fotoSeleccionada;

  @override
  Widget build(BuildContext context) {
    const double radio = 56;
    ImageProvider? imagen;

    if (fotoSeleccionada != null && !kIsWeb) {
      imagen = FileImage(File(fotoSeleccionada!.path));
    } else if (fotoSeleccionada != null) {
      imagen = NetworkImage(fotoSeleccionada!.path);
    } else if (fotoUrl != null && fotoUrl!.isNotEmpty) {
      imagen = NetworkImage(fotoUrl!);
    }

    return CircleAvatar(
      radius: radio,
      backgroundImage: imagen,
      child: imagen == null ? const Icon(Icons.person, size: radio) : null,
    );
  }
}

/// Estado de las notificaciones push en este móvil, con botón para activarlas.
///
/// Sirve al Usuario para saber si recibirá el aviso de "ya tienes plaza" y,
/// si no, por qué. El detalle técnico se puede desplegar para soporte.
class _EstadoNotificaciones extends StatefulWidget {
  const _EstadoNotificaciones();

  @override
  State<_EstadoNotificaciones> createState() => _EstadoNotificacionesState();
}

class _EstadoNotificacionesState extends State<_EstadoNotificaciones> {
  late Future<DiagnosticoPush> _diagnostico = PushNotifications.diagnostico();
  bool _trabajando = false;

  Future<void> _activar() async {
    setState(() => _trabajando = true);
    await PushNotifications.pedirPermiso();
    await PushNotifications.registrarDispositivo();
    if (!mounted) return;
    setState(() {
      _trabajando = false;
      _diagnostico = PushNotifications.diagnostico();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DiagnosticoPush>(
      future: _diagnostico,
      builder: (context, snapshot) {
        final diag = snapshot.data;
        if (diag == null) return const SizedBox.shrink();

        final (
          IconData icono,
          String texto,
          bool activable,
        ) = switch (diag.estado) {
          EstadoPush.activo => (
            Icons.notifications_active_outlined,
            'Activadas: te avisaremos si consigues plaza desde la lista de '
                'espera.',
            false,
          ),
          EstadoPush.sinPermiso => (
            Icons.notifications_off_outlined,
            'Sin permiso. Actívalas para saber cuándo consigues plaza.',
            true,
          ),
          EstadoPush.pendienteRegistro => (
            Icons.sync_problem_outlined,
            'Permiso concedido, pero el móvil aún no se ha registrado.',
            true,
          ),
          EstadoPush.sinConfiguracion => (
            Icons.error_outline,
            'No disponibles en esta versión de la app.',
            false,
          ),
          EstadoPush.noSoportado => (
            Icons.notifications_off_outlined,
            'No disponibles en este dispositivo.',
            false,
          ),
        };

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icono),
                    const SizedBox(width: 12),
                    Text(
                      'Notificaciones',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(texto),
                if (activable)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _trabajando ? null : _activar,
                      child: Text(
                        diag.estado == EstadoPush.sinPermiso
                            ? 'Activar'
                            : 'Reintentar',
                      ),
                    ),
                  ),
                if (diag.detalle != null)
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'Detalle técnico',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      children: [
                        SelectableText(
                          diag.detalle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Campo de visualización en solo lectura con etiqueta e icono.
class _CampoSoloLectura extends StatelessWidget {
  const _CampoSoloLectura({
    required this.etiqueta,
    required this.valor,
    required this.icono,
  });

  final String etiqueta;
  final String valor;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: etiqueta,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icono),
        enabled: false,
      ),
      child: Text(valor),
    );
  }
}
