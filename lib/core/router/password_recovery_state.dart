// Estado compartido del flujo de recuperación de contraseña.
//
// Problema que resuelve: en móvil, al abrir el enlace del correo, el deep link
// lo procesa `supabase_flutter` durante `Supabase.initialize()` (en `main()`),
// que es ANTES de que el `AppRouter` monte su listener de `onAuthStateChange`
// en `initState`. Como el stream solo entrega eventos futuros a cada nuevo
// suscriptor, el router se perdía el evento `passwordRecovery` y dejaba al
// Usuario en la zona autenticada en lugar de la pantalla de nueva contraseña.
//
// Solución: suscribirse a `onAuthStateChange` lo antes posible (desde `main()`
// mediante [observarRecuperacionPassword]) y recordar en un [ValueNotifier] si
// hay un flujo de recuperación en curso. El `AppRouter` observa este notifier,
// de modo que el estado se captura aunque el evento llegue antes de montar la
// UI.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Clave global del Navigator raíz del `MaterialApp`.
///
/// Permite manipular la pila de navegación desde fuera del árbol de widgets
/// (p. ej. al llegar el deep link de recuperación) para destapar la pantalla
/// de nueva contraseña aunque haya rutas apiladas (login -> recuperar).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Indica si hay un flujo de recuperación de contraseña activo (el Usuario abrió
/// el enlace del correo y debe fijar una nueva contraseña, Req 9.6/9.7).
///
/// Lo actualiza [observarRecuperacionPassword] al recibir `passwordRecovery` y
/// se restablece a `false` al cerrar sesión o tras consumirse el flujo.
final ValueNotifier<bool> recuperacionPasswordActiva = ValueNotifier<bool>(
  false,
);

StreamSubscription<AuthState>? _suscripcion;

/// Empieza a observar los cambios de autenticación para detectar el evento de
/// recuperación de contraseña lo antes posible (idealmente desde `main()`,
/// justo tras `initSupabase()`).
///
/// Es idempotente: múltiples llamadas no crean suscripciones duplicadas.
void observarRecuperacionPassword() {
  if (_suscripcion != null) return;
  _suscripcion = Supabase.instance.client.auth.onAuthStateChange.listen((
    AuthState state,
  ) {
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        recuperacionPasswordActiva.value = true;
        // Limpia cualquier ruta apilada (p. ej. login -> "Recuperar
        // contraseña") para que la ResetPasswordScreen que el AppRouter pinta
        // por debajo quede visible de inmediato, sin que el Usuario tenga que
        // pulsar atrás.
        _descartarRutasApiladas();
      case AuthChangeEvent.signedOut:
        recuperacionPasswordActiva.value = false;
      default:
        break;
    }
  });
}

/// Hace pop de todas las rutas apiladas sobre la raíz del Navigator, dejando
/// visible el widget raíz (controlado por el AppRouter). Se pospone al final
/// del frame para asegurar que el Navigator ya está montado.
void _descartarRutasApiladas() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final nav = rootNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
  });
}

/// Marca el flujo de recuperación como consumido (p. ej. tras fijar con éxito
/// la nueva contraseña) para que el enrutado vuelva a su comportamiento normal.
void finalizarRecuperacionPassword() {
  recuperacionPasswordActiva.value = false;
}
