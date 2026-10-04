// Prueba de propiedad del modelo puro de reservas.
//
// Feature: gym-management-app, Property 28
//
// Property 28: Cancelar estando en lista de espera no afecta al saldo.
// "Para cualquier usuario que figura en la Lista_De_Espera de una Clase,
//  cancelar su solicitud elimina su entrada de la Lista_De_Espera de esa Clase
//  y deja su saldo_clases sin cambios."
//
// Validates: Requirements 8.11
//
// La propiedad se verifica contra el modelo de dominio puro de reservas
// (`ReservasEstado.cancelar`), espejo de la RPC `cancelar_reserva` del backend,
// usando `glados` con un mínimo de 100 iteraciones. Cada iteración genera una
// clase con el aforo completo (para justificar la existencia de la espera), una
// lista de espera previa en la que el usuario cancelante ocupa una posición
// arbitraria entre otras entradas, y un saldo inicial arbitrario (0..10,
// incluyendo los extremos). Comprueba que `cancelar`:
//   - no libera plaza confirmada (el usuario estaba en espera, no confirmado),
//   - no reembolsa clase alguna,
//   - elimina al usuario de la Lista_De_Espera preservando el orden FIFO del
//     resto,
//   - deja el saldo_clases del cancelante EXACTAMENTE igual (Req 8.11).

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';

/// Escenario de cancelación de una entrada en lista de espera.
///
/// Modela la precondición de la propiedad: `aforo` es el aforo de la Clase
/// (1..10), que se asume completo para justificar la existencia de la espera;
/// `enEsperaPrevia` es el número total de entradas en la lista de espera
/// (1..20, al menos la del cancelante); `posicionCancelante` es el índice
/// (0-indexado, 0..enEsperaPrevia-1) que ocupa el usuario cancelante dentro de
/// la espera; `saldoInicial` es su saldo antes de cancelar (0..10, incluyendo
/// ambos extremos).
class _EscenarioEspera {
  const _EscenarioEspera(
    this.aforo,
    this.enEsperaPrevia,
    this.posicionCancelante,
    this.saldoInicial,
  );

  final int aforo;
  final int enEsperaPrevia;
  final int posicionCancelante;
  final int saldoInicial;

  @override
  String toString() =>
      '_EscenarioEspera(aforo: $aforo, enEsperaPrevia: $enEsperaPrevia, '
      'posicionCancelante: $posicionCancelante, saldoInicial: $saldoInicial)';
}

/// Generador de escenarios con el cancelante en la lista de espera.
///
/// - `aforo` en 1..kAforoMax (10).
/// - `enEsperaPrevia` en 1..kWaitlistMax (1..20), garantizando al menos la
///   entrada del cancelante.
/// - `posicionCancelante` en 0..enEsperaPrevia-1, posición arbitraria del
///   cancelante dentro de la espera.
/// - `saldoInicial` en kBonoMin..kBonoMax (0..10), incluyendo ambos extremos.
Generator<_EscenarioEspera> get _anyEscenarioEspera => any
    .intInRange(1, kAforoMax + 1)
    .bind(
      (aforo) => any
          .intInRange(1, kWaitlistMax + 1)
          .bind(
            (enEsperaPrevia) => any
                .intInRange(0, enEsperaPrevia)
                .bind(
                  (posicionCancelante) => any
                      .intInRange(kBonoMin, kBonoMax + 1)
                      .map(
                        (saldoInicial) => _EscenarioEspera(
                          aforo,
                          enEsperaPrevia,
                          posicionCancelante,
                          saldoInicial,
                        ),
                      ),
                ),
          ),
    );

void main() {
  group(
    'Feature: gym-management-app, Property 28 - cancelar estando en lista de '
    'espera no afecta al saldo',
    () {
      Glados(_anyEscenarioEspera).test(
        'para cualquier usuario en la lista de espera, cancelar elimina su '
        'entrada (preservando el FIFO) y deja su saldo_clases sin cambios '
        '(Req 8.11)',
        (escenario) {
          // Clase con aforo completo: tantas confirmadas como aforo.
          final confirmadas = List.generate(
            escenario.aforo,
            (i) => 'ocupante$i',
          );

          // Lista de espera previa en orden FIFO conocido; el cancelante ocupa
          // la posición generada.
          const usuario = 'cancelante';
          final esperaPrevia = List.generate(
            escenario.enEsperaPrevia,
            (i) => i == escenario.posicionCancelante ? usuario : 'espera$i',
          );

          // Saldos arbitrarios para ocupantes y resto de la espera; el usuario
          // cancelante tiene el saldo generado.
          final saldos = <String, int>{
            for (final id in confirmadas) id: kBonoMax,
            for (final id in esperaPrevia) id: kBonoMax,
            usuario: escenario.saldoInicial,
          };

          final estado = ReservasEstado(
            aforo: escenario.aforo,
            saldos: saldos,
            confirmadas: confirmadas,
            espera: esperaPrevia,
          );

          // Precondición de la propiedad: el usuario está en la espera y no
          // confirmado.
          expect(
            estado.espera,
            contains(usuario),
            reason: 'el usuario debe figurar en la lista de espera',
          );
          expect(
            estado.confirmadas,
            isNot(contains(usuario)),
            reason: 'el usuario no debe tener reserva confirmada',
          );
          final saldoAntes = estado.saldoDe(usuario);

          // La antelación es irrelevante para una entrada en espera; se usa un
          // valor arbitrario para evidenciar que no influye en el saldo.
          final res = estado.cancelar(usuario, antelacionHoras: 5);

          // No se libera plaza (no estaba confirmado) ni hay reembolso.
          expect(
            res.liberoPlaza,
            isFalse,
            reason: 'cancelar una entrada en espera no libera plaza confirmada',
          );
          expect(
            res.huboReembolso,
            isFalse,
            reason: 'cancelar una entrada en espera no reembolsa clases',
          );
          expect(
            res.promocionado,
            isNull,
            reason: 'cancelar en espera no promociona a nadie',
          );

          // Invariante 1 (Property 28 / Req 8.11): la entrada del usuario se
          // elimina de la lista de espera.
          expect(
            res.estado.espera,
            isNot(contains(usuario)),
            reason: 'el usuario debe desaparecer de la lista de espera',
          );
          expect(res.estado.espera.length, esperaPrevia.length - 1);

          // El orden FIFO del resto de la espera se preserva.
          final esperaEsperada = esperaPrevia
              .where((id) => id != usuario)
              .toList();
          expect(
            res.estado.espera,
            orderedEquals(esperaEsperada),
            reason: 'el orden FIFO del resto de la espera se preserva',
          );

          // Invariante central (Property 28 / Req 8.11): el saldo_clases del
          // cancelante permanece EXACTAMENTE igual.
          expect(
            res.estado.saldoDe(usuario),
            saldoAntes,
            reason: 'cancelar estando en espera no debe modificar el saldo',
          );
          // Y continúa dentro del rango permitido (Req 8.10).
          expect(
            res.estado.saldoDe(usuario),
            inInclusiveRange(kBonoMin, kBonoMax),
          );
        },
      );
    },
  );
}
