// Fuente de datos remota del bono (Supabase).
//
// Encapsula la llamada directa al SDK de Supabase para el Servicio_Bono:
//   - `select` sobre `profiles` filtrando por el id del Usuario autenticado
//     (`auth.uid()`), devolviendo unicamente la columna `saldo_clases` para
//     consultar el saldo propio (Req 4.1).
//
// Devuelve valores crudos; el mapeo a dominio se realiza en el repositorio.
// Las excepciones del SDK se propagan tal cual para que el repositorio las
// traduzca a `Failure` de dominio.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Nombre de la tabla de perfiles en PostgreSQL.
const String kProfilesTable = 'profiles';

/// Nombre de la columna del saldo de clases (bono) en `profiles`.
const String kSaldoClasesColumn = 'saldo_clases';

/// Fuente de datos remota que habla con Supabase (Postgres).
class BonoRemoteDataSource {
  /// Crea la fuente de datos.
  ///
  /// Si no se proporciona [client], usa la instancia global del SDK ya
  /// inicializada por `initSupabase()`.
  BonoRemoteDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Devuelve el id del Usuario autenticado actual.
  ///
  /// Lanza [StateError] si no hay sesion activa (sin sesion no hay acceso a
  /// datos, Req 7.3).
  String get _currentUserId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No hay una sesión activa');
    }
    return userId;
  }

  /// Lee el `saldo_clases` del Usuario autenticado (Req 4.1).
  ///
  /// La politica RLS de `SELECT` garantiza que solo se obtiene la fila propia,
  /// por lo que basta con filtrar por `id`.
  Future<int> fetchSaldo() async {
    final row = await _client
        .from(kProfilesTable)
        .select(kSaldoClasesColumn)
        .eq('id', _currentUserId)
        .single();
    return (row[kSaldoClasesColumn] as num).toInt();
  }
}
