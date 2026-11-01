// Notificaciones push (Firebase Cloud Messaging) de la app Olympus.
//
// Solo se usa la mensajería de Firebase: la sesión y los datos siguen en
// Supabase. Este servicio:
//
//   - Inicializa Firebase en Android/iOS. Si falta la configuración
//     (`google-services.json` / `GoogleService-Info.plist`) o la plataforma no
//     es móvil, queda DESACTIVADO y todas sus operaciones son no-op: la app
//     funciona igual, solo que sin notificaciones push.
//   - Registra el token FCM del móvil en Supabase (RPC `registrar_dispositivo`,
//     migración 0016) al iniciar sesión, al arrancar con sesión, al conceder el
//     permiso y cuando FCM renueva el token; lo elimina (RPC
//     `eliminar_dispositivo`) al cerrar sesión, para que el móvil no reciba
//     avisos de otra cuenta.
//   - Pide el permiso de notificaciones solo cuando tiene sentido (al entrar en
//     una lista de espera, o desde "Mi perfil"), no nada más abrir la app.
//   - Con la app abierta, Android no muestra la notificación del sistema: se
//     reenvía a [onAvisoEnPrimerPlano] para mostrarla dentro de la app. Las
//     notificaciones recibidas o pulsadas se publican en [avisos] para que las
//     pantallas refresquen sus datos.
//   - Guarda su estado ([diagnostico]) para mostrarlo en "Mi perfil" y poder
//     saber, sin cable USB, por qué un móvil no recibe avisos.
//
// Nota sobre `getToken()`: firebase_messaging 17 lo marca como obsoleto en
// favor de `register()` + `onRegistered` (Firebase Installation ID). Con esa
// API nueva el móvil nunca llegó a registrarse en las pruebas, así que se usa
// `getToken()`, que devuelve el token directamente y que la API HTTP v1 de FCM
// sigue aceptando. Migrar al FID cuando Google retire el token.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tipo de aviso enviado por la Edge Function `notificar-plaza`.
const String kAvisoPlazaConseguida = 'plaza_conseguida';

/// Estado de las notificaciones en este móvil, para mostrarlo al Usuario.
enum EstadoPush {
  /// La plataforma no admite notificaciones push (web, escritorio).
  noSoportado,

  /// Firebase no pudo inicializarse (falta configuración u otro error).
  sinConfiguracion,

  /// El Usuario no ha concedido (o ha denegado) el permiso de notificaciones.
  sinPermiso,

  /// Permiso concedido, pero el móvil aún no se ha registrado en el servidor.
  pendienteRegistro,

  /// Todo listo: el móvil está registrado y recibirá avisos.
  activo,
}

/// Instantánea del estado de las notificaciones con su detalle técnico.
class DiagnosticoPush {
  const DiagnosticoPush(this.estado, [this.detalle]);

  /// Estado general.
  final EstadoPush estado;

  /// Último error técnico, si lo hay (para soporte).
  final String? detalle;
}

/// Servicio estático de notificaciones push.
class PushNotifications {
  PushNotifications._();

  static bool _activo = false;
  static String? _errorInicio;
  static String? _ultimoError;

  /// Último token registrado con éxito en Supabase en esta sesión de la app.
  static String? _tokenRegistrado;

  static final StreamController<Map<String, dynamic>> _avisos =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Indica si las notificaciones push están disponibles en este dispositivo.
  static bool get disponible => _activo;

  /// Datos (`data`) de cada notificación recibida con la app abierta o pulsada
  /// por el Usuario. Incluye `tipo` (p. ej. [kAvisoPlazaConseguida]).
  static Stream<Map<String, dynamic>> get avisos => _avisos.stream;

  /// Se invoca con el título y el cuerpo de una notificación recibida con la
  /// app en primer plano en Android (el sistema no la muestra en ese caso).
  static void Function(String titulo, String cuerpo)? onAvisoEnPrimerPlano;

