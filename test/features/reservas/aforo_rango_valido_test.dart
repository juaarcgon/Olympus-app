// Prueba de propiedad del rango de aforo de una Clase.
//
// Feature: gym-management-app, Property 21
//
// Property 21: El aforo de una clase está en el rango 1..10.
// "Para cualquier clase creada o editada por un superadministrador, su `aforo`
//  se acepta si y solo si `1 <= aforo <= 10`; valores fuera de rango se
//  rechazan."
//
// Validates: Requirements 8.1
//
// La propiedad se verifica contra el validador de dominio puro `esAforoValido`
// (espejo en el cliente del `CHECK (aforo BETWEEN 1 AND 10)` de la tabla
// `clases`), usando `glados` con un mínimo de 100 iteraciones. Se cubren las
// dos ramas de la propiedad (bicondicional):
//   - aforo dentro de 1..10: se acepta (`esAforoValido == true`);
//   - aforo fuera de 1..10: se rechaza (`esAforoValido == false`).
// Los casos borde (0, 1, 10, 11, negativos) se cubren además con ejemplos
// explícitos para fijar los extremos exactos del rango.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';

/// Generador de un aforo dentro del rango cerrado 1..10.
///
/// `intInRange` genera en [min, max) por lo que el límite superior es
/// `kAforoMax + 1` para incluir el extremo 10.
Generator<int> get _anyAforoEnRango => any.intInRange(kAforoMin, kAforoMax + 1);

/// Generador de un aforo fuera del rango 1..10 (cero, negativos y > 10).
///
/// Se genera un entero sobre un rango amplio contiguo y se mapea para excluir
/// por construcción el intervalo permitido 1..10, cubriendo ambos extremos:
///   - `n` en -20..0 se mantiene como aforo <= 0 (fuera de rango por abajo,
///     incluyendo el borde 0);
///   - `n` en 1..19 se desplaza a 11..29 (fuera de rango por arriba).
/// Usa solo `intInRange` y `.map`, combinadores ya empleados en las pruebas
/// hermanas (p. ej. la Property 17 del bono).
Generator<int> get _anyAforoFueraDeRango =>
    any.intInRange(-20, 20).map((n) => n <= 0 ? n : kAforoMax + n);

void main() {
  group('Feature: gym-management-app, Property 21 - el aforo de una clase está '
      'en el rango 1..10', () {
    Glados<int>(_anyAforoEnRango).test(
      'para cualquier aforo en 1..10, se acepta (Req 8.1)',
      (aforo) {
        // Precondición de esta rama: el aforo pertenece al rango 1..10.
        expect(aforo, inInclusiveRange(kAforoMin, kAforoMax));

        // Invariante central (Property 21 / Req 8.1): el aforo dentro de rango
        // siempre se acepta.
        expect(
          esAforoValido(aforo),
          isTrue,
          reason:
              'esAforoValido($aforo) debería ser true para un aforo en '
              '1..10',
        );
      },
    );

    Glados<int>(_anyAforoFueraDeRango).test(
      'para cualquier aforo fuera de 1..10, se rechaza (Req 8.1)',
      (aforo) {
        // Precondición de esta rama: el aforo está fuera del rango 1..10.
        expect(aforo < kAforoMin || aforo > kAforoMax, isTrue);

        // Invariante central (Property 21 / Req 8.1): el aforo fuera de rango
        // siempre se rechaza.
        expect(
          esAforoValido(aforo),
          isFalse,
          reason:
              'esAforoValido($aforo) debería ser false para un aforo '
              'fuera de 1..10',
        );
      },
    );
  });

  group('Feature: gym-management-app, Property 21 - casos borde del rango de '
      'aforo', () {
    test('el límite inferior exacto (1) se acepta (Req 8.1)', () {
      expect(esAforoValido(kAforoMin), isTrue);
      expect(esAforoValido(1), isTrue);
    });

    test('el límite superior exacto (10) se acepta (Req 8.1)', () {
      expect(esAforoValido(kAforoMax), isTrue);
      expect(esAforoValido(10), isTrue);
    });

    test('cero (0), justo por debajo del mínimo, se rechaza (Req 8.1)', () {
      expect(esAforoValido(0), isFalse);
    });

    test('once (11), justo por encima del máximo, se rechaza (Req 8.1)', () {
      expect(esAforoValido(kAforoMax + 1), isFalse);
      expect(esAforoValido(11), isFalse);
    });

    test('un aforo negativo se rechaza (Req 8.1)', () {
      expect(esAforoValido(-1), isFalse);
      expect(esAforoValido(-10), isFalse);
    });
  });
}
