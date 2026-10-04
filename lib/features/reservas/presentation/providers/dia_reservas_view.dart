// Modelos de vista agregados para la pantalla del calendario/reservas.
//
// `DiaReservasView` reúne, para un día concreto, el plan de entrenamiento
// (opcional) y la lista de franjas horarias (Clases) con su ocupación y el
// estado de la reserva del Usuario de la sesión. `FranjaReserva` describe cada
// franja individual. Son modelos inmutables de la capa de presentación: no
// dependen del SDK de Supabase (Req 8.1, 8.3, 8.5).

import '../../domain/entities/clase.dart';
import '../../domain/entities/entrenamiento_dia.dart';
import '../../domain/entities/reserva.dart';

/// Vista agregada del día seleccionado en el calendario.
class DiaReservasView {
  const DiaReservasView({
    required this.fecha,
    required this.plan,
    required this.franjas,
  });

  /// Día (fecha local a medianoche) al que corresponde esta vista.
  final DateTime fecha;

  /// Plan de entrenamiento del día; `null` si no hay plan asignado.
  final EntrenamientoDia? plan;

  /// Franjas horarias (Clases) del día, ordenadas por horario ascendente.
  final List<FranjaReserva> franjas;

  /// Indica si el día tiene un plan de entrenamiento con actividades.
  bool get tienePlan => plan != null && plan!.actividades.isNotEmpty;
}

/// Franja horaria (Clase) con su ocupación y el estado de la reserva propia.
class FranjaReserva {
  const FranjaReserva({
    required this.clase,
    required this.confirmadas,
    required this.espera,
    this.miReserva,
  });

  /// Clase (franja horaria) a la que corresponde esta entrada.
  final Clase clase;

  /// Número de reservas confirmadas (plazas ocupadas) de la Clase.
  final int confirmadas;

  /// Número de entradas en lista de espera de la Clase.
  final int espera;

  /// Reserva del Usuario de la sesión en esta Clase; `null` si no tiene.
  final Reserva? miReserva;

  /// Indica si el aforo está completo (no quedan plazas confirmadas libres).
  bool get aforoCompleto => confirmadas >= clase.aforo;

  /// Indica si el Usuario tiene una reserva confirmada en esta franja.
  bool get tengoConfirmada => miReserva?.esConfirmada ?? false;

  /// Indica si el Usuario figura en la lista de espera de esta franja.
  bool get tengoEspera => miReserva?.enEspera ?? false;

  /// Indica si el Usuario no tiene ninguna reserva en esta franja.
  bool get sinReserva => miReserva == null;
}
