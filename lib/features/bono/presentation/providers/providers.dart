// Providers de Riverpod para el Servicio_Bono (saldo de clases del Usuario).
//
// Esta capa de estado expone el Saldo_De_Clases del Usuario autenticado para
// que la UI (p. ej. la pantalla de reservas) pueda mostrarlo y refrescarlo en
// tiempo real tras reservar o cancelar, sin obligar al Usuario a salir y
// volver a entrar en la aplicación (Req 4.1).
//
//   - [bonoRepositoryProvider]: inyecta la implementación concreta del
//     repositorio ([BonoRepositoryImpl]) de forma testable (se puede
//     sobrescribir en pruebas con `overrideWithValue`).
//   - [saldoBonoProvider]: `FutureProvider` que lee el saldo actual. Se
//     invalida tras cada reserva/cancelación para reflejar el valor nuevo.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/bono_repository_impl.dart';
import '../../domain/repositories/bono_repository.dart';

/// Provee la implementación del [BonoRepository] (Servicio_Bono).
///
/// Por defecto construye un [BonoRepositoryImpl] respaldado por Supabase. En
/// pruebas puede sobrescribirse con `bonoRepositoryProvider.overrideWithValue`.
final bonoRepositoryProvider = Provider<BonoRepository>(
  (ref) => BonoRepositoryImpl(),
);

/// Expone el Saldo_De_Clases actual del Usuario autenticado (carga/éxito/error).
///
/// La UI lo observa para mostrar cuántas clases del bono le quedan. Tras
/// reservar o cancelar, el notifier de reservas invalida este provider para
/// que el valor se actualice al instante (Req 4.1).
final saldoBonoProvider = FutureProvider<int>(
  (ref) => ref.read(bonoRepositoryProvider).getSaldo(),
);
