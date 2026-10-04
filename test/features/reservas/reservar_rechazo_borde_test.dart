// Prueba de propiedad del modelo puro de reservas.
//
// Feature: gym-management-app, Property 30
//
// Property 30: Rechazo de reserva por saldo cero y por lista de espera llena
// (casos borde).
// "Para cualquier usuario con saldo_clases == 0, reservar cualquier clase se
//  rechaza sin crear reserva ni entrada en lista de espera; y para cualquier
//  clase con aforo completo y lista de espera con exactamente veinte (20)
//  entradas, reservar se rechaza con mensaje de lista de espera completa."
//
// Validates: Requirements 4.3, 8.4, 8.12
//
// La propiedad se verifica contra el modelo de dominio puro de reservas
// (`ReservasEstado.reservar`), espejo de la RPC `reservar_clase` del backend,
// usando `glados` con un mínimo de 100 iteraciones por caso borde.
//
// Se cubren los dos casos borde de forma independiente:
//
//   (a) Saldo cero (Req 4.3, 8.4): para cualquier clase (con aforo libre o
//       completo, con la espera en cualquier estado) y cualquier usuario SIN
//       entrada previa cuyo `saldo_clases == 0`, `reservar` se rechaza con
//       `SinClasesFailure` ("No quedan clases disponibles en tu bono") y NO
//       crea ni una Reserva_Confirmada ni una entrada en la Lista_De_Espera
//       (confirmadas y espera permanecen idénticas y el saldo sigue en 0).
//
//   (b) Lista de espera llena (Req 8.12): para cualquier clase con el aforo
//       completo y la espera con EXACTAMENTE veinte (20) entradas, y cualquier
//       usuario nuevo con saldo > 0, `reservar` se rechaza con
//       `ListaEsperaLlenaFailure` ("La lista de espera está completa") sin
//       modificar confirmadas, espera ni saldo.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';

/// Escenario del caso borde (a): usuario con saldo cero (Req 4.3, 8.4).
///
/// - `aforo` es el aforo de la Clase (1..10).
/// - `confirmadasPrevias` es el número de Reservas_Confirmadas ya existentes
///   (0..aforo); cuando iguala al aforo la clase está completa, de modo que el
///   rechazo por saldo cero debe tener prioridad frente a entrar en espera.
/// - `enEsperaPrevia` es el número de entradas ya presentes en la espera
///   (0..kWaitlistMax = 0..20), cubriendo también la espera llena.
class _EscenarioSaldoCero {
  const _EscenarioSaldoCero(
    this.aforo,
    this.confirmadasPrevias,
    this.enEsperaPrevia,
  );

  final int aforo;
  final int confirmadasPrevias;
  final int enEsperaPrevia;

  @override
  String toString() =>
      '_EscenarioSaldoCero(aforo: $aforo, '
      'confirmadasPrevias: $confirmadasPrevias, '
      'enEsperaPrevia: $enEsperaPrevia)';
}

/// Generador de escenarios con un usuario de saldo cero sin entrada previa.
///
/// - `aforo` en 1..kAforoMax (10).
/// - `confirmadasPrevias` en 0..aforo (incluye el aforo completo).
/// - `enEsperaPrevia` en 0..kWaitlistMax (0..20, incluye la espera llena).
Generator<_EscenarioSaldoCero> get _anyEscenarioSaldoCero => any
    .intInRange(1, kAforoMax + 1)
    .bind(
      (aforo) => any
          .intInRange(0, aforo + 1)
          .bind(
            (confirmadasPrevias) => any
                .intInRange(0, kWaitlistMax + 1)
                .map(
                  (enEsperaPrevia) => _EscenarioSaldoCero(
                    aforo,
                    confirmadasPrevias,
                    enEsperaPrevia,
                  ),
                ),
          ),
    );

/// Escenario del caso borde (b): aforo completo y espera con 20 entradas.
///
/// - `aforo` es el aforo de la Clase (1..10); al estar completo hay exactamente
///   `aforo` reservas confirmadas.
/// - `saldo` es el saldo del usuario que reserva (1..10, estrictamente > 0),
///   para asegurar que el rechazo se debe a la espera llena y no al saldo.
class _EscenarioEsperaLlena {
  const _EscenarioEsperaLlena(this.aforo, this.saldo);

  final int aforo;
  final int saldo;

  @override
  String toString() => '_EscenarioEsperaLlena(aforo: $aforo, saldo: $saldo)';
}

/// Generador de escenarios con aforo completo y espera llena (20) y saldo > 0.
///
/// - `aforo` en 1..kAforoMax (10).
/// - `saldo` en 1..kBonoMax (10), garantizando `saldo_clases > 0`.
Generator<_EscenarioEsperaLlena> get _anyEscenarioEsperaLlena => any
    .intInRange(1, kAforoMax + 1)
    .bind(
      (aforo) => any
          .intInRange(kBonoMin + 1, kBonoMax + 1)
          .map((saldo) => _EscenarioEsperaLlena(aforo, saldo)),
    );