  static bool get _plataformaMovil =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get _plataforma =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Inicializa Firebase y los listeners. Llamar una vez tras `initSupabase()`.
  static Future<void> iniciar() async {
    if (_activo || !_plataformaMovil) return;
    try {
      // Sin opciones: Android las lee de google-services.json e iOS de
      // GoogleService-Info.plist.
      await Firebase.initializeApp();
    } on Object catch (e) {
      _errorInicio = '$e';
      debugPrint('Notificaciones push desactivadas: $e');
      return;
    }
    _activo = true;

    final messaging = FirebaseMessaging.instance;

    try {
      // iOS: mostrar la notificación del sistema también con la app abierta.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } on Object catch (e) {
      debugPrint('Opciones de presentación no aplicadas: $e');
    }

    FirebaseMessaging.onMessage.listen((mensaje) {
      final notificacion = mensaje.notification;
      if (defaultTargetPlatform == TargetPlatform.android &&
          notificacion != null) {
        onAvisoEnPrimerPlano?.call(
          notificacion.title ?? '',
          notificacion.body ?? '',
        );
      }
      _avisos.add(mensaje.data);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _avisos.add(m.data));

    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen((token) => unawaited(_registrar(token)));

    final auth = Supabase.instance.client.auth;
    auth.onAuthStateChange.listen((estado) {
      if (estado.session != null &&
          (estado.event == AuthChangeEvent.signedIn ||
              estado.event == AuthChangeEvent.initialSession)) {
        unawaited(registrarDispositivo());
      }
    });
    // Sesión restaurada al arrancar.
    if (auth.currentSession != null) unawaited(registrarDispositivo());
  }

  /// Obtiene el token FCM y lo asocia al Usuario de la sesión.
  ///
  /// Nunca lanza: un fallo (sin red, iOS sin token de APNs todavía…) se guarda
  /// en [diagnostico] y se reintenta en la siguiente ocasión.
  static Future<void> registrarDispositivo() async {
    if (!_activo) return;
    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        _ultimoError = 'Firebase no ha devuelto ningún token';
        return;
      }
      await _registrar(token);
    } on Object catch (e) {
      _ultimoError = 'No se pudo obtener el token: $e';
      debugPrint(_ultimoError);
    }
  }

  static Future<void> _registrar(String token) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;
    try {
      await client.rpc(
        'registrar_dispositivo',
        params: <String, dynamic>{
          'p_token': token,
          'p_plataforma': _plataforma,
        },
      );
      _tokenRegistrado = token;
      _ultimoError = null;
    } on Object catch (e) {
      _ultimoError = 'No se pudo registrar en el servidor: $e';
      debugPrint(_ultimoError);
    }
  }

  /// Pide permiso para mostrar notificaciones (Android 13+ e iOS) y vuelve a
  /// registrar el dispositivo. Devuelve `true` si el permiso está concedido.
  static Future<bool> pedirPermiso() async {
    if (!_activo) return false;
    try {
      final ajustes = await FirebaseMessaging.instance.requestPermission();
      final concedido = _permisoConcedido(ajustes.authorizationStatus);
      // En iOS el token solo está disponible tras conceder el permiso.
      if (concedido) await registrarDispositivo();
      return concedido;
    } on Object catch (e) {
      _ultimoError = 'No se pudo pedir el permiso: $e';
      debugPrint(_ultimoError);
      return false;
    }
  }

  /// Estado actual de las notificaciones en este móvil (para "Mi perfil").
  static Future<DiagnosticoPush> diagnostico() async {
    if (!_plataformaMovil) {
      return const DiagnosticoPush(EstadoPush.noSoportado);
    }
    if (!_activo) {
      return DiagnosticoPush(EstadoPush.sinConfiguracion, _errorInicio);
    }
    try {
      final ajustes = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (!_permisoConcedido(ajustes.authorizationStatus)) {
        return DiagnosticoPush(EstadoPush.sinPermiso, _ultimoError);
      }
    } on Object catch (e) {
      return DiagnosticoPush(EstadoPush.sinPermiso, '$e');
    }
    if (_tokenRegistrado == null) {
      return DiagnosticoPush(EstadoPush.pendienteRegistro, _ultimoError);
    }
    return const DiagnosticoPush(EstadoPush.activo);
  }

  static bool _permisoConcedido(AuthorizationStatus estado) =>
      estado == AuthorizationStatus.authorized ||
      estado == AuthorizationStatus.provisional;

  /// Desvincula este móvil del Usuario. Debe llamarse ANTES de cerrar sesión
  /// (la RPC necesita la sesión). Nunca lanza.
  static Future<void> desregistrarDispositivo() async {
    if (!_activo) return;
    try {
      final token =
          // ignore: deprecated_member_use
          _tokenRegistrado ?? await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await Supabase.instance.client.rpc(
        'eliminar_dispositivo',
        params: <String, dynamic>{'p_token': token},
      );
      _tokenRegistrado = null;
    } on Object catch (e) {
      debugPrint('No se pudo desregistrar el dispositivo: $e');
    }
  }
}
