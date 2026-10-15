// Prueba de propiedad del modelo puro de eliminación de usuarios por un
// superadministrador.
//
// Feature: gym-management-app, Property 18
//
// Property 18: Un superadministrador no puede autoeliminarse.
// "Para cualquier superadministrador, el intento de eliminar su propia cuenta
//  se rechaza y la cuenta persiste."
//
// Validates: Requirements 6.7
//
// La propiedad se verifica contra el modelo de dominio puro
// [EliminacionEstado] (espejo de la RPC `eliminar_usuario`; ver design.md y
// `0005_rpc_admin.sql`, y `AdminRepositoryImpl`, que traduce el `42501` de
// autoeliminación a [AutoeliminacionFailure]) usando `glados` con un mínimo de
// 100 iteraciones. Cada iteración genera un superadministrador arbitrario
// dentro de un conjunto de usuarios con roles arbitrarios y comprueba que su
// intento de eliminarse a sí mismo se rechaza con [AutoeliminacionFailure] y
// que su cuenta persiste inalterada.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/admin/domain/eliminacion_usuario_model.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Conjunto fijo de ids de usuario sobre el que se generan los estados.
const _usuarios = ['u1', 'u2', 'u3', 'u4', 'u5'];

/// Generador del índice (0..n-1) de un usuario del conjunto [_usuarios].
///
/// Se genera un entero no negativo y se reduce con módulo al rango del
/// conjunto, obteniendo así un id válido en cada iteración.
Generator<int> get _anyIndiceUsuario =>
    any.positiveIntOrZero.map((n) => n % _usuarios.length);

/// Generador de un rol de usuario arbitrario (estándar o superadmin).
Generator<RolUsuario> get _anyRol => any.positiveIntOrZero.map(
  (n) => RolUsuario.values[n % RolUsuario.values.length],
);

/// Generador de una asignación de roles para todo el conjunto de usuarios.
///
/// Produce una lista de roles (uno por usuario de [_usuarios]) que luego se
/// empareja por posición para construir el mapa de roles del estado.
Generator<List<RolUsuario>> get _anyRoles =>
    any.listWithLength(_usuarios.length, _anyRol);

void main() {
  group('Feature: gym-management-app, Property 18 - un superadministrador no '
      'puede autoeliminarse', () {
    Glados2(_anyRoles, _anyIndiceUsuario).test(
      'para cualquier superadministrador, eliminar su propia cuenta se rechaza '
      'con AutoeliminacionFailure y la cuenta persiste (Req 6.7)',
      (roles, indiceSuperadmin) {
        // Construye el estado inicial a partir de los roles generados, pero
        // garantiza que el usuario elegido (el llamante) es superadministrador:
        // la propiedad cuantifica sobre *cualquier* superadministrador.
        final superadminId = _usuarios[indiceSuperadmin];
        final mapaRoles = <String, RolUsuario>{
          for (var i = 0; i < _usuarios.length; i++) _usuarios[i]: roles[i],
          superadminId: RolUsuario.superadmin,
        };
        final estado = EliminacionEstado(mapaRoles);

        // Precondiciones del estado generado.
        expect(estado.rolDe(superadminId), equals(RolUsuario.superadmin));
        expect(estado.existe(superadminId), isTrue);

        // El superadministrador intenta eliminar su propia cuenta.
        final res = estado.eliminarUsuario(
          callerId: superadminId,
          targetUserId: superadminId,
        );

        // Invariante central (Property 18 / Req 6.7): el intento se rechaza
        // con AutoeliminacionFailure.
        expect(
          res.esExito,
          isFalse,
          reason: 'la autoeliminación de un superadmin debe rechazarse',
        );
        expect(res.failure, isA<AutoeliminacionFailure>());

        // La cuenta persiste inalterada: sigue existiendo y conserva su rol.
        expect(
          res.estado.existe(superadminId),
          isTrue,
          reason: 'la cuenta del superadmin debe persistir tras el rechazo',
        );
        expect(res.estado.rolDe(superadminId), equals(RolUsuario.superadmin));

        // El estado completo no cambia (ninguna otra cuenta se ve afectada).
        expect(res.estado.roles, equals(estado.roles));
      },
    );
  });
}
