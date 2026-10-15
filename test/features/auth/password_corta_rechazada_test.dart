// Prueba de propiedad de la validación de longitud de contraseña.
//
// Feature: gym-management-app, Property 6
//
// Property 6: La contraseña demasiado corta se rechaza.
// "Para cualquier contraseña de longitud menor que ocho (8) caracteres, el
//  registro y el restablecimiento se rechazan con un error de longitud de
//  contraseña."
//
// Validates: Requirements 1.6, 9.6
//
// La propiedad se verifica contra el validador de dominio puro
// `validarPassword` (`lib/core/utils/validators.dart`), que es el espejo exacto
// del guard que `AuthRepositoryImpl.signUp` (Req 1.6) y el flujo de
// restablecimiento con `updatePasswordWithToken` (Req 9.6) ejecutan ANTES de
// llamar a Supabase Auth: si la contraseña tiene menos de ocho (8) caracteres,
// lanza `PasswordCortaFailure` y la operación no llega al backend. Se usa
// `glados` con un mínimo de 100 iteraciones.
//
// Como la propiedad habla de "cualquier contraseña de longitud menor que 8",
// el reto está en generar contraseñas que sean CORTAS de forma fiable. En
// lugar de generar texto arbitrario (que casi siempre produciría cadenas de 8
// o más caracteres y rara vez ejercitaría el límite), se usa un generador
// inteligente que construye por construcción cadenas de longitud 0..7,
// cubriendo todo el espacio de contraseñas demasiado cortas, incluidos los
// casos borde de la cadena vacía y de siete (7) caracteres (justo por debajo
// del mínimo).

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/core/utils/utils.dart';

/// Generador de contraseñas DEMASIADO CORTAS por construcción (longitud 0..7).
///
/// Se parte de una cadena arbitraria no vacía de letras o dígitos y se recorta
/// a una longitud objetivo en el rango 0..`kPasswordMinLength - 1` (0..7). Así
/// el espacio explorado contiene únicamente contraseñas inválidas por longitud,
/// incluyendo la cadena vacía y la de siete (7) caracteres (caso borde justo
/// por debajo del mínimo de ocho).
Generator<String> get _anyPasswordCorta => any.combine2(
  any.nonEmptyLetterOrDigits,
  any.intInRange(0, kPasswordMinLength), // longitud objetivo 0..7
  (String texto, int longitud) {
    // Garantiza material suficiente para recortar hasta la longitud pedida
    // repitiendo el texto base, y luego corta a la longitud objetivo.
    final repetido = texto * (longitud ~/ texto.length + 1);
    return repetido.substring(0, longitud);
  },
);

void main() {
  group(
    'Feature: gym-management-app, Property 6 - la contraseña demasiado corta '
    'se rechaza',
    () {
      Glados(_anyPasswordCorta).test(
        'para cualquier contraseña de menos de 8 caracteres, validarPassword '
        'devuelve PasswordCortaFailure y esPasswordValida es false '
        '(Req 1.6, 9.6)',
        (passwordCorta) {
          // Precondición del generador: la contraseña es demasiado corta.
          expect(
            passwordCorta.length < kPasswordMinLength,
            isTrue,
            reason:
                'la contraseña "$passwordCorta" (longitud '
                '${passwordCorta.length}) debe tener menos de '
                '$kPasswordMinLength caracteres',
          );

          // El predicado de longitud rechaza la contraseña.
          expect(
            esPasswordValida(passwordCorta),
            isFalse,
            reason:
                'una contraseña de longitud ${passwordCorta.length} '
                '(< $kPasswordMinLength) no es válida',
          );

          // Req 1.6 / 9.6: el registro y el restablecimiento se rechazan con un
          // error de longitud de contraseña. `validarPassword` es el guard que
          // ejecutan AuthRepositoryImpl.signUp y el flujo de restablecimiento
          // antes de llamar a Auth; aquí devuelve el Failure que luego se lanza.
          final failure = validarPassword(passwordCorta);
          expect(
            failure,
            isA<PasswordCortaFailure>(),
            reason:
                'una contraseña demasiado corta debe producir un '
                'PasswordCortaFailure (la operación no llega al backend)',
          );
        },
      );

      // Caso borde explícito del límite: exactamente 7 caracteres se rechaza y
      // exactamente 8 caracteres se acepta (frontera del Req 1.6/9.6).
      test('la frontera de longitud es estricta: 7 se rechaza y 8 se acepta '
          '(Req 1.6, 9.6)', () {
        const siete = '1234567'; // kPasswordMinLength - 1
        const ocho = '12345678'; // kPasswordMinLength

        expect(esPasswordValida(siete), isFalse);
        expect(validarPassword(siete), isA<PasswordCortaFailure>());

        expect(esPasswordValida(ocho), isTrue);
        expect(validarPassword(ocho), isNull);
      });
    },
  );
}
