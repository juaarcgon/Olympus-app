// Prueba de propiedad del modelo puro de rechazo de email duplicado.
//
// Feature: gym-management-app, Property 4
//
// Property 4: El email duplicado se rechaza.
// "Para cualquier email ya asociado a un usuario existente, un segundo intento
//  de registro con ese mismo email se rechaza y no crea una segunda cuenta."
//
// Validates: Requirements 1.4
//
// La propiedad se verifica contra el modelo de dominio puro [RegistroEstado]
// (espejo del constraint UNIQUE de `profiles.email` y del rechazo de email
// duplicado de Supabase Auth, traducido a `EmailEnUsoFailure` en
// `auth_repository_impl.dart`) usando `glados` con un mínimo de 100
// iteraciones. Cada iteración genera una secuencia arbitraria de registros
// sobre un conjunto acotado de emails (para que las colisiones sean frecuentes)
// y comprueba, tras cada paso, que:
//   - si el email ya existía, el registro se rechaza con EmailEnUsoFailure y el
//     número total de cuentas no cambia (no se crea una segunda cuenta),
//   - si el email era nuevo, el registro tiene éxito y el total aumenta en 1,
// cumpliendo así el Req 1.4 sin red ni backend, igual que el resto de pruebas
// de dominio de la app.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/auth/domain/registration_model.dart';

/// Conjunto fijo y acotado de emails base sobre el que se generan los registros.
///
/// Se usa un conjunto pequeño para que las secuencias generadas ejerciten de
/// forma frecuente la colisión de emails (el caso de rechazo del Req 1.4). Se
/// incluyen variantes con mayúsculas y espacios para comprobar que la unicidad
/// se evalúa de forma normalizada (espejo de `auth.users.email`).
const _emails = <String>[
  'ana@example.com',
  'bruno@example.com',
  'ANA@example.com', // misma cuenta que 'ana@example.com' tras normalizar.
  '  bruno@example.com  ', // misma cuenta que 'bruno@example.com'.
  'carla@example.com',
];

/// Generador del índice (0..n-1) de un email del conjunto acotado.
///
/// Se genera un entero no negativo y se reduce con módulo al rango de [_emails],
/// obteniendo así un email válido para cada intento de registro.
Generator<int> get _anyIndiceEmail =>
    any.positiveIntOrZero.map((n) => n % _emails.length);

/// Generador de una secuencia arbitraria de registros (lista de índices).
Generator<List<int>> get _anySecuencia => any.list(_anyIndiceEmail);

void main() {
  group(
    'Feature: gym-management-app, Property 4 - el email duplicado se rechaza',
    () {
      Glados(_anySecuencia).test(
        'para cualquier email ya existente, un segundo registro se rechaza con '
        'EmailEnUsoFailure y no crea una segunda cuenta (Req 1.4)',
        (secuencia) {
          // Estado inicial: sin cuentas registradas.
          var estado = RegistroEstado();
          var contador = 0;

          for (final indice in secuencia) {
            final email = _emails[indice];
            final yaExistia = estado.existeEmail(email);
            final totalPrevio = estado.totalCuentas;

            final registro = RegistroUsuario(
              id: 'id-$indice-$contador',
              nombre: 'Nombre$indice',
              apellidos: 'Apellidos$indice',
              email: email,
            );
            contador++;

            final res = estado.registrar(registro);

            if (yaExistia) {
              // Req 1.4: el email duplicado se rechaza con EmailEnUsoFailure...
              expect(res.esExito, isFalse);
              expect(res.failure, isA<EmailEnUsoFailure>());
              expect(res.cuenta, isNull);
              // ...y NO se crea una segunda cuenta (el total no cambia).
              expect(res.estado.totalCuentas, equals(totalPrevio));
            } else {
              // Email nuevo: el registro tiene éxito y el total aumenta en 1.
              expect(res.esExito, isTrue);
              expect(res.failure, isNull);
              expect(res.cuenta, isNotNull);
              expect(res.estado.totalCuentas, equals(totalPrevio + 1));
              // La cuenta creada queda registrada bajo ese email.
              expect(res.estado.existeEmail(email), isTrue);
            }

            // Avanza el estado para el siguiente registro de la secuencia.
            estado = res.estado;
          }

          // Invariante final: nunca hay dos cuentas para el mismo email, por lo
          // que el total de cuentas no supera el número de emails distintos
          // (normalizados) del conjunto acotado.
          final emailsDistintos = _emails.map(normalizarEmail).toSet().length;
          expect(estado.totalCuentas, lessThanOrEqualTo(emailsDistintos));
        },
      );
    },
  );
}
