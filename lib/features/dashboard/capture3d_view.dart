import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'point_link.dart';

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'capture3d_view_stub.dart'
    if (dart.library.html) 'capture3d_view_web.dart'
    as impl;

/// Vista 3D reutilizable del punto de captación (pozo o agua superficial).
///
/// Renderiza un escenario Three.js real en web (WebGL, orbitable) y cae a una
/// vista previa 2D en plataformas no web. Pensada para moverse a otras
/// presentaciones sin tocar su contenido: solo hay que darle los datos del
/// punto.
///
/// El iframe se crea una sola vez por tipo de punto: los cambios de nivel,
/// caudal y estado (p. ej. durante el replay) se envían con `postMessage` y
/// la escena los interpola suavemente, sin recargar ni saltar.
class Capture3DView extends StatefulWidget {
  const Capture3DView({
    required this.isSurface,
    required this.levelFill,
    required this.flowLitersPerSecond,
    required this.link,
    this.levelMeters,
    super.key,
  });

  final bool isSurface;
  final double? levelFill;
  final double? flowLitersPerSecond;
  final PointLink link;
  final double? levelMeters;

  @override
  State<Capture3DView> createState() => _Capture3DViewState();
}

class _Capture3DViewState extends State<Capture3DView> {
  String get _status => switch (widget.link) {
    PointLink.connected => 'connected',
    PointLink.gap => 'gap',
    PointLink.incident => 'incident',
  };

  String get _kind => widget.isSurface ? 'surface' : 'well';

  /// Tipo de vista estable: NO depende de los valores vivos, así el platform
  /// view (y su iframe) sobrevive a las actualizaciones del replay.
  String get _viewType => 'capture3d-$_kind';

  double get _fill => (widget.levelFill ?? 0.6).clamp(0.0, 1.0);
  double get _flow => widget.flowLitersPerSecond ?? 0;

  String get _initialUrl {
    final params = [
      'kind=$_kind',
      'fill=${_fill.toStringAsFixed(2)}',
      'flow=${_flow.toStringAsFixed(2)}',
      'status=$_status',
    ].join('&');
    return 'capture3d.html?$params';
  }

  @override
  void didUpdateWidget(covariant Capture3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSurface != widget.isSurface) return; // cambia el viewType
    impl.postCaptureUpdate(_viewType, {
      'fill': _fill,
      'flow': _flow,
      'status': _status,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return _Capture3DFallback(isSurface: widget.isSurface, link: widget.link);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: impl.buildPlatformView(_viewType, _initialUrl),
    );
  }
}

/// Fallback para plataformas sin WebGL/webview embebido.
class _Capture3DFallback extends StatelessWidget {
  const _Capture3DFallback({required this.isSurface, required this.link});

  final bool isSurface;
  final PointLink link;

  @override
  Widget build(BuildContext context) {
    final color = switch (link) {
      PointLink.connected => const Color(0xFF66E0C2),
      PointLink.gap => const Color(0xFFFFC46B),
      PointLink.incident => const Color(0xFFFF847A),
    };
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF10222B), Color(0xFF0C181D), Color(0xFF081114)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSurface
                  ? Icons.waves_rounded
                  : Icons.vertical_align_bottom_rounded,
              color: color,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              isSurface ? 'Agua superficial' : 'Pozo subterráneo',
              style: const TextStyle(
                color: Color(0xFFE8F2F1),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Vista 3D disponible en la versión web',
              style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
