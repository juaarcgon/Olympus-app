/// Widget raíz de la aplicación Olympus.
///
/// Construye el [MaterialApp] con el tema central (`core/theme`) y el shell de
/// enrutado con guarda de sesión (`core/router`). No contiene lógica de
/// negocio: delega la decisión de qué pantalla mostrar en [AppRouter].
library;

import 'package:flutter/material.dart';

import 'core/router/router.dart';
import 'core/theme/theme.dart';

/// Raíz de la aplicación.
class OlympusApp extends StatelessWidget {
  /// Crea la aplicación Olympus.
  const OlympusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Olympus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AppRouter(),
    );
  }
}
