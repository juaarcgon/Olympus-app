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

  @override
  Widget build(BuildContext context) {
    final diaSeleccionado = ref.watch(diaSeleccionadoProvider);
    final estadoDia = ref.watch(diaReservasProvider);
    // El superadministrador ve la lista nominal de apuntados (Req 8.2).
    final esSuperadmin = ref
        .watch(profileNotifierProvider)
        .maybeWhen(data: (p) => p.esSuperadmin, orElse: () => false);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendario')),
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
  });

  final DiaReservasView vista;
  final bool esSuperadmin;
  final Future<void> Function(String claseId) onReservar;
  final Future<void> Function(String claseId) onCancelar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PlanDelDia(plan: vista.plan),
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
            ),
          ),
      ],
    );
  }
}

/// Tarjeta de cabecera con el plan de entrenamiento del día (Req 8.1).
class _PlanDelDia extends StatelessWidget {
  const _PlanDelDia({required this.plan});

  final EntrenamientoDia? plan;

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
  });

  final FranjaReserva franja;
  final bool esSuperadmin;
  final Future<void> Function(String claseId) onReservar;
  final Future<void> Function(String claseId) onCancelar;

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
            ? _FranjaExpandibleAdmin(claseId: clase.id, cabecera: cabecera)
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
  const _FranjaExpandibleAdmin({required this.claseId, required this.cabecera});

  final String claseId;
  final Widget cabecera;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      title: cabecera,
      children: [
        FutureBuilder<List<Apuntado>>(
          future: ref.read(reservasRepositoryProvider).getApuntados(claseId),
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
