// Entidad de dominio Apuntado para la app Olympus.
//
// Representa a un Usuario apuntado a una Clase (confirmado o en lista de espera)
// con su nombre y apellidos, destinado a la vista del superadministrador. La
// lista nominal de apuntados solo es visible para el superadministrador: la RLS
// de `reservas` limita la lectura de las filas ajenas al resto de Usuarios
// (Req 8.2). Modelo de dominio puro e inmutable.

import 'reserva.dart';

/// Usuario apuntado a una Clase (confirmado o en espera), con su nombre.
class Apuntado {
  const Apuntado({
    required this.userId,
    required this.nombre,
    required this.apellidos,
    required this.status,
    this.posicion,
  });

  /// Id del Usuario apuntado.
  final String userId;

  /// Nombre del Usuario apuntado.
  final String nombre;

  /// Apellidos del Usuario apuntado.
  final String apellidos;

  /// Estado del apuntado: confirmada o en espera.
  final ReservaStatus status;

  /// Posición FIFO en la lista de espera; `null` si está confirmado.
  final int? posicion;

  /// Nombre completo "nombre apellidos" (sin espacios sobrantes).
  String get nombreCompleto => '$nombre $apellidos'.trim();

  /// Indica si el apuntado ocupa una plaza confirmada.
  bool get esConfirmado => status == ReservaStatus.confirmada;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Apuntado &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          nombre == other.nombre &&
          apellidos == other.apellidos &&
          status == other.status &&
          posicion == other.posicion);

  @override
  int get hashCode => Object.hash(userId, nombre, apellidos, status, posicion);

  @override
  String toString() =>
      'Apuntado(userId: $userId, nombre: $nombreCompleto, '
      'status: ${status.valor}, posicion: $posicion)';
}
