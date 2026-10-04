// Notificaciones tipo "toast" ancladas arriba a la derecha.
//
// Sustituyen a los `SnackBar` (que aparecían abajo) por tarjetas flotantes en
// la esquina superior derecha, apiladas verticalmente. El color comunica el
// tipo:
//
//   - Éxito  -> verde  (operación correcta).
//   - Error  -> rojo   (fallo o `Failure` de dominio).
//
// Cada notificación aparece con una breve animación, se mantiene unos segundos
// y desaparece sola; también puede cerrarse pulsando la X. El uso típico es:
//
// ```dart
// AppNotifications.exito(context, 'Reserva confirmada');
// AppNotifications.error(context, failure.mensaje);
// ```
//
// La implementación se apoya en un único `OverlayEntry` por aplicación que
// gestiona una pila de mensajes, de modo que varias notificaciones seguidas se
// apilan sin solaparse.

import 'package:flutter/material.dart';

/// Tipo de notificación, que determina el color y el icono mostrados.
enum _TipoNotificacion { exito, error }

/// API estática para mostrar notificaciones flotantes arriba a la derecha.
class AppNotifications {
  AppNotifications._();

  /// Muestra una notificación de ÉXITO (verde) con el [mensaje] indicado.
  static void exito(BuildContext context, String mensaje) {
    _mostrar(context, mensaje, _TipoNotificacion.exito);
  }

  /// Muestra una notificación de ERROR (rojo) con el [mensaje] indicado.
  static void error(BuildContext context, String mensaje) {
    _mostrar(context, mensaje, _TipoNotificacion.error);
  }

  static void _mostrar(
    BuildContext context,
    String mensaje,
    _TipoNotificacion tipo,
  ) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _NotificationHost.of(overlay).add(mensaje, tipo);
  }
}

/// Gestiona la pila de notificaciones sobre un único [OverlayState].
///
/// Mantiene un `OverlayEntry` persistente anclado arriba a la derecha que
/// renderiza una columna con las notificaciones activas.
class _NotificationHost {
  _NotificationHost._(this._overlay);

  final OverlayState _overlay;
  final GlobalKey<_NotificationStackState> _stackKey =
      GlobalKey<_NotificationStackState>();
  OverlayEntry? _entry;

  static final Map<OverlayState, _NotificationHost> _hosts =
      <OverlayState, _NotificationHost>{};

  /// Obtiene (o crea) el host asociado a un [OverlayState].
  static _NotificationHost of(OverlayState overlay) {
    return _hosts.putIfAbsent(overlay, () => _NotificationHost._(overlay));
  }

  void add(String mensaje, _TipoNotificacion tipo) {
    _ensureInserted();
    _stackKey.currentState?.push(mensaje, tipo);
  }

  void _ensureInserted() {
    if (_entry != null) return;
    _entry = OverlayEntry(
      builder: (context) => _NotificationStack(key: _stackKey),
    );
    _overlay.insert(_entry!);
  }
}

/// Columna de notificaciones activas anclada arriba a la derecha.
class _NotificationStack extends StatefulWidget {
  const _NotificationStack({super.key});

  @override
  State<_NotificationStack> createState() => _NotificationStackState();
}

class _NotificationStackState extends State<_NotificationStack> {
  final List<_NotificationData> _items = <_NotificationData>[];
  int _nextId = 0;

  void push(String mensaje, _TipoNotificacion tipo) {
    final id = _nextId++;
    setState(() {
      _items.add(_NotificationData(id: id, mensaje: mensaje, tipo: tipo));
    });
  }

  void _remove(int id) {
    setState(() => _items.removeWhere((item) => item.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      top: media.padding.top + 12,
      right: 12,
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final item in _items)
                _NotificationCard(
                  key: ValueKey<int>(item.id),
                  data: item,
                  onDismiss: () => _remove(item.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Datos de una notificación individual.
class _NotificationData {
  const _NotificationData({
    required this.id,
    required this.mensaje,
    required this.tipo,
  });

  final int id;
  final String mensaje;
  final _TipoNotificacion tipo;
}

/// Tarjeta animada de una notificación; se auto-cierra tras unos segundos.
class _NotificationCard extends StatefulWidget {
  const _NotificationCard({
    required this.data,
    required this.onDismiss,
    super.key,
  });

  final _NotificationData data;
  final VoidCallback onDismiss;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;

  /// Tiempo que la notificación permanece visible antes de auto-cerrarse.
  static const Duration _visibleDuration = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();

    // Auto-cierre: espera visible y luego anima la salida.
    Future<void>.delayed(_visibleDuration).then((_) => _cerrar());
  }

  Future<void> _cerrar() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esExito = widget.data.tipo == _TipoNotificacion.exito;
    final color = esExito ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final icono = esExito ? Icons.check_circle : Icons.error;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _offset,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(10),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icono, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.data.mensaje,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _cerrar,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, color: Colors.white70, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
