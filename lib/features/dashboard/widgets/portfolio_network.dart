import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../../../shared/widgets/hydro_glass.dart';
import '../point_link.dart';

/// Vista general de los cuerpos de agua de la cartera.
///
/// Cada punto se proyecta como una captación sobre una lámina de agua con
/// perspectiva 2.5D: se inclina levemente al arrastrar (pan) y los cuerpos
/// lejanos se ven más pequeños y más oscuros (profundidad). Sirve como
/// navegación hacia la vista singular de cada punto.
class PortfolioNetwork extends StatefulWidget {
  const PortfolioNetwork({
    required this.points,
    required this.onPointSelected,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onPointSelected;

  @override
  State<PortfolioNetwork> createState() => _PortfolioNetworkState();
}

class _PortfolioNetworkState extends State<PortfolioNetwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  /// Inclinación de la cámara (-1 a 1) al arrastrar horizontal/vertical.
  double _tiltX = 0;
  double _tiltY = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _animation.stop();
      _animation.value = 0;
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _onPan(DragUpdateDetails d) {
    setState(() {
      _tiltX = (_tiltX + d.delta.dx * 0.004).clamp(-1, 1);
      _tiltY = (_tiltY + d.delta.dy * 0.004).clamp(-1, 1);
    });
  }

  void _resetTilt() => setState(() {
    _tiltX = 0;
    _tiltY = 0;
  });

  @override
  Widget build(BuildContext context) {
    final nodes = widget.points.take(8).toList(growable: false);
    final extraCount = widget.points.length - nodes.length;
    final connected = widget.points
        .where((point) => pointLinkOf(point) == PointLink.connected)
        .length;
    final gaps = widget.points
        .where((point) => pointLinkOf(point) == PointLink.gap)
        .length;
    return HydroGlass(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Cuerpos de agua',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Text(
                '$connected en línea',
                style: const TextStyle(
                  color: Color(0xFF66E0C2),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Arrastra para mirar alrededor · toca un punto para abrir su vista',
            style: TextStyle(color: Color(0xFF91A8AA), fontSize: 10),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: _onPan,
                  onPanEnd: (_) => _resetTilt(),
                  onTapUp: (details) {
                    final index = _WaterScenePainter.nearestPoint(
                      size,
                      nodes.length,
                      details.localPosition,
                      _animation.value,
                      _tiltX,
                      _tiltY,
                    );
                    if (index != null) widget.onPointSelected(nodes[index]);
                  },
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, _) => CustomPaint(
                      painter: _WaterScenePainter(
                        points: nodes,
                        phase: _animation.value,
                        tiltX: _tiltX,
                        tiltY: _tiltY,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            ),
          ),
          if (extraCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: Text(
                '+$extraCount puntos más en el listado',
                style: const TextStyle(color: Color(0xFF91A8AA), fontSize: 10),
              ),
            ),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              const _NetworkLegend(
                color: Color(0xFF66E0C2),
                label: 'Conectado',
              ),
              _NetworkLegend(
                color: const Color(0xFFFFC46B),
                label: 'Advertencia${gaps == 0 ? '' : ' · $gaps'}',
              ),
              const _NetworkLegend(
                color: Color(0xFFFF847A),
                label: 'Incidencia',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NetworkLegend extends StatelessWidget {
  const _NetworkLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(color: Color(0xFF91A8AA), fontSize: 10),
      ),
    ],
  );
}

class _WaterScenePainter extends CustomPainter {
  const _WaterScenePainter({
    required this.points,
    required this.phase,
    required this.tiltX,
    required this.tiltY,
  });

  final List<Map<String, dynamic>> points;
  final double phase;
  final double tiltX;
  final double tiltY;

  static const _mint = Color(0xFF66E0C2);
  static const _amber = Color(0xFFFFC46B);
  static const _coral = Color(0xFFFF847A);

  // Proyección 2.5D: cada punto ocupa una fila de profundidad distinta.
  // Los puntos traseros (depth alto) se ven más pequeños, más altos y atenuados.
  static double _depthOf(int index, int count) {
    // Reparte en 3 filas de profundidad.
    if (count <= 1) return 0.15;
    final row = (index % 3);
    return 0.15 + row * 0.42;
  }

  static Offset _project(
    Size size,
    int index,
    int count,
    double tiltX,
    double tiltY,
  ) {
    final depth = _depthOf(index, count);
    // Horizonte y suelo.
    final horizon = size.height * 0.30;
    final floor = size.height * 0.95;
    final depthScale = 1.0 - depth * 0.55; // escala por profundidad
    // Reparte horizontalmente según profundidad (más atrás = más al centro).
    final col = (index / 3).floor();
    final cols = math.max((count / 3).ceil(), 1);
    final spread = size.width * 0.9 * depthScale;
    final centerX = size.width * 0.5 + tiltX * 26;
    final x =
        centerX -
        spread / 2 +
        (cols <= 1 ? spread / 2 : spread * col / (cols - 1));
    final baseY = horizon + (floor - horizon) * (1 - depthScale) + tiltY * 12;
    return Offset(x, baseY);
  }

  static int? nearestPoint(
    Size size,
    int count,
    Offset position,
    double phase,
    double tiltX,
    double tiltY,
  ) {
    for (var index = 0; index < count; index++) {
      final p = _project(size, index, count, tiltX, tiltY);
      final depthScale = 1.0 - _depthOf(index, count) * 0.55;
      final hit = Rect.fromCenter(
        center: Offset(p.dx, p.dy - 34 * depthScale),
        width: 64 * depthScale + 20,
        height: 90 * depthScale + 20,
      );
      if (hit.contains(position)) return index;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(frame, const Radius.circular(16)));

    // Cielo superior.
    canvas.drawRect(
      frame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16343A), Color(0xFF0C1E22)],
        ).createShader(frame),
    );

