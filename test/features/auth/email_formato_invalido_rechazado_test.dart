// Prueba de propiedad de la validación de formato de email (registro).
//
// Feature: gym-management-app, Property 5
//
// Property 5: El formato de email inválido se rechaza.
// "Para cualquier cadena que no cumpla el formato de una dirección de correo
//  válida, el registro se rechaza con un error de formato de correo."
//
// Validates: Requirements 1.5
//
// La propiedad se verifica contra el validador de dominio puro `validarEmail`
// (`lib/core/utils/validators.dart`), que es el espejo exacto del guard que
// `AuthRepositoryImpl.signUp` ejecuta ANTES de llamar a Supabase Auth: si el
// email no es válido, lanza `FormatoEmailFailure` y el alta no llega al
// backend (Req 1.5). Se usa `glados` con un mínimo de 100 iteraciones.
//
// Como la propiedad habla de "cualquier cadena que no cumpla el formato", el
// reto está en generar cadenas que sean INVÁLIDAS de forma fiable. En lugar de
// generar texto arbitrario (que raramente produce un email con estructura
// casi-válida y, además, podría colisionar accidentalmente con un formato
// válido), se usan generadores inteligentes que construyen cadenas inválidas
// por construcción, cubriendo las familias típicas de email malformado:
//   - sin arroba,
//   - sin parte local,
//   - sin dominio,
//   - con espacios en blanco,
//   - sin punto / sin TLD,
//   - con TLD demasiado corto (1 carácter),
//   - cadena vacía o solo espacios,
//   - múltiples arrobas.
// Para cada una se comprueba que `validarEmail` devuelve un
// `FormatoEmailFailure` (el registro se rechaza con error de formato) y que el
// predicado `esEmailValido` es `false`.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/core/utils/utils.dart';

/// Generador de un fragmento de texto "simple" sin espacios ni arrobas.
///
/// Sirve como pieza de construcción para las partes local y de dominio de los
/// emails inválidos sintéticos. Se parte de letras o dígitos no vacíos y se
/// filtran los caracteres que podrían dar estructura válida accidental.
Generator<String> get _anyFragmento => any.nonEmptyLetterOrDigits.map(
  (s) => s.replaceAll('@', '').replaceAll(RegExp(r'\s'), ''),
);

/// Generador de cadenas de email INVÁLIDAS por construcción.
///
/// Combina varias familias de malformación, cada una derivada de fragmentos
/// arbitrarios para explorar un amplio espacio de entradas que, sin embargo,
/// nunca cumplen el formato `local@dominio.tld` exigido por el Req 1.5.
Generator<String> get _anyEmailInvalido => any.oneOf([
  // Sin arroba: "localdominio.com".
  any.combine2(_anyFragmento, _anyFragmento, (a, b) => '$a$b.com'),
  // Sin parte local: "@dominio.com".
  _anyFragmento.map((d) => '@$d.com'),
  // Sin dominio: "local@".
  _anyFragmento.map((l) => '$l@'),
  // Sin punto ni TLD: "local@dominio".
  any.combine2(_anyFragmento, _anyFragmento, (l, d) => '$l@$d'),
  // Con espacio en la parte local: "lo cal@dominio.com".
  any.combine2(_anyFragmento, _anyFragmento, (l, d) => '$l $l@$d.com'),
  // Con espacio en el dominio: "local@do minio.com".
  any.combine2(_anyFragmento, _anyFragmento, (l, d) => '$l@$d $d.com'),
  // TLD demasiado corto (1 carácter): "local@dominio.c".
  any.combine2(_anyFragmento, _anyFragmento, (l, d) => '$l@$d.c'),
  // Dos arrobas: "local@do@minio.com".
  any.combine2(_anyFragmento, _anyFragmento, (l, d) => '$l@$d@$d.com'),
  // Termina en punto (sin TLD): "local@dominio.".
  any.combine2(_anyFragmento, _anyFragmento, (l, d) => '$l@$d.'),
]);

void main() {
  group(
    'Feature: gym-management-app, Property 5 - el formato de email inválido se '
    'rechaza',
    () {
      Glados(_anyEmailInvalido).test(
        'para cualquier cadena con formato de correo inválido, validarEmail '
        'devuelve FormatoEmailFailure y esEmailValido es false (Req 1.5)',
        (emailInvalido) {
          // El predicado de formato rechaza la cadena.
          expect(
            esEmailValido(emailInvalido),
            isFalse,
            reason:
                'la cadena "$emailInvalido" no es un email con formato '
                'válido y debe rechazarse',
          );

          // Req 1.5: el registro se rechaza con un error de formato de correo.
          // `validarEmail` es el guard que ejecuta AuthRepositoryImpl.signUp
          // antes de llamar a Auth; aquí devuelve el Failure que luego se lanza.
          final failure = validarEmail(emailInvalido);
          expect(
            failure,
            isA<FormatoEmailFailure>(),
            reason:
                'un email con formato inválido debe producir un '
                'FormatoEmailFailure (el registro no llega al backend)',
          );
        },
      );

      // Casos borde explícitos: cadena vacía y solo espacios en blanco. Son
      // formatos claramente inválidos que el Req 1.5 también debe rechazar.
      test('la cadena vacía y las cadenas solo de espacios se rechazan '
          '(Req 1.5)', () {
        for (final vacio in <String>['', '   ', '\t', '\n']) {
          expect(esEmailValido(vacio), isFalse);
          expect(validarEmail(vacio), isA<FormatoEmailFailure>());
        }
      });
    },
  );
}
