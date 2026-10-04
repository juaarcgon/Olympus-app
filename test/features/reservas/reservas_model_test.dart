import 'package:flutter_test/flutter_test.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/reservas/domain/entities/entities.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';

/// Crea un estado base con el aforo y saldos indicados.
ReservasEstado estadoBase({
  int aforo = 2,
  Map<String, int>? saldos,
  List<String> confirmadas = const <String>[],
  List<String> espera = const <String>[],
}) {
  return ReservasEstado(
    aforo: aforo,
    saldos: saldos ?? const {'u1': 10, 'u2': 10, 'u3': 10},
    confirmadas: confirmadas,
    espera: espera,
  );
}

void main() {
  group('reservar', () {
    test(
      'con aforo libre y saldo > 0 crea confirmada y descuenta 1 (Req 8.3)',
      () {
        final estado = estadoBase(aforo: 2, saldos: {'u1': 5});
        final res = estado.reservar('u1');

        expect(res.esExito, isTrue);
        expect(res.resultado!.outcome, ReservaOutcome.confirmada);
        expect(res.resultado!.saldoResultante, 4);
        expect(res.estado.confirmadas, ['u1']);
        expect(res.estado.saldoDe('u1'), 4);
        // El estado original no se muta.
        expect(estado.confirmadas, isEmpty);
        expect(estado.saldoDe('u1'), 5);
      },
    );

    test('con saldo 0 se rechaza sin reserva ni espera (Req 8.4)', () {
      final estado = estadoBase(aforo: 2, saldos: {'u1': 0});
      final res = estado.reservar('u1');

      expect(res.esExito, isFalse);
      expect(res.failure, isA<SinClasesFailure>());
      expect(res.estado.confirmadas, isEmpty);
      expect(res.estado.espera, isEmpty);
    });

    test(
      'con aforo lleno y espera < 20 añade al final FIFO sin tocar saldo (Req 8.5)',
      () {
        final estado = estadoBase(
          aforo: 1,
          saldos: {'u1': 3, 'u2': 7},
          confirmadas: ['u1'],
        );
        final res = estado.reservar('u2');

        expect(res.esExito, isTrue);
        expect(res.resultado!.outcome, ReservaOutcome.enEspera);
        expect(res.resultado!.posicion, 1);
        expect(res.resultado!.saldoResultante, 7); // saldo intacto
        expect(res.estado.espera, ['u2']);
        expect(res.estado.saldoDe('u2'), 7);
      },
    );

    test('respeta el orden FIFO al añadir varios a la espera (Req 8.5)', () {
      var estado = estadoBase(
        aforo: 1,
        saldos: {'u1': 5, 'u2': 5, 'u3': 5},
        confirmadas: ['u1'],
      );
      estado = estado.reservar('u2').estado;
      estado = estado.reservar('u3').estado;

      expect(estado.espera, ['u2', 'u3']);
      expect(estado.posicionEspera('u2'), 1);
      expect(estado.posicionEspera('u3'), 2);
    });

    test('rechaza duplicado si ya está confirmado (Req 8.6)', () {
      final estado = estadoBase(
        aforo: 2,
        saldos: {'u1': 5},
        confirmadas: ['u1'],
      );
      final res = estado.reservar('u1');

      expect(res.failure, isA<ReservaDuplicadaFailure>());
      expect(res.estado.confirmadas, ['u1']); // sin duplicar
    });

    test('rechaza duplicado si ya está en espera (Req 8.6)', () {
      final estado = estadoBase(
        aforo: 1,
        saldos: {'u1': 5, 'u2': 5},
        confirmadas: ['u1'],
        espera: ['u2'],
      );
      final res = estado.reservar('u2');

      expect(res.failure, isA<ReservaDuplicadaFailure>());
      expect(res.estado.espera, ['u2']); // sin duplicar
    });

    test('rechaza cuando la lista de espera está llena (20) (Req 8.12)', () {
      final espera = List.generate(20, (i) => 'w$i');
      final saldos = {for (final id in espera) id: 5, 'u1': 5, 'nuevo': 5};
      final estado = ReservasEstado(
        aforo: 1,
        saldos: saldos,
        confirmadas: ['u1'],
        espera: espera,
      );
      final res = estado.reservar('nuevo');

      expect(res.failure, isA<ListaEsperaLlenaFailure>());
      expect(res.estado.espera.length, 20);
    });
  });

  group('cancelar', () {
    test('con antelación >= 2h libera plaza y reembolsa 1 (Req 8.7)', () {
      final estado = estadoBase(
        aforo: 2,
        saldos: {'u1': 4},
        confirmadas: ['u1'],
      );
      final res = estado.cancelar('u1', antelacionHoras: 2);

      expect(res.liberoPlaza, isTrue);
      expect(res.huboReembolso, isTrue);
      expect(res.estado.confirmadas, isEmpty);
      expect(res.estado.saldoDe('u1'), 5);
    });

    test('con antelación < 2h libera plaza sin reembolso (Req 8.8)', () {
      final estado = estadoBase(
        aforo: 2,
        saldos: {'u1': 4},
        confirmadas: ['u1'],
      );
      final res = estado.cancelar('u1', antelacionHoras: 1);

      expect(res.liberoPlaza, isTrue);
      expect(res.huboReembolso, isFalse);
      expect(res.estado.saldoDe('u1'), 4); // sin cambios
    });

    test(
      'promociona al primero de la espera con saldo > 0 y descuenta 1 (Req 8.9)',
      () {
        final estado = estadoBase(
          aforo: 1,
          saldos: {'u1': 3, 'u2': 6, 'u3': 6},
          confirmadas: ['u1'],
          espera: ['u2', 'u3'],
        );
        final res = estado.cancelar('u1', antelacionHoras: 5);

        expect(res.promocionado, 'u2');
        expect(res.estado.confirmadas, contains('u2'));
        expect(res.estado.espera, ['u3']);
        expect(res.estado.saldoDe('u2'), 5); // 6 - 1
      },
    );

    test(
      'salta a usuarios de la espera con saldo 0 al promocionar (Req 8.9)',
      () {
        final estado = estadoBase(
          aforo: 1,
          saldos: {'u1': 3, 'u2': 0, 'u3': 4},
          confirmadas: ['u1'],
          espera: ['u2', 'u3'],
        );
        final res = estado.cancelar('u1', antelacionHoras: 5);

        expect(res.promocionado, 'u3');
        expect(res.estado.confirmadas, contains('u3'));
        expect(res.estado.espera, ['u2']); // u2 permanece en espera
        expect(res.estado.saldoDe('u3'), 3);
      },
    );

    test('no promociona si nadie en espera tiene saldo (Req 8.9)', () {
      final estado = estadoBase(
        aforo: 1,
        saldos: {'u1': 3, 'u2': 0},
        confirmadas: ['u1'],
        espera: ['u2'],
      );
      final res = estado.cancelar('u1', antelacionHoras: 5);

      expect(res.promocionado, isNull);
      expect(res.estado.confirmadas, isEmpty);
      expect(res.estado.espera, ['u2']);
    });

    test(
      'cancelar estando en espera elimina la entrada sin tocar saldo (Req 8.11)',
      () {
        final estado = estadoBase(
          aforo: 1,
          saldos: {'u1': 5, 'u2': 7},
          confirmadas: ['u1'],
          espera: ['u2'],
        );
        final res = estado.cancelar('u2', antelacionHoras: 10);

        expect(res.liberoPlaza, isFalse);
        expect(res.huboReembolso, isFalse);
        expect(res.estado.espera, isEmpty);
        expect(res.estado.confirmadas, ['u1']); // sin cambios
        expect(res.estado.saldoDe('u2'), 7); // sin cambios
      },
    );

    test('el reembolso respeta el límite superior del saldo (Req 8.10)', () {
      final estado = estadoBase(
        aforo: 2,
        saldos: {'u1': 10},
        confirmadas: ['u1'],
      );
      final res = estado.cancelar('u1', antelacionHoras: 3);

      expect(res.estado.saldoDe('u1'), 10); // clamp a 10
    });
  });
}
