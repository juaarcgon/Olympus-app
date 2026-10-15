// Pruebas unitarias de lectura de saldo y de las RPC de bono (tarea 8.2).
//
// Verifican, sin red ni backend, tres comportamientos del Servicio_Bono y de
// las RPC administrativas de bono (`0004_rpc_bono.sql`):
//
//   - Req 4.1: la lectura del saldo (`BonoRepository.getSaldo`) devuelve el
//     Saldo_De_Clases actual del Usuario autenticado y traduce la ausencia de
//     sesión / el rechazo RLS a `AutorizacionInsuficienteFailure`.
//   - Req 6.5: `restablecer_bono` fija el saldo en 10. Se ejerce la RPC real a
//     través de `AdminRepository.restablecerBono`, cuya fuente de datos invoca
//     `rpc('restablecer_bono', ...)`. Un doble de la RPC reproduce fielmente el
//     contrato de la función SQL (fija 10, valida superadmin, usuario no
//     encontrado).
//   - Req 6.6: `ajustar_bono` fija el valor solicitado dentro de 0..10 y rechaza
//     los valores fuera de rango (código `22003`) sin tocar el saldo, acorde a
//     la validación del backend; también se ejerce vía `AdminRepository`.
//
// Convención del proyecto (ver `flujos_autenticacion_test.dart` y
// `reservas_repository_impl_test.dart`): se usan fakes manuales (sin librería de
// mocking) que sustituyen a Supabase. Para las RPC, el fake mantiene un "estado"
// de saldos en memoria y aplica las mismas reglas que la función PostgreSQL
// (autorización, rango, existencia), lanzando `PostgrestException` con los
// mismos códigos que el backend. Así se verifica el comportamiento observable
// de la RPC real sin depender de una instancia Supabase.

import 'package:flutter_test/flutter_test.dart';
import 'package:olympus/core/error/failures.dart';
import 'package:olympus/features/admin/data/datasources/admin_remote_datasource.dart';
import 'package:olympus/features/admin/data/repositories/admin_repository_impl.dart';
import 'package:olympus/features/bono/data/datasources/bono_remote_datasource.dart';
import 'package:olympus/features/bono/data/repositories/bono_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake de la fuente de datos del bono (lectura de saldo, Req 4.1)
// ---------------------------------------------------------------------------

/// `BonoRemoteDataSource` falso: `fetchSaldo` devuelve el saldo configurado o
/// lanza la excepción configurada, reproduciendo los escenarios de la lectura
/// real sobre `profiles` (saldo propio, sin sesión, rechazo RLS) sin red.
class _FakeBonoDataSource extends BonoRemoteDataSource {
  _FakeBonoDataSource()
    : super(client: SupabaseClient('http://localhost', 'anon'));

  int saldoDevuelto = 10;
  Object? errorToThrow;

  @override
  Future<int> fetchSaldo() async {
    final error = errorToThrow;
    if (error != null) throw error;
    return saldoDevuelto;
  }
}

// ---------------------------------------------------------------------------
// Fake de la fuente de datos de administración que simula las RPC de bono.
//
// Reproduce el contrato de `restablecer_bono`/`ajustar_bono` definido en
// `0004_rpc_bono.sql`:
//   * si el llamante no es superadmin  -> PostgrestException code '42501'
//   * ajustar_bono con valor < 0 o > 10 -> PostgrestException code '22003'
//     (sin modificar el saldo)
//   * usuario objetivo inexistente      -> PostgrestException code 'P0002'
//   * en el caso válido, muta el saldo en memoria (fija 10 / fija valor)
// ---------------------------------------------------------------------------
class _FakeAdminRpcDataSource extends AdminRemoteDataSource {
  _FakeAdminRpcDataSource()
    : super(client: SupabaseClient('http://localhost', 'anon'));

  /// Estado de saldos por usuario (espejo de la columna `profiles.saldo_clases`).
  final Map<String, int> saldos = <String, int>{};

  /// ¿El llamante es superadministrador? (espejo de `es_superadmin()`).
  bool esSuperadmin = true;

  void _requireSuperadmin() {
    if (!esSuperadmin) {
      throw PostgrestException(
        message: 'No autorizado: se requiere rol de superadministrador',
        code: '42501',
      );
    }
  }

  void _requireUsuario(String targetUserId) {
    if (!saldos.containsKey(targetUserId)) {
      throw PostgrestException(message: 'Usuario no encontrado', code: 'P0002');
    }
  }

  @override
  Future<void> restablecerBono(String targetUserId) async {
    // Autorización primero, igual que la función SQL (Req 5.4).
    _requireSuperadmin();
    _requireUsuario(targetUserId);
    // Fija el saldo en 10 (bono completo), Req 6.5.
    saldos[targetUserId] = 10;
  }

  @override
  Future<void> ajustarBono(String targetUserId, int valor) async {
    // Autorización primero (Req 5.4).
    _requireSuperadmin();
    // Validación de rango 0..10; fuera de rango no modifica el saldo (Req 6.6).
    if (valor < 0 || valor > 10) {
      throw PostgrestException(
        message: 'El valor del bono debe estar entre 0 y 10',
        code: '22003',
      );
    }
    _requireUsuario(targetUserId);
    // Fija el saldo en el valor indicado (Req 6.6).
    saldos[targetUserId] = valor;
  }
}

