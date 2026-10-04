// Zona horaria del gimnasio (Europe/Madrid).
//
// El gimnasio es físico y opera en horario de España, así que la hora de las
// Clases debe interpretarse y mostrarse SIEMPRE en Europe/Madrid, con el cambio
// verano/invierno (DST) automático, independientemente de la zona horaria del
// dispositivo del Usuario.
//
// Se apoya en el paquete `timezone`, que contiene las reglas DST. Debe llamarse
// a [initGymTimezone] una vez durante el arranque de la app (en `main`).

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Identificador IANA de la zona horaria del gimnasio.
const String kGymTimeZoneId = 'Europe/Madrid';

/// Ubicación de la zona horaria del gimnasio, inicializada en [initGymTimezone].
late tz.Location _gymLocation;

/// Inicializa la base de datos de zonas horarias y fija la del gimnasio.
///
/// Debe invocarse una sola vez al arrancar la app, antes de usar las demás
/// funciones de este módulo.
void initGymTimezone() {
  tz_data.initializeTimeZones();
  _gymLocation = tz.getLocation(kGymTimeZoneId);
}

/// Convierte una fecha/hora en UTC (la que almacena el backend) a la hora del
/// gimnasio (Europe/Madrid) para mostrarla en la UI.
tz.TZDateTime utcAHoraGimnasio(DateTime utc) {
  return tz.TZDateTime.from(utc.toUtc(), _gymLocation);
}

/// Construye un instante en la zona del gimnasio a partir de los componentes de
/// fecha y hora que el Usuario elige (interpretados como hora de Madrid) y lo
/// devuelve en UTC, listo para persistir en el backend.
///
/// Ejemplo: 17:00 del 5 de julio en Madrid (UTC+2 en verano) produce las 15:00
/// UTC. En invierno (UTC+1) produciría las 16:00 UTC. El desfase lo resuelve
/// automáticamente la base de datos de zonas horarias.
DateTime horaGimnasioAUtc(
  int anio,
  int mes,
  int dia,
  int hora, [
  int minuto = 0,
]) {
  final enMadrid = tz.TZDateTime(_gymLocation, anio, mes, dia, hora, minuto);
  return enMadrid.toUtc();
}
