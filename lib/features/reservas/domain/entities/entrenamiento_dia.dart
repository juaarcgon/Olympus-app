// Entidad de dominio EntrenamientoDia para la app Olympus.
//
// Representa el plan de entrenamiento asociado a una fecha concreta (tabla
// `entrenamiento_dia`): una lista ordenada de actividades (p. ej.
// "Calentamiento", "Fuerza") común a todas las franjas horarias de ese día.
// Modelo de dominio puro e inmutable, independiente de Supabase (Req 8.1).

/// Plan de entrenamiento de un día del calendario del gimnasio.
///
/// Inmutable: todos sus campos son `final`. Usa [copyWith] para derivar copias
/// modificadas. Implementa igualdad estructural por valor.
class EntrenamientoDia {
  const EntrenamientoDia({
    required this.id,
    required this.fecha,
    required this.actividades,
    this.createdBy,
    this.createdAt,
  });

  /// Identificador único del plan del día.
  final String id;

  /// Fecha (día natural) a la que se asocia el plan; clave natural única.
  final DateTime fecha;

  /// Lista ordenada de actividades del día (Req 8.1).
  final List<String> actividades;

  /// Id del superadministrador que creó/actualizó el plan; `null` si no se
  /// conoce.
  final String? createdBy;

  /// Fecha de creación del registro; `null` si aún no se conoce.
  final DateTime? createdAt;

  /// Devuelve una copia del plan con los campos indicados reemplazados.
  EntrenamientoDia copyWith({
    String? id,
    DateTime? fecha,
    List<String>? actividades,
    Object? createdBy = _sentinel,
    Object? createdAt = _sentinel,
  }) {
    return EntrenamientoDia(
      id: id ?? this.id,
      fecha: fecha ?? this.fecha,
      actividades: actividades ?? this.actividades,
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
      (other is EntrenamientoDia &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fecha == other.fecha &&
          _listEquals(actividades, other.actividades) &&
          createdBy == other.createdBy &&
          createdAt == other.createdAt);

  @override
  int get hashCode =>
      Object.hash(id, fecha, Object.hashAll(actividades), createdBy, createdAt);

  @override
  String toString() =>
      'EntrenamientoDia(id: $id, fecha: $fecha, actividades: $actividades)';
}

/// Centinela interno para distinguir "no modificar" de "fijar a null" en
/// [EntrenamientoDia.copyWith] para campos anulables.
const Object _sentinel = Object();

/// Igualdad posicional de dos listas de actividades.
bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