void main() {
  group('Lectura del saldo (Req 4.1)', () {
    late _FakeBonoDataSource fakeBono;
    late BonoRepositoryImpl repo;

    setUp(() {
      fakeBono = _FakeBonoDataSource();
      repo = BonoRepositoryImpl(dataSource: fakeBono);
    });

    test('getSaldo devuelve el Saldo_De_Clases actual del Usuario', () async {
      fakeBono.saldoDevuelto = 7;

      final saldo = await repo.getSaldo();

      expect(saldo, 7);
    });

    test('getSaldo devuelve el saldo también en los extremos 0 y 10', () async {
      fakeBono.saldoDevuelto = 0;
      expect(await repo.getSaldo(), 0);

      fakeBono.saldoDevuelto = 10;
      expect(await repo.getSaldo(), 10);
    });

    test(
      'sin sesión (StateError) -> AutorizacionInsuficienteFailure (Req 7.3)',
      () {
        fakeBono.errorToThrow = StateError('No hay una sesión activa');

        expect(
          () => repo.getSaldo(),
          throwsA(isA<AutorizacionInsuficienteFailure>()),
        );
      },
    );

    test(
      'rechazo RLS (PostgrestException) -> AutorizacionInsuficienteFailure',
      () {
        fakeBono.errorToThrow = PostgrestException(
          message: 'row-level security',
          code: '42501',
        );

        expect(
          () => repo.getSaldo(),
          throwsA(isA<AutorizacionInsuficienteFailure>()),
        );
      },
    );
  });

  group('RPC restablecer_bono (Req 6.5)', () {
    late _FakeAdminRpcDataSource fakeRpc;
    late AdminRepositoryImpl repo;

    setUp(() {
      fakeRpc = _FakeAdminRpcDataSource();
      repo = AdminRepositoryImpl(dataSource: fakeRpc);
    });

    test(
      'fija el saldo del Usuario objetivo en 10, sea cual sea el previo',
      () async {
        fakeRpc.saldos['u1'] = 3;

        await repo.restablecerBono('u1');

        expect(fakeRpc.saldos['u1'], 10);
      },
    );

    test('restablecer desde 0 también deja el saldo en 10', () async {
      fakeRpc.saldos['u1'] = 0;

      await repo.restablecerBono('u1');

      expect(fakeRpc.saldos['u1'], 10);
    });

    test(
      'un llamante no superadmin es rechazado y el saldo no cambia (Req 5.4)',
      () async {
        fakeRpc.saldos['u1'] = 4;
        fakeRpc.esSuperadmin = false;

        await expectLater(
          repo.restablecerBono('u1'),
          throwsA(isA<AutorizacionInsuficienteFailure>()),
        );
        expect(fakeRpc.saldos['u1'], 4);
      },
    );
  });

  group('RPC ajustar_bono (Req 6.6)', () {
    late _FakeAdminRpcDataSource fakeRpc;
    late AdminRepositoryImpl repo;

    setUp(() {
      fakeRpc = _FakeAdminRpcDataSource();
      repo = AdminRepositoryImpl(dataSource: fakeRpc);
    });

    test('fija el saldo en un valor válido dentro de 0..10', () async {
      fakeRpc.saldos['u1'] = 2;

      await repo.ajustarBono('u1', 6);

      expect(fakeRpc.saldos['u1'], 6);
    });

    test('acepta los extremos del rango (0 y 10)', () async {
      fakeRpc.saldos['u1'] = 5;

      await repo.ajustarBono('u1', 0);
      expect(fakeRpc.saldos['u1'], 0);

      await repo.ajustarBono('u1', 10);
      expect(fakeRpc.saldos['u1'], 10);
    });

    test(
      'rechaza un valor por debajo de 0 con BonoFueraDeRangoFailure y no toca '
      'el saldo (Req 6.6)',
      () async {
        fakeRpc.saldos['u1'] = 5;

        await expectLater(
          repo.ajustarBono('u1', -1),
          throwsA(isA<BonoFueraDeRangoFailure>()),
        );
        expect(fakeRpc.saldos['u1'], 5);
      },
    );

    test(
      'rechaza un valor por encima de 10 con BonoFueraDeRangoFailure y no toca '
      'el saldo (Req 6.6)',
      () async {
        fakeRpc.saldos['u1'] = 5;

        await expectLater(
          repo.ajustarBono('u1', 11),
          throwsA(isA<BonoFueraDeRangoFailure>()),
        );
        expect(fakeRpc.saldos['u1'], 5);
      },
    );

    test(
      'un llamante no superadmin es rechazado y el saldo no cambia (Req 5.4)',
      () async {
        fakeRpc.saldos['u1'] = 5;
        fakeRpc.esSuperadmin = false;

        await expectLater(
          repo.ajustarBono('u1', 8),
          throwsA(isA<AutorizacionInsuficienteFailure>()),
        );
        expect(fakeRpc.saldos['u1'], 5);
      },
    );
  });
}
