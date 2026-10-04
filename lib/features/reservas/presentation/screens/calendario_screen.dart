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
// gestión reflejan estados de carga, muestran notificaciones en español
// (verde para éxito, rojo para error) derivadas de `Failure.mensaje` y
// refrescan la vista tras completarse con éxito.
//
// Los estados de carga y error se reflejan con un indicador de progreso y
// notificaciones flotantes arriba a la derecha derivadas de `Failure.mensaje`;
// nunca se muestran trazas técnicas. Al reservar/cancelar con éxito se muestra
// una notificación verde y se refresca la vista.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/config/constants.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/gym_timezone.dart';
import '../../../../shared/widgets/widgets.dart';
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

  /// Reserva una plaza en la franja [claseId] y notifica el desenlace.
  Future<void> _reservar(String claseId) async {
    try {
      final resultado = await ref
          .read(diaReservasProvider.notifier)
          .reservar(claseId);
      if (!mounted) return;
      if (resultado.esConfirmada) {
        _mostrarExito('Reserva confirmada');
      } else {
        _mostrarExito(
          'Aforo completo: estás en lista de espera (posición '
          '${resultado.posicion})',
        );
      }
    } on Failure catch (failure) {
      _mostrarError(failure.mensaje);
    } on Object {
      _mostrarError('Ha ocurrido un error. Inténtalo de nuevo.');
    }
  }

  /// Cancela la reserva del Usuario en la franja [claseId] y lo notifica.
  Future<void> _cancelar(String claseId) async {
    try {
      await ref.read(diaReservasProvider.notifier).cancelar(claseId);
      _mostrarExito('Reserva cancelada');
    } on Failure catch (failure) {
      _mostrarError(failure.mensaje);
    } on Object {
      _mostrarError('Ha ocurrido un error. Inténtalo de nuevo.');
    }
  }

  // --- Gestión del superadministrador (Req 8.1, 8.2) --------------------------

  /// Combina la fecha del día seleccionado con una hora [hora] interpretada
  /// como hora del gimnasio (Europe/Madrid) y devuelve el instante en UTC.
  ///
  /// Así la hora que elige el superadministrador es siempre la hora española
  /// real; la conversión a UTC (que es lo que almacena el backend) la resuelve
  /// la zona horaria del gimnasio con el cambio verano/invierno automático.
  DateTime _combinarFechaHora(TimeOfDay hora) {
    final dia = ref.read(diaSeleccionadoProvider);
    return horaGimnasioAUtc(
      dia.year,
      dia.month,
      dia.day,
      hora.hour,
      hora.minute,
    );
  }

  /// Abre el diálogo de rango para generar una o varias franjas de una hora y
  /// las crea (Req 8.1).
  ///
  /// Un rango de 10:00 a 12:00 crea dos franjas (10–11 y 11–12), cada una con
  /// el monitor indicado. Las franjas se crean de forma independiente: si
  /// alguna falla (p. ej. ya existe), el resto se crean igualmente y se informa
  /// del resumen.
  Future<void> _anadirFranja() async {
    final datos = await showDialog<_DatosFranja>(
      context: context,
      builder: (_) => const _RangoFranjasDialog(),
    );
    if (datos == null || !mounted) return;

    final notifier = ref.read(diaReservasProvider.notifier);
    var creadas = 0;
    var omitidas = 0;
    for (final franja in datos.franjas) {
      try {
        await notifier.crearFranja(
          horario: _combinarFechaHora(franja.hora),
          aforo: datos.aforo,
          monitor: franja.monitor,
        );
        creadas++;
      } on Failure {
        omitidas++;
      } on Object {
        omitidas++;
      }
    }
    if (!mounted) return;
    if (omitidas == 0) {
      _mostrarExito(
        creadas == 1 ? 'Franja creada' : '$creadas franjas creadas',
      );
    } else {
      _mostrarError('Franjas creadas: $creadas · omitidas: $omitidas');
    }
  }

  /// Abre el diálogo de edición de una franja ya existente y la actualiza
  /// (Req 8.1). Los campos se prellenan con los valores actuales de la Clase.
  Future<void> _editarFranja(Clase clase) async {
    final datos = await showDialog<_DatosEdicionFranja>(
      context: context,
      builder: (_) => _EditarFranjaDialog(claseInicial: clase),
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
      _mostrarExito('Franja actualizada');
    } on Failure catch (failure) {
      _mostrarError(failure.mensaje);
    } on Object {
      _mostrarError('Ha ocurrido un error. Inténtalo de nuevo.');
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
      _mostrarExito('Franja eliminada');
    } on Failure catch (failure) {
      _mostrarError(failure.mensaje);
    } on Object {
      _mostrarError('Ha ocurrido un error. Inténtalo de nuevo.');
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
      _mostrarExito('Plan del día guardado');
    } on Failure catch (failure) {
      _mostrarError(failure.mensaje);
    } on Object {
      _mostrarError('Ha ocurrido un error. Inténtalo de nuevo.');
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
/// `FloatingActionButton` para no saturar la pantalla: "Añadir franjas" (por
/// rango) y "Editar plan del día". Solo se renderiza cuando el Usuario actual
/// es superadministrador.
class _MenuGestionAdmin extends StatelessWidget {
  const _MenuGestionAdmin({
    required this.onAnadirFranja,
    required this.onEditarPlan,
  });

  final Future<void> Function() onAnadirFranja;
  final Future<void> Function() onEditarPlan;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Gestionar día',
      onSelected: (opcion) {
        switch (opcion) {
          case 'anadir':
            onAnadirFranja();
          case 'plan':
            onEditarPlan();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'anadir',
          child: ListTile(
            leading: Icon(Icons.add),
            title: Text('Añadir franjas'),
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

/// Una franja concreta a crear: hora de inicio (en punto) y su monitor.
class _FranjaGenerada {
  const _FranjaGenerada({required this.hora, required this.monitor});

  /// Hora de inicio de la franja (minutos a cero).
  final TimeOfDay hora;

  /// Monitor asignado a esta franja concreta.
  final String monitor;
}

/// Datos recogidos por [_RangoFranjasDialog] al crear franjas por rango (Req 8.1).
///
/// Un rango de 10:00 a 12:00 produce dos franjas (10–11 y 11–12), cada una con
/// su propio monitor y compartiendo el mismo [aforo].
class _DatosFranja {
  const _DatosFranja({required this.aforo, required this.franjas});

  /// Aforo común a todas las franjas del rango; invariante 1..10.
  final int aforo;

  /// Franjas de una hora generadas a partir del rango, con su monitor.
  final List<_FranjaGenerada> franjas;
}

/// Datos recogidos al editar una franja existente (hora, aforo y monitor).
class _DatosEdicionFranja {
  const _DatosEdicionFranja({
    required this.hora,
    required this.aforo,
    required this.monitor,
  });

  final TimeOfDay hora;
  final int aforo;
  final String monitor;
}

/// Diálogo para generar franjas de una hora a partir de un RANGO (Req 8.1).
///
/// El superadministrador elige la hora de inicio y la de fin del rango y el
/// aforo común; el diálogo calcula las franjas de una hora resultantes (p. ej.
/// 10:00–12:00 → 10–11 y 11–12) y muestra un campo de monitor por cada franja,
/// de modo que el monitor pueda variar entre franjas. Al confirmar devuelve un
/// [_DatosFranja] con el aforo y la lista de franjas con su monitor.
class _RangoFranjasDialog extends StatefulWidget {
  const _RangoFranjasDialog();

  @override
  State<_RangoFranjasDialog> createState() => _RangoFranjasDialogState();
}

class _RangoFranjasDialogState extends State<_RangoFranjasDialog> {
  final _formKey = GlobalKey<FormState>();
  final _aforoController = TextEditingController();

  /// Hora de inicio y fin del rango (en punto). El rango [inicio, fin) genera
  /// una franja de una hora por cada hora entera contenida.
  int _horaInicio = 10;
  int _horaFin = 12;

  /// Controladores del monitor de cada franja generada, indexados por hora de
  /// inicio de la franja. Se conservan entre recálculos para no perder lo
  /// escrito al ajustar el rango.
  final Map<int, TextEditingController> _monitores =
      <int, TextEditingController>{};

  @override
  void dispose() {
    _aforoController.dispose();
    for (final c in _monitores.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Horas de inicio de las franjas del rango [_horaInicio, _horaFin).
  List<int> get _horasFranjas => [
    for (var h = _horaInicio; h < _horaFin; h += kDuracionFranjaHoras) h,
  ];

  /// Devuelve (creando si hace falta) el controlador de monitor de la franja
  /// que empieza a la hora [hora].
  TextEditingController _controladorMonitor(int hora) {
    return _monitores.putIfAbsent(hora, TextEditingController.new);
  }

  /// Etiqueta "HH:00 - (HH+1):00" de una franja de una hora.
  String _etiquetaFranja(int hora) {
    final inicio = hora.toString().padLeft(2, '0');
    final fin = (hora + 1).toString().padLeft(2, '0');
    return '$inicio:00 - $fin:00';
  }

  /// Valida el formulario y devuelve el aforo y las franjas con su monitor.
  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    if (_horaFin <= _horaInicio) return;

    final franjas = [
      for (final hora in _horasFranjas)
        _FranjaGenerada(
          hora: TimeOfDay(hour: hora, minute: 0),
          monitor: _controladorMonitor(hora).text.trim(),
        ),
    ];

    Navigator.of(context).pop(
      _DatosFranja(
        aforo: int.parse(_aforoController.text.trim()),
        franjas: franjas,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rangoValido = _horaFin > _horaInicio;

    return AlertDialog(
      title: const Text('Generar franjas por rango'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _horaInicio,
                      decoration: const InputDecoration(
                        labelText: 'Desde',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var h = 0; h <= 23; h++)
                          DropdownMenuItem<int>(
                            value: h,
                            child: Text('${h.toString().padLeft(2, '0')}:00'),
                          ),
                      ],
                      onChanged: (valor) {
                        if (valor != null) {
                          setState(() => _horaInicio = valor);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _horaFin,
                      decoration: const InputDecoration(
                        labelText: 'Hasta',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var h = 1; h <= 24; h++)
                          DropdownMenuItem<int>(
                            value: h,
                            child: Text('${h.toString().padLeft(2, '0')}:00'),
                          ),
                      ],
                      onChanged: (valor) {
                        if (valor != null) {
                          setState(() => _horaFin = valor);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _aforoController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Aforo (1-10) para todas las franjas',
                  border: OutlineInputBorder(),
                ),
                validator: (valor) {
                  final numero = int.tryParse(valor?.trim() ?? '');
                  if (numero == null) return 'Introduce un número';
                  if (numero < 1 || numero > 10) {
                    return 'El aforo debe estar entre 1 y 10';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (!rangoValido)
                const Text(
                  'La hora de fin debe ser posterior a la de inicio.',
                  style: TextStyle(color: Colors.red),
                )
              else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Monitor por franja (${_horasFranjas.length}):',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                for (final hora in _horasFranjas) ...[
                  TextFormField(
                    controller: _controladorMonitor(hora),
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Monitor ${_etiquetaFranja(hora)}',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: (valor) => (valor?.trim() ?? '').isEmpty
                        ? 'Indica el monitor'
                        : null,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: rangoValido ? _guardar : null,
          child: const Text('Generar'),
        ),
      ],
    );
  }
}

/// Diálogo de edición de una franja existente: hora (en punto), aforo y monitor.
class _EditarFranjaDialog extends StatefulWidget {
  const _EditarFranjaDialog({required this.claseInicial});

  final Clase claseInicial;

  @override
  State<_EditarFranjaDialog> createState() => _EditarFranjaDialogState();
}

class _EditarFranjaDialogState extends State<_EditarFranjaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _aforoController;
  late final TextEditingController _monitorController;
  late int _hora;

  @override
  void initState() {
    super.initState();
    final clase = widget.claseInicial;
    _hora = clase.horario.hour;
    _aforoController = TextEditingController(text: clase.aforo.toString());
    _monitorController = TextEditingController(text: clase.monitor);
  }

  @override
  void dispose() {
    _aforoController.dispose();
    _monitorController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _DatosEdicionFranja(
        hora: TimeOfDay(hour: _hora, minute: 0),
        aforo: int.parse(_aforoController.text.trim()),
        monitor: _monitorController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar franja'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _hora,
              decoration: const InputDecoration(
                labelText: 'Hora de inicio',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.access_time),
              ),
              items: [
                for (var h = 0; h <= 23; h++)
                  DropdownMenuItem<int>(
                    value: h,
                    child: Text('${h.toString().padLeft(2, '0')}:00'),
                  ),
              ],
              onChanged: (valor) {
                if (valor != null) setState(() => _hora = valor);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _aforoController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Aforo (1-10)',
                border: OutlineInputBorder(),
              ),
              validator: (valor) {
                final numero = int.tryParse(valor?.trim() ?? '');
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
              validator: (valor) =>
                  (valor?.trim() ?? '').isEmpty ? 'Indica el monitor' : null,
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
