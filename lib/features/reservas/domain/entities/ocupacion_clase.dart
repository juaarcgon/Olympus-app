// Entidad de dominio OcupacionClase para la app Olympus.
//
// Resumen de ocupación de una Clase: número de reservas confirmadas y en lista
// de espera. Procede de la RPC de solo lectura `ocupacion_clase` (migración
// 0008), que devuelve estos conteos a cualquier Usuario autenticado sin exponer
// la identidad de los apuntados (Req 8.1). Modelo de dominio puro e inmutable.

/// Ocupación agregada de una Clase (sin identidades).
class OcupacionClase {
  const OcupacionClase({required this.confirmadas, required this.espera});

  /// Número de reservas confirmadas (plazas efectivas ocupadas).
  final int confirmadas;

  /// Número de entradas en la lista de espera.
  final int espera;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OcupacionClase &&
          runtimeType == other.runtimeType &&
          confirmadas == other.confirmadas &&
          espera == other.espera);

  @override
  int get hashCode => Object.hash(confirmadas, espera);

  @override
  String toString() =>
      'OcupacionClase(confirmadas: $confirmadas, espera: $espera)';
}
