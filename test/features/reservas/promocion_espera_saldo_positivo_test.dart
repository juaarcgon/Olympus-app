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
// clase con el aforo completo (hay un usuario cancelante con Reserva_Confirmada)
// y una lista de espera NO vacía cuyos usuarios tienen saldos arbitrarios
// (0..10). Al liberar la plaza del cancelante, comprueba que `cancelar`:
//   - promociona exactamente al PRIMER usuario de la espera (FIFO) con
//     saldo_clases > 0 (saltando a los de saldo cero que lo precedan),
//   - deja a ese usuario como Reserva_Confirmada,
//   - reduce su saldo_clases en exactamente 1,
//   - lo elimina de la lista de espera preservando el orden FIFO del resto,
//   - no promociona a nadie cuando ningún usuario en espera tiene saldo > 0.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';

/// Escenario de liberación de plaza con lista de espera no vacía.
///
/// Modela la precondición de la propiedad: `aforo` es el aforo de la Clase
/// (1..10) y, al estar completo, hay exactamente `aforo` reservas confirmadas
/// (una de ellas la del usuario cancelante). `saldosEspera` son los saldos
/// (0..10) de los usuarios de la Lista_De_Espera en orden FIFO; la lista nunca
/// es vacía (1..kWaitlistMax entradas). `antelacionHoras` cubre ambos lados del
/// umbral de reembolso (0..5): la promoción debe ocurrir con independencia del
/// reembolso del cancelante.
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

/// Generador de escenarios con lista de espera no vacía y saldos arbitrarios.
///
/// - `aforo` en 1..kAforoMax (10).
/// - `saldosEspera`: lista NO vacía (1..kWaitlistMax entradas) de saldos en
///   kBonoMin..kBonoMax (0..10). Incluir ceros intercalados ejercita la regla
///   FIFO "primero con saldo > 0" (se saltan los de saldo cero).
/// - `antelacionHoras` en 0..5, a ambos lados del umbral kCancelacionHoras (2).
Generator<_EscenarioPromocion> get _anyEscenarioPromocion => any
    .intInRange(1, kAforoMax + 1)
    .bind(
      (aforo) => any
          .nonEmptyList(any.intInRange(kBonoMin, kBonoMax + 1))
          .map((saldos) => saldos.take(kWaitlistMax).toList())
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
  group(
    'Feature: gym-management-app, Property 27 - promoción del primero de la '
    'espera con saldo > 0 y descuento 1',
    () {
      Glados(_anyEscenarioPromocion).test(
        'al liberar una plaza con espera no vacía, se promociona al primer '
        'usuario FIFO con saldo > 0 y se le descuenta exactamente 1 (Req 8.9)',
        (escenario) {
          const cancelante = 'cancelante';

          // El aforo está completo: el cancelante ocupa una plaza confirmada y
          // el resto se rellena con ocupantes arbitrarios para completar el
          // aforo.
          final otrosOcupantes = List.generate(
            escenario.aforo - 1,
            (i) => 'ocupante$i',
          );
          final confirmadas = <String>[cancelante, ...otrosOcupantes];

          // Lista de espera en orden FIFO, con saldos del escenario.
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

          // Precondiciones de la propiedad.
          expect(
            estado.aforoCompleto,
            isTrue,
            reason: 'el escenario debe tener el aforo completo',
          );
          expect(
            estado.espera,
            isNotEmpty,
            reason: 'la lista de espera no debe estar vacía',
          );
          expect(estado.confirmadas, contains(cancelante));

          final res = estado.cancelar(
            cancelante,
            antelacionHoras: escenario.antelacionHoras,
          );

          // Liberar la plaza del cancelante siempre ocurre (Req 8.7/8.8).
          expect(
            res.liberoPlaza,
            isTrue,
            reason: 'cancelar una reserva confirmada debe liberar la plaza',
          );

          // Determina, de forma independiente, el candidato esperado: el primer
          // usuario de la espera (orden FIFO) con saldo_clases > 0.
          final indiceEsperado = escenario.saldosEspera.indexWhere(
            (s) => s > 0,
          );

          if (indiceEsperado == -1) {
            // Ningún usuario en espera tiene saldo > 0: no hay promoción.
            expect(
              res.promocionado,
              isNull,
              reason:
                  'no debe promocionarse a nadie si ningún usuario en espera '
                  'tiene saldo > 0',
            );
            // La lista de espera se conserva íntegra (nadie promocionado).
            expect(
              res.estado.espera,
              orderedEquals(espera),
              reason: 'la espera no cambia si no hay candidato con saldo > 0',
            );
            return;
          }

          final promocionadoEsperado = espera[indiceEsperado];
          final saldoAntes = escenario.saldosEspera[indiceEsperado];

          // Invariante central (Property 27 / Req 8.9): se promociona al PRIMER
          // usuario FIFO con saldo > 0.
          expect(
            res.promocionado,
            promocionadoEsperado,
            reason:
                'debe promocionarse el primer usuario FIFO con saldo > 0 '
                '($promocionadoEsperado en la posición ${indiceEsperado + 1})',
          );

          // El promocionado pasa a Reserva_Confirmada.
          expect(
            res.estado.confirmadas,
            contains(promocionadoEsperado),
            reason: 'el promocionado debe quedar como Reserva_Confirmada',
          );

          // Su saldo_clases se reduce en EXACTAMENTE 1.
          expect(
            res.estado.saldoDe(promocionadoEsperado),
            saldoAntes - 1,
            reason:
                'el saldo del promocionado debe reducirse en exactamente 1 '
                '(antes: $saldoAntes)',
          );

          // El promocionado ya no figura en la lista de espera, y el orden FIFO
          // del resto se preserva.
          expect(
            res.estado.espera,
            isNot(contains(promocionadoEsperado)),
            reason: 'el promocionado debe salir de la lista de espera',
          );
          final esperaEsperada = [
            for (var i = 0; i < espera.length; i++)
              if (i != indiceEsperado) espera[i],
          ];
          expect(
            res.estado.espera,
            orderedEquals(esperaEsperada),
            reason: 'el orden FIFO del resto de la espera se preserva',
          );

          // El saldo del promocionado permanece dentro del rango 0..10.
          expect(
            res.estado.saldoDe(promocionadoEsperado),
            inInclusiveRange(kBonoMin, kBonoMax),
          );
        },
      );
    },
  );
}
