// Implementación del Servicio_Reservas (ReservasRepository) sobre Supabase.
//
// Orquesta la [ReservasRemoteDataSource] y realiza:
//   - el mapeo de filas de `clases` a la entidad de dominio [Clase] (Req 8.1),
//   - el mapeo del jsonb devuelto por la RPC `reservar_clase` a
//     [ReservaResult] (Req 8.3, 8.5),
//   - la traducción de las excepciones del SDK a `Failure` de dominio tipados,
//     acorde a la estrategia de "Error Handling" del diseño.
//
// Mapeo de errores (RPC `reservar_clase`, errores de negocio con ERRCODE
// 'P0001' diferenciados por mensaje):
//   - "No quedan clases disponibles en tu bono" -> [SinClasesFailure] (Req 8.4)
//   - "Ya existe una reserva para esta clase"   -> [ReservaDuplicadaFailure]
//     (Req 8.6)
//   - "La lista de espera está completa"        -> [ListaEsperaLlenaFailure]
//     (Req 8.12)
//   - ERRCODE '42501' (sin sesión / violación RLS en el CRUD de Clases) ->
//     [AutorizacionInsuficienteFailure] (Req 8.2, 7.3)
//   - ERRCODE 'P0002' (Clase/usuario/reserva no encontrada) -> se interpreta,
//     para la reserva, como falta de clases disponibles (no hay nada que
//     reservar); el resto se trata como autorización insuficiente.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/apuntado.dart';
import '../../domain/entities/clase.dart';
import '../../domain/entities/ocupacion_clase.dart';
import '../../domain/entities/reserva.dart';
import '../../domain/entities/reserva_result.dart';
import '../../domain/repositories/reservas_repository.dart';
import '../datasources/reservas_remote_datasource.dart';

/// Implementación de [ReservasRepository] respaldada por Supabase.
class ReservasRepositoryImpl implements ReservasRepository {
  /// Crea el repositorio con su [ReservasRemoteDataSource].
  ReservasRepositoryImpl({ReservasRemoteDataSource? dataSource})
    : _dataSource = dataSource ?? ReservasRemoteDataSource();

  final ReservasRemoteDataSource _dataSource;

