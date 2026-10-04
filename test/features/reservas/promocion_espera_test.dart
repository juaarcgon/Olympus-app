// Prueba de propiedad del modelo puro de reservas.
//
// Feature: gym-management-app, Property 27
//
// Property 27: Al liberarse una plaza se promociona al primero de la espera
// con saldo > 0 y se descuenta 1.
// "Para cualquier clase con la lista de espera no vacía en la que se libera una
//  plaza, el primer usuario de la lista (FIFO) con saldo_clases > 0 pasa a
//  Reserva_Confirmada y su saldo_clases se reduce en exactamente 1."
//
// Validates: Requirements 8.9
//
// La propiedad se verifica contra el modelo de dominio puro de reservas
// (`ReservasEstado.cancelar`), espejo de la RPC `cancelar_reserva` del backend,
// usando `glados` con un mínimo de 100 iteraciones. Cada iteración genera una
// clase con el aforo completo (incluido un usuario cancelante) y una lista de
// espera FIFO no vacía cuyos usuarios tienen saldos arbitrarios (0..10),
// mezclando usuarios con saldo 0 y con saldo > 0. Al cancelar el usuario
// confirmado (que libera una plaza), comprueba que:
//   - si existe algún usuario en espera con saldo > 0, se promociona
//     exactamente al PRIMER usuario FIFO con saldo > 0 (Req 8.9), saltando
//     los usuarios iniciales con saldo 0,
//   - el promocionado pasa a Reserva_Confirmada y abandona la lista de espera,
//   - su saldo se reduce en exactamente 1,
//   - los usuarios con saldo 0 situados antes del promocionado NO se promocionan
//     y permanecen en espera con su saldo intacto,
//   - si ningún usuario en espera tiene saldo > 0, no hay promoción alguna.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';

/// Escenario de promoción desde la lista de espera al liberarse una plaza.
///
/// Modela la precondición de la propiedad: `aforo` es el aforo de la Clase
/// (1..10); la Clase está llena (todas las plazas confirmadas, una de ellas
/// del usuario cancelante); `saldosEspera` son los saldos (0..10) de los
/// usuarios de la lista de espera, en estricto orden FIFO. Al menos un usuario
/// en espera está siempre presente (lista no vacía). `antelacionHoras` cubre
/// ambos lados del umbral de 2h; no afecta a la promoción pero se varía para
/// ejercitar la operación completa de cancelación.
class _EscenarioPromocion {
  const _EscenarioPromocion(
    this.aforo,
    this.saldosEspera,
    this.antelacionHoras,
  );

  final int aforo;
  final List<int> saldosEspera;
  final int antelacionHoras;

  @override
  String toString() =>
      '_EscenarioPromocion(aforo: $aforo, saldosEspera: $saldosEspera, '
      'antelacionHoras: $antelacionHoras)';
}

/// Generador de escenarios de promoción.
///
/// - `aforo` en 1..kAforoMax (10).
/// - `saldosEspera`: lista no vacía (1..kWaitlistMax entradas) de saldos en
///   kBonoMin..kBonoMax (0..10), de modo que se mezclen usuarios con saldo 0 y
///   con saldo > 0, incluyendo prefijos de ceros para ejercitar el salto FIFO.
/// - `antelacionHoras` en 0..5, cubriendo ambos lados del umbral de
///   kCancelacionHoras (2).
Generator<_EscenarioPromocion> get _anyEscenarioPromocion => any
    .intInRange(1, kAforoMax + 1)
    .bind(
      (aforo) => any
          .listWithLengthInRange(
            1,
            kWaitlistMax,
            any.intInRange(kBonoMin, kBonoMax + 1),
          )
          .bind(
            (saldosEspera) => any
                .intInRange(0, 6)
                .map(
                  (antelacion) =>
                      _EscenarioPromocion(aforo, saldosEspera, antelacion),
                ),
          ),
    );

