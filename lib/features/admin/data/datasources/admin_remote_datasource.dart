// Fuente de datos remota de administración (Supabase).
//
// Encapsula las llamadas directas al SDK de Supabase para el
// Servicio_Administracion:
//   - `select` sobre `profiles` para listar Usuarios; la política RLS devuelve
//     todas las filas solo cuando el llamante es superadministrador (Req 6.1).
//   - `rpc(...)` sobre las funciones transaccionales de la migración
//     `0005_rpc_admin.sql` (`suspender_usuario`, `reactivar_usuario`,
//     `eliminar_usuario`, `conceder_superadmin`) y de `0004_rpc_bono.sql`
//     (`restablecer_bono`, `ajustar_bono`), que validan el rol de
//     superadministrador en el backend (Req 5.3, 5.4, 6.2–6.7).
//
// Trabaja con filas crudas (`Map<String, dynamic>`); el mapeo DTO <-> dominio y
// la traducción de excepciones a `Failure` se realizan en el repositorio. Las
// excepciones del SDK (`PostgrestException`) se propagan tal cual.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Nombre de la tabla de perfiles en PostgreSQL.
const String kProfilesTable = 'profiles';

/// Fuente de datos remota que habla con Supabase (Postgres + RPC) para la
/// gestión administrativa de Usuarios.
class AdminRemoteDataSource {
  /// Crea la fuente de datos.
  ///
  /// Si no se proporciona [client], usa la instancia global del SDK ya
  /// inicializada por `initSupabase()`.
  AdminRemoteDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Lee todas las filas visibles de `profiles` ordenadas por fecha de alta
  /// (Req 6.1).
  ///
  /// Devuelve una lista de filas crudas. Gracias a la RLS, un superadministrador
  /// obtiene todos los Usuarios; un Usuario estándar solo vería su propia fila.
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final rows = await _client
        .from(kProfilesTable)
        .select()
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Da de baja al Usuario objetivo vía RPC `suspender_usuario` (Req 6.2).
  Future<void> suspenderUsuario(String targetUserId) async {
    await _client.rpc(
      'suspender_usuario',
      params: {'target_user_id': targetUserId},
    );
  }

  /// Reactiva al Usuario objetivo vía RPC `reactivar_usuario` (Req 6.3).
  Future<void> reactivarUsuario(String targetUserId) async {
    await _client.rpc(
      'reactivar_usuario',
      params: {'target_user_id': targetUserId},
    );
  }

  /// Elimina el registro del Usuario objetivo vía RPC `eliminar_usuario`
  /// (Req 6.4). La propia función rechaza la autoeliminación (Req 6.7).
  Future<void> eliminarUsuario(String targetUserId) async {
    await _client.rpc(
      'eliminar_usuario',
      params: {'target_user_id': targetUserId},
    );
  }

  /// Restablece el bono del Usuario objetivo a 10 vía RPC `restablecer_bono`
  /// (Req 6.5).
  Future<void> restablecerBono(String targetUserId) async {
    await _client.rpc(
      'restablecer_bono',
      params: {'target_user_id': targetUserId},
    );
  }

  /// Ajusta el saldo del Usuario objetivo al [valor] indicado vía RPC
  /// `ajustar_bono` (Req 6.6). La función valida el rango 0..10 en el backend.
  Future<void> ajustarBono(String targetUserId, int valor) async {
    await _client.rpc(
      'ajustar_bono',
      params: {'target_user_id': targetUserId, 'valor': valor},
    );
  }

  /// Concede el rol de superadministrador al Usuario objetivo vía RPC
  /// `conceder_superadmin`, respetando el máximo de dos (Req 5.1, 5.2).
  Future<void> concederSuperadmin(String targetUserId) async {
    await _client.rpc(
      'conceder_superadmin',
      params: {'target_user_id': targetUserId},
    );
  }
}
