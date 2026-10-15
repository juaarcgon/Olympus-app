// Modelo de dominio puro del alta de usuario (registro) para la app Olympus.
//
// Reúne, como función pura en memoria (sin efectos secundarios, sin
// dependencias de Supabase y completamente determinista), el espejo del
// comportamiento del backend al crear la cuenta de un Usuario a partir de un
// registro válido: el trigger `on_auth_user_created` (migración 0002) inserta
// la fila en `public.profiles` con `estado = 'activo'` y `saldo_clases = 10`.
//
// Supabase (trigger + constraints de la tabla `profiles`) es quien materializa
// realmente esta inicialización en el backend; este modelo la mirror-ea de
// forma determinista para poder verificar la propiedad de dominio
// ("inicialización del bono y estado al registrarse", Property 1 /
// Req 1.1, 1.2) con pruebas basadas en propiedades, de forma consistente con
// el resto de modelos de dominio de la app (`bono_model.dart`,
// `credential_model.dart`, `superadmin_model.dart`).

import 'package:olympus/core/config/constants.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Datos de un registro de usuario válido.
///
/// Representa la entrada conocida del formulario de registro (Req 1.1): los
/// campos [nombre], [apellidos] y [email]. La contraseña no forma parte de
/// este modelo porque su tratamiento (hashing) lo cubre `credential_model.dart`
/// y Supabase Auth; aquí solo interesa la inicialización del perfil creado.
///
/// Inmutable.
class RegistroUsuario {
  const RegistroUsuario({
    required this.id,
    required this.nombre,
    required this.apellidos,
    required this.email,
  });

  /// Identificador de la cuenta de Auth que origina el perfil.
  final String id;

  /// Nombre del Usuario (Req 1.1).
  final String nombre;

  /// Apellidos del Usuario (Req 1.1).
  final String apellidos;

  /// Correo electrónico del Usuario.
  final String email;
}

/// Crea la cuenta de Usuario a partir de un registro válido (espejo del trigger
/// `on_auth_user_created`).
///
/// Devuelve el [Profile] inicial que el Sistema persiste tras un registro
/// válido, con las invariantes de inicialización garantizadas:
///   - `estado == EstadoUsuario.activo` (Req 1.1),
///   - `saldoClases == kBonoMax == 10` (Req 1.2),
///   - `rol == RolUsuario.usuario` (rol estándar por defecto).
///
/// Es una función pura y determinista: para los mismos datos de registro
/// produce siempre el mismo perfil inicial, con independencia de los valores
/// de [RegistroUsuario.nombre], [RegistroUsuario.apellidos] o
/// [RegistroUsuario.email].
Profile crearCuentaDesdeRegistro(RegistroUsuario registro) {
  return Profile(
    id: registro.id,
    nombre: registro.nombre,
    apellidos: registro.apellidos,
    email: registro.email,
    // Inicialización del bono: un bono completo otorga 10 clases (Req 1.2).
    saldoClases: kBonoMax,
    // Estado inicial de toda cuenta recién creada (Req 1.1).
    estado: EstadoUsuario.activo,
    // Rol estándar por defecto; el superadmin se concede aparte (Req 5).
    rol: RolUsuario.usuario,
  );
}

// ---------------------------------------------------------------------------
// Modelo puro del rechazo de email duplicado en el registro (Property 4).
// ---------------------------------------------------------------------------
//
// Reúne, como modelo de dominio puro, inmutable y determinista (sin red ni
// Supabase), el espejo del comportamiento del backend al registrar una cuenta:
// la columna `profiles.email` es NOT NULL UNIQUE (migración 0001) y Supabase
// Auth rechaza un segundo alta con un email ya registrado, que la capa de
// repositorio traduce a [EmailEnUsoFailure] (ver `auth_repository_impl.dart`,
// Req 1.4).
//
// Invariante modelada (Req 1.4):
// - Para cualquier email ya asociado a un usuario existente, un segundo intento
//   de registro con ese mismo email se rechaza con [EmailEnUsoFailure] y NO
//   crea una segunda cuenta (el total de cuentas no cambia).
// - La unicidad del email replica el constraint UNIQUE del backend: se compara
//   de forma normalizada (recortando espacios y sin distinguir mayúsculas de
//   minúsculas) para reflejar que `profiles.email` es espejo de
//   `auth.users.email`.

