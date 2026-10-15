// Prueba de propiedad del modelo puro de suspensión y reactivación de usuarios.
//
// Feature: gym-management-app, Property 14
//
// Property 14: Suspender y reactivar (round trip de estado).
// "Para cualquier usuario, suspenderlo fija su `estado` en 'suspendido', y
//  reactivarlo a continuación lo restaura a 'activo'."
//
// Validates: Requirements 6.2, 6.3
//
// La propiedad se verifica contra el modelo de dominio puro [SuspensionEstado]
// (espejo de las RPC `suspender_usuario`/`reactivar_usuario`; ver design.md,
// "Funciones RPC del backend", y `0005_rpc_admin.sql`; `AdminRepositoryImpl`
// invoca esas RPC desde `suspendUser`/`reactivateUser`) usando `glados` con un
// mínimo de 100 iteraciones. Cada iteración parte de un `estado` inicial
// arbitrario para el usuario objetivo y comprueba el round trip:
//   - suspender → 'suspendido' (Req 6.2),
//   - reactivar a continuación → 'activo' (Req 6.3),
// sin afectar al resto de cuentas del conjunto.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/features/admin/domain/suspension_model.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Conjunto fijo de ids de usuario sobre el que se generan los estados.
///
/// Se usa un conjunto acotado para poder comprobar que la transición del
/// usuario objetivo no afecta al resto de cuentas.
const _usuarios = ['u1', 'u2', 'u3', 'u4', 'u5'];

/// Generador del índice (0..n-1) de un usuario del conjunto [_usuarios].
///
/// Se genera un entero no negativo y se reduce con módulo al rango del
/// conjunto, obteniendo así un id válido en cada iteración.
Generator<int> get _anyIndiceUsuario =>
    any.positiveIntOrZero.map((n) => n % _usuarios.length);

/// Generador de un estado de usuario arbitrario (activo o suspendido).
Generator<EstadoUsuario> get _anyEstado => any.positiveIntOrZero.map(
  (n) => EstadoUsuario.values[n % EstadoUsuario.values.length],
);

/// Generador de una asignación de estados para todo el conjunto de usuarios.
///
/// Produce una lista de estados (uno por usuario de [_usuarios]) que luego se
/// empareja por posición para construir el mapa de estados del estado inicial.
Generator<List<EstadoUsuario>> get _anyEstados =>
    any.listWithLength(_usuarios.length, _anyEstado);

void main() {
  group('Feature: gym-management-app, Property 14 - suspender y reactivar '
      '(round trip de estado)', () {
    Glados2(_anyEstados, _anyIndiceUsuario).test(
      'para cualquier usuario, suspenderlo fija estado=suspendido y '
      'reactivarlo a continuación lo restaura a estado=activo (Req 6.2, 6.3)',
      (estados, indiceObjetivo) {
        // Estado inicial arbitrario: cada usuario con su estado generado.
        final estadoInicial = SuspensionEstado({
          for (var i = 0; i < _usuarios.length; i++) _usuarios[i]: estados[i],
        });

        final targetId = _usuarios[indiceObjetivo];

        // Precondición: el usuario objetivo existe en el estado inicial.
        expect(estadoInicial.existe(targetId), isTrue);

        // Paso 1: suspender fija el estado del objetivo en 'suspendido'
        // (Req 6.2), con independencia de su estado previo.
        final trasSuspender = estadoInicial.suspender(targetId);
        expect(
          trasSuspender.estadoDe(targetId),
          equals(EstadoUsuario.suspendido),
          reason: 'suspender debe fijar el estado en suspendido',
        );

        // Paso 2: reactivar a continuación restaura el estado en 'activo'
        // (Req 6.3), completando el round trip.
        final trasReactivar = trasSuspender.reactivar(targetId);
        expect(
          trasReactivar.estadoDe(targetId),
          equals(EstadoUsuario.activo),
          reason: 'reactivar debe restaurar el estado a activo',
        );

        // El round trip no afecta al resto de cuentas: su estado se conserva
        // exactamente igual al del estado inicial.
        for (final id in _usuarios) {
          if (id == targetId) continue;
          expect(
            trasReactivar.estadoDe(id),
            equals(estadoInicial.estadoDe(id)),
            reason: 'la transición del objetivo no debe afectar a $id',
          );
        }
      },
    );
  });
}
