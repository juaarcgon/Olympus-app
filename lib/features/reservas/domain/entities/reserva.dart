// Entidad de dominio Reserva para la app Olympus.
//
// Unifica la reserva confirmada y la entrada en lista de espera en un solo
// modelo mediante el campo `status` (tabla `reservas`). Modelo de dominio puro
// e inmutable, independiente de Supabase.

/// Estado de una Reserva dentro de una Clase.
enum ReservaStatus {
  /// Plaza efectiva dentro del Aforo de la Clase (Reserva_Confirmada).
  confirmada,

  /// Entrada en la Lista_De_Espera de la Clase (Req 8.5).
  espera;

  /// Valor textual tal y como se persiste en la columna `status`.
  String get valor => name;

  /// Construye el estado a partir de su representación textual persistida.
  ///
  /// Lanza [ArgumentError] si [valor] no corresponde a ningún estado válido.
  static ReservaStatus desdeValor(String valor) {
    for (final status in ReservaStatus.values) {
      if (status.name == valor) return status;
    }
    throw ArgumentError.value(valor, 'valor', 'Estado de reserva no válido');
  }
}

/// Vínculo entre un Usuario y una Clase.
///
/// Una `confirmada` ocupa plaza efectiva; una `espera` figura en la lista de
/// espera con una `posicion` FIFO. Inmutable; usa [copyWith] para copias.
class Reserva {
  const Reserva({
    required this.id,
    required this.claseId,
    required this.userId,
    required this.status,
    this.posicion,
    this.createdAt,
  });

  /// Identificador único de la Reserva.
  final String id;

  /// Id de la Clase a la que pertenece la Reserva.
  final String claseId;

  /// Id del Usuario titular de la Reserva.
  final String userId;

  /// Estado de la Reserva: confirmada o en espera.
  final ReservaStatus status;

  /// Posición FIFO en la lista de espera; `null` para reservas confirmadas
  /// (Req 8.5, 8.9).
  final int? posicion;

  /// Fecha de creación; usada como desempate de orden; `null` si no se conoce.
  final DateTime? createdAt;

  /// Indica si la Reserva ocupa una plaza confirmada.
  bool get esConfirmada => status == ReservaStatus.confirmada;

  /// Indica si la Reserva está en lista de espera.
  bool get enEspera => status == ReservaStatus.espera;

  /// Devuelve una copia de la Reserva con los campos indicados reemplazados.
  Reserva copyWith({
    String? id,
    String? claseId,
    String? userId,
    ReservaStatus? status,
    Object? posicion = _sentinel,
    Object? createdAt = _sentinel,
  }) {
    return Reserva(
      id: id ?? this.id,
      claseId: claseId ?? this.claseId,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      posicion: identical(posicion, _sentinel)
          ? this.posicion
          : posicion as int?,
      createdAt: identical(createdAt, _sentinel)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Reserva &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          claseId == other.claseId &&
          userId == other.userId &&
          status == other.status &&
          posicion == other.posicion &&
          createdAt == other.createdAt);

  @override
  int get hashCode =>
      Object.hash(id, claseId, userId, status, posicion, createdAt);

  @override
  String toString() =>
      'Reserva(id: $id, claseId: $claseId, userId: $userId, '
      'status: ${status.valor}, posicion: $posicion)';
}

/// Centinela interno para distinguir "no modificar" de "fijar a null" en
/// [Reserva.copyWith] para campos anulables.
const Object _sentinel = Object();