    final horizon = size.height * 0.30;
    // Horizonte luminoso cyan Ikolu.
    canvas.drawRect(
      Rect.fromLTWH(0, horizon - 2, size.width, 4),
      Paint()
        ..shader = LinearGradient(
          colors: [
            IkoluColors.cyan.withValues(alpha: 0),
            IkoluColors.cyan.withValues(alpha: 0.35),
            IkoluColors.cyan.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, horizon - 2, size.width, 4)),
    );

    // Lámina de agua con ondas en perspectiva (más abajo = más ancho).
    final water = Path()..moveTo(0, horizon);
    for (var x = 0.0; x <= size.width; x += 6) {
      final along = x / size.width;
      final wave =
          math.sin(along * math.pi * 2 + phase * math.pi * 2) * 3 +
          math.sin(along * math.pi * 6 - phase * math.pi * 4) * 1.4;
      water.lineTo(x, horizon + 6 + wave);
    }
    water
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      water,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF14616C),
                const Color(0xFF0E3A44),
                const Color(0xFF0A242C),
              ],
            ).createShader(
              Rect.fromLTWH(0, horizon, size.width, size.height - horizon),
            ),
    );

    // Reflejos cáusticos que se abren con la perspectiva.
    for (var i = 0; i < 5; i++) {
      final t = i / 4;
      final y = horizon + 24 + (size.height - horizon - 30) * t;
      final width = size.width * (0.25 + t * 0.9);
      final cx = size.width * 0.5 + tiltX * 30 * t;
      final drift = math.sin(phase * math.pi * 2 + i * 1.7) * 22 * (0.4 + t);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + drift, y),
          width: width,
          height: 10 + t * 14,
        ),
        Paint()..color = IkoluColors.cyan.withValues(alpha: 0.05 + t * 0.05),
      );
    }

    // Puntos proyectados, ordenados de atrás hacia adelante (pintar los lejanos primero).
    final order = List<int>.generate(points.length, (i) => i)
      ..sort(
        (a, b) =>
            _depthOf(b, points.length).compareTo(_depthOf(a, points.length)),
      );
    for (final index in order) {
      _drawPoint(canvas, size, index, points.length, points[index]);
    }

    canvas.restore();
  }

  void _drawPoint(
    Canvas canvas,
    Size size,
    int index,
    int count,
    Map<String, dynamic> point,
  ) {
    final link = pointLinkOf(point);
    final color = switch (link) {
      PointLink.connected => _mint,
      PointLink.gap => _amber,
      PointLink.incident => _coral,
    };
    final depth = _depthOf(index, count);
    final depthScale = 1.0 - depth * 0.55;
    final fade = 1.0 - depth * 0.5; // los lejanos se atenúan
    final p = _project(size, index, count, tiltX, tiltY);
    // Vaivén suave de boya: cada punto mece con su propia fase.
    final bob = math.sin(phase * math.pi * 2 + index * 1.3) * 3.2 * depthScale;
    final head = Offset(p.dx, p.dy - 34 * depthScale + bob);

    // Sombra/reflejo sobre el agua.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(p.dx, p.dy + 4),
        width: 46 * depthScale,
        height: 12 * depthScale,
      ),
      Paint()..color = color.withValues(alpha: 0.16 * fade),
    );

    // Mástil.
    canvas.drawLine(
      Offset(p.dx, p.dy),
      head,
      Paint()
        ..color = color.withValues(alpha: 0.85 * fade)
        ..strokeWidth = (2.4 * depthScale).clamp(1.0, 3.0)
        ..strokeCap = StrokeCap.round,
    );

    // Cabeza con halo.
    canvas.drawCircle(
      head,
      12 * depthScale,
      Paint()..color = color.withValues(alpha: 0.18 * fade),
    );
    canvas.drawCircle(
      head,
      7.5 * depthScale,
      Paint()..color = const Color(0xFF0C1F24),
    );
    canvas.drawCircle(
      head,
      4.6 * depthScale,
      Paint()..color = color.withValues(alpha: fade),
    );

    // Pulso de incidencia.
    if (link == PointLink.incident) {
      final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
      canvas.drawCircle(
        head,
        (11 + pulse * 8) * depthScale,
        Paint()
          ..color = _coral.withValues(alpha: (0.32 - pulse * 0.22) * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // Rótulo solo en los puntos del frente para no saturar.
    if (depthScale > 0.75) {
      final title = point['title']?.toString() ?? 'Punto';
      final short = title.length > 12 ? '${title.substring(0, 11)}…' : title;
      final text = TextPainter(
        text: TextSpan(
          text: short,
          style: TextStyle(
            color: Color(0xFFF4FBF8).withValues(alpha: fade),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 90);
      final w = text.width + 12;
      final h = text.height + 6;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(head.dx, head.dy - 20),
          width: w,
          height: h,
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = const Color(0xFF081619).withValues(alpha: 0.72),
      );
      text.paint(
        canvas,
        Offset(head.dx - text.width / 2, head.dy - 20 - text.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaterScenePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.tiltX != tiltX ||
      oldDelegate.tiltY != tiltY ||
      oldDelegate.points != points;
}
