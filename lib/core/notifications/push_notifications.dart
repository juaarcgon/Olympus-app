// Notificaciones push (Firebase Cloud Messaging) de la app Olympus.
//
// Solo se usa la mensajería de Firebase: la sesión y los datos siguen en
// Supabase. Este servicio:
//
//   - Inicializa Firebase en Android/iOS. Si falta la configuración
//     (`google-services.json` / `GoogleService-Info.plist`) o la plataforma no
//     es móvil, queda DESACTIVADO y todas sus operaciones son no-op: la app
//     funciona igual, solo que sin notificaciones push.
//   - Registra el móvil en Supabase (RPC `registrar_dispositivo`, migración
//     0015) al iniciar sesión, al arrancar con sesión y cada vez que FCM lo
//     sincroniza; lo elimina (RPC `eliminar_dispositivo`) al cerrar sesión,
//     para que el móvil no reciba avisos de otra cuenta. El identificador es el
//     Firebase Installation ID (FID) que entrega `onRegistered`: FCM ha
//     sustituido los tokens de registro (`getToken`, obsoleto) por el FID.
//   - Pide el permiso de notificaciones solo cuando tiene sentido (al entrar en
//     una lista de espera), no nada más abrir la app.
//   - Con la app abierta, Android no muestra la notificación del sistema: se
//     reenvía a [onAvisoEnPrimerPlano] para mostrarla dentro de la app. Las
//     notificaciones recibidas o pulsadas se publican en [avisos] para que las
//     pantallas refresquen sus datos.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tipo de aviso enviado por la Edge Function `notificar-plaza`.
const String kAvisoPlazaConseguida = 'plaza_conseguida';

/// Servicio estático de notificaciones push.
class PushNotifications {
  PushNotifications._();

  static bool _activo = false;

  /// Último FID entregado por FCM (puede llegar antes de iniciar sesión).
  static String? _fid;
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
      debugPrint('Notificaciones push desactivadas: $e');
      return;
    }
    _activo = true;

    final messaging = FirebaseMessaging.instance;

    // iOS: mostrar la notificación del sistema también con la app abierta.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

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

    // FCM entrega el FID al arrancar (sincronización rutinaria) y cuando
    // cambia. Se guarda siempre y se sube a Supabase si hay sesión.
    messaging.onRegistered.listen((fid) {
      _fid = fid;
      unawaited(_registrar(fid));
    });

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

  /// Asocia este móvil al Usuario de la sesión.
  ///
  /// Sube el FID ya conocido y pide a FCM que vuelva a registrar el móvil, lo
  /// que dispara `onRegistered` con el FID vigente. Nunca lanza: un fallo (sin
  /// red, iOS sin token de APNs todavía…) solo se registra en el log y se
  /// reintenta en la siguiente ocasión.
  static Future<void> registrarDispositivo() async {
    if (!_activo) return;
    final fid = _fid;
    if (fid != null) await _registrar(fid);
    try {
      await FirebaseMessaging.instance.register();
    } on Object catch (e) {
      debugPrint('No se pudo registrar en FCM: $e');
    }
  }

  static Future<void> _registrar(String fid) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;
    try {
      await client.rpc(
        'registrar_dispositivo',
        params: <String, dynamic>{'p_fid': fid, 'p_plataforma': _plataforma},
      );
    } on Object catch (e) {
      debugPrint('No se pudo registrar el dispositivo: $e');
    }
  }

  /// Pide permiso para mostrar notificaciones (Android 13+ e iOS) y vuelve a
  /// registrar el dispositivo. Devuelve `true` si el permiso está concedido.
  static Future<bool> pedirPermiso() async {
    if (!_activo) return false;
    try {
      final ajustes = await FirebaseMessaging.instance.requestPermission();
      final concedido =
          ajustes.authorizationStatus == AuthorizationStatus.authorized ||
          ajustes.authorizationStatus == AuthorizationStatus.provisional;
      // En iOS el registro en FCM solo se completa tras conceder el permiso.
      if (concedido) await registrarDispositivo();
      return concedido;
    } on Object catch (e) {
      debugPrint('No se pudo pedir el permiso de notificaciones: $e');
      return false;
    }
  }

  /// Desvincula este móvil del Usuario. Debe llamarse ANTES de cerrar sesión
  /// (la RPC necesita la sesión). Nunca lanza.
  static Future<void> desregistrarDispositivo() async {
    final fid = _fid;
    if (!_activo || fid == null) return;
    try {
      await Supabase.instance.client.rpc(
        'eliminar_dispositivo',
        params: <String, dynamic>{'p_fid': fid},
      );
    } on Object catch (e) {
      debugPrint('No se pudo desregistrar el dispositivo: $e');
    }
  }
}
