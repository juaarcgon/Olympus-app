// Tipos de error de dominio (Failure) para la app Olympus.
//
// Esta jerarquía traduce fallos técnicos (excepciones del SDK de Supabase,
// errores de RPC de PostgreSQL, validaciones del cliente) en errores de
// dominio tipados con mensajes claros en español, tal como describe la
// sección "Error Handling" del documento de diseño.
//
// Cada subclase define un mensaje por defecto en español acorde a los
// mensajes exigidos en requirements.md. Se puede sobrescribir el mensaje
// pasando uno personalizado al constructor.

/// Clase base abstracta de todos los errores de dominio.
///
/// Expone un [mensaje] legible en español destinado a mostrarse al usuario.
/// Implementa igualdad por tipo y mensaje para facilitar las pruebas
/// (dos failures son iguales si son de la misma subclase y comparten mensaje).
abstract class Failure {
  const Failure(this.mensaje);

  /// Mensaje de error legible en español.
  final String mensaje;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Failure &&
          runtimeType == other.runtimeType &&
          mensaje == other.mensaje);

  @override
  int get hashCode => Object.hash(runtimeType, mensaje);

  @override
  String toString() => '$runtimeType($mensaje)';
}

/// El correo electrónico ya está asociado a un usuario existente (Req 1.4).
class EmailEnUsoFailure extends Failure {
  const EmailEnUsoFailure([
    super.mensaje = 'El correo electrónico ya está en uso',
  ]);
}

/// El correo electrónico no cumple el formato de una dirección válida (Req 1.5).
class FormatoEmailFailure extends Failure {
  const FormatoEmailFailure([
    super.mensaje = 'El formato del correo electrónico no es válido',
  ]);
}

/// La contraseña tiene menos de 8 caracteres (Req 1.6, 9.6).
class PasswordCortaFailure extends Failure {
  const PasswordCortaFailure([
    super.mensaje = 'La contraseña debe tener al menos 8 caracteres',
  ]);
}

/// Las credenciales no coinciden con ninguna cuenta existente (Req 2.2).
class CredencialesInvalidasFailure extends Failure {
  const CredencialesInvalidasFailure([
    super.mensaje = 'Correo electrónico o contraseña incorrectos',
  ]);
}

/// La cuenta del usuario está suspendida (Req 2.3, 9.10).
class CuentaSuspendidaFailure extends Failure {
  const CuentaSuspendidaFailure([super.mensaje = 'La cuenta está suspendida']);
}

/// No quedan clases disponibles en el bono del usuario (Req 4.3, 8.4).
class SinClasesFailure extends Failure {
  const SinClasesFailure([
    super.mensaje = 'No quedan clases disponibles en tu bono',
  ]);
}

/// La lista de espera de la clase ya está completa (Req 8.12).
class ListaEsperaLlenaFailure extends Failure {
  const ListaEsperaLlenaFailure([
    super.mensaje = 'La lista de espera está completa',
  ]);
}

/// El usuario ya tiene una reserva o figura en la lista de espera (Req 8.6).
class ReservaDuplicadaFailure extends Failure {
  const ReservaDuplicadaFailure([
    super.mensaje = 'Ya existe una reserva para esta clase',
  ]);
}

/// El usuario no tiene permisos suficientes para la operación (Req 5.4, 7.2, 8.2).
class AutorizacionInsuficienteFailure extends Failure {
  const AutorizacionInsuficienteFailure([
    super.mensaje = 'No tienes autorización para realizar esta operación',
  ]);
}

/// Se ha alcanzado el máximo de superadministradores (Req 5.2).
class MaxSuperadminsFailure extends Failure {
  const MaxSuperadminsFailure([
    super.mensaje = 'Se ha alcanzado el número máximo de superadministradores',
  ]);
}

/// Un superadministrador no puede eliminarse a sí mismo (Req 6.7).
class AutoeliminacionFailure extends Failure {
  const AutoeliminacionFailure([
    super.mensaje = 'Un superadministrador no puede eliminarse a sí mismo',
  ]);
}

/// El enlace/token de restablecimiento es inválido o ha caducado (Req 9.4, 9.5).
class TokenInvalidoFailure extends Failure {
  const TokenInvalidoFailure([
    super.mensaje = 'El enlace es inválido o ha caducado',
  ]);
}
