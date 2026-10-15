// Prueba de propiedad del modelo puro de eliminación de usuarios por un
// superadministrador.
//
// Feature: gym-management-app, Property 15
//
// Property 15: La eliminación de un usuario borra su registro.
// "Para cualquier usuario existente, cuando un superadministrador (distinto de
//  él) solicita eliminarlo, la operación tiene éxito y el registro de ese
//  usuario deja de existir en el almacén de datos."
//
// Validates: Requirements 6.4
//
// La propiedad se verifica contra el modelo de dominio puro
// [EliminacionEstado] (espejo de la RPC `eliminar_usuario`; ver design.md,
// "Funciones RPC del backend", y `0005_rpc_admin.sql`; `AdminRepositoryImpl`
// invoca esa RPC desde `deleteUser`) usando `glados` con un mínimo de 100
// iteraciones. Cada iteración genera un conjunto de usuarios con roles
// arbitrarios, garantiza un superadministrador llamante y un objetivo
// *distinto* que existe, y comprueba que tras la eliminación el objetivo deja
// de existir mientras el resto de cuentas persiste inalterado.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/features/admin/domain/eliminacion_usuario_model.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Conjunto fijo de ids de usuario sobre el que se generan los estados.
///
/// Se usa un conjunto acotado (> 2) para que llamante y objetivo puedan ser
/// cuentas distintas en cada iteración.
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
  group('Feature: gym-management-app, Property 15 - la eliminación de un '
      'usuario borra su registro', () {
    Glados3(_anyRoles, _anyIndiceUsuario, _anyIndiceUsuario).test(
      'para cualquier usuario objetivo, un superadministrador distinto lo '
      'elimina con éxito y su registro deja de existir (Req 6.4)',
      (roles, indiceSuperadmin, indiceObjetivo) {
        // Elige llamante y objetivo distintos: la propiedad cuantifica sobre
        // la eliminación de *otro* usuario (la autoeliminación se cubre en
        // Property 18). Si los índices coinciden, se desplaza el objetivo al
        // siguiente usuario del conjunto.
        final superadminId = _usuarios[indiceSuperadmin];
        var idxObjetivo = indiceObjetivo;
        if (idxObjetivo == indiceSuperadmin) {
          idxObjetivo = (idxObjetivo + 1) % _usuarios.length;
        }
        final targetId = _usuarios[idxObjetivo];

        // Construye el estado inicial a partir de los roles generados, pero
        // garantiza que el llamante es superadministrador: la propiedad asume
        // una solicitud de eliminación legítima (Req 6.4).
        final mapaRoles = <String, RolUsuario>{
          for (var i = 0; i < _usuarios.length; i++) _usuarios[i]: roles[i],
          superadminId: RolUsuario.superadmin,
        };
        final estado = EliminacionEstado(mapaRoles);

        // Precondiciones del estado generado: el objetivo existe y es distinto
        // del llamante superadministrador.
        expect(targetId, isNot(equals(superadminId)));
        expect(estado.rolDe(superadminId), equals(RolUsuario.superadmin));
        expect(estado.existe(targetId), isTrue);

        // El superadministrador solicita eliminar al usuario objetivo.
        final res = estado.eliminarUsuario(
          callerId: superadminId,
          targetUserId: targetId,
        );

        // Invariante central (Property 15 / Req 6.4): la operación tiene éxito
        // y el registro del objetivo deja de existir.
        expect(
          res.esExito,
          isTrue,
          reason: 'un superadmin debe poder eliminar a otro usuario existente',
        );
        expect(
          res.estado.existe(targetId),
          isFalse,
          reason: 'el registro del usuario eliminado no debe seguir existiendo',
        );
        expect(res.estado.rolDe(targetId), isNull);

        // El resto de cuentas persiste inalterado: solo se borra el objetivo.
        for (final id in _usuarios) {
          if (id == targetId) continue;
          expect(
            res.estado.existe(id),
            isTrue,
            reason: 'la eliminación no debe afectar a otras cuentas ($id)',
          );
          expect(res.estado.rolDe(id), equals(estado.rolDe(id)));
        }

        // El estado resultante tiene exactamente una cuenta menos.
        expect(res.estado.roles.length, equals(estado.roles.length - 1));
      },
    );
  });
}
