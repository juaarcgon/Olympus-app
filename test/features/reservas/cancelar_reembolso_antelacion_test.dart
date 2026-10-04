// Prueba de propiedad del modelo puro de reservas.
//
// Feature: gym-management-app, Property 26
//
// Property 26: El reembolso al cancelar ocurre si y solo si la antelación es
// ≥ 2 horas.
// "Para cualquier reserva confirmada que se cancela, la plaza se libera
//  siempre; el saldo_clases se incrementa en exactamente 1 si la cancelación
//  ocurre con dos (2) horas o más de antelación respecto al Horario_Clase, y
//  permanece inalterado si ocurre con menos de 2 horas."
//
// Validates: Requirements 8.7, 8.8
//
// La propiedad se verifica contra el modelo de dominio puro de reservas
// (`ReservasEstado.cancelar`), espejo de la RPC `cancelar_reserva` del backend,
// usando `glados` con un mínimo de 100 iteraciones. Cada iteración genera una
// clase con un usuario que posee una Reserva_Confirmada, un saldo inicial
// arbitrario (0..10, incluyendo el tope para ejercitar el clamp de Req 8.10) y
// una antelación arbitraria a ambos lados del umbral de 2 horas. Comprueba que
// `cancelar`:
//   - libera siempre la plaza del usuario cancelante (Req 8.7/8.8),
//   - reembolsa exactamente +1 clase si y solo si antelacionHoras >= 2 (Req 8.7),
//   - deja el saldo inalterado si antelacionHoras < 2 (Req 8.8),
//   - respeta el rango 0..10 del saldo (Req 8.10) en el reembolso.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/reservas/domain/reservas_model.dart';

/// Escenario de cancelación de una Reserva_Confirmada.
///
/// Modela la precondición de la propiedad: `aforo` es el aforo de la Clase
/// (1..10); `plazasOcupadas` es el número de Reservas_Confirmadas previas,
/// además de la del usuario cancelante (0..aforo-1); `saldoInicial` es el
/// saldo del cancelante antes de cancelar (0..10, incluyendo el tope para
/// ejercitar el clamp); `antelacionHoras` son las horas hasta el Horario_Clase
/// en el momento de la cancelación (0..5, cubriendo ambos lados del umbral de
/// 2h).
class _EscenarioCancelacion {
  const _EscenarioCancelacion(
    this.aforo,
    this.plazasOcupadas,
    this.saldoInicial,
    this.antelacionHoras,
  );

  final int aforo;
  final int plazasOcupadas;
  final int saldoInicial;
  final int antelacionHoras;

  @override
  String toString() =>
      '_EscenarioCancelacion(aforo: $aforo, plazasOcupadas: $plazasOcupadas, '
      'saldoInicial: $saldoInicial, antelacionHoras: $antelacionHoras)';
}

/// Generador de escenarios de cancelación de una reserva confirmada.
///
/// - `aforo` en 1..kAforoMax (10).
/// - `plazasOcupadas` (ocupantes distintos del cancelante) en 0..aforo-1, de
///   modo que el cancelante quepa como confirmado adicional.
/// - `saldoInicial` en kBonoMin..kBonoMax (0..10), incluyendo el tope para
///   comprobar el clamp del reembolso.
/// - `antelacionHoras` en 0..5, cubriendo valores por debajo, en y por encima
///   del umbral de kCancelacionHoras (2).
Generator<_EscenarioCancelacion> get _anyEscenarioCancelacion => any
    .intInRange(1, kAforoMax + 1)
    .bind(
      (aforo) => any
          .intInRange(0, aforo)
          .bind(
            (plazasOcupadas) => any
                .intInRange(kBonoMin, kBonoMax + 1)
                .bind(
                  (saldoInicial) => any
                      .intInRange(0, 6)
                      .map(
                        (antelacion) => _EscenarioCancelacion(
                          aforo,
                          plazasOcupadas,
                          saldoInicial,
                          antelacion,
                        ),
                      ),
                ),
          ),
    );

void main() {
  group('Feature: gym-management-app, Property 26 - reembolso al cancelar sii '
      'antelación >= 2h', () {
    Glados(
      _anyEscenarioCancelacion,
    ).test('cancelar una reserva confirmada libera la plaza y reembolsa +1 sii '
        'antelacionHoras >= 2 (Req 8.7, 8.8, 8.10)', (escenario) {
      // El cancelante se coloca el primero entre los confirmados; el resto
      // son ocupantes arbitrarios con saldo máximo.
      const usuario = 'cancelante';
      final otrosOcupantes = List.generate(
        escenario.plazasOcupadas,
        (i) => 'ocupante$i',
      );
      final confirmadas = <String>[usuario, ...otrosOcupantes];

      final saldos = <String, int>{
        usuario: escenario.saldoInicial,
        for (final id in otrosOcupantes) id: kBonoMax,
      };

      final estado = ReservasEstado(
        aforo: escenario.aforo,
        saldos: saldos,
        confirmadas: confirmadas,
      );

      // Precondición: el usuario tiene una Reserva_Confirmada.
      expect(estado.confirmadas, contains(usuario));
      final saldoAntes = estado.saldoDe(usuario);

      final res = estado.cancelar(
        usuario,
        antelacionHoras: escenario.antelacionHoras,
      );

      // Invariante 1 (Req 8.7/8.8): la plaza se libera siempre.
      expect(
        res.liberoPlaza,
        isTrue,
        reason: 'cancelar una reserva confirmada debe liberar la plaza',
      );
      expect(
        res.estado.confirmadas,
        isNot(contains(usuario)),
        reason: 'el usuario cancelante ya no debe figurar como confirmado',
      );

      // El reembolso ocurre si y solo si la antelación alcanza el umbral.
      final deberiaReembolsar = escenario.antelacionHoras >= kCancelacionHoras;
      expect(
        res.huboReembolso,
        deberiaReembolsar,
        reason:
            'huboReembolso debe ser $deberiaReembolsar para antelación '
            '${escenario.antelacionHoras}h (umbral $kCancelacionHoras h)',
      );

      // Invariante 2 (Req 8.7/8.8/8.10): el saldo del cancelante refleja el
      // reembolso exactamente, respetando el tope de 10.
      final saldoEsperado = deberiaReembolsar
          ? (saldoAntes + 1 > kBonoMax ? kBonoMax : saldoAntes + 1)
          : saldoAntes;
      expect(
        res.estado.saldoDe(usuario),
        saldoEsperado,
        reason:
            'el saldo del cancelante debería ser $saldoEsperado '
            '(antes: $saldoAntes, reembolso: $deberiaReembolsar)',
      );

      // El saldo permanece dentro del rango permitido (Req 8.10).
      expect(res.estado.saldoDe(usuario), inInclusiveRange(kBonoMin, kBonoMax));
    });
  });
}
