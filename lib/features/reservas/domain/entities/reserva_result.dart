// Entidad de dominio ReservaResult para la app Olympus.
//
// Resultado devuelto por la operación de reserva (RPC `reservar_clase`).
// Indica si la solicitud terminó en una Reserva_Confirmada o en la
// Lista_De_Espera, la posición en espera (si aplica) y el saldo resultante.
// Modelo de dominio puro e inmutable.

import 'package:olympus/features/reservas/domain/entities/reserva.dart';

/// Desenlace de una solicitud de reserva.
enum ReservaOutcome {
  /// La solicitud creó una Reserva_Confirmada (había aforo libre) (Req 8.3).
  confirmada,

  /// La solicitud se añadió a la Lista_De_Espera (aforo completo) (Req 8.5).
  enEspera;

  /// Valor textual estable (útil para mapear desde la RPC).
  String get valor => name;

  /// Construye el desenlace a partir de su representación textual.
  ///
  /// Acepta tanto `confirmada`/`enEspera` como el `status` de la tabla
  /// `reservas` (`confirmada`/`espera`). Lanza [ArgumentError] si no coincide.
  static ReservaOutcome desdeValor(String valor) {
    switch (valor) {
      case 'confirmada':
        return ReservaOutcome.confirmada;
      case 'enEspera':
      case 'espera':
        return ReservaOutcome.enEspera;
      default:
        throw ArgumentError.value(
          valor,
          'valor',
          'Desenlace de reserva no válido',
        );
    }
  }
}

/// Resultado de la operación de reserva.
///
/// - [outcome]: si quedó confirmada o en lista de espera.
/// - [posicion]: posición FIFO en la lista de espera; `null` si quedó
///   confirmada (Req 8.5).
/// - [saldoResultante]: saldo de clases del Usuario tras la operación. Se
///   descuenta 1 al confirmar y no cambia al entrar en espera (Req 8.3, 8.5).
/// - [reserva]: la fila de reserva creada, si la operación la expone.
///
/// Inmutable; implementa igualdad estructural por valor.
class ReservaResult {
  const ReservaResult({
    required this.outcome,
    required this.saldoResultante,
    this.posicion,
    this.reserva,
  });

  /// Crea un resultado de reserva confirmada (aforo libre).
  const ReservaResult.confirmada({
    required int saldoResultante,
    Reserva? reserva,
  }) : this(
         outcome: ReservaOutcome.confirmada,
         saldoResultante: saldoResultante,
         posicion: null,
         reserva: reserva,
       );

  /// Crea un resultado de entrada en lista de espera (aforo completo).
  const ReservaResult.enEspera({
    required int posicion,
    required int saldoResultante,
    Reserva? reserva,
  }) : this(
         outcome: ReservaOutcome.enEspera,
         saldoResultante: saldoResultante,
         posicion: posicion,
         reserva: reserva,
       );

  /// Desenlace de la solicitud: confirmada o en espera.
  final ReservaOutcome outcome;

  /// Posición FIFO en la lista de espera; `null` si quedó confirmada.
  final int? posicion;

  /// Saldo de clases del Usuario tras la operación.
  final int saldoResultante;

  /// Fila de reserva creada, si la operación la expone; puede ser `null`.
  final Reserva? reserva;

  /// Indica si la reserva quedó confirmada.
  bool get esConfirmada => outcome == ReservaOutcome.confirmada;

  /// Indica si la solicitud quedó en lista de espera.
  bool get enEspera => outcome == ReservaOutcome.enEspera;

  /// Devuelve una copia del resultado con los campos indicados reemplazados.
  ReservaResult copyWith({
    ReservaOutcome? outcome,
    int? saldoResultante,
    Object? posicion = _sentinel,
    Object? reserva = _sentinel,
  }) {
    return ReservaResult(
      outcome: outcome ?? this.outcome,
      saldoResultante: saldoResultante ?? this.saldoResultante,
      posicion: identical(posicion, _sentinel)
          ? this.posicion
          : posicion as int?,
      reserva: identical(reserva, _sentinel)
          ? this.reserva
          : reserva as Reserva?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReservaResult &&
          runtimeType == other.runtimeType &&
          outcome == other.outcome &&
          posicion == other.posicion &&
          saldoResultante == other.saldoResultante &&
          reserva == other.reserva);

  @override
  int get hashCode => Object.hash(outcome, posicion, saldoResultante, reserva);

  @override
  String toString() =>
      'ReservaResult(outcome: ${outcome.valor}, posicion: $posicion, '
      'saldoResultante: $saldoResultante)';
}

/// Centinela interno para distinguir "no modificar" de "fijar a null" en
/// [ReservaResult.copyWith] para campos anulables.
const Object _sentinel = Object();
