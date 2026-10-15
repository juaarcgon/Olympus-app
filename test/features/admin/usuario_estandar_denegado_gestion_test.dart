// Prueba de propiedad de la guarda de autorización del Servicio_Administracion.
//
// Feature: gym-management-app, Property 13
//
// Property 13: El usuario estándar es denegado en operaciones de gestión.
// "Para cualquier usuario con rol estándar y cualquier operación de gestión de
//  usuarios, el acceso se deniega con un mensaje de autorización insuficiente."
//
// Validates: Requirements 5.4
//
// La propiedad se verifica contra la guarda de dominio pura `autorizarGestion`
// (espejo de la comprobación `es_superadmin()` que las RPC `SECURITY DEFINER`
// del backend realizan antes de cada operación de gestión; ver design.md y
// `AdminRepositoryImpl`, que traduce el `42501` a `AutorizacionInsuficienteFailure`).
// Se usa `glados` con un mínimo de 100 iteraciones. Cada iteración elige una
// operación de gestión arbitraria y comprueba que, para el rol estándar
// ('usuario'), la guarda la deniega con `AutorizacionInsuficienteFailure` y un
// mensaje de autorización insuficiente; y que, como contraste, el rol
// 'superadmin' sí queda autorizado para la misma operación.

// `glados` reexporta el paquete `test` (expect, group, test, matchers), por lo
// que no se importa `flutter_test`: esta es una prueba de dominio puro.
import 'package:glados/glados.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/admin/domain/admin_authorization.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Generador de una operación de gestión arbitraria del conjunto completo
/// (suspender, reactivar, eliminar, restablecer/ajustar bono, conceder
/// superadmin). Se genera un entero no negativo y se reduce con módulo al
/// rango del enum para obtener una operación válida en cada iteración.
Generator<OperacionGestion> get _anyOperacionGestion => any.positiveIntOrZero
    .map((n) => OperacionGestion.values[n % OperacionGestion.values.length]);

void main() {
  group('Feature: gym-management-app, Property 13 - el usuario estándar es '
      'denegado en operaciones de gestión', () {
    Glados(_anyOperacionGestion).test(
      'para cualquier operación de gestión, un usuario con rol estándar '
      'es denegado con AutorizacionInsuficienteFailure (Req 5.4)',
      (operacion) {
        // Precondición de la propiedad: el llamante tiene rol estándar.
        const rolLlamante = RolUsuario.usuario;

        final failure = autorizarGestion(rolLlamante, operacion);

        // Invariante central (Property 13 / Req 5.4): el acceso se deniega
        // con un fallo de autorización insuficiente, para *cualquier*
        // operación de gestión.
        expect(
          failure,
          isA<AutorizacionInsuficienteFailure>(),
          reason:
              'el rol estándar debe ser denegado en la operación $operacion',
        );
        // El mensaje transmite autorización insuficiente al usuario.
        expect(failure!.mensaje, contains('autorización'));

        // Contraste: el mismo tipo de operación sí está permitido al
        // superadministrador (no se deniega), lo que confirma que la
        // denegación se debe al rol y no a la operación en sí.
        expect(
          autorizarGestion(RolUsuario.superadmin, operacion),
          isNull,
          reason: 'el superadministrador no debe ser denegado en $operacion',
        );
      },
    );
  });
}
