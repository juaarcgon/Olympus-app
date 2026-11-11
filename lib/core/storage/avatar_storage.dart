// Borrado de las fotos de perfil de un Usuario en Supabase Storage.
//
// Las fotos viven en el bucket `avatars`, en la carpeta `<userId>/`. Supabase
// prohíbe borrar objetos de Storage con SQL (trigger `storage.protect_delete`),
// así que al eliminar una cuenta la app debe borrarlas con la API de Storage
// ANTES de llamar a la función que borra la cuenta (`eliminar_mi_cuenta` o
// `eliminar_usuario`, migración 0017).
//
// Permisos (RLS de `storage.objects`): cada Usuario puede borrar su propia
// carpeta (migración 0009) y el superadministrador cualquiera (migración 0017).

import 'package:supabase_flutter/supabase_flutter.dart';

/// Bucket de Supabase Storage con las fotos de perfil.
const String kBucketAvatares = 'avatars';

/// Borra todos los archivos de la carpeta `avatars/<userId>/`.
///
/// No hace nada si la carpeta está vacía o no existe. Propaga la
/// [StorageException] si el borrado falla, para que quien llama NO siga
/// adelante y no deje una foto pública de una cuenta ya eliminada.
Future<void> borrarAvataresDe(SupabaseClient client, String userId) async {
  final bucket = client.storage.from(kBucketAvatares);
  final archivos = await bucket.list(path: userId);
  if (archivos.isEmpty) return;
  await bucket.remove([for (final f in archivos) '$userId/${f.name}']);
}
