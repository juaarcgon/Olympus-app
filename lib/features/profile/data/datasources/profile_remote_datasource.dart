// Fuente de datos remota del perfil (Supabase).
//
// Encapsula las llamadas directas al SDK de Supabase para el Servicio_Usuarios:
//   - `select` sobre `profiles` filtrando por el id del Usuario autenticado
//     (`auth.uid()`), para consultar el perfil propio (Req 3.1).
//   - `update` sobre `profiles` restringido a las columnas editables
//     (`nombre`, `apellidos`, `foto_url`, `metadata`), nunca `saldo_clases`,
//     `estado` ni `rol` (Req 3.2, 3.3, 3.4; reforzado por RLS).
//   - subida de la foto de perfil al bucket de Storage `avatars` y obtención de
//     su URL pública (Req 1.7).
//
// Trabaja con filas crudas (`Map<String, dynamic>`); el mapeo DTO <-> dominio
// se realiza en el repositorio. Las excepciones del SDK se propagan tal cual
// para que el repositorio las traduzca a `Failure` de dominio.

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Nombre del bucket de Supabase Storage para las fotos de perfil.
const String kAvatarsBucket = 'avatars';

/// Nombre de la tabla de perfiles en PostgreSQL.
const String kProfilesTable = 'profiles';

/// Fuente de datos remota que habla con Supabase (Postgres + Storage).
class ProfileRemoteDataSource {
  /// Crea la fuente de datos.
  ///
  /// Si no se proporciona [client], usa la instancia global del SDK ya
  /// inicializada por `initSupabase()`.
  ProfileRemoteDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Devuelve el id del Usuario autenticado actual.
  ///
  /// Lanza [StateError] si no hay sesión activa (sin sesión no hay acceso a
  /// datos, Req 7.3).
  String get _currentUserId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No hay una sesión activa');
    }
    return userId;
  }

  /// Lee la fila de `profiles` del Usuario autenticado (Req 3.1).
  ///
  /// Devuelve la fila cruda como `Map<String, dynamic>`. La política RLS de
  /// `SELECT` garantiza que solo se obtiene la fila propia (o cualquiera si es
  /// superadmin), por lo que basta con filtrar por `id`.
  Future<Map<String, dynamic>> fetchMyProfile() async {
    final row = await _client
        .from(kProfilesTable)
        .select()
        .eq('id', _currentUserId)
        .single();
    return row;
  }

  /// Actualiza las columnas editables del perfil propio y devuelve la fila
  /// resultante (Req 3.2).
  ///
  /// Solo se envían las columnas presentes en [cambios]. El llamante
  /// (repositorio) es responsable de restringir [cambios] a `nombre`,
  /// `apellidos`, `foto_url` y `metadata`; las políticas RLS rechazan cualquier
  /// intento de modificar `saldo_clases`, `estado` o `rol` (Req 3.3, 3.4).
  ///
  /// Si [cambios] está vacío, no realiza ninguna escritura y devuelve la fila
  /// actual mediante [fetchMyProfile].
  Future<Map<String, dynamic>> updateMyProfile(
    Map<String, dynamic> cambios,
  ) async {
    if (cambios.isEmpty) {
      return fetchMyProfile();
    }
    final row = await _client
        .from(kProfilesTable)
        .update(cambios)
        .eq('id', _currentUserId)
        .select()
        .single();
    return row;
  }

  /// Sube la foto [bytes] al bucket `avatars` para el Usuario autenticado y
  /// devuelve su URL pública (Req 1.7).
  ///
  /// La imagen se guarda con una ruta determinista por Usuario
  /// (`<userId>/avatar<ext>`) usando `upsert`, de modo que una nueva subida
  /// reemplaza la anterior.
  Future<String> uploadAvatar(
    Uint8List bytes, {
    required String fileExtension,
    String? contentType,
  }) async {
    final userId = _currentUserId;
    final ext = _normalizarExtension(fileExtension);
    final path = '$userId/avatar$ext';

    await _client.storage
        .from(kAvatarsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );

    return _client.storage.from(kAvatarsBucket).getPublicUrl(path);
  }

  /// Normaliza una extensión de archivo asegurando el punto inicial.
  ///
  /// Devuelve una cadena vacía si [extension] es vacía, o `.<ext>` en caso
  /// contrario (p. ej. `jpg` -> `.jpg`, `.png` -> `.png`).
  String _normalizarExtension(String extension) {
    if (extension.isEmpty) return '';
    return extension.startsWith('.') ? extension : '.$extension';
  }
}