void main() {
  group('Feature: gym-management-app, Property 27 - al liberar plaza se '
      'promociona al primero de la espera con saldo > 0 y se descuenta 1', () {
    Glados(
      _anyEscenarioPromocion,
    ).test('cancelar una reserva confirmada promociona al primer usuario FIFO '
        'con saldo > 0 descontándole exactamente 1 (Req 8.9)', (escenario) {
      // La Clase está llena: el cancelante ocupa la primera plaza y el resto
      // se completa con ocupantes de relleno (saldo máximo, irrelevante aquí).
      const cancelante = 'cancelante';
      final otrosOcupantes = List.generate(
        escenario.aforo - 1,
        (i) => 'ocupante$i',
      );
      final confirmadas = <String>[cancelante, ...otrosOcupantes];

      // Lista de espera FIFO: un usuario por cada saldo generado, en orden.
      final espera = List.generate(
        escenario.saldosEspera.length,
        (i) => 'espera$i',
      );

      final saldos = <String, int>{
        cancelante: kBonoMax,
        for (final id in otrosOcupantes) id: kBonoMax,
        for (var i = 0; i < espera.length; i++)
          espera[i]: escenario.saldosEspera[i],
      };

      final estado = ReservasEstado(
        aforo: escenario.aforo,
        saldos: saldos,
        confirmadas: confirmadas,
        espera: espera,
      );

      // Precondiciones: aforo completo, cancelante confirmado y espera no vacía.
      expect(estado.aforoCompleto, isTrue);
      expect(estado.confirmadas, contains(cancelante));
      expect(estado.espera, isNotEmpty);

      final res = estado.cancelar(
        cancelante,
        antelacionHoras: escenario.antelacionHoras,
      );

      // La plaza del cancelante siempre se libera.
      expect(res.liberoPlaza, isTrue);
      expect(res.estado.confirmadas, isNot(contains(cancelante)));

      // Índice del primer usuario FIFO con saldo > 0, o -1 si no hay ninguno.
      final indiceEsperado = escenario.saldosEspera.indexWhere((s) => s > 0);

      if (indiceEsperado == -1) {
        // Ningún usuario en espera tiene saldo > 0: no hay promoción (Req 8.9).
        expect(
          res.promocionado,
          isNull,
          reason:
              'sin usuarios con saldo > 0 en espera no debe haber promoción',
        );
        // La lista de espera permanece intacta y nadie entra a confirmadas.
        expect(res.estado.espera, equals(espera));
        for (var i = 0; i < espera.length; i++) {
          expect(res.estado.saldoDe(espera[i]), escenario.saldosEspera[i]);
        }
        return;
      }

      final promocionadoEsperado = espera[indiceEsperado];

      // Se promociona exactamente al primer usuario FIFO con saldo > 0.
      expect(
        res.promocionado,
        promocionadoEsperado,
        reason:
            'debe promocionarse el primer usuario FIFO con saldo > 0 '
            '(índice $indiceEsperado)',
      );

      // El promocionado pasa a Reserva_Confirmada y abandona la espera.
      expect(res.estado.confirmadas, contains(promocionadoEsperado));
      expect(res.estado.espera, isNot(contains(promocionadoEsperado)));

      // Su saldo se reduce en exactamente 1 (Req 8.9).
      expect(
        res.estado.saldoDe(promocionadoEsperado),
        escenario.saldosEspera[indiceEsperado] - 1,
        reason: 'el saldo del promocionado debe reducirse en exactamente 1',
      );

      // Los usuarios con saldo 0 anteriores (prefijo FIFO) NO se promocionan y
      // permanecen en espera con su saldo intacto (0).
      for (var i = 0; i < indiceEsperado; i++) {
        final anterior = espera[i];
        expect(
          res.estado.espera,
          contains(anterior),
          reason: 'un usuario con saldo 0 anterior no debe promocionarse',
        );
        expect(res.estado.confirmadas, isNot(contains(anterior)));
        expect(res.estado.saldoDe(anterior), 0);
      }
    });
  });
}
