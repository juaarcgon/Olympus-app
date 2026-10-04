// Pantalla de calendario y reservas (Servicio_Reservas).
//
// Permite al Usuario navegar por el calendario, elegir un día y:
//
//   - Ver el PLAN DE ENTRENAMIENTO del día (lista ordenada de actividades) en
//     una tarjeta de cabecera; si no hay plan, muestra "Sin entrenamiento
//     asignado" (Req 8.1).
//   - Ver las FRANJAS horarias (Clases) de ese día, cada una con su hora
//     (HH:mm), monitor, aforo "confirmadas/aforo", el estado de la reserva del
//     Usuario (confirmada / en espera posición N / sin reserva) y un botón
//     Reservar o Cancelar según corresponda (Req 8.3, 8.5, 8.7).
//   - Si el Usuario es superadministrador, cada franja es expandible y muestra
//     la lista nominal de los apuntados (nombre apellidos + estado). El Usuario
//     normal solo ve el número de ocupación, nunca los nombres (Req 8.2).
//
// Además, SOLO el superadministrador dispone de controles de GESTIÓN (Req 8.1,
// 8.2): un botón flotante para "Añadir franja", "Generar franjas 17–20h" y
// "Editar plan del día", y en cada franja acciones de editar/eliminar. El
// Usuario normal nunca ve ninguno de estos controles. Todas las operaciones de
// gestión reflejan estados de carga, muestran `SnackBar` en español derivados
// de `Failure.mensaje` y refrescan la vista tras completarse con éxito.
//
// Los estados de carga y error se reflejan con un indicador de progreso y
// mensajes en español derivados de `Failure.mensaje`; nunca se muestran trazas
// técnicas. Al reservar/cancelar con éxito se muestra un `SnackBar` y se
// refresca la vista.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/error/failures.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/entities/apuntado.dart';
import '../../domain/entities/clase.dart';
import '../../domain/entities/entrenamiento_dia.dart';
import '../providers/dia_reservas_view.dart';
import '../providers/reservas_providers.dart';

