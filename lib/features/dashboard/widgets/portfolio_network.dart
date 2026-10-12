import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/widgets/hydro_glass.dart';
import '../point_link.dart';

/// Cuerpo de agua del inicio. Cada punto es una captación sobre la superficie.
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
    duration: const Duration(seconds: 16),
  );

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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$connected en línea',
              style: const TextStyle(
                color: Color(0xFF66E0C2),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 300,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final index = _WaterBodyPainter.nearestIntake(
                      size,
                      nodes.length,
                      details.localPosition,
                      _animation.value,
                    );
                    if (index != null) widget.onPointSelected(nodes[index]);
                  },
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, _) => CustomPaint(
                      painter: _WaterBodyPainter(
                        points: nodes,
                        phase: _animation.value,
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
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '+$extraCount puntos en el listado',
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

class _WaterBodyPainter extends CustomPainter {
  const _WaterBodyPainter({required this.points, required this.phase});

  final List<Map<String, dynamic>> points;
  final double phase;

  static const _mint = Color(0xFF66E0C2);
  static const _amber = Color(0xFFFFC46B);
  static const _coral = Color(0xFFFF847A);

  static double _surfaceY(Size size, double x, double phase) {
    final width = math.max(size.width, 1.0);
    final along = x / width;
    final travel = phase * math.pi * 2;
    final base = size.height * 0.32;
    // Harmónicos enteros: en phase 0 y 1 la ola coincide y el bucle no salta.
    return base +
        math.sin(along * math.pi * 2 + travel) * 12 +
        math.sin(along * math.pi * 4 - travel * 2) * 4.2 +
        math.sin(along * math.pi * 8 + travel * 3) * 1.4;
  }

  static double _intakeX(Size size, int index, int count) {
    final slots = math.max(count, 1);
    final span = size.width - 36;
    return 18 + span * ((index + 0.5) / slots);
  }

  static int? nearestIntake(
    Size size,
    int count,
    Offset position,
    double phase,
  ) {
    for (var index = 0; index < count; index++) {
      final x = _intakeX(size, index, count);
      final surface = _surfaceY(size, x, phase);
      final hit = Rect.fromCenter(
        center: Offset(x, surface - 18),
        width: 48,
        height: 78,
      );
      if (hit.contains(position)) return index;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(sky, const Radius.circular(16)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16343A), Color(0xFF0E2429), Color(0xFF071316)],
        ).createShader(sky),
    );

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(sky, const Radius.circular(16)));
    canvas.drawPath(
      _bodyPath(size),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C6E74), Color(0xFF123E49), Color(0xFF0A242C)],
        ).createShader(sky),
    );
    canvas.drawPath(
      _skinPath(size),
      Paint()..color = const Color(0xFF3D9AA0).withValues(alpha: 0.28),
    );
    _drawCaustic(canvas, size);
    canvas.drawPath(
      _crestPath(size),
      Paint()
        ..color = const Color(0xFFD8FFF4).withValues(alpha: 0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    for (var index = 0; index < points.length; index++) {
      _drawIntake(canvas, size, index, points.length, points[index]);
    }
    canvas.restore();
  }

  Path _bodyPath(Size size) {
    final path = Path()..moveTo(0, _surfaceY(size, 0, phase));
    for (var x = 4.0; x < size.width; x += 4) {
      path.lineTo(x, _surfaceY(size, x, phase));
    }
    path
      ..lineTo(size.width, _surfaceY(size, size.width, phase))
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  /// Lámina clara bajo la cresta. Su grosor respira con una ola en contrafase.
  Path _skinPath(Size size) {
    final path = Path()..moveTo(0, _surfaceY(size, 0, phase));
    for (var x = 5.0; x < size.width; x += 5) {
      path.lineTo(x, _surfaceY(size, x, phase));
    }
    path.lineTo(size.width, _surfaceY(size, size.width, phase));
    final width = math.max(size.width, 1.0);
    for (var x = size.width; x >= 0; x -= 5.0) {
      path.lineTo(x, _skinFloor(size, x, width));
    }
    path
      ..lineTo(0, _skinFloor(size, 0, width))
      ..close();
    return path;
  }

  double _skinFloor(Size size, double x, double width) {
    final along = x / width;
    final breath = math.sin(along * math.pi * 3 - phase * math.pi * 4) * 4;
    return _surfaceY(size, x, phase) + 26 + breath;
  }

  Path _crestPath(Size size) {
    final path = Path()..moveTo(0, _surfaceY(size, 0, phase));
    for (var x = 4.0; x < size.width; x += 4) {
      path.lineTo(x, _surfaceY(size, x, phase));
    }
    path.lineTo(size.width, _surfaceY(size, size.width, phase));
    return path;
  }

  void _drawCaustic(Canvas canvas, Size size) {
    final width = math.max(size.width, 1.0);
    final travel = phase * math.pi * 2;
    final path = Path();
    for (var x = 0.0; x <= size.width; x += 5) {
      final along = x / width;
      final y =
          _surfaceY(size, x, phase) +
          16 +
          math.sin(along * math.pi * 6 - travel * 2) * 5;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFB8FFF0).withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawIntake(
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
    final x = _intakeX(size, index, count);
    final surface = _surfaceY(size, x, phase);
    final head = Offset(x, surface - 28);

    final title = point['title']?.toString() ?? 'Punto';
    final short = title.length > 10 ? '${title.substring(0, 9)}…' : title;
    final text = TextPainter(
      text: TextSpan(
        text: short,
        style: const TextStyle(
          color: Color(0xFFF4FBF8),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 72);

    // Pill badge de fondo para el texto del punto
    final badgeW = text.width + 12;
    final badgeH = text.height + 6;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x, head.dy - 18),
        width: badgeW,
        height: badgeH,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      badgeRect,
      Paint()..color = const Color(0xFF081619).withValues(alpha: 0.88),
    );
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    text.paint(
      canvas,
      Offset(x - text.width / 2, head.dy - 18 - text.height / 2),
    );

    // Pin de captación moderno con anillo de halo y centro brillante
    canvas.drawCircle(head, 10, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawCircle(head, 7, Paint()..color = const Color(0xFF0C1F24));
    canvas.drawCircle(
      head,
      4.5,
      Paint()
        ..color = color.withValues(alpha: link == PointLink.gap ? 0.75 : 1),
    );
    // Destello blanco central
    canvas.drawCircle(
      head.translate(-1, -1),
      1.5,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );

    // Mástil que conecta con el agua
    canvas.drawLine(
      head.translate(0, 7),
      Offset(x, surface),
      Paint()
        ..color = color.withValues(alpha: link == PointLink.gap ? 0.5 : 0.85)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    if (link == PointLink.connected) {
      _drawStream(canvas, size, x, surface, index);
      _drawRipple(canvas, x, surface, index);
    }

    if (link == PointLink.incident) {
      final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
      canvas.drawCircle(
        head,
        12 + pulse * 8,
        Paint()
          ..color = _coral.withValues(alpha: 0.35 - pulse * 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  void _drawRipple(Canvas canvas, double x, double surface, int index) {
    final travel = (phase + index * 0.17) % 1;
    final fade = math.sin(travel * math.pi);
    if (fade < 0.05) return;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, surface + 3),
        width: 8 + travel * 26,
        height: 3.2 + travel * 5,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _mint.withValues(alpha: fade * 0.55),
    );
  }

  void _drawStream(
    Canvas canvas,
    Size size,
    double x,
    double surface,
    int index,
  ) {
    const drops = 4;
    final depth = math.max(size.height - surface - 20, 24);
    for (var drop = 0; drop < drops; drop++) {
      final travel = (phase * 1.5 + drop / drops + index * 0.17) % 1;
      final fade = math.sin(travel * math.pi);
      if (fade < 0.08) continue;
      final y = surface + 8 + depth * travel;
      final drift = math.sin((travel + index) * math.pi * 2) * 3;
      // Estela suave difuminada
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + drift, y),
            width: 3.5,
            height: 6 + fade * 8,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = _mint.withValues(alpha: 0.15 * fade),
      );
      // Núcleo brillante pequeño
      canvas.drawCircle(
        Offset(x + drift, y),
        1.2,
        Paint()..color = const Color(0xFFEFFFFA).withValues(alpha: 0.45 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaterBodyPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.points != points;
}
