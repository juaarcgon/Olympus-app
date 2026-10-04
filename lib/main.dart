/// Punto de entrada de la aplicación Olympus.
///
/// Garantiza la inicialización del binding de Flutter, arranca el cliente de
/// Supabase ([initSupabase]) y monta la app dentro de un [ProviderScope] de
/// Riverpod para que las features puedan declarar y consumir providers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/config.dart';
import 'core/utils/gym_timezone.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fija la zona horaria del gimnasio (Europe/Madrid) para que la hora de las
  // clases sea siempre la de España, independiente del dispositivo.
  initGymTimezone();
  await initSupabase();
  runApp(const ProviderScope(child: OlympusApp()));
}
