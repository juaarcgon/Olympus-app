// Pruebas del Servicio_Reservas (ReservasRepositoryImpl).
//
// Verifican el mapeo de filas de `clases` a [Clase], el mapeo del jsonb de la
// RPC `reservar_clase` a [ReservaResult] y la traducción de las excepciones del
// SDK a `Failure` de dominio (Req 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.12).
//
// Se usa una fuente de datos falsa (sin red) que sustituye a Supabase y permite
// inyectar filas, jsonb y excepciones [PostgrestException] arbitrarias.

import 'package:flutter_test/flutter_test.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/reservas/data/datasources/reservas_remote_datasource.dart';
import 'package:olympus/features/reservas/data/repositories/reservas_repository_impl.dart';
import 'package:olympus/features/reservas/domain/entities/entities.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fuente de datos falsa: todas las operaciones devuelven lo configurado o
/// lanzan la excepción configurada, sin contactar con Supabase.
class _FakeDataSource extends ReservasRemoteDataSource {
  _FakeDataSource() : super(client: SupabaseClient('http://localhost', 'anon'));

  List<Map<String, dynamic>> calendario = <Map<String, dynamic>>[];
  Map<String, dynamic> claseRow = <String, dynamic>{};
  Map<String, dynamic> reservarJson = <String, dynamic>{};

  Object? errorToThrow;

  // Registro de llamadas para aserciones.
  DateTime? desdeRecibido;
  DateTime? hastaRecibido;
  Map<String, dynamic>? cambiosRecibidos;
  String? claseIdRecibido;
  bool eliminarLlamado = false;
  bool cancelarLlamado = false;

