// Implementación del plan de entrenamiento del día (EntrenamientoRepository)
// sobre Supabase.
//
// Orquesta la [EntrenamientoRemoteDataSource] y realiza:
//   - la conversión de la [DateTime] de dominio al formato 'yyyy-MM-dd' que usa
//     la columna `fecha` (tipo `date`) de PostgreSQL,
//   - el mapeo de la fila cruda a la entidad [EntrenamientoDia] (Req 8.1),
//   - la traducción de las excepciones del SDK a `Failure` de dominio: un
//     rechazo por política RLS en la escritura (no superadministrador) se
//     traduce a [AutorizacionInsuficienteFailure] (Req 8.2).

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/entrenamiento_dia.dart';
import '../../domain/repositories/entrenamiento_repository.dart';
import '../datasources/entrenamiento_remote_datasource.dart';

/// Implementación de [EntrenamientoRepository] respaldada por Supabase.
class EntrenamientoRepositoryImpl implements EntrenamientoRepository {
  /// Crea el repositorio con su [EntrenamientoRemoteDataSource].
  EntrenamientoRepositoryImpl({EntrenamientoRemoteDataSource? dataSource})
    : _dataSource = dataSource ?? EntrenamientoRemoteDataSource();

  final EntrenamientoRemoteDataSource _dataSource;

  @override
  Future<EntrenamientoDia?> getPorFecha(DateTime fecha) async {
    try {
      final row = await _dataSource.fetchPorFecha(_fechaIso(fecha));
      if (row == null) return null;
      return _mapRowToEntrenamiento(row);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  @override
  Future<EntrenamientoDia> guardar(
    DateTime fecha,
    List<String> actividades,
  ) async {
    try {
      final row = await _dataSource.upsertPorFecha(
        _fechaIso(fecha),
        actividades,
      );
      return _mapRowToEntrenamiento(row);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  /// Convierte una [DateTime] a la cadena 'yyyy-MM-dd' que espera la columna
  /// `fecha` (tipo `date`). Solo se usa la parte de fecha.
  String _fechaIso(DateTime fecha) {
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');
    return '${fecha.year.toString().padLeft(4, '0')}-$mes-$dia';
  }

  /// Mapea una fila cruda de `entrenamiento_dia` a la entidad de dominio
  /// [EntrenamientoDia] (Req 8.1).
  ///
  /// La columna `fecha` (tipo `date`) llega como cadena 'yyyy-MM-dd'; se
  /// interpreta como fecha local a medianoche. `actividades` llega como lista.
  EntrenamientoDia _mapRowToEntrenamiento(Map<String, dynamic> row) {
    final createdAtRaw = row['created_at'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)
        : null;

    final actividadesRaw = row['actividades'];
    final actividades = actividadesRaw is List
        ? actividadesRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    return EntrenamientoDia(
      id: row['id'] as String,
      fecha: _parseFecha(row['fecha'] as String),
      actividades: actividades,
      createdBy: row['created_by'] as String?,
      createdAt: createdAt,
    );
  }

  /// Interpreta una cadena 'yyyy-MM-dd' como [DateTime] local a medianoche.
  DateTime _parseFecha(String fecha) {
    final partes = fecha.split('-');
    return DateTime(
      int.parse(partes[0]),
      int.parse(partes[1]),
      int.parse(partes[2]),
    );
  }

  /// Traduce una [PostgrestException] a un [Failure] de dominio.
  ///
  /// Un rechazo por política RLS en la escritura (plan guardado por un no
  /// superadministrador) o la ausencia de sesión se interpretan como falta de
  /// autorización (Req 8.2, 7.3).
  Failure _mapPostgrestException(PostgrestException e) {
    return const AutorizacionInsuficienteFailure();
  }
}
