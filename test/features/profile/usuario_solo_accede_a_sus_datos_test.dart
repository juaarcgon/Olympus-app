// Prueba de propiedad del Servicio_Usuarios (control de acceso a `profiles`).
//
// Feature: gym-management-app, Property 19
//
// Property 19: Un usuario solo accede a sus propios datos (salvo superadmin).
// "Para cualquier par de usuarios (solicitante, objetivo) donde el solicitante
//  no es el objetivo ni un superadministrador, la petición de los datos del
//  objetivo se deniega."
//
// Validates: Requirements 7.2
//
// La propiedad se verifica contra la guarda de dominio pura
// `autorizarAccesoAProfile` (espejo de la política RLS `SELECT` del backend
// sobre `profiles`: `USING (auth.uid() = id OR es_superadmin())`, ver
// design.md "Security and RLS Strategy"). La enforcement real en PostgreSQL se
// cubre aparte con las pruebas de integración de RLS (tarea 12.3). Aquí se usa
// `glados` con un mínimo de 100 iteraciones.
//
// Cada iteración genera un par (solicitante, objetivo). El caso central de la
// propiedad construye deliberadamente un solicitante que NO es el objetivo y
// que NO es superadministrador, y comprueba que la petición se deniega con
// `AutorizacionInsuficienteFailure` y un mensaje de autorización insuficiente.
// Como contraste se comprueban los dos caminos que SÍ se permiten según la
// política: acceder a los propios datos, y el acceso de un superadministrador.

// `glados` reexporta el paquete `test` (expect, group, test, matchers), por lo
// que no se importa `flutter_test`: esta es una prueba de dominio puro.
import 'package:glados/glados.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';
import 'package:olympus/features/profile/domain/profile_access_control.dart';

/// Par de identificadores (solicitante, objetivo) para una petición de datos.
///
/// Los identificadores se construyen a partir de dos enteros no negativos
/// arbitrarios: así se cubren tanto pares con ids distintos como pares con el
/// mismo id (acceso a los propios datos).
class _ParAcceso {
  const _ParAcceso({required this.solicitanteId, required this.objetivoId});

  final String solicitanteId;
  final String objetivoId;

  @override
  String toString() =>
      '_ParAcceso(solicitanteId: $solicitanteId, objetivoId: $objetivoId)';
}

/// Genera pares de ids a partir de dos enteros arbitrarios no negativos.
Generator<_ParAcceso> get _anyParAcceso => any.positiveIntOrZero.bind(
  (a) => any.positiveIntOrZero.map(
    (b) => _ParAcceso(solicitanteId: 'user-$a', objetivoId: 'user-$b'),
  ),
);

void main() {
  group(
    'Feature: gym-management-app, Property 19 - un usuario solo accede a sus '
    'propios datos (salvo superadmin)',
    () {
      Glados(_anyParAcceso).test(
        'un solicitante estándar que no es el objetivo es denegado al pedir '
        'los datos del objetivo (Req 7.2)',
        (par) {
          // Precondición de la propiedad: el solicitante NO es el objetivo.
          // Si el generador produce ids iguales, se fuerza un objetivo
          // distinto para mantener la precondición "no es el objetivo".
          final objetivoId = par.solicitanteId == par.objetivoId
              ? '${par.objetivoId}-otro'
              : par.objetivoId;

          // El solicitante tiene rol estándar (no es superadministrador),
          // completando así la precondición de la propiedad.
          const solicitanteRol = RolUsuario.usuario;

          final failure = autorizarAccesoAProfile(
            solicitanteId: par.solicitanteId,
            solicitanteRol: solicitanteRol,
            objetivoId: objetivoId,
          );

          // Invariante central (Property 19 / Req 7.2): la petición se deniega
          // con un fallo de autorización insuficiente.
          expect(
            failure,
            isA<AutorizacionInsuficienteFailure>(),
            reason:
                'un usuario estándar no debe acceder a los datos de otro '
                '(solicitante ${par.solicitanteId}, objetivo $objetivoId)',
          );
          // El mensaje transmite autorización insuficiente al usuario.
          expect(failure!.mensaje, contains('autorización'));
        },
      );

      // Contraste 1: acceder a los propios datos siempre está permitido,
      // sea cual sea el rol del solicitante (rama `auth.uid() = id`).
      Glados(_anyParAcceso).test(
        'acceder a los propios datos está siempre permitido (rama auth.uid() = '
        'id de la política RLS)',
        (par) {
          for (final rol in RolUsuario.values) {
            expect(
              autorizarAccesoAProfile(
                solicitanteId: par.solicitanteId,
                solicitanteRol: rol,
                objetivoId: par.solicitanteId,
              ),
              isNull,
              reason:
                  'todo usuario (${rol.valor}) debe acceder a sus propios '
                  'datos (${par.solicitanteId})',
            );
          }
        },
      );

      // Contraste 2: un superadministrador accede a los datos de cualquier
      // usuario (rama `es_superadmin()` de la política RLS).
      Glados(_anyParAcceso).test(
        'un superadministrador accede a los datos de cualquier usuario (rama '
        'es_superadmin() de la política RLS)',
        (par) {
          expect(
            autorizarAccesoAProfile(
              solicitanteId: par.solicitanteId,
              solicitanteRol: RolUsuario.superadmin,
              objetivoId: par.objetivoId,
            ),
            isNull,
            reason:
                'un superadministrador (${par.solicitanteId}) debe acceder a '
                'los datos del objetivo (${par.objetivoId})',
          );
        },
      );
    },
  );
}
