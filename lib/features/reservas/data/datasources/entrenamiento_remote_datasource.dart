// Fuente de datos remota del plan de entrenamiento del día (Supabase).
//
// Encapsula las llamadas directas al SDK de Supabase sobre la tabla
// `entrenamiento_dia`:
//   - `select` filtrando por `fecha` (en formato 'yyyy-MM-dd') para consultar
//     el plan de un día (Req 8.1).
//   - `upsert` con `onConflict: 'fecha'` para crear o actualizar el plan del
//     día; la autorización de superadministrador la refuerzan las políticas RLS
//     de la migración 0007 (Req 8.2).
//
// Trabaja con filas crudas (`Map<String, dynamic>`); el mapeo DTO <-> dominio y
// la traducción de errores se realizan en el repositorio. Las excepciones del
// SDK se propagan tal cual para que el repositorio las traduzca a `Failure`.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Nombre de la tabla del plan de entrenamiento del día en PostgreSQL.
const String kEntrenamientoDiaTable = 'entrenamiento_dia';

/// Fuente de datos remota que habla con Supabase (Postgres).
class EntrenamientoRemoteDataSource {
  /// Crea la fuente de datos.
  ///
  /// Si no se proporciona [client], usa la instancia global del SDK ya
  /// inicializada por `initSupabase()`.
  EntrenamientoRemoteDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Lee la fila de `entrenamiento_dia` cuya `fecha` coincide con [fechaIso]
  /// (formato 'yyyy-MM-dd'); devuelve `null` si no existe (Req 8.1).
  Future<Map<String, dynamic>?> fetchPorFecha(String fechaIso) async {
    final row = await _client
        .from(kEntrenamientoDiaTable)
        .select()
        .eq('fecha', fechaIso)
        .maybeSingle();
    return row;
  }

  /// Inserta o actualiza (upsert por `fecha`) el plan del día [fechaIso] con la
  /// lista ordenada [actividades] y devuelve la fila resultante (Req 8.1, 8.2).
  ///
  /// La RLS de `INSERT`/`UPDATE` solo permite la operación a
  /// superadministradores (Req 8.2); en caso contrario el SDK lanza una
  /// [PostgrestException].
  Future<Map<String, dynamic>> upsertPorFecha(
    String fechaIso,
    List<String> actividades,
  ) async {
    final row = await _client
        .from(kEntrenamientoDiaTable)
        .upsert(<String, dynamic>{
          'fecha': fechaIso,
          'actividades': actividades,
        }, onConflict: 'fecha')
        .select()
        .single();
    return row;
  }
}
