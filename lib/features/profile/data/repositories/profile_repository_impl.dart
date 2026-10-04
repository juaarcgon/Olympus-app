// Implementación del Servicio_Usuarios (ProfileRepository) sobre Supabase.
//
// Orquesta la [ProfileRemoteDataSource] y realiza el mapeo DTO <-> dominio:
//   - lee el perfil propio (Req 3.1),
//   - actualiza solo los campos editables (nombre, apellidos, foto) (Req 3.2),
//   - nunca envía `saldo_clases`, `estado` ni `rol` en las actualizaciones
//     (Req 3.3, 3.4; la RLS lo refuerza en el backend),
//   - preserva íntegramente `metadata` en los round trips (Req 3.5).
//
// Las excepciones del SDK de Supabase se traducen a `Failure` de dominio
// tipados, acorde a la estrategia de "Error Handling" del diseño.

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_remote_datasource.dart';

/// Implementación de [ProfileRepository] respaldada por Supabase.
class ProfileRepositoryImpl implements ProfileRepository {
  /// Crea el repositorio con su [ProfileRemoteDataSource].
  ProfileRepositoryImpl({ProfileRemoteDataSource? dataSource})
    : _dataSource = dataSource ?? ProfileRemoteDataSource();

  final ProfileRemoteDataSource _dataSource;

  @override
  Future<Profile> getMyProfile() async {
    try {
      final row = await _dataSource.fetchMyProfile();
      return _mapRowToProfile(row);
    } on StateError {
      // Sin sesión activa: no hay acceso a datos (Req 7.3).
      throw const AutorizacionInsuficienteFailure(
        'No tienes autorización para realizar esta operación',
      );
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } on StorageException catch (e) {
      throw _mapStorageException(e);
    }
  }

  @override
  Future<Profile> updateMyProfile({
    String? nombre,
    String? apellidos,
    XFile? foto,
  }) async {
    try {
      // Solo se incluyen las columnas EDITABLES: nombre, apellidos, foto_url.
      // Nunca saldo_clases, estado ni rol (Req 3.3, 3.4).
      final cambios = <String, dynamic>{};

      if (nombre != null) cambios['nombre'] = nombre;
      if (apellidos != null) cambios['apellidos'] = apellidos;

      if (foto != null) {
        final bytes = await foto.readAsBytes();
        final fotoUrl = await _dataSource.uploadAvatar(
          bytes,
          fileExtension: _extensionDe(foto),
          contentType: foto.mimeType,
        );
        cambios['foto_url'] = fotoUrl;
      }

      final row = await _dataSource.updateMyProfile(cambios);
      return _mapRowToProfile(row);
    } on StateError {
      throw const AutorizacionInsuficienteFailure(
        'No tienes autorización para realizar esta operación',
      );
    } on PostgrestException catch (e) {
      throw _mapPostgrestException(e);
    } on StorageException catch (e) {
      throw _mapStorageException(e);
    }
  }

  /// Deriva la extensión de archivo de un [XFile] a partir de su nombre.
  ///
  /// Devuelve `.jpg` por defecto cuando el nombre no incluye extensión, para
  /// garantizar una ruta de Storage con sufijo coherente.
  String _extensionDe(XFile foto) {
    final name = foto.name;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.jpg';
    return name.substring(dot);
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

  /// Traduce una [PostgrestException] a un [Failure] de dominio.
  ///
  /// Un rechazo por política RLS (p. ej. intentar escribir columnas no
  /// permitidas, o leer datos ajenos sin ser superadmin) se interpreta como
  /// falta de autorización (Req 3.3, 3.4, 7.2).
  Failure _mapPostgrestException(PostgrestException e) {
    // Códigos típicos: 42501 (violación de política RLS), PGRST301 (JWT
    // ausente/ inválido), PGRST116 (ninguna fila por RLS). En todos los casos
    // la causa de dominio es la misma: autorización insuficiente.
    return const AutorizacionInsuficienteFailure();
  }

  /// Traduce una [StorageException] (subida de la foto) a un [Failure].
  Failure _mapStorageException(StorageException e) {
    return const AutorizacionInsuficienteFailure();
  }
}
