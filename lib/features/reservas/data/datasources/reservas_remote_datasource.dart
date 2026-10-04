// Fuente de datos remota del Servicio_Reservas (Supabase).
//
// Encapsula las llamadas directas al SDK de Supabase:
//   - `select` sobre `clases`, opcionalmente acotado por rango de `horario` y
//     ordenado ascendentemente, para el calendario (Req 8.1).
//   - `insert` / `update` / `delete` sobre `clases` para el CRUD de Clases; la
//     autorización de superadministrador la refuerzan las políticas RLS de la
//     migración 0003 (Req 8.1, 8.2).
//   - `rpc('reservar_clase', ...)` y `rpc('cancelar_reserva', ...)` para las
//     operaciones transaccionales de reserva y cancelación (Req 8.3–8.12).
//
// Trabaja con filas crudas (`Map<String, dynamic>`) y jsonb; el mapeo
// DTO <-> dominio y la traducción de errores se realizan en el repositorio.
// Las excepciones del SDK se propagan tal cual para que el repositorio las
// traduzca a `Failure` de dominio.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Nombre de la tabla de Clases en PostgreSQL.
const String kClasesTable = 'clases';

/// Nombre de la tabla de Reservas en PostgreSQL.
const String kReservasTable = 'reservas';

/// Nombre de la RPC transaccional de reserva de una Clase.
const String kReservarRpc = 'reservar_clase';

/// Nombre de la RPC transaccional de cancelación de una Reserva.
const String kCancelarRpc = 'cancelar_reserva';

/// Nombre de la RPC de solo lectura que devuelve la ocupación de una Clase sin
/// exponer identidades (migración 0008).
const String kOcupacionRpc = 'ocupacion_clase';

/// Fuente de datos remota que habla con Supabase (Postgres + RPC).
class ReservasRemoteDataSource {
  /// Crea la fuente de datos.
  ///
  /// Si no se proporciona [client], usa la instancia global del SDK ya
  /// inicializada por `initSupabase()`.
  ReservasRemoteDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Lee las filas de `clases` del calendario, ordenadas por `horario`
  /// ascendente (Req 8.1).
  ///
  /// Si se indica [desde] filtra por `horario >= desde`; si se indica [hasta]
  /// filtra por `horario <= hasta`. Las fechas se envían en formato ISO-8601
  /// (UTC) para preservar la zona horaria.
  Future<List<Map<String, dynamic>>> fetchCalendario({
    DateTime? desde,
    DateTime? hasta,
  }) async {
    var query = _client.from(kClasesTable).select();

    if (desde != null) {
      query = query.gte('horario', desde.toUtc().toIso8601String());
    }
    if (hasta != null) {
      query = query.lte('horario', hasta.toUtc().toIso8601String());
    }

    final rows = await query.order('horario', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Inserta una nueva fila en `clases` y devuelve la fila creada (Req 8.1).
  ///
  /// La RLS de `INSERT` solo permite la operación a superadministradores
  /// (Req 8.2); en caso contrario el SDK lanza una [PostgrestException].
  Future<Map<String, dynamic>> insertClase({
    required DateTime horario,
    required int aforo,
    required String monitor,
  }) async {
    final row = await _client
        .from(kClasesTable)
        .insert(<String, dynamic>{
          'horario': horario.toUtc().toIso8601String(),
          'aforo': aforo,
          'monitor': monitor,
        })
        .select()
        .single();
    return row;
  }

  /// Actualiza las columnas presentes en [cambios] de la Clase [claseId] y
  /// devuelve la fila resultante (Req 8.1).
  ///
  /// Si [cambios] está vacío, no realiza ninguna escritura y devuelve la fila
  /// actual. La RLS de `UPDATE` solo permite la operación a
  /// superadministradores (Req 8.2).
  Future<Map<String, dynamic>> updateClase(
    String claseId,
    Map<String, dynamic> cambios,
  ) async {
    if (cambios.isEmpty) {
      return _client.from(kClasesTable).select().eq('id', claseId).single();
    }
    final row = await _client
        .from(kClasesTable)
        .update(cambios)
        .eq('id', claseId)
        .select()
        .single();
    return row;
  }

  /// Elimina la fila de `clases` con id [claseId] (Req 8.1).
  ///
  /// La RLS de `DELETE` solo permite la operación a superadministradores
  /// (Req 8.2).
  Future<void> deleteClase(String claseId) async {
    await _client.from(kClasesTable).delete().eq('id', claseId);
  }

  /// Invoca la RPC transaccional `reservar_clase` y devuelve su jsonb como
  /// `Map<String, dynamic>` (Req 8.3, 8.4, 8.5, 8.6, 8.12).
  Future<Map<String, dynamic>> reservarClase(String claseId) async {
    final result = await _client.rpc(
      kReservarRpc,
      params: <String, dynamic>{'p_clase_id': claseId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// Invoca la RPC transaccional `cancelar_reserva` (Req 8.7, 8.8, 8.9, 8.11).
  Future<void> cancelarReserva(String claseId) async {
    await _client.rpc(
      kCancelarRpc,
      params: <String, dynamic>{'p_clase_id': claseId},
    );
  }

  /// Invoca la RPC de solo lectura `ocupacion_clase` y devuelve su jsonb como
  /// `Map<String, dynamic>` con la ocupación de la Clase: `{confirmadas, espera}`.
  ///
  /// La función es `SECURITY DEFINER` (migración 0008) y la pueden ejecutar
  /// todos los Usuarios autenticados sin exponer las identidades de los
  /// apuntados. Permite mostrar el aforo real "confirmadas/aforo" a un Usuario
  /// normal, cuya RLS sobre `reservas` solo le dejaría ver sus propias filas.
  Future<Map<String, dynamic>> fetchOcupacion(String claseId) async {
    final result = await _client.rpc(
      kOcupacionRpc,
      params: <String, dynamic>{'p_clase_id': claseId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// Lee las reservas propias del Usuario de la sesión para las Clases
  /// indicadas en [claseIds].
  ///
  /// La RLS de `reservas` (migración 0003) garantiza que solo se devuelven las
  /// filas del propio Usuario, por lo que basta con filtrar por `clase_id`.
  /// Permite a la pantalla saber el estado de la reserva del Usuario en cada
  /// franja (confirmada / en espera / sin reserva). Si [claseIds] está vacío,
  /// devuelve una lista vacía sin consultar.
  Future<List<Map<String, dynamic>>> fetchMisReservas(
    List<String> claseIds,
  ) async {
    if (claseIds.isEmpty) return <Map<String, dynamic>>[];
    final rows = await _client
        .from(kReservasTable)
        .select()
        .inFilter('clase_id', claseIds);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Lee las reservas de la Clase [claseId] con los datos del Usuario apuntado
  /// (join con `profiles`), ordenadas por `status` y `posicion`.
  ///
  /// SOLO debe invocarse cuando el Usuario de la sesión es superadministrador:
  /// la RLS de `reservas` restringe esta lectura a sus propias filas para un
  /// Usuario normal, por lo que la lista completa de apuntados únicamente es
  /// visible para el superadministrador. Cada fila incluye el `status`, la
  /// `posicion` y los campos `nombre`/`apellidos` del perfil anidado.
  Future<List<Map<String, dynamic>>> fetchApuntados(String claseId) async {
    final rows = await _client
        .from(kReservasTable)
        .select('id, user_id, status, posicion, profiles(nombre, apellidos)')
        .eq('clase_id', claseId)
        .order('status', ascending: true)
        .order('posicion', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }
}