void main() {
  group(
    'Feature: gym-management-app, Property 30 - rechazo de reserva por saldo '
    'cero y por lista de espera llena (casos borde)',
    () {
      // Caso borde (a): saldo cero (Req 4.3, 8.4).
      Glados(_anyEscenarioSaldoCero).test(
        'para cualquier usuario con saldo_clases == 0, reservar se rechaza con '
        'SinClasesFailure sin crear reserva ni entrada en espera (Req 4.3, '
        '8.4)',
        (escenario) {
          const usuario = 'reservante';

          final confirmadasPrevias = List.generate(
            escenario.confirmadasPrevias,
            (i) => 'confirmado$i',
          );
          final esperaPrevia = List.generate(
            escenario.enEsperaPrevia,
            (i) => 'espera$i',
          );

          // El usuario que reserva tiene saldo CERO; el resto, saldo máximo.
          final saldos = <String, int>{
            for (final id in confirmadasPrevias) id: kBonoMax,
            for (final id in esperaPrevia) id: kBonoMax,
            usuario: 0,
          };

          final estado = ReservasEstado(
            aforo: escenario.aforo,
            saldos: saldos,
            confirmadas: confirmadasPrevias,
            espera: esperaPrevia,
          );

          // Precondiciones de la propiedad.
          expect(
            estado.saldoDe(usuario),
            0,
            reason: 'el usuario debe tener saldo cero',
          );
          expect(
            estado.tieneEntrada(usuario),
            isFalse,
            reason: 'el usuario no debe tener entrada previa',
          );

          final res = estado.reservar(usuario);

          // Invariante central (Req 4.3, 8.4): se rechaza con el mensaje de
          // "sin clases disponibles" sin producir un resultado de reserva.
          expect(
            res.esExito,
            isFalse,
            reason: 'reservar con saldo cero debe rechazarse',
          );
          expect(res.resultado, isNull);
          expect(
            res.failure,
            isA<SinClasesFailure>(),
            reason: 'el fallo debe indicar que no quedan clases (Req 4.3, 8.4)',
          );
          expect(
            res.failure!.mensaje,
            'No quedan clases disponibles en tu bono',
          );

          // No se crea NI reserva confirmada NI entrada en espera: el estado
          // (confirmadas, espera, saldo) permanece idéntico (Req 8.4).
          expect(
            res.estado.confirmadas,
            orderedEquals(confirmadasPrevias),
            reason: 'no debe crearse ninguna reserva confirmada',
          );
          expect(
            res.estado.espera,
            orderedEquals(esperaPrevia),
            reason: 'no debe crearse ninguna entrada en la lista de espera',
          );
          expect(
            res.estado.tieneEntrada(usuario),
            isFalse,
            reason: 'el usuario no debe figurar en la clase tras el rechazo',
          );
          expect(
            res.estado.saldoDe(usuario),
            0,
            reason: 'el saldo del usuario debe seguir siendo cero',
          );
        },
      );

      // Caso borde (b): lista de espera llena con 20 entradas (Req 8.12).
      Glados(_anyEscenarioEsperaLlena).test(
        'para cualquier clase con aforo completo y espera con exactamente 20 '
        'entradas, reservar se rechaza con ListaEsperaLlenaFailure (Req 8.12)',
        (escenario) {
          const usuario = 'reservante';

          // Clase completa: tantas confirmadas como aforo.
          final confirmadas = List.generate(
            escenario.aforo,
            (i) => 'ocupante$i',
          );
          // Lista de espera llena: EXACTAMENTE kWaitlistMax (20) entradas.
          final esperaPrevia = List.generate(kWaitlistMax, (i) => 'espera$i');

          final saldos = <String, int>{
            for (final id in confirmadas) id: kBonoMax,
            for (final id in esperaPrevia) id: kBonoMax,
            usuario: escenario.saldo,
          };

          final estado = ReservasEstado(
            aforo: escenario.aforo,
            saldos: saldos,
            confirmadas: confirmadas,
            espera: esperaPrevia,
          );

          // Precondiciones de la propiedad.
          expect(
            estado.aforoCompleto,
            isTrue,
            reason: 'el escenario debe tener el aforo completo',
          );
          expect(
            estado.espera.length,
            kWaitlistMax,
            reason: 'la espera debe tener exactamente 20 entradas',
          );
          expect(estado.saldoDe(usuario), greaterThan(0));
          expect(
            estado.tieneEntrada(usuario),
            isFalse,
            reason: 'el usuario no debe tener entrada previa',
          );

          final res = estado.reservar(usuario);

          // Invariante central (Req 8.12): se rechaza con el mensaje de lista
          // de espera completa sin producir un resultado de reserva.
          expect(
            res.esExito,
            isFalse,
            reason: 'reservar con la espera llena debe rechazarse',
          );
          expect(res.resultado, isNull);
          expect(
            res.failure,
            isA<ListaEsperaLlenaFailure>(),
            reason: 'el fallo debe indicar que la espera está completa (8.12)',
          );
          expect(res.failure!.mensaje, 'La lista de espera está completa');

          // El estado no cambia: ni confirmadas, ni espera, ni saldo.
          expect(
            res.estado.confirmadas,
            orderedEquals(confirmadas),
            reason: 'las confirmadas no deben cambiar tras el rechazo',
          );
          expect(
            res.estado.espera,
            orderedEquals(esperaPrevia),
            reason: 'la lista de espera no debe cambiar tras el rechazo',
          );
          expect(
            res.estado.tieneEntrada(usuario),
            isFalse,
            reason: 'el usuario no debe figurar en la clase tras el rechazo',
          );
          expect(
            res.estado.saldoDe(usuario),
            escenario.saldo,
            reason: 'el saldo del usuario no debe cambiar tras el rechazo',
          );
        },
      );
    },
  );
}
