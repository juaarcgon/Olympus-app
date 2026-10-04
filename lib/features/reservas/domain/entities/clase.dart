// Entidad de dominio Clase para la app Olympus.
//
// Representa una sesión programada del calendario del gimnasio (tabla
// `clases`). Modelo de dominio puro e inmutable, independiente de Supabase.

/// Clase programada en el calendario del gimnasio.
///
/// Inmutable: todos sus campos son `final`. Usa [copyWith] para derivar copias
/// modificadas. Implementa igualdad estructural por valor.
class Clase {
  const Clase({
    required this.id,
    required this.horario,
    required this.aforo,
    required this.monitor,
    this.createdBy,
    this.createdAt,
  });

  /// Identificador único de la Clase.
  final String id;

  /// Fecha y hora de inicio de la Clase (Horario_Clase, Req 8.1).
  final DateTime horario;

  /// Aforo máximo de plazas; invariante 1..10 (Req 8.1).
  final int aforo;

  /// Monitor asignado a la Clase (Req 8.1).
  final String monitor;

  /// Id del superadministrador que creó la Clase; `null` si no se conoce.
  final String? createdBy;

  /// Fecha de creación del registro; `null` si aún no se conoce.
  final DateTime? createdAt;

  /// Devuelve una copia de la Clase con los campos indicados reemplazados.
  Clase copyWith({
    String? id,
    DateTime? horario,
    int? aforo,
    String? monitor,
    Object? createdBy = _sentinel,
    Object? createdAt = _sentinel,
  }) {
    return Clase(
      id: id ?? this.id,
      horario: horario ?? this.horario,
      aforo: aforo ?? this.aforo,
      monitor: monitor ?? this.monitor,
      createdBy: identical(createdBy, _sentinel)
          ? this.createdBy
          : createdBy as String?,
      createdAt: identical(createdAt, _sentinel)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Clase &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          horario == other.horario &&
          aforo == other.aforo &&
          monitor == other.monitor &&
          createdBy == other.createdBy &&
          createdAt == other.createdAt);

  @override
  int get hashCode =>
      Object.hash(id, horario, aforo, monitor, createdBy, createdAt);

  @override
  String toString() =>
      'Clase(id: $id, horario: $horario, aforo: $aforo, monitor: $monitor)';
}

/// Centinela interno para distinguir "no modificar" de "fijar a null" en
/// [Clase.copyWith] para campos anulables.
const Object _sentinel = Object();
