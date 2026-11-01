/// Punto de entrada de la aplicación Olympus.
///
/// Garantiza la inicialización del binding de Flutter, arranca el cliente de
/// Supabase ([initSupabase]) y monta la app dentro de un [ProviderScope] de
/// Riverpod para que las features puedan declarar y consumir providers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/config/config.dart';
import 'core/notifications/push_notifications.dart';
import 'core/router/password_recovery_state.dart';
import 'core/utils/gym_timezone.dart';
import 'shared/widgets/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fija la zona horaria del gimnasio (Europe/Madrid) para que la hora de las
  // clases sea siempre la de España, independiente del dispositivo.
  initGymTimezone();
  // Carga los símbolos de formato de fecha en español de España para que el
  // calendario muestre meses y días en español (semana de lunes a domingo).
  await initializeDateFormatting('es_ES');
  await initSupabase();
  // Observa el evento de recuperación de contraseña cuanto antes: el deep link
  // del correo puede procesarse antes de montar el AppRouter, así no se pierde.
  observarRecuperacionPassword();
  // Notificaciones push (FCM). Si falta la configuración de Firebase queda
  // desactivado sin afectar al resto de la app.
  PushNotifications.onAvisoEnPrimerPlano = (titulo, cuerpo) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    AppNotifications.exitoEnOverlay(
      overlay,
      cuerpo.isEmpty ? titulo : '$titulo $cuerpo',
    );
  };
  await PushNotifications.iniciar();
  runApp(const ProviderScope(child: OlympusApp()));
}
