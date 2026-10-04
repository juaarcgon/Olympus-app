/// Constantes centrales del Sistema (Olympus).
///
/// Agrupa los límites e invariantes configurables del dominio descritos en el
/// diseño (`core/config`). Mantenerlos aquí evita "números mágicos" dispersos
/// por la base de código y facilita ajustarlos en el futuro sin romper la
/// estructura existente.
library;

/// Saldo máximo de clases del bono de un Usuario.
///
/// Un bono completo otorga diez (10) clases. El `saldo_clases` nunca debe
/// superar este valor (Req 4.4, 8.10).
const int kBonoMax = 10;

/// Saldo mínimo de clases del bono de un Usuario.
///
/// El `saldo_clases` nunca debe ser inferior a cero (0) (Req 4.4, 8.10).
const int kBonoMin = 0;

/// Aforo máximo configurable de una Clase.
///
/// Límite superior del número de plazas de una Clase. Su valor actual es diez
/// (10) y puede aumentarse en el futuro sin cambiar la estructura (Req 8.1).
const int kAforoMax = 10;

/// Número máximo de Usuarios en la Lista_De_Espera de una Clase.
///
/// Su valor es veinte (20) (Req 8.12).
const int kWaitlistMax = 20;

/// Longitud mínima exigida a una contraseña.
///
/// Las contraseñas deben tener al menos ocho (8) caracteres (Req 1.6, 9.6).
const int kPasswordMinLength = 8;

/// Antelación mínima (en horas) para que una cancelación conlleve reembolso.
///
/// Cancelar con dos (2) horas o más de antelación respecto al Horario_Clase
/// reembolsa una (1) clase; con menos antelación no hay reembolso (Req 8.7, 8.8).
const int kCancelacionHoras = 2;

/// Duración fija de cada franja de Clase, en horas.
///
/// Las Clases se generan en franjas consecutivas de una (1) hora. Un rango de
/// 10:00 a 12:00, por ejemplo, produce dos franjas: 10:00–11:00 y 11:00–12:00.
const int kDuracionFranjaHoras = 1;

/// Comprueba si [horario] es una hora de inicio de franja válida (en punto).
///
/// Las franjas empiezan siempre en punto (minutos, segundos y milisegundos a
/// cero). No hay restricción de hora del día: se permite cualquier franja.
bool esHorarioClaseValido(DateTime horario) {
  return horario.minute == 0 && horario.second == 0 && horario.millisecond == 0;
}
