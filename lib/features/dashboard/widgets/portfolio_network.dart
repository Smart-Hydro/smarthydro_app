import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../../../shared/widgets/hydro_glass.dart';
import '../capture_stage.dart';
import '../point_link.dart';

/// Vista general de los cuerpos de agua de la cartera.
///
/// Cada punto se proyecta sobre una lámina de agua con perspectiva 2.5D:
/// los pozos se dibujan como un fuste hundido con su nivel interior y las
/// captaciones superficiales como boyas flotantes con oleaje. Los puntos se
/// reparten a lo ancho en carriles de profundidad alternos (atrás = más
/// pequeños, atenuados y hacia el centro). Arrastrar inclina la cámara y
/// tocar un punto abre su vista singular.
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
    with TickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  /// Entrada escalonada de los puntos al montar la tarjeta.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
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
      _entrance
        ..stop()
        ..value = 1;
    } else {
      if (!_animation.isAnimating) _animation.repeat();
      if (!_entrance.isAnimating && _entrance.value < 1) _entrance.forward();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _entrance.dispose();
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
    final wells = widget.points
        .where((point) => captureKindOf(point) == CaptureKind.well)
        .length;
    final surface = widget.points.length - wells;
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
            'Toca un punto para abrir su vista · arrastra para mirar alrededor',
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
                      _tiltX,
                      _tiltY,
                    );
                    if (index != null) widget.onPointSelected(nodes[index]);
                  },
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_animation, _entrance]),
                    builder: (context, _) => CustomPaint(
                      painter: _WaterScenePainter(
                        points: nodes,
                        phase: _animation.value,
                        entrance: _entrance.value,
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
              _TypeLegend(kind: CaptureKind.well, label: 'Pozo · $wells'),
              _TypeLegend(
                kind: CaptureKind.surface,
                label: 'Superficial · $surface',
              ),
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

/// Glifo del tipo de captación para la leyenda: fuste de pozo o boya.
class _TypeLegend extends StatelessWidget {
  const _TypeLegend({required this.kind, required this.label});

  final CaptureKind kind;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 10,
        height: 10,
        child: CustomPaint(painter: _TypeGlyphPainter(kind: kind)),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(color: Color(0xFF91A8AA), fontSize: 10),
      ),
    ],
  );
}

class _TypeGlyphPainter extends CustomPainter {
  const _TypeGlyphPainter({required this.kind});

  final CaptureKind kind;
  static const _fog = Color(0xFFC3D3D2);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _fog;
    if (kind == CaptureKind.well) {
      // Fuste hundido: trapecio vertical con aro de brocal.
      final cx = size.width / 2;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, 2.4),
          width: size.width * 0.9,
          height: 3.2,
        ),
        paint,
      );
      final shaft = Path()
        ..moveTo(cx - 2.6, 3.2)
        ..lineTo(cx + 2.6, 3.2)
        ..lineTo(cx + 1.6, size.height)
        ..lineTo(cx - 1.6, size.height)
        ..close();
      canvas.drawPath(shaft, paint..color = _fog.withValues(alpha: 0.55));
    } else {
      // Boya: casco semihundido con mástil.
      final cx = size.width / 2;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, size.height - 2.6),
          width: size.width * 0.9,
          height: 4,
        ),
        paint,
      );
      canvas.drawLine(
        Offset(cx, size.height - 4.4),
        Offset(cx, 1.4),
        paint
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        Offset(cx, 1.4),
        1.6,
        paint..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TypeGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind;
}

class _WaterScenePainter extends CustomPainter {
  const _WaterScenePainter({
    required this.points,
    required this.phase,
    required this.entrance,
    required this.tiltX,
    required this.tiltY,
  });

  final List<Map<String, dynamic>> points;
  final double phase;
  final double entrance;
  final double tiltX;
  final double tiltY;

  static const _mint = Color(0xFF66E0C2);
  static const _amber = Color(0xFFFFC46B);
  static const _coral = Color(0xFFFF847A);
  static const _tau = math.pi * 2;

  /// Carril de profundidad alterno: 0 lejano → 1 cercano. Alternar evita
  /// filas rígidas y reparte los puntos como una red sobre la lámina.
  static double _nearnessOf(int index) => switch (index % 3) {
    0 => 0.94,
    1 => 0.56,
    _ => 0.24,
  };

  static double _scaleOf(int index) => 0.62 + _nearnessOf(index) * 0.52;

