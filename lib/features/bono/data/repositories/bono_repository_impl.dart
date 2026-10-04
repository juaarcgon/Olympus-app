// Implementacion del Servicio_Bono (BonoRepository) sobre Supabase.
//
// Orquesta la [BonoRemoteDataSource] para leer el Saldo_De_Clases del Usuario
// autenticado (Req 4.1). Las excepciones del SDK de Supabase se traducen a
// `Failure` de dominio tipados, acorde a la estrategia de "Error Handling" del
// diseno.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failures.dart';
import '../../domain/repositories/bono_repository.dart';
import '../datasources/bono_remote_datasource.dart';

/// Implementacion de [BonoRepository] respaldada por Supabase.
class BonoRepositoryImpl implements BonoRepository {
  /// Crea el repositorio con su [BonoRemoteDataSource].
  BonoRepositoryImpl({BonoRemoteDataSource? dataSource})
    : _dataSource = dataSource ?? BonoRemoteDataSource();

  final BonoRemoteDataSource _dataSource;

  @override
  Future<int> getSaldo() async {
    try {
      return await _dataSource.fetchSaldo();
    } on StateError {
      // Sin sesion activa: no hay acceso a datos (Req 7.3).
      throw const AutorizacionInsuficienteFailure(
        'No tienes autorización para realizar esta operación',
      );
    } on PostgrestException {
      // Un rechazo por politica RLS o la ausencia de fila (JWT ausente, lectura
      // ajena sin ser superadmin) se interpreta como falta de autorizacion
      // (Req 7.2, 7.3).
      throw const AutorizacionInsuficienteFailure();
    }
  }
}