  @override
  Future<List<Clase>> getCalendario({DateTime? desde, DateTime? hasta}) async {
    try {
      final rows = await _dataSource.fetchCalendario(
        desde: desde,
        hasta: hasta,
      );
      return rows.map(_mapRowToClase).toList(growable: false);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  @override
  Future<Clase> crearClase({
    required DateTime horario,
    required int aforo,
    required String monitor,
  }) async {
    try {
      final row = await _dataSource.insertClase(
        horario: horario,
        aforo: aforo,
        monitor: monitor,
      );
      return _mapRowToClase(row);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  @override
  Future<Clase> editarClase(
    String claseId, {
    DateTime? horario,
    int? aforo,
    String? monitor,
  }) async {
    try {
      final cambios = <String, dynamic>{};
      if (horario != null) {
        cambios['horario'] = horario.toUtc().toIso8601String();
      }
      if (aforo != null) cambios['aforo'] = aforo;
      if (monitor != null) cambios['monitor'] = monitor;

      final row = await _dataSource.updateClase(claseId, cambios);
      return _mapRowToClase(row);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  @override
  Future<void> eliminarClase(String claseId) async {
    try {
      await _dataSource.deleteClase(claseId);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  @override
  Future<ReservaResult> reservar(String claseId) async {
    try {
      final json = await _dataSource.reservarClase(claseId);
      return _mapJsonToReservaResult(json);
    } on PostgrestException catch (e) {
      throw _mapReservarException(e);
    }
  }

  @override
  Future<void> cancelar(String claseId) async {
    try {
      await _dataSource.cancelarReserva(claseId);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  @override
  Future<OcupacionClase> getOcupacion(String claseId) async {
    try {
      final json = await _dataSource.fetchOcupacion(claseId);
      final confirmadas = (json['confirmadas'] as num?)?.toInt() ?? 0;
      final espera = (json['espera'] as num?)?.toInt() ?? 0;
      return OcupacionClase(confirmadas: confirmadas, espera: espera);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  @override
  Future<List<Apuntado>> getApuntados(String claseId) async {
    try {
      final rows = await _dataSource.fetchApuntados(claseId);
      return rows.map(_mapRowToApuntado).toList(growable: false);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  @override
  Future<Map<String, Reserva>> getMisReservas(List<String> claseIds) async {
    try {
      final rows = await _dataSource.fetchMisReservas(claseIds);
      final mapa = <String, Reserva>{};
      for (final row in rows) {
        final reserva = _mapRowToReserva(row);
        mapa[reserva.claseId] = reserva;
      }
      return mapa;
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  /// Mapea una fila cruda de `clases` a la entidad de dominio [Clase] (Req 8.1).
  Clase _mapRowToClase(Map<String, dynamic> row) {
    final createdAtRaw = row['created_at'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)
        : null;

    return Clase(
      id: row['id'] as String,
      horario: DateTime.parse(row['horario'] as String),
      aforo: (row['aforo'] as num).toInt(),
      monitor: row['monitor'] as String,
      createdBy: row['created_by'] as String?,
      createdAt: createdAt,
    );
  }

  /// Mapea una fila cruda de `reservas` a la entidad de dominio [Reserva].
  Reserva _mapRowToReserva(Map<String, dynamic> row) {
    final createdAtRaw = row['created_at'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)
        : null;
    final posicionRaw = row['posicion'];

    return Reserva(
      id: row['id'] as String,
      claseId: row['clase_id'] as String,
      userId: row['user_id'] as String,
      status: ReservaStatus.desdeValor(row['status'] as String),
      posicion: posicionRaw is num ? posicionRaw.toInt() : null,
      createdAt: createdAt,
    );
  }

  /// Mapea una fila cruda de `reservas` (con el perfil anidado) a [Apuntado]
  /// (Req 8.2).
  ///
  /// La fila incluye `status`, `posicion` y un objeto anidado `profiles` con el
  /// `nombre` y los `apellidos` del Usuario apuntado.
  Apuntado _mapRowToApuntado(Map<String, dynamic> row) {
    final perfil = row['profiles'];
    final datosPerfil = perfil is Map
        ? Map<String, dynamic>.from(perfil)
        : const <String, dynamic>{};
    final posicionRaw = row['posicion'];

    return Apuntado(
      userId: row['user_id'] as String,
      nombre: (datosPerfil['nombre'] as String?) ?? '',
      apellidos: (datosPerfil['apellidos'] as String?) ?? '',
      status: ReservaStatus.desdeValor(row['status'] as String),
      posicion: posicionRaw is num ? posicionRaw.toInt() : null,
    );
  }

  /// Mapea el jsonb devuelto por `reservar_clase` a [ReservaResult]
  /// (Req 8.3, 8.5).
  ///
  /// El backend devuelve `{ status, posicion, saldo_resultante }`, donde
  /// `status` es `confirmada` o `espera`.
  ReservaResult _mapJsonToReservaResult(Map<String, dynamic> json) {
    final outcome = ReservaOutcome.desdeValor(json['status'] as String);
    final saldo = (json['saldo_resultante'] as num?)?.toInt() ?? 0;
    final posicionRaw = json['posicion'];
    final posicion = posicionRaw is num ? posicionRaw.toInt() : null;

    if (outcome == ReservaOutcome.enEspera) {
      return ReservaResult.enEspera(
        posicion: posicion ?? 0,
        saldoResultante: saldo,
      );
    }
    return ReservaResult.confirmada(saldoResultante: saldo);
  }

  /// Traduce una [PostgrestException] del CRUD de Clases o de la cancelación a
  /// un [Failure] de dominio.
  ///
  /// Un rechazo por política RLS (CRUD de Clases por un no superadministrador)
  /// o la ausencia de sesión (ERRCODE '42501') se interpretan como falta de
  /// autorización (Req 8.2, 7.3).
  Failure _mapPostgrestException(PostgrestException e) {
    return const AutorizacionInsuficienteFailure();
  }

  /// Traduce una [PostgrestException] de la RPC `reservar_clase` a un [Failure]
  /// de dominio, diferenciando los errores de negocio por su mensaje.
  Failure _mapReservarException(PostgrestException e) {
    final mensaje = e.message;

    if (mensaje.contains('No quedan clases disponibles')) {
      return const SinClasesFailure();
    }
    if (mensaje.contains('Ya existe una reserva')) {
      return const ReservaDuplicadaFailure();
    }
    if (mensaje.contains('lista de espera está completa')) {
      return const ListaEsperaLlenaFailure();
    }

    // 'P0002' (Clase o usuario no encontrados): no hay nada que reservar.
    if (e.code == 'P0002') {
      return const SinClasesFailure();
    }

    // '42501' (sin sesión) y cualquier otro rechazo: autorización insuficiente.
    return const AutorizacionInsuficienteFailure();
  }
}