  static Offset _project(
    Size size,
    int index,
    int count,
    double tiltX,
    double tiltY,
  ) {
    final nearness = _nearnessOf(index);
    final horizon = size.height * 0.24;
    final floor = size.height * 0.94;
    // Reparto horizontal parejo entre márgenes.
    final t = count <= 1 ? 0.5 : index / (count - 1);
    final margin = size.width * 0.10;
    var x = margin + t * (size.width - margin * 2);
    // Convergencia de perspectiva: lo lejano se acerca al centro.
    final centerX = size.width / 2;
    x = centerX + (x - centerX) * (0.72 + nearness * 0.28);
    x += tiltX * 20 * nearness;
    final y = horizon + (floor - horizon) * nearness + tiltY * 12 * nearness;
    return Offset(x, y);
  }

  static int? nearestPoint(
    Size size,
    int count,
    Offset position,
    double tiltX,
    double tiltY,
  ) {
    // De frente hacia atrás: si dos áreas se solapan, gana el más cercano.
    final order = List<int>.generate(count, (i) => i)
      ..sort((a, b) => _nearnessOf(b).compareTo(_nearnessOf(a)));
    for (final index in order) {
      final p = _project(size, index, count, tiltX, tiltY);
      final s = _scaleOf(index);
      final hit = Rect.fromCenter(
        center: Offset(p.dx, p.dy - 10 * s),
        width: 78 * s + 14,
        height: 98 * s + 14,
      );
      if (hit.contains(position)) return index;
    }
    return null;
  }

  /// Aparición escalonada por punto al montar la tarjeta (0..1).
  double _entranceOf(int index) {
    final raw = (entrance * 1.5 - index * 0.12).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(raw);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(frame, const Radius.circular(16)));

    _paintSky(canvas, frame);
    final horizon = size.height * 0.24;
    _paintHorizonGlow(canvas, size, horizon);
    _paintWater(canvas, size, horizon);
    _paintCrests(canvas, size, horizon);
    _paintCaustics(canvas, size, horizon);

    // Puntos de atrás hacia adelante.
    final order = List<int>.generate(points.length, (i) => i)
      ..sort((a, b) => _nearnessOf(a).compareTo(_nearnessOf(b)));
    for (final index in order) {
      _drawPoint(canvas, size, index, points[index]);
    }

