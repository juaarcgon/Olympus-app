// Prueba de propiedad de la guarda de autorización del CRUD de Clases del
// Servicio_Reservas.
//
// Feature: gym-management-app, Property 22
//
// Property 22: El usuario estándar no puede modificar clases.
// "Para cualquier usuario con rol estándar y cualquier intento de crear,
//  editar o eliminar una clase, la operación se deniega y la clase no se
//  modifica."
//
// Validates: Requirements 8.2
//
// La propiedad se verifica contra la guarda de dominio pura
// `autorizarModificacionClase` (espejo de las políticas RLS de PostgreSQL
// —migración 0003— que solo permiten INSERT/UPDATE/DELETE sobre `clases` si
// `es_superadmin()`; ver design.md, "Security and RLS Strategy", y
// `ReservasRepositoryImpl`, que traduce el rechazo por RLS/sin sesión al
// `AutorizacionInsuficienteFailure`). Se usa `glados` con un mínimo de 100
// iteraciones.
//
// Cada iteración elige una operación de modificación arbitraria (crear, editar
// o eliminar) y verifica las dos mitades de la propiedad para el rol estándar
// ('usuario'):
//   1) la operación se deniega con `AutorizacionInsuficienteFailure` y un
//      mensaje de autorización insuficiente;
//   2) la clase afectada queda inalterada (idéntica a su estado inicial),
//      modelado con un repositorio falso que solo aplica el cambio si la
//      guarda autoriza.
// Como contraste, el rol 'superadmin' sí queda autorizado para la misma
// operación, confirmando que la denegación se debe al rol y no a la operación.

// `glados` reexporta el paquete `test` (expect, group, test, matchers), por lo
// que no se importa `flutter_test`: esta es una prueba de dominio puro.
import 'package:glados/glados.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';
import 'package:olympus/features/reservas/domain/clase_authorization.dart';
import 'package:olympus/features/reservas/domain/entities/clase.dart';

/// Almacén de Clases en memoria que replica la semántica del CRUD real: antes
/// de crear, editar o eliminar aplica la guarda `autorizarModificacionClase`.
/// Si el llamante no está autorizado, devuelve el `Failure` sin modificar nada
/// (espejo de la RLS que rechaza la operación dejando la Clase intacta).
class _FakeCalendario {
  _FakeCalendario(Clase clase) : _clase = clase;

  Clase? _clase;

  /// Snapshot inmutable de la Clase actual (o `null` si fue eliminada).
  Clase? get clase => _clase;

  /// Intenta editar la Clase; aplica el cambio solo si el rol está autorizado.
  AutorizacionInsuficienteFailure? editar(RolUsuario rol, Clase nueva) {
    final failure = autorizarModificacionClase(rol, OperacionClase.editar);
    if (failure != null) return failure;
    _clase = nueva;
    return null;
  }

  /// Intenta eliminar la Clase; la borra solo si el rol está autorizado.
  AutorizacionInsuficienteFailure? eliminar(RolUsuario rol) {
    final failure = autorizarModificacionClase(rol, OperacionClase.eliminar);
    if (failure != null) return failure;
    _clase = null;
    return null;
  }
}

/// Generador de una operación de modificación de Clases arbitraria (crear,
/// editar o eliminar). Se genera un entero no negativo y se reduce con módulo
/// al rango del enum para obtener una operación válida en cada iteración.
Generator<OperacionClase> get _anyOperacionClase => any.positiveIntOrZero.map(
  (n) => OperacionClase.values[n % OperacionClase.values.length],
);

/// Clase de ejemplo fija usada como estado inicial del calendario.
Clase _claseInicial() => Clase(
  id: 'clase-1',
  horario: DateTime.utc(2025, 1, 1, 10),
  aforo: 8,
  monitor: 'Monitor Base',
  createdBy: 'superadmin-1',
);

void main() {
  group('Feature: gym-management-app, Property 22 - el usuario estándar no '
      'puede modificar clases', () {
    Glados(_anyOperacionClase).test(
      'para cualquier operación de modificación de clases, un usuario con rol '
      'estándar es denegado con AutorizacionInsuficienteFailure (Req 8.2)',
      (operacion) {
        // Precondición de la propiedad: el llamante tiene rol estándar.
        const rolLlamante = RolUsuario.usuario;

        final failure = autorizarModificacionClase(rolLlamante, operacion);

        // Invariante central (Property 22 / Req 8.2): el acceso se deniega
        // con un fallo de autorización insuficiente, para *cualquier*
        // operación de modificación de Clase.
        expect(
          failure,
          isA<AutorizacionInsuficienteFailure>(),
          reason:
              'el rol estándar debe ser denegado en la operación $operacion',
        );
        // El mensaje transmite autorización insuficiente al usuario.
        expect(failure!.mensaje, contains('autorización'));

        // Contraste: la misma operación sí está permitida al
        // superadministrador (no se deniega), lo que confirma que la
        // denegación se debe al rol y no a la operación en sí.
        expect(
          autorizarModificacionClase(RolUsuario.superadmin, operacion),
          isNull,
          reason: 'el superadministrador no debe ser denegado en $operacion',
        );
      },
    );

    Glados(_anyOperacionClase).test(
      'tras un intento de modificación por un usuario estándar, la clase '
      'permanece inalterada (Req 8.2)',
      (operacion) {
        const rolLlamante = RolUsuario.usuario;
        final inicial = _claseInicial();
        final calendario = _FakeCalendario(inicial);

        // El usuario estándar intenta editar o eliminar la Clase. (La creación
        // no parte de una Clase previa; la rama de edición/eliminación cubre la
        // segunda mitad de la propiedad: "la clase no se modifica").
        final AutorizacionInsuficienteFailure? failure;
        switch (operacion) {
          case OperacionClase.editar:
          case OperacionClase.crear:
            // Se intenta sobrescribir todos los campos modificables.
            failure = calendario.editar(
              rolLlamante,
              inicial.copyWith(
                horario: DateTime.utc(2030, 12, 31, 23),
                aforo: 1,
                monitor: 'Monitor Intruso',
              ),
            );
          case OperacionClase.eliminar:
            failure = calendario.eliminar(rolLlamante);
        }

        // La operación se deniega...
        expect(failure, isA<AutorizacionInsuficienteFailure>());

        // ...y la Clase queda exactamente igual que al inicio (ni modificada
        // ni eliminada): invariante "la clase no se modifica" (Req 8.2).
        expect(
          calendario.clase,
          isNotNull,
          reason: 'la clase no debe eliminarse por un usuario estándar',
        );
        expect(
          calendario.clase,
          inicial,
          reason: 'la clase debe permanecer idéntica a su estado inicial',
        );
      },
    );
  });

  group('Feature: gym-management-app, Property 22 - contraste: el '
      'superadministrador sí puede modificar clases', () {
    test('el superadministrador puede editar la clase (Req 8.2)', () {
      final inicial = _claseInicial();
      final calendario = _FakeCalendario(inicial);

      final editada = inicial.copyWith(monitor: 'Nuevo Monitor');
      final failure = calendario.editar(RolUsuario.superadmin, editada);

      expect(failure, isNull);
      expect(calendario.clase, editada);
    });

    test('el superadministrador puede eliminar la clase (Req 8.2)', () {
      final calendario = _FakeCalendario(_claseInicial());

      final failure = calendario.eliminar(RolUsuario.superadmin);

      expect(failure, isNull);
      expect(calendario.clase, isNull);
    });
  });
}