/// Pantalla del calendario con el plan del día y las franjas reservables.
class CalendarioScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla del calendario.
  const CalendarioScreen({super.key});

  @override
  ConsumerState<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends ConsumerState<CalendarioScreen> {
  /// Mes/día enfocado actualmente en el calendario (controla el mes visible).
  DateTime _focusedDay = DateTime.now();

  /// Primer y último día navegables del calendario (ventana de ±1 año).
  late final DateTime _firstDay;
  late final DateTime _lastDay;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _firstDay = DateTime(hoy.year - 1, hoy.month, hoy.day);
    _lastDay = DateTime(hoy.year + 1, hoy.month, hoy.day);
  }

  /// Traduce un error a un mensaje legible en español.
  String _mensajeDeError(Object error) {
    if (error is Failure) return error.mensaje;
    return 'Ha ocurrido un error. Inténtalo de nuevo.';
  }

  /// Muestra un `SnackBar` con un mensaje en español.
  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Reserva una plaza en la franja [claseId] y notifica el desenlace.
  Future<void> _reservar(String claseId) async {
    try {
      final resultado = await ref
          .read(diaReservasProvider.notifier)
          .reservar(claseId);
      if (!mounted) return;
      if (resultado.esConfirmada) {
        _mostrarMensaje('Reserva confirmada');
      } else {
        _mostrarMensaje(
          'Aforo completo: estás en lista de espera (posición '
          '${resultado.posicion})',
        );
      }
    } on Failure catch (failure) {
      if (!mounted) return;
      _mostrarMensaje(failure.mensaje);
    } on Object {
      if (!mounted) return;
      _mostrarMensaje('Ha ocurrido un error. Inténtalo de nuevo.');
    }
  }

  /// Cancela la reserva del Usuario en la franja [claseId] y lo notifica.
  Future<void> _cancelar(String claseId) async {
    try {
      await ref.read(diaReservasProvider.notifier).cancelar(claseId);
      if (!mounted) return;
      _mostrarMensaje('Reserva cancelada');
    } on Failure catch (failure) {
      if (!mounted) return;
      _mostrarMensaje(failure.mensaje);
    } on Object {
      if (!mounted) return;
      _mostrarMensaje('Ha ocurrido un error. Inténtalo de nuevo.');
    }
  }

  // --- Gestión del superadministrador (Req 8.1, 8.2) --------------------------

  /// Combina la fecha del día seleccionado con una hora [hora] del día.
  DateTime _combinarFechaHora(TimeOfDay hora) {
    final dia = ref.read(diaSeleccionadoProvider);
    return DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute);
  }

  /// Abre el diálogo para añadir una nueva franja al día y la crea (Req 8.1).
  Future<void> _anadirFranja() async {
    final datos = await showDialog<_DatosFranja>(
      context: context,
      builder: (_) => const _FranjaDialog(),
    );
    if (datos == null || !mounted) return;
    try {
      await ref
          .read(diaReservasProvider.notifier)
          .crearFranja(
            horario: _combinarFechaHora(datos.hora),
            aforo: datos.aforo,
            monitor: datos.monitor,
          );
      if (!mounted) return;
      _mostrarMensaje('Franja creada');
    } on Failure catch (failure) {
      if (!mounted) return;
      _mostrarMensaje(failure.mensaje);
    } on Object {
      if (!mounted) return;
      _mostrarMensaje('Ha ocurrido un error. Inténtalo de nuevo.');
    }
  }

  /// Abre el diálogo de edición de una franja ya existente y la actualiza
  /// (Req 8.1). Los campos se prellenan con los valores actuales de la Clase.
  Future<void> _editarFranja(Clase clase) async {
    final datos = await showDialog<_DatosFranja>(
      context: context,
      builder: (_) => _FranjaDialog(claseInicial: clase),
    );
    if (datos == null || !mounted) return;
    try {
      await ref
          .read(diaReservasProvider.notifier)
          .editarFranja(
            clase.id,
            horario: _combinarFechaHora(datos.hora),
            aforo: datos.aforo,
            monitor: datos.monitor,
          );
      if (!mounted) return;
      _mostrarMensaje('Franja actualizada');
    } on Failure catch (failure) {
      if (!mounted) return;
      _mostrarMensaje(failure.mensaje);
    } on Object {
      if (!mounted) return;
      _mostrarMensaje('Ha ocurrido un error. Inténtalo de nuevo.');
    }
  }

  /// Pide confirmación y elimina la franja [clase] del día (Req 8.1).
  Future<void> _eliminarFranja(Clase clase) async {
    final h = clase.horario.hour.toString().padLeft(2, '0');
    final m = clase.horario.minute.toString().padLeft(2, '0');
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar franja'),
        content: Text(
          '¿Seguro que quieres eliminar la franja de las $h:$m? '
          'Esta acción no se puede deshacer.',
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
    if (confirmado != true || !mounted) return;
    try {
      await ref.read(diaReservasProvider.notifier).eliminarFranja(clase.id);
      if (!mounted) return;
      _mostrarMensaje('Franja eliminada');
    } on Failure catch (failure) {
      if (!mounted) return;
      _mostrarMensaje(failure.mensaje);
    } on Object {
      if (!mounted) return;
      _mostrarMensaje('Ha ocurrido un error. Inténtalo de nuevo.');
    }
  }

  /// Genera las 4 franjas estándar (17, 18, 19 y 20 h) del día con un aforo y
  /// monitor por defecto que el superadministrador indica una sola vez
  /// (Req 8.1).
  ///
  /// Es una acción de conveniencia claramente opcional: crea cada franja de
  /// forma independiente capturando los errores por franja, de modo que si
  /// alguna ya existe ([ReservaDuplicadaFailure]) u otra falla, el resto se
  /// crean igualmente y se informa del resumen.
  Future<void> _generarFranjasEstandar() async {
    final datos = await showDialog<_DatosFranja>(
      context: context,
      builder: (_) => const _FranjaDialog(
        titulo: 'Generar franjas 17–20h',
        ocultarHora: true,
      ),
    );
    if (datos == null || !mounted) return;

    final notifier = ref.read(diaReservasProvider.notifier);
    var creadas = 0;
    var omitidas = 0;
    for (final horaDelDia in const [17, 18, 19, 20]) {
      try {
        await notifier.crearFranja(
          horario: _combinarFechaHora(TimeOfDay(hour: horaDelDia, minute: 0)),
          aforo: datos.aforo,
          monitor: datos.monitor,
        );
        creadas++;
      } on Failure {
        // P. ej. una franja duplicada; se omite y se continúa con el resto.
        omitidas++;
      } on Object {
        omitidas++;
      }
    }
    if (!mounted) return;
    if (omitidas == 0) {
      _mostrarMensaje('Franjas 17–20h generadas');
    } else {
      _mostrarMensaje('Franjas creadas: $creadas · omitidas: $omitidas');
    }
  }

  /// Abre el diálogo de edición del plan del día y lo guarda (Req 8.1, 8.2).
  ///
  /// Prellena el editor con el plan actual (una actividad por línea) si existe.
  Future<void> _editarPlan(EntrenamientoDia? planActual) async {
    final actividades = await showDialog<List<String>>(
      context: context,
      builder: (_) => _PlanDialog(actividades: planActual?.actividades),
    );
    if (actividades == null || !mounted) return;
    try {
      await ref.read(diaReservasProvider.notifier).guardarPlan(actividades);
      if (!mounted) return;
      _mostrarMensaje('Plan del día guardado');
    } on Failure catch (failure) {
      if (!mounted) return;
      _mostrarMensaje(failure.mensaje);
    } on Object {
      if (!mounted) return;
      _mostrarMensaje('Ha ocurrido un error. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final diaSeleccionado = ref.watch(diaSeleccionadoProvider);
    final estadoDia = ref.watch(diaReservasProvider);
    // El superadministrador ve la lista nominal de apuntados (Req 8.2).
    final esSuperadmin = ref
        .watch(profileNotifierProvider)
        .maybeWhen(data: (p) => p.esSuperadmin, orElse: () => false);

    // El plan actual del día (si la vista ya está cargada) se usa para
    // prellenar el editor de plan desde el menú de gestión (Req 8.1).
    final planActual = estadoDia.asData?.value.plan;

    return Scaffold(
      appBar: AppBar(title: const Text('Calendario')),
      // Controles de GESTIÓN del superadministrador (Req 8.1, 8.2). El Usuario
      // normal no ve ningún botón de acción flotante.
      floatingActionButton: esSuperadmin
          ? _MenuGestionAdmin(
              onAnadirFranja: _anadirFranja,
              onGenerarFranjas: _generarFranjasEstandar,
              onEditarPlan: () => _editarPlan(planActual),
            )
          : null,
      body: Column(
        children: [
          _Calendario(
            firstDay: _firstDay,
            lastDay: _lastDay,
            focusedDay: _focusedDay,
            diaSeleccionado: diaSeleccionado,
            onDaySelected: (selectedDay, focusedDay) {
              setState(() => _focusedDay = focusedDay);
              ref
                  .read(diaSeleccionadoProvider.notifier)
                  .seleccionar(selectedDay);
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: estadoDia.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorDia(
                mensaje: _mensajeDeError(error),
                onReintentar: () =>
                    ref.read(diaReservasProvider.notifier).refrescar(),
              ),
              data: (vista) => _ContenidoDia(
                vista: vista,
                esSuperadmin: esSuperadmin,
                onReservar: _reservar,
                onCancelar: _cancelar,
                onEditarFranja: _editarFranja,
                onEliminarFranja: _eliminarFranja,
                onEditarPlan: _editarPlan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Calendario mensual para elegir el día (table_calendar).
class _Calendario extends StatelessWidget {
  const _Calendario({
    required this.firstDay,
    required this.lastDay,
    required this.focusedDay,
    required this.diaSeleccionado,
    required this.onDaySelected,
  });

  final DateTime firstDay;
  final DateTime lastDay;
  final DateTime focusedDay;
  final DateTime diaSeleccionado;
  final OnDaySelected onDaySelected;

  @override
  Widget build(BuildContext context) {
    return TableCalendar<void>(
      firstDay: firstDay,
      lastDay: lastDay,
      focusedDay: focusedDay,
      availableGestures: AvailableGestures.horizontalSwipe,
      headerStyle: const HeaderStyle(formatButtonVisible: false),
      selectedDayPredicate: (day) => isSameDay(day, diaSeleccionado),
      onDaySelected: onDaySelected,
    );
  }
}

/// Contenido del día: plan de entrenamiento y lista de franjas horarias.
class _ContenidoDia extends StatelessWidget {
  const _ContenidoDia({
    required this.vista,
    required this.esSuperadmin,
    required this.onReservar,
    required this.onCancelar,
    required this.onEditarFranja,
    required this.onEliminarFranja,
    required this.onEditarPlan,
  });

  final DiaReservasView vista;
  final bool esSuperadmin;
  final Future<void> Function(String claseId) onReservar;
  final Future<void> Function(String claseId) onCancelar;

  /// Abre la edición de la franja indicada (solo superadministrador, Req 8.1).
  final Future<void> Function(Clase clase) onEditarFranja;

  /// Elimina la franja indicada con confirmación (solo superadmin, Req 8.1).
  final Future<void> Function(Clase clase) onEliminarFranja;

  /// Abre la edición del plan del día (solo superadministrador, Req 8.1, 8.2).
  final Future<void> Function(EntrenamientoDia? plan) onEditarPlan;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PlanDelDia(
          plan: vista.plan,
          esSuperadmin: esSuperadmin,
          onEditarPlan: onEditarPlan,
        ),
        const SizedBox(height: 16),
        Text('Clases del día', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (vista.franjas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No hay clases programadas este día')),
          )
        else
          ...vista.franjas.map(
            (franja) => _FranjaCard(
              franja: franja,
              esSuperadmin: esSuperadmin,
              onReservar: onReservar,
              onCancelar: onCancelar,
              onEditarFranja: onEditarFranja,
              onEliminarFranja: onEliminarFranja,
            ),
          ),
      ],
    );
  }
}

/// Tarjeta de cabecera con el plan de entrenamiento del día (Req 8.1).
class _PlanDelDia extends StatelessWidget {
  const _PlanDelDia({
    required this.plan,
    required this.esSuperadmin,
    required this.onEditarPlan,
  });

  final EntrenamientoDia? plan;

  /// Si el Usuario actual es superadministrador (muestra el botón de edición).
  final bool esSuperadmin;

  /// Abre la edición del plan del día (solo superadministrador, Req 8.1, 8.2).
  final Future<void> Function(EntrenamientoDia? plan) onEditarPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actividades = plan?.actividades ?? const <String>[];
    final tienePlan = actividades.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center),
                const SizedBox(width: 8),
                Text(
                  'Entrenamiento del día',
                  style: theme.textTheme.titleMedium,
                ),
                // Edición del plan del día (solo superadministrador, Req 8.2).
                if (esSuperadmin) ...[
                  const Spacer(),
                  IconButton(
                    tooltip: 'Editar plan del día',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => onEditarPlan(plan),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (!tienePlan)
              const Text('Sin entrenamiento asignado')
            else
              ...List.generate(actividades.length, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. '),
                      Expanded(child: Text(actividades[i])),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de una franja horaria (Clase) con la acción de reserva/cancelación.
///
/// Para el superadministrador la tarjeta es expandible y muestra la lista
/// nominal de apuntados; para el Usuario normal solo muestra el número de
/// ocupación (Req 8.2).
class _FranjaCard extends ConsumerWidget {
  const _FranjaCard({
    required this.franja,
    required this.esSuperadmin,
    required this.onReservar,
    required this.onCancelar,
    required this.onEditarFranja,
    required this.onEliminarFranja,
  });

  final FranjaReserva franja;
  final bool esSuperadmin;
  final Future<void> Function(String claseId) onReservar;
  final Future<void> Function(String claseId) onCancelar;

  /// Abre la edición de esta franja (solo superadministrador, Req 8.1).
  final Future<void> Function(Clase clase) onEditarFranja;

  /// Elimina esta franja con confirmación (solo superadministrador, Req 8.1).
  final Future<void> Function(Clase clase) onEliminarFranja;

  /// Formatea la hora de la Clase como "HH:mm".
  String _hora(Clase clase) {
    final h = clase.horario.hour.toString().padLeft(2, '0');
    final m = clase.horario.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Texto del estado de la reserva del Usuario en esta franja.
  String _estadoReserva() {
    if (franja.tengoConfirmada) return 'Reserva confirmada';
    if (franja.tengoEspera) {
      return 'En lista de espera (posición ${franja.miReserva?.posicion})';
    }
    return 'Sin reserva';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final clase = franja.clase;
    final aforoTexto = '${franja.confirmadas}/${clase.aforo}';

    final cabecera = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(_hora(clase), style: theme.textTheme.titleLarge),
            const Spacer(),
            Chip(
              label: Text('Aforo $aforoTexto'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Monitor: ${clase.monitor}'),
        const SizedBox(height: 4),
        Text(_estadoReserva(), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        _AccionReserva(
          franja: franja,
          onReservar: onReservar,
          onCancelar: onCancelar,
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: esSuperadmin
            ? _FranjaExpandibleAdmin(
                clase: clase,
                cabecera: cabecera,
                onEditarFranja: onEditarFranja,
                onEliminarFranja: onEliminarFranja,
              )
            : cabecera,
      ),
    );
  }
}

/// Botón de Reservar/Cancelar según el estado de la reserva del Usuario.
class _AccionReserva extends StatelessWidget {
  const _AccionReserva({
    required this.franja,
    required this.onReservar,
    required this.onCancelar,
  });

  final FranjaReserva franja;
  final Future<void> Function(String claseId) onReservar;
  final Future<void> Function(String claseId) onCancelar;

  @override
  Widget build(BuildContext context) {
    final claseId = franja.clase.id;

    // Con reserva (confirmada o en espera): ofrecer Cancelar (Req 8.7, 8.11).
    if (!franja.sinReserva) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: () => onCancelar(claseId),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Cancelar'),
        ),
      );
    }

    // Sin reserva: Reservar. Si el aforo está completo, el botón sigue activo
    // porque la reserva pasa a lista de espera (Req 8.5); solo se deshabilita
    // mientras se recarga el estado.
    final enEspera = franja.aforoCompleto;
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: () => onReservar(claseId),
        icon: const Icon(Icons.event_available),
        label: Text(enEspera ? 'Apuntarme a la espera' : 'Reservar'),
      ),
    );
  }
}

/// Envoltura expandible para el superadministrador que carga, bajo demanda, la
/// lista nominal de apuntados de la Clase (Req 8.2).
class _FranjaExpandibleAdmin extends ConsumerWidget {
  const _FranjaExpandibleAdmin({
    required this.clase,
    required this.cabecera,
    required this.onEditarFranja,
    required this.onEliminarFranja,
  });

  final Clase clase;
  final Widget cabecera;

  /// Abre la edición de esta franja (Req 8.1).
  final Future<void> Function(Clase clase) onEditarFranja;

  /// Elimina esta franja con confirmación (Req 8.1).
  final Future<void> Function(Clase clase) onEliminarFranja;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      title: cabecera,
      children: [
        // Acciones de gestión de la franja (editar/eliminar), solo visibles
        // para el superadministrador (Req 8.1).
        Align(
          alignment: Alignment.centerLeft,
          child: OverflowBar(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => onEditarFranja(clase),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar franja'),
              ),
              TextButton.icon(
                onPressed: () => onEliminarFranja(clase),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar franja'),
              ),
            ],
          ),
        ),
        const Divider(),
        FutureBuilder<List<Apuntado>>(
          future: ref.read(reservasRepositoryProvider).getApuntados(clase.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No se pudo cargar la lista de apuntados'),
              );
            }
            final apuntados = snapshot.data ?? const <Apuntado>[];
            if (apuntados.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Nadie se ha apuntado todavía'),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: apuntados
                  .map((apuntado) {
                    final estado = apuntado.esConfirmado
                        ? 'confirmada'
                        : 'espera (posición ${apuntado.posicion})';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        apuntado.esConfirmado
                            ? Icons.check_circle_outline
                            : Icons.hourglass_empty,
                      ),
                      title: Text(apuntado.nombreCompleto),
                      subtitle: Text(estado),
                    );
                  })
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

/// Menú flotante de gestión del superadministrador (Req 8.1, 8.2).
///
/// Agrupa las acciones de gestión en un `PopupMenuButton` sobre un
/// `FloatingActionButton` para no saturar la pantalla: "Añadir franja",
/// "Generar franjas 17–20h" y "Editar plan del día". Solo se renderiza cuando
/// el Usuario actual es superadministrador.
class _MenuGestionAdmin extends StatelessWidget {
  const _MenuGestionAdmin({
    required this.onAnadirFranja,
    required this.onGenerarFranjas,
    required this.onEditarPlan,
  });

  final Future<void> Function() onAnadirFranja;
  final Future<void> Function() onGenerarFranjas;
  final Future<void> Function() onEditarPlan;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Gestionar día',
      onSelected: (opcion) {
        switch (opcion) {
          case 'anadir':
            onAnadirFranja();
          case 'generar':
            onGenerarFranjas();
          case 'plan':
            onEditarPlan();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'anadir',
          child: ListTile(
            leading: Icon(Icons.add),
            title: Text('Añadir franja'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'generar',
          child: ListTile(
            leading: Icon(Icons.schedule),
            title: Text('Generar franjas 17–20h'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'plan',
          child: ListTile(
            leading: Icon(Icons.fitness_center),
            title: Text('Editar plan del día'),
          ),
        ),
      ],
      child: const FloatingActionButton(
        onPressed: null,
        child: Icon(Icons.admin_panel_settings),
      ),
    );
  }
}

/// Datos recogidos por [_FranjaDialog] para crear/editar una franja (Req 8.1).
class _DatosFranja {
  const _DatosFranja({
    required this.hora,
    required this.aforo,
    required this.monitor,
  });

  /// Hora del día de la franja (la fecha la aporta el día seleccionado).
  final TimeOfDay hora;

  /// Aforo de la franja; invariante 1..10 validada en el formulario.
  final int aforo;

  /// Monitor asignado a la franja.
  final String monitor;
}

/// Diálogo de creación/edición de una franja horaria (Req 8.1).
///
/// Permite elegir la hora (selector de hora, con cualquier valor permitido),
/// el aforo (1..10, validado) y el monitor. Si se pasa [claseInicial] los
/// campos se prellenan con sus valores para la edición. Con [ocultarHora] se
/// oculta el selector de hora (lo usa la generación de franjas estándar, que
/// fija las horas 17–20).
class _FranjaDialog extends StatefulWidget {
  const _FranjaDialog({
    this.claseInicial,
    this.titulo,
    this.ocultarHora = false,
  });

  final Clase? claseInicial;
  final String? titulo;
  final bool ocultarHora;

  @override
  State<_FranjaDialog> createState() => _FranjaDialogState();
}

class _FranjaDialogState extends State<_FranjaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _aforoController;
  late final TextEditingController _monitorController;
  late TimeOfDay _hora;

  @override
  void initState() {
    super.initState();
    final clase = widget.claseInicial;
    _hora = clase != null
        ? TimeOfDay(hour: clase.horario.hour, minute: clase.horario.minute)
        : const TimeOfDay(hour: 17, minute: 0);
    _aforoController = TextEditingController(
      text: clase != null ? clase.aforo.toString() : '',
    );
    _monitorController = TextEditingController(text: clase?.monitor ?? '');
  }

  @override
  void dispose() {
    _aforoController.dispose();
    _monitorController.dispose();
    super.dispose();
  }

  /// Formatea la hora seleccionada como "HH:mm".
  String get _horaTexto {
    final h = _hora.hour.toString().padLeft(2, '0');
    final m = _hora.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Abre el selector de hora nativo y actualiza la hora elegida.
  Future<void> _elegirHora() async {
    final elegida = await showTimePicker(context: context, initialTime: _hora);
    if (elegida != null) setState(() => _hora = elegida);
  }

  /// Valida el formulario y devuelve los datos de la franja al cerrar.
  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _DatosFranja(
        hora: _hora,
        aforo: int.parse(_aforoController.text.trim()),
        monitor: _monitorController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo =
        widget.titulo ??
        (widget.claseInicial != null ? 'Editar franja' : 'Añadir franja');

    return AlertDialog(
      title: Text(titulo),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Selector de hora (se oculta al generar las franjas estándar).
            if (!widget.ocultarHora)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time),
                title: const Text('Hora'),
                subtitle: Text(_horaTexto),
                trailing: TextButton(
                  onPressed: _elegirHora,
                  child: const Text('Cambiar'),
                ),
              ),
            TextFormField(
              controller: _aforoController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Aforo (1-10)',
                border: OutlineInputBorder(),
              ),
              validator: (valor) {
                final texto = valor?.trim() ?? '';
                final numero = int.tryParse(texto);
                if (numero == null) return 'Introduce un número';
                if (numero < 1 || numero > 10) {
                  return 'El aforo debe estar entre 1 y 10';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _monitorController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Monitor',
                border: OutlineInputBorder(),
              ),
              validator: (valor) {
                if ((valor?.trim() ?? '').isEmpty) {
                  return 'Indica el monitor';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Diálogo de edición del plan de entrenamiento del día (Req 8.1, 8.2).
///
/// Edita la lista de actividades mediante un `TextField` multilínea con una
/// actividad por línea; al guardar se convierte en `List<String>` descartando
/// las líneas vacías. Se prellena con el plan actual si existe.
class _PlanDialog extends StatefulWidget {
  const _PlanDialog({this.actividades});

  final List<String>? actividades;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: (widget.actividades ?? const <String>[]).join('\n'),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Convierte el texto en una lista de actividades (una por línea, sin vacías)
  /// y la devuelve al cerrar el diálogo.
  void _guardar() {
    final actividades = _controller.text
        .split('\n')
        .map((linea) => linea.trim())
        .where((linea) => linea.isNotEmpty)
        .toList(growable: false);
    Navigator.of(context).pop(actividades);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar plan del día'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Una actividad por línea:'),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 8,
            minLines: 4,
            decoration: const InputDecoration(
              hintText: 'Calentamiento\nFuerza\nCardio',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Vista de error del día con opción de reintentar.
class _ErrorDia extends StatelessWidget {
  const _ErrorDia({required this.mensaje, required this.onReintentar});

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