  void _maybeThrow() {
    final error = errorToThrow;
    if (error != null) throw error;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCalendario({
    DateTime? desde,
    DateTime? hasta,
  }) async {
    desdeRecibido = desde;
    hastaRecibido = hasta;
    _maybeThrow();
    return calendario;
  }

  @override
  Future<Map<String, dynamic>> insertClase({
    required DateTime horario,
    required int aforo,
    required String monitor,
  }) async {
    _maybeThrow();
    return claseRow;
  }

  @override
  Future<Map<String, dynamic>> updateClase(
    String claseId,
    Map<String, dynamic> cambios,
  ) async {
    claseIdRecibido = claseId;
    cambiosRecibidos = cambios;
    _maybeThrow();
    return claseRow;
  }

  @override
  Future<void> deleteClase(String claseId) async {
    claseIdRecibido = claseId;
    eliminarLlamado = true;
    _maybeThrow();
  }

  @override
  Future<Map<String, dynamic>> reservarClase(String claseId) async {
    claseIdRecibido = claseId;
    _maybeThrow();
    return reservarJson;
  }

  @override
  Future<void> cancelarReserva(String claseId) async {
    claseIdRecibido = claseId;
    cancelarLlamado = true;
    _maybeThrow();
  }
}

PostgrestException _pgError(String message, {String? code}) =>
    PostgrestException(message: message, code: code);

Map<String, dynamic> _claseRow({
  String id = 'c1',
  String horario = '2025-01-15T18:00:00.000Z',
  int aforo = 5,
  String monitor = 'Ana',
  String? createdBy = 'sa1',
  String? createdAt = '2025-01-01T00:00:00.000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'horario': horario,
    'aforo': aforo,
    'monitor': monitor,
    'created_by': createdBy,
    'created_at': createdAt,
  };
}

void main() {
  late _FakeDataSource fake;
  late ReservasRepositoryImpl repo;

  setUp(() {
    fake = _FakeDataSource();
    repo = ReservasRepositoryImpl(dataSource: fake);
  });

  group('getCalendario', () {
    test('mapea filas a Clase y preserva el orden (Req 8.1)', () async {
      fake.calendario = [
        _claseRow(id: 'c1', horario: '2025-01-15T18:00:00.000Z'),
        _claseRow(id: 'c2', horario: '2025-01-16T18:00:00.000Z', aforo: 10),
      ];

      final clases = await repo.getCalendario();

      expect(clases, hasLength(2));
      expect(clases.first.id, 'c1');
      expect(clases.first.aforo, 5);
      expect(clases.first.monitor, 'Ana');
      expect(clases[1].id, 'c2');
      expect(clases[1].aforo, 10);
    });

    test('propaga el rango de fechas a la fuente de datos (Req 8.1)', () async {
      final desde = DateTime.utc(2025, 1, 1);
      final hasta = DateTime.utc(2025, 1, 31);

      await repo.getCalendario(desde: desde, hasta: hasta);

      expect(fake.desdeRecibido, desde);
      expect(fake.hastaRecibido, hasta);
    });

    test('traduce PostgrestException a AutorizacionInsuficienteFailure', () {
      fake.errorToThrow = _pgError('jwt expired', code: 'PGRST301');

      expect(
        () => repo.getCalendario(),
        throwsA(isA<AutorizacionInsuficienteFailure>()),
      );
    });
  });

  group('crearClase', () {
    test('devuelve la Clase creada mapeada (Req 8.1)', () async {
      fake.claseRow = _claseRow(id: 'nueva', monitor: 'Luis');

      final clase = await repo.crearClase(
        horario: DateTime.utc(2025, 2, 1, 10),
        aforo: 8,
        monitor: 'Luis',
      );

      expect(clase.id, 'nueva');
      expect(clase.monitor, 'Luis');
    });

    test(
      'un no superadmin (RLS) produce AutorizacionInsuficienteFailure (Req 8.2)',
      () {
        fake.errorToThrow = _pgError(
          'new row violates row-level security policy',
          code: '42501',
        );

        expect(
          () => repo.crearClase(
            horario: DateTime.utc(2025, 2, 1, 10),
            aforo: 8,
            monitor: 'Luis',
          ),
          throwsA(isA<AutorizacionInsuficienteFailure>()),
        );
      },
    );
  });

  group('editarClase', () {
    test('solo envía los campos no nulos y mapea el resultado', () async {
      fake.claseRow = _claseRow(id: 'c1', aforo: 6);

      final clase = await repo.editarClase('c1', aforo: 6);

      expect(clase.aforo, 6);
      expect(fake.claseIdRecibido, 'c1');
      expect(fake.cambiosRecibidos, {'aforo': 6});
    });

    test(
      'RLS sobre no superadmin produce AutorizacionInsuficienteFailure (Req 8.2)',
      () {
        fake.errorToThrow = _pgError('rls', code: '42501');

        expect(
          () => repo.editarClase('c1', monitor: 'X'),
          throwsA(isA<AutorizacionInsuficienteFailure>()),
        );
      },
    );
  });

  group('eliminarClase', () {
    test('invoca la fuente de datos con el id (Req 8.1)', () async {
      await repo.eliminarClase('c9');

      expect(fake.eliminarLlamado, isTrue);
      expect(fake.claseIdRecibido, 'c9');
    });

    test(
      'RLS sobre no superadmin produce AutorizacionInsuficienteFailure (Req 8.2)',
      () {
        fake.errorToThrow = _pgError('rls', code: '42501');

        expect(
          () => repo.eliminarClase('c9'),
          throwsA(isA<AutorizacionInsuficienteFailure>()),
        );
      },
    );
  });

  group('reservar', () {
    test(
      'mapea status=confirmada a ReservaResult confirmada (Req 8.3)',
      () async {
        fake.reservarJson = {
          'status': 'confirmada',
          'posicion': null,
          'saldo_resultante': 4,
        };

        final res = await repo.reservar('c1');

        expect(res.outcome, ReservaOutcome.confirmada);
        expect(res.esConfirmada, isTrue);
        expect(res.saldoResultante, 4);
        expect(res.posicion, isNull);
      },
    );

    test(
      'mapea status=espera a ReservaResult en espera con posición (Req 8.5)',
      () async {
        fake.reservarJson = {
          'status': 'espera',
          'posicion': 3,
          'saldo_resultante': 7,
        };

        final res = await repo.reservar('c1');

        expect(res.outcome, ReservaOutcome.enEspera);
        expect(res.enEspera, isTrue);
        expect(res.posicion, 3);
        expect(res.saldoResultante, 7);
      },
    );

    test('saldo 0 -> SinClasesFailure (Req 8.4)', () {
      fake.errorToThrow = _pgError(
        'No quedan clases disponibles en tu bono',
        code: 'P0001',
      );

      expect(() => repo.reservar('c1'), throwsA(isA<SinClasesFailure>()));
    });

    test('duplicado -> ReservaDuplicadaFailure (Req 8.6)', () {
      fake.errorToThrow = _pgError(
        'Ya existe una reserva para esta clase',
        code: 'P0001',
      );

      expect(
        () => repo.reservar('c1'),
        throwsA(isA<ReservaDuplicadaFailure>()),
      );
    });

    test('lista de espera llena -> ListaEsperaLlenaFailure (Req 8.12)', () {
      fake.errorToThrow = _pgError(
        'La lista de espera está completa',
        code: 'P0001',
      );

      expect(
        () => repo.reservar('c1'),
        throwsA(isA<ListaEsperaLlenaFailure>()),
      );
    });

    test('sin sesión (42501) -> AutorizacionInsuficienteFailure (Req 7.3)', () {
      fake.errorToThrow = _pgError(
        'No autenticado: se requiere una sesion activa',
        code: '42501',
      );

      expect(
        () => repo.reservar('c1'),
        throwsA(isA<AutorizacionInsuficienteFailure>()),
      );
    });

    test('clase no encontrada (P0002) -> SinClasesFailure', () {
      fake.errorToThrow = _pgError('Clase no encontrada', code: 'P0002');

      expect(() => repo.reservar('c1'), throwsA(isA<SinClasesFailure>()));
    });
  });

  group('cancelar', () {
    test('invoca la RPC de cancelación con el id (Req 8.7)', () async {
      await repo.cancelar('c1');

      expect(fake.cancelarLlamado, isTrue);
      expect(fake.claseIdRecibido, 'c1');
    });

    test('sin sesión (42501) -> AutorizacionInsuficienteFailure (Req 7.3)', () {
      fake.errorToThrow = _pgError('no auth', code: '42501');

      expect(
        () => repo.cancelar('c1'),
        throwsA(isA<AutorizacionInsuficienteFailure>()),
      );
    });
  });
}