/// Normaliza un email para comparar unicidad igual que el backend.
///
/// Recorta espacios (el repositorio hace `email.trim()` antes de llamar a Auth)
/// y pasa a minúsculas, de modo que `A@X.com` y `  a@x.com ` se consideran el
/// mismo email, reflejando la unicidad efectiva de `auth.users.email`.
String normalizarEmail(String email) => email.trim().toLowerCase();

/// Estado inmutable en memoria del conjunto de cuentas registradas.
///
/// Modela únicamente lo necesario para la invariante de email único: las
/// cuentas creadas (sus [Profile]) indexadas por su email normalizado. Es la
/// fuente de verdad sobre la que opera [registrar], que devuelve siempre un
/// nuevo estado sin mutar el actual (espejo de la tabla `profiles` con su
/// constraint UNIQUE sobre `email`).
class RegistroEstado {
  /// Crea un estado a partir del mapa de cuentas por email normalizado.
  ///
  /// Copia defensivamente el mapa recibido para garantizar la inmutabilidad.
  RegistroEstado([Map<String, Profile> cuentasPorEmail = const {}])
    : cuentasPorEmail = Map<String, Profile>.unmodifiable(cuentasPorEmail);

  /// Cuentas registradas indexadas por su email normalizado.
  final Map<String, Profile> cuentasPorEmail;

  /// Número de cuentas registradas en el estado actual.
  int get totalCuentas => cuentasPorEmail.length;

  /// Indica si ya existe una cuenta con el email [email] (comparación
  /// normalizada).
  bool existeEmail(String email) =>
      cuentasPorEmail.containsKey(normalizarEmail(email));

  /// Registra una nueva cuenta a partir de [registro] (espejo del alta con el
  /// constraint UNIQUE de `profiles.email`).
  ///
  /// Reglas (Req 1.4):
  /// - Si ya existe una cuenta con el mismo email (normalizado): se rechaza con
  ///   [EmailEnUsoFailure] y el estado no cambia (no se crea una segunda
  ///   cuenta).
  /// - En otro caso: crea la cuenta con [crearCuentaDesdeRegistro] y devuelve el
  ///   nuevo estado que la incluye.
  ///
  /// Devuelve un [RegistroResult] con el nuevo estado y el perfil creado, o el
  /// fallo en caso de rechazo.
  RegistroResult registrar(RegistroUsuario registro) {
    final clave = normalizarEmail(registro.email);

    // Email duplicado: se rechaza sin crear una segunda cuenta (Req 1.4).
    if (cuentasPorEmail.containsKey(clave)) {
      return RegistroResult.fallo(this, const EmailEnUsoFailure());
    }

    // Email libre: se crea la cuenta con la inicialización estándar.
    final cuenta = crearCuentaDesdeRegistro(registro);
    final nuevas = <String, Profile>{...cuentasPorEmail, clave: cuenta};
    return RegistroResult.exito(RegistroEstado(nuevas), cuenta);
  }

  @override
  String toString() => 'RegistroEstado(totalCuentas: $totalCuentas)';
}

/// Resultado de [RegistroEstado.registrar].
///
/// Contiene el nuevo [estado] (siempre no nulo; coincide con el estado previo
/// cuando la operación se rechaza), la [cuenta] creada en caso de éxito y, de
/// forma mutuamente excluyente, el [failure] en caso de rechazo.
class RegistroResult {
  const RegistroResult._({required this.estado, this.cuenta, this.failure});

  /// Crea un resultado de registro exitoso con la [cuenta] creada.
  const RegistroResult.exito(RegistroEstado estado, Profile cuenta)
    : this._(estado: estado, cuenta: cuenta);

  /// Crea un resultado de registro rechazado; el estado no cambia.
  const RegistroResult.fallo(RegistroEstado estado, Failure failure)
    : this._(estado: estado, failure: failure);

  /// Estado resultante de la operación.
  final RegistroEstado estado;

  /// Cuenta creada cuando el registro tuvo éxito; `null` si fue rechazado.
  final Profile? cuenta;

  /// Fallo de dominio cuando el registro fue rechazado; `null` si tuvo éxito.
  final Failure? failure;

  /// Indica si la operación tuvo éxito.
  bool get esExito => failure == null;

  @override
  String toString() => esExito
      ? 'RegistroResult.exito($estado)'
      : 'RegistroResult.fallo($failure)';
}
