/// Tema visual central de la aplicación Olympus.
///
/// Define un [ThemeData] mínimo basado en Material 3 y una semilla de color,
/// usado por `OlympusApp` en `lib/app.dart`. Se mantiene simple a propósito;
/// las features posteriores pueden ampliarlo sin romper la estructura.
library;

import 'package:flutter/material.dart';

/// Agrupa la configuración de tema de la aplicación.
abstract final class AppTheme {
  /// Color semilla a partir del cual se deriva el esquema de color Material 3.
  static const Color _seedColor = Color(0xFF1565C0);

  /// Tema claro de la aplicación.
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
  );
}
