// Prueba de propiedad del modelo puro de credenciales.
//
// Feature: gym-management-app, Property 3
//
// Property 3: Las contraseñas nunca se almacenan ni comparan en texto plano.
// "Para cualquier contraseña proporcionada en el registro o en el
//  restablecimiento, el valor persistido nunca es igual a la contraseña en
//  texto plano ni la contiene, y la verificación de credenciales nunca utiliza
//  el texto plano persistido."
//
// Validates: Requirements 1.3, 2.5, 7.1, 9.7
//
// La propiedad se verifica contra el modelo de dominio puro de credenciales
// (`store` / `verify` / `hashPassword`), espejo del hashing que aplica
// Supabase Auth (bcrypt) en el backend, usando `glados` con un mínimo de 100
// iteraciones. Supabase Auth hashea realmente las contraseñas; este modelo las
// mirror-ea de forma determinista para poder comprobar la invariante "nunca
// texto plano" sin red ni backend, igual que el resto de pruebas de dominio.
//
// Para cada contraseña arbitraria se comprueba que, al persistirla
// (registro Req 1.3 / restablecimiento Req 9.7, almacenamiento Req 7.1):
//   - el valor persistido NO es igual a la contraseña en texto plano,
//   - el valor persistido NO contiene la contraseña en texto plano,
// y que la verificación de credenciales (Req 2.5):
//   - acepta la contraseña correcta comparando hashes (no el texto plano),
//   - rechaza una contraseña distinta,
//   - sigue funcionando aunque el texto plano no se conserve en ningún campo.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/features/auth/domain/credential_model.dart';

/// Generador de contraseñas arbitrarias.
///
/// Se usan cadenas no vacías de letras y dígitos para modelar contraseñas
/// reales (una contraseña vacía no es un caso de interés para esta propiedad).
/// Con esto se cubre un amplio espacio de entradas, incluidas contraseñas con
/// caracteres repetidos, mayúsculas, minúsculas y dígitos.
Generator<String> get _anyPassword => any.nonEmptyLetterOrDigits;

void main() {
  group('Feature: gym-management-app, Property 3 - las contraseñas nunca se '
      'almacenan ni comparan en texto plano', () {
    Glados(_anyPassword).test(
      'para cualquier contraseña, el valor persistido no es ni contiene el '
      'texto plano, y la verificación compara hashes (Req 1.3, 2.5, 7.1, '
      '9.7)',
      (password) {
        // Registro / restablecimiento: la contraseña se persiste como
        // Contraseña_Cifrada (Req 1.3, 7.1, 9.7).
        final almacenada = store(password);

        // El valor persistido NUNCA es igual al texto plano (Req 7.1).
        expect(
          almacenada.digest,
          isNot(equals(password)),
          reason: 'el valor persistido no debe ser la contraseña en claro',
        );

        // El valor persistido NUNCA contiene el texto plano (Req 7.1).
        expect(
          almacenada.digest.contains(password),
          isFalse,
          reason: 'el valor persistido no debe contener el texto plano',
        );

        // Verificación de credenciales: la contraseña correcta se acepta
        // comparando hashes, sin usar texto plano persistido (Req 2.5).
        expect(
          verify(almacenada, password),
          isTrue,
          reason: 'la contraseña correcta debe verificarse por hash',
        );

        // La verificación opera sobre el hash del intento, no sobre el texto
        // plano: una contraseña distinta se rechaza. Se construye un intento
        // garantizado distinto para evitar colisiones del generador.
        final intentoDistinto = '$password#';
        expect(
          intentoDistinto == password,
          isFalse,
          reason: 'el intento alternativo debe diferir del original',
        );
        expect(
          verify(almacenada, intentoDistinto),
          isFalse,
          reason: 'una contraseña distinta no debe verificarse',
        );

        // El hashing es determinista (misma entrada -> mismo digest), lo que
        // permite verificar sin conservar nunca el texto plano.
        expect(
          hashPassword(password),
          equals(almacenada.digest),
          reason: 'el hashing debe ser determinista para poder verificar',
        );
      },
    );
  });
}
