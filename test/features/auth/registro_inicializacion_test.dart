// Prueba de propiedad del modelo puro de alta de usuario (registro).
//
// Feature: gym-management-app, Property 1
//
// Property 1: Inicialización del bono y estado al registrarse.
// "Para cualquier registro de usuario válido, la cuenta creada debe tener
//  estado == 'activo' y saldo_clases == 10."
//
// Validates: Requirements 1.1, 1.2
//
// La propiedad se verifica contra el modelo de dominio puro del alta
// (`crearCuentaDesdeRegistro`), espejo del trigger `on_auth_user_created` del
// backend (migración 0002), que inserta la fila en `public.profiles` con
// `estado = 'activo'` y `saldo_clases = 10`. Se usa `glados` con un mínimo de
// 100 iteraciones. Para cada registro válido arbitrario (nombre, apellidos e
// email generados) se comprueba que la cuenta creada cumple siempre:
//   - estado == activo (Req 1.1),
//   - saldoClases == 10 (Req 1.2),
// con total independencia de los datos concretos del registro. Esto mirror-ea
// la inicialización que Supabase materializa en el backend sin red ni backend,
// igual que el resto de pruebas de dominio de la app.

// `glados` reexporta el paquete `test`, que ya aporta `expect`, `group`,
// `test`, los matchers y la API de aserciones; por eso no se importa
// `flutter_test` (evita la colisión de símbolos y es suficiente para esta
// prueba de dominio puro sin widgets).
import 'package:glados/glados.dart';
import 'package:olympus/core/config/constants.dart';
import 'package:olympus/features/auth/domain/registration_model.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Generador de un registro de usuario válido arbitrario.
///
/// Combina cadenas no vacías para nombre y apellidos y deriva un email bien
/// formado y un id a partir de otra cadena arbitraria. Al variar todos los
/// campos se cubre un amplio espacio de registros válidos, expresando
/// fielmente "cualquier registro de usuario válido": la inicialización del
/// perfil debe ser siempre la misma sea cual sea el contenido de los datos.
Generator<RegistroUsuario> get _anyRegistro => any
    .combine2(
      any.nonEmptyLetterOrDigits,
      any.nonEmptyLetterOrDigits,
      (String nombre, String apellidos) => (nombre, apellidos),
    )
    .bind(
      ((String, String) nombreApellidos) => any.nonEmptyLetterOrDigits.map(
        (String local) => RegistroUsuario(
          id: 'id-$local',
          nombre: nombreApellidos.$1,
          apellidos: nombreApellidos.$2,
          email: '$local@example.com',
        ),
      ),
    );

void main() {
  group(
    'Feature: gym-management-app, Property 1 - inicialización del bono y estado '
    'al registrarse',
    () {
      Glados(_anyRegistro).test(
        'para cualquier registro válido, la cuenta creada tiene estado activo y '
        'saldo_clases == 10 (Req 1.1, 1.2)',
        (registro) {
          final cuenta = crearCuentaDesdeRegistro(registro);

          // Req 1.1: la cuenta recién creada está en estado 'activo'.
          expect(
            cuenta.estado,
            EstadoUsuario.activo,
            reason: 'una cuenta recién registrada debe quedar en estado activo',
          );
          expect(cuenta.estaActivo, isTrue);

          // Req 1.2: el saldo de clases se inicializa en 10 (bono completo).
          expect(
            cuenta.saldoClases,
            kBonoMax,
            reason: 'el saldo de clases inicial debe ser $kBonoMax',
          );
          expect(cuenta.saldoClases, 10);
        },
      );
    },
  );
}
