// Implementación del Servicio_Administracion (AdminRepository) sobre Supabase.
//
// Orquesta la [AdminRemoteDataSource] y realiza:
//   - el mapeo de filas crudas de `profiles` a la entidad de dominio [Profile]
//     para el listado de Usuarios (Req 6.1),
//   - la invocación de las RPC administrativas (suspender, reactivar, eliminar,
//     restablecer/ajustar bono, conceder superadmin) (Req 6.2–6.7, 5.1, 5.2),
//   - la traducción de las excepciones del backend (`PostgrestException`) a
//     `Failure` de dominio tipados, acorde a la estrategia de "Error Handling"
//     del diseño.
//
// Mapeo de errores de las RPC (ver `0004_rpc_bono.sql` y `0005_rpc_admin.sql`):
//   * `P0001`  -> MaxSuperadminsFailure            (Req 5.2)
//   * `42501` con mensaje de autoeliminación -> AutoeliminacionFailure (Req 6.7)
//   * `42501` genérico -> AutorizacionInsuficienteFailure (Req 5.4)
//   * `22003` -> BonoFueraDeRangoFailure           (Req 6.6)
//   * `P0002` u otros -> OperacionFallidaFailure (con el mensaje del backend)

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failures.dart';
import '../../../profile/domain/entities/profile.dart';
import '../../domain/repositories/admin_repository.dart';
import '../datasources/admin_remote_datasource.dart';

/// Implementación de [AdminRepository] respaldada por Supabase.
class AdminRepositoryImpl implements AdminRepository {
  /// Crea el repositorio con su [AdminRemoteDataSource].
  AdminRepositoryImpl({AdminRemoteDataSource? dataSource})
    : _dataSource = dataSource ?? AdminRemoteDataSource();

  final AdminRemoteDataSource _dataSource;

  @override
  Future<List<Profile>> listUsers() async {
    try {
      final rows = await _dataSource.fetchUsers();
      return rows.map(_mapRowToProfile).toList(growable: false);
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  @override
  Future<void> suspendUser(String userId) =>
      _ejecutarRpc(() => _dataSource.suspenderUsuario(userId));

  @override
  Future<void> reactivateUser(String userId) =>
      _ejecutarRpc(() => _dataSource.reactivarUsuario(userId));

  @override
  Future<void> deleteUser(String userId) =>
      _ejecutarRpc(() => _dataSource.eliminarUsuario(userId));

  @override
  Future<void> restablecerBono(String userId) =>
      _ejecutarRpc(() => _dataSource.restablecerBono(userId));

  @override
  Future<void> ajustarBono(String userId, int valor) =>
      _ejecutarRpc(() => _dataSource.ajustarBono(userId, valor));

  @override
  Future<void> grantSuperadmin(String userId) =>
      _ejecutarRpc(() => _dataSource.concederSuperadmin(userId));

  /// Ejecuta una operación RPC traduciendo cualquier [PostgrestException] a un
  /// [Failure] de dominio tipado.
  Future<void> _ejecutarRpc(Future<void> Function() accion) async {
    try {
      await accion();
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    }
  }

  /// Mapea una fila cruda de `profiles` a la entidad de dominio [Profile].
  ///
  /// Preserva `metadata` íntegramente (Req 3.5) y traduce las columnas de texto
  /// `estado`/`rol` a sus enumeraciones de dominio.
  Profile _mapRowToProfile(Map<String, dynamic> row) {
    final metadataRaw = row['metadata'];
    final metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : <String, dynamic>{};

    final createdAtRaw = row['created_at'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)
        : null;

    return Profile(
      id: row['id'] as String,
      nombre: row['nombre'] as String,
      apellidos: row['apellidos'] as String,
      fotoUrl: row['foto_url'] as String?,
      email: row['email'] as String,
      saldoClases: (row['saldo_clases'] as num).toInt(),
      estado: EstadoUsuario.desdeValor(row['estado'] as String),
      rol: RolUsuario.desdeValor(row['rol'] as String),
      metadata: metadata,
      createdAt: createdAt,
    );
  }

  /// Traduce una [PostgrestException] lanzada por una RPC administrativa a un
  /// [Failure] de dominio, según su código de error de PostgreSQL.
  Failure _mapPostgrestException(PostgrestException e) {
    final code = e.code;
    final mensaje = e.message;

    // Máximo de superadministradores alcanzado (Req 5.2).
    if (code == 'P0001') {
      return const MaxSuperadminsFailure();
    }

    // Valor del bono fuera del rango 0..10 en ajustar_bono (Req 6.6).
    if (code == '22003') {
      return const BonoFueraDeRangoFailure();
    }

    // Autorización insuficiente o autoeliminación: ambos usan 42501, se
    // distinguen por el mensaje de la excepción.
    if (code == '42501') {
      if (_esAutoeliminacion(mensaje)) {
        // Un superadministrador no puede eliminarse a sí mismo (Req 6.7).
        return const AutoeliminacionFailure();
      }
      // Falta de rol de superadministrador (Req 5.4).
      return const AutorizacionInsuficienteFailure();
    }

    // PGRST301 / 401: petición sin sesión válida -> sin acceso (Req 7.3).
    if (code == 'PGRST301' || code == '401') {
      return const AutorizacionInsuficienteFailure();
    }

    // Dato no encontrado (P0002) u otro error inesperado del backend: se
    // conserva el mensaje del servidor para no perder el contexto.
    return OperacionFallidaFailure(mensaje);
  }

  /// Determina si el mensaje de un error 42501 corresponde a un intento de
  /// autoeliminación de superadministrador (Req 6.7).
  bool _esAutoeliminacion(String mensaje) {
    final normalizado = mensaje.toLowerCase();
    return normalizado.contains('no puede eliminarse') ||
        normalizado.contains('eliminarse a si mismo') ||
        normalizado.contains('eliminarse a sí mismo');
  }
}