    canvas.restore();
  }

  void _paintSky(Canvas canvas, Rect frame) {
    canvas.drawRect(
      frame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF15343B), Color(0xFF0C1F24)],
        ).createShader(frame),
    );
    // Resplandor alto, como luz sobre el agua lejana.
    canvas.drawCircle(
      Offset(frame.width * 0.78, frame.height * 0.10),
      frame.shortestSide * 0.34,
      Paint()..color = IkoluColors.cyan.withValues(alpha: 0.05),
    );
  }

  void _paintHorizonGlow(Canvas canvas, Size size, double horizon) {
    canvas.drawRect(
      Rect.fromLTWH(0, horizon - 1.5, size.width, 3),
      Paint()
        ..shader = LinearGradient(
          colors: [
            IkoluColors.cyan.withValues(alpha: 0),
            IkoluColors.cyan.withValues(alpha: 0.38),
            IkoluColors.cyan.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, horizon - 1.5, size.width, 3)),
    );
  }

  void _paintWater(Canvas canvas, Size size, double horizon) {
    final water = Path()..moveTo(0, horizon);
    for (var x = 0.0; x <= size.width; x += 6) {
      final along = x / size.width;
      final wave =
          math.sin(along * _tau + phase * _tau) * 2.6 +
          math.sin(along * _tau * 3 - phase * _tau * 2) * 1.2;
      water.lineTo(x, horizon + 5 + wave);
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
              colors: const [
                Color(0xFF1A7079),
                Color(0xFF114B56),
                Color(0xFF0A2830),
              ],
            ).createShader(
              Rect.fromLTWH(0, horizon, size.width, size.height - horizon),
            ),
    );
  }

  /// Crestas de oleaje en perspectiva: separación y amplitud crecen hacia
  /// el frente, reforzando la lectura de lámina de agua.
  void _paintCrests(Canvas canvas, Size size, double horizon) {
    for (var k = 0; k < 4; k++) {
      final t = (k + 1) / 4.5;
      final y = horizon + 16 + (size.height - horizon - 26) * t;
      final amplitude = 1.2 + t * 3.2;
      final drift = phase * _tau * (0.6 + t * 0.7) + k * 1.9;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 8) {
        final along = x / size.width;
        path.lineTo(
          x,
          y +
              math.sin(along * _tau * (1.4 + t) + drift) * amplitude +
              math.sin(along * _tau * 4.2 - drift * 1.6) * amplitude * 0.35,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF9BE8DC).withValues(alpha: 0.05 + t * 0.11)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9 + t * 1.1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintCaustics(Canvas canvas, Size size, double horizon) {
    for (var i = 0; i < 5; i++) {
      final t = i / 4;
      final y = horizon + 22 + (size.height - horizon - 30) * t;
      final width = size.width * (0.22 + t * 0.85);
      final cx = size.width * 0.5 + tiltX * 28 * t;
      final drift = math.sin(phase * _tau + i * 1.7) * 20 * (0.4 + t);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + drift, y),
          width: width,
          height: 9 + t * 13,
        ),
        Paint()..color = IkoluColors.cyan.withValues(alpha: 0.05 + t * 0.06),
      );
    }
  }

  void _drawPoint(
    Canvas canvas,
    Size size,
    int index,
    Map<String, dynamic> point,
  ) {
    final appear = _entranceOf(index);
    if (appear <= 0.01) return;
    final link = pointLinkOf(point);
    final color = switch (link) {
      PointLink.connected => _mint,
      PointLink.gap => _amber,
      PointLink.incident => _coral,
    };
    final nearness = _nearnessOf(index);
    final s = _scaleOf(index) * appear;
    final fade = (0.55 + nearness * 0.45) * appear.clamp(0.0, 1.0);
    final p = _project(size, index, points.length, tiltX, tiltY);
    final kind = captureKindOf(point);

    final head = kind == CaptureKind.well
        ? _drawWell(canvas, p, s, fade, color, index)
        : _drawBuoy(canvas, p, s, fade, color, index);

    if (link == PointLink.incident) {
      final pulse = (math.sin(phase * _tau) + 1) / 2;
      canvas.drawCircle(
        head,
        (10 + pulse * 8) * s,
        Paint()
          ..color = _coral.withValues(alpha: (0.34 - pulse * 0.24) * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    _drawLabel(canvas, head, s, fade, point);
  }

  /// Pozo: fuste hundido con nivel interior, burbujas y brocal. Devuelve la
  /// posición de la cabeza para rótulo y pulso.
  Offset _drawWell(
    Canvas canvas,
    Offset p,
    double s,
    double fade,
    Color color,
    int index,
  ) {
    final shaftH = 28.0 * s;
    final halfW = 8.5 * s;

    // Halo de estado sobre la lámina.
    canvas.drawOval(
      Rect.fromCenter(center: p, width: 34 * s, height: 10 * s),
      Paint()..color = color.withValues(alpha: 0.15 * fade),
    );

    // Fuste: trapecio que se hunde y desvanece con la profundidad.
    final shaft = Path()
      ..moveTo(p.dx - halfW, p.dy)
      ..lineTo(p.dx + halfW, p.dy)
      ..lineTo(p.dx + halfW * 0.72, p.dy + shaftH)
      ..lineTo(p.dx - halfW * 0.72, p.dy + shaftH)
      ..close();
    canvas.drawPath(
      shaft,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.32 * fade),
            color.withValues(alpha: 0.03 * fade),
          ],
        ).createShader(Rect.fromLTWH(p.dx - halfW, p.dy, halfW * 2, shaftH)),
    );

    // Nivel interior: línea brillante que respira dentro del fuste.
    final levelY =
        p.dy + shaftH * (0.36 + 0.07 * math.sin(phase * _tau + index * 1.1));
    canvas.drawLine(
      Offset(p.dx - halfW * 0.82, levelY),
      Offset(p.dx + halfW * 0.82, levelY),
      Paint()
        ..color = const Color(0xFFEFFFFA).withValues(alpha: 0.55 * fade)
        ..strokeWidth = 1.6 * s
        ..strokeCap = StrokeCap.round,
    );

    // Burbujas ascendiendo por el fuste.
    for (var b = 0; b < 2; b++) {
      final rise = (phase + index * 0.31 + b * 0.47) % 1.0;
      final bubbleY = p.dy + shaftH * (0.92 - rise * 0.6);
      canvas.drawCircle(
        Offset(p.dx + (b == 0 ? -1 : 1) * halfW * 0.3, bubbleY),
        (1.3 + b * 0.5) * s,
        Paint()
          ..color = const Color(
            0xFFEFFFFA,
          ).withValues(alpha: (1 - rise) * 0.4 * fade),
      );
    }

    // Brocal: elipse oscura con aro de color de estado.
    final collar = Rect.fromCenter(center: p, width: 26 * s, height: 9 * s);
    canvas.drawOval(collar, Paint()..color = const Color(0xFF0A1B20));
    canvas.drawOval(
      collar,
      Paint()
        ..color = color.withValues(alpha: 0.9 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s,
    );

    // Poste y cabeza.
    final head = Offset(p.dx, p.dy - 18 * s);
    canvas.drawLine(
      Offset(p.dx, p.dy - 2 * s),
      head,
      Paint()
        ..color = color.withValues(alpha: 0.85 * fade)
        ..strokeWidth = 2.2 * s
        ..strokeCap = StrokeCap.round,
    );
    _drawHead(canvas, head, s, fade, color);
    return head;
  }

  /// Captación superficial: boya con casco, mástil y anillo de oleaje.
  Offset _drawBuoy(
    Canvas canvas,
    Offset p,
    double s,
    double fade,
    Color color,
    int index,
  ) {
    final bob = math.sin(phase * _tau + index * 1.7) * 2.6 * s;
    final base = Offset(p.dx, p.dy + bob);

    // Reflejo y anillo de oleaje expansivo.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(p.dx, p.dy + 3 * s),
        width: 40 * s,
        height: 10 * s,
      ),
      Paint()..color = color.withValues(alpha: 0.16 * fade),
    );
    final ringT = (phase + index * 0.41) % 1.0;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(p.dx, p.dy + 2 * s),
        width: (24 + ringT * 30) * s,
        height: (7 + ringT * 9) * s,
      ),
      Paint()
        ..color = color.withValues(alpha: (1 - ringT) * 0.3 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1 * s,
    );

    // Casco semihundido.
    final hull = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(base.dx, base.dy - 4 * s),
        width: 20 * s,
        height: 9 * s,
      ),
      Radius.circular(4.5 * s),
    );
    canvas.drawRRect(hull, Paint()..color = const Color(0xFF0C2027));
    canvas.drawLine(
      Offset(base.dx - 8 * s, base.dy - 2.5 * s),
      Offset(base.dx + 8 * s, base.dy - 2.5 * s),
      Paint()
        ..color = color.withValues(alpha: 0.7 * fade)
        ..strokeWidth = 1.4 * s
        ..strokeCap = StrokeCap.round,
    );

    // Mástil y cabeza.
    final head = Offset(base.dx, base.dy - 26 * s);
    canvas.drawLine(
      Offset(base.dx, base.dy - 6 * s),
      head,
      Paint()
        ..color = color.withValues(alpha: 0.85 * fade)
        ..strokeWidth = 2 * s
        ..strokeCap = StrokeCap.round,
    );
    _drawHead(canvas, head, s, fade, color);
    return head;
  }

  void _drawHead(Canvas canvas, Offset head, double s, double fade, Color c) {
    canvas.drawCircle(
      head,
      8.5 * s,
      Paint()..color = c.withValues(alpha: 0.2 * fade),
    );
    canvas.drawCircle(head, 5.4 * s, Paint()..color = const Color(0xFF0C1F24));
    canvas.drawCircle(
      head,
      3.3 * s,
      Paint()..color = c.withValues(alpha: fade),
    );
  }

  void _drawLabel(
    Canvas canvas,
    Offset head,
    double s,
    double fade,
    Map<String, dynamic> point,
  ) {
    if (s < 0.62) return;
    final title = point['title']?.toString() ?? 'Punto';
    final short = title.length > 11 ? '${title.substring(0, 10)}…' : title;
    final text = TextPainter(
      text: TextSpan(
        text: short,
        style: TextStyle(
          color: const Color(0xFFF4FBF8).withValues(alpha: fade),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 84);
    final w = text.width + 10;
    final h = text.height + 5;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(head.dx, head.dy - 14 * s),
        width: w,
        height: h,
      ),
      const Radius.circular(7),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xFF081619).withValues(alpha: 0.72 * fade),
    );
    text.paint(
      canvas,
      Offset(head.dx - text.width / 2, head.dy - 14 * s - text.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _WaterScenePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.entrance != entrance ||
      oldDelegate.tiltX != tiltX ||
      oldDelegate.tiltY != tiltY ||
      oldDelegate.points != points;
}
