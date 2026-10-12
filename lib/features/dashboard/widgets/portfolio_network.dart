import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../shared/widgets/hydro_glass.dart';
import '../point_link.dart';

/// Mini mapa isométrico de la cartera: pozos y superficies vistos desde lejos.
class PortfolioNetwork extends StatefulWidget {
  const PortfolioNetwork({
    required this.points,
    required this.onPointSelected,
    this.userName,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onPointSelected;
  final String? userName;

  @override
  State<PortfolioNetwork> createState() => _PortfolioNetworkState();
}

class _PortfolioNetworkState extends State<PortfolioNetwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );
  int? _hovered;

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
    final incidents = widget.points
        .where((point) => pointLinkOf(point) == PointLink.incident)
        .length;
    final greeting = (widget.userName ?? '').trim();

    return HydroGlass(
      padding: EdgeInsets.zero,
      radius: 24,
      intensity: HydroGlassIntensity.strong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (greeting.isNotEmpty)
                        Text(
                          'Hola, $greeting',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: Color(0xFFF4FBF8),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        nodes.isEmpty
                            ? 'Sin captaciones en cartera'
                            : 'Vista lejana · mapa isométrico de captaciones',
                        style: const TextStyle(
                          color: Color(0xFF91A8AA),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(
                  label: '$connected en línea',
                  color: const Color(0xFF66E0C2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return MouseRegion(
                  onHover: (event) {
                    final index = _IsoPortfolioPainter.nearestIntake(
                      size,
                      nodes,
                      event.localPosition,
                    );
                    if (index != _hovered) setState(() => _hovered = index);
                  },
                  onExit: (_) {
                    if (_hovered != null) setState(() => _hovered = null);
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final index = _IsoPortfolioPainter.nearestIntake(
                        size,
                        nodes,
                        details.localPosition,
                      );
                      if (index != null) {
                        widget.onPointSelected(nodes[index]);
                      }
                    },
                    child: AnimatedBuilder(
                      animation: _animation,
                      builder: (context, _) => CustomPaint(
                        painter: _IsoPortfolioPainter(
                          points: nodes,
                          phase: _animation.value,
                          highlight: _hovered,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (extraCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '+$extraCount puntos más en el listado',
                      style: const TextStyle(
                        color: Color(0xFF91A8AA),
                        fontSize: 10,
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 10,
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
                    _NetworkLegend(
                      color: const Color(0xFFFF847A),
                      label: 'Tensión${incidents == 0 ? '' : ' · $incidents'}',
                    ),
                    const _NetworkLegend(
                      color: Color(0xFF7EB8C4),
                      label: 'Pozo / superficial',
                      diamond: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkLegend extends StatelessWidget {
  const _NetworkLegend({
    required this.color,
    required this.label,
    this.diamond = false,
  });

  final Color color;
  final String label;
  final bool diamond;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (diamond)
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        )
      else
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

/// Mini pozo isométrico reutilizable (listados / tarjetas).
class MiniIsoWell extends StatelessWidget {
  const MiniIsoWell({
    required this.link,
    required this.isSurface,
    this.size = 44,
    super.key,
  });

  final PointLink link;
  final bool isSurface;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MiniIsoWellPainter(link: link, isSurface: isSurface),
      ),
    );
  }
}

class _MiniIsoWellPainter extends CustomPainter {
  const _MiniIsoWellPainter({required this.link, required this.isSurface});

  final PointLink link;
  final bool isSurface;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = switch (link) {
      PointLink.connected => const Color(0xFF66E0C2),
      PointLink.gap => const Color(0xFFFFC46B),
      PointLink.incident => const Color(0xFFFF847A),
    };
    final origin = Offset(size.width * 0.5, size.height * 0.62);
    if (isSurface) {
      _drawSurface(canvas, origin, size.width * 0.34, accent);
    } else {
      _drawWell(canvas, origin, size.width * 0.22, size.height * 0.28, accent);
    }
  }

  void _drawWell(
    Canvas canvas,
    Offset origin,
    double rx,
    double shaft,
    Color accent,
  ) {
    final ry = rx * 0.45;
    final top = origin.translate(0, -shaft);
    final left = [
      Offset(origin.dx - rx, origin.dy),
      Offset(top.dx - rx, top.dy),
      Offset(top.dx, top.dy + ry),
      Offset(origin.dx, origin.dy + ry),
    ];
    final right = [
      Offset(origin.dx + rx, origin.dy),
      Offset(top.dx + rx, top.dy),
      Offset(top.dx, top.dy + ry),
      Offset(origin.dx, origin.dy + ry),
    ];
    canvas.drawPath(
      Path()..addPolygon(left, true),
      Paint()..color = const Color(0xFF2A3D42),
    );
    canvas.drawPath(
      Path()..addPolygon(right, true),
      Paint()..color = const Color(0xFF1A2A2E),
    );
    canvas.drawOval(
      Rect.fromCenter(center: top, width: rx * 2, height: ry * 2),
      Paint()..color = const Color(0xFFD5E4DC),
    );
    canvas.drawOval(
      Rect.fromCenter(center: top, width: rx * 1.45, height: ry * 1.45),
      Paint()..color = const Color(0xFF0A1A1E),
    );
    canvas.drawOval(
      Rect.fromCenter(center: top, width: rx * 1.15, height: ry * 1.15),
      Paint()..color = accent.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      top.translate(0, -ry - 4),
      2.2,
      Paint()..color = accent,
    );
  }

  void _drawSurface(Canvas canvas, Offset origin, double rx, Color accent) {
    final ry = rx * 0.42;
    final pad = Path()
      ..moveTo(origin.dx, origin.dy - ry * 1.4)
      ..lineTo(origin.dx + rx * 1.35, origin.dy)
      ..lineTo(origin.dx, origin.dy + ry * 1.4)
      ..lineTo(origin.dx - rx * 1.35, origin.dy)
      ..close();
    canvas.drawPath(pad, Paint()..color = const Color(0xFF24362F));
    canvas.drawOval(
      Rect.fromCenter(center: origin, width: rx * 1.7, height: ry * 1.7),
      Paint()..color = accent.withValues(alpha: 0.75),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: origin.translate(0, -1),
        width: rx * 1.2,
        height: ry * 1.1,
      ),
      Paint()..color = const Color(0xFFBFF7EA).withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _MiniIsoWellPainter oldDelegate) =>
      oldDelegate.link != link || oldDelegate.isSurface != isSurface;
}

class _IsoPortfolioPainter extends CustomPainter {
  const _IsoPortfolioPainter({
    required this.points,
    required this.phase,
    this.highlight,
  });

  final List<Map<String, dynamic>> points;
  final double phase;
  final int? highlight;

  static const _mint = Color(0xFF66E0C2);
  static const _amber = Color(0xFFFFC46B);
  static const _coral = Color(0xFFFF847A);

  static const _slots = <Offset>[
    Offset(0, 0),
    Offset(1.15, -0.35),
    Offset(-0.95, 0.55),
    Offset(0.35, 1.1),
    Offset(-1.25, -0.7),
    Offset(1.45, 0.75),
    Offset(-0.2, -1.15),
    Offset(0.85, -1.05),
  ];

  static Offset _project(Offset grid, Offset origin, double tw, double th) {
    return Offset(
      origin.dx + (grid.dx - grid.dy) * tw * 0.5,
      origin.dy + (grid.dx + grid.dy) * th * 0.5,
    );
  }

  static List<Offset> _anchors(Size size, int count) {
    final origin = Offset(size.width * 0.5, size.height * 0.46);
    final tw = size.width * 0.22;
    final th = size.height * 0.13;
    return List<Offset>.generate(count, (index) {
      final slot = _slots[index % _slots.length];
      return _project(slot, origin, tw, th);
    }, growable: false);
  }

  static int? nearestIntake(
    Size size,
    List<Map<String, dynamic>> points,
    Offset position,
  ) {
    final anchors = _anchors(size, points.length);
    for (var index = 0; index < anchors.length; index++) {
      final hit = Rect.fromCenter(
        center: anchors[index].translate(0, -18),
        width: 54,
        height: 70,
      );
      if (hit.contains(position)) return index;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final clip = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(4),
    );
    canvas.save();
    canvas.clipRRect(clip);

    _paintSky(canvas, size);
    _paintTerrain(canvas, size);
    _paintGrid(canvas, size);
    _paintAtmosphere(canvas, size);

    final anchors = _anchors(size, points.length);
    final order = List<int>.generate(points.length, (i) => i)
      ..sort((a, b) => anchors[a].dy.compareTo(anchors[b].dy));

    for (final index in order) {
      _drawCapture(
        canvas,
        size,
        anchors[index],
        points[index],
        index,
        highlight == index,
      );
    }

    canvas.restore();
  }

  void _paintSky(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A3A42), Color(0xFF0E2429), Color(0xFF071316)],
          stops: [0, 0.45, 1],
        ).createShader(rect),
    );
    // Halo lejano: profundidad aérea.
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.18),
      size.width * 0.28,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF66E0C2).withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.72, size.height * 0.18),
            radius: size.width * 0.28,
          ),
        ),
    );
  }

  void _paintTerrain(Canvas canvas, Size size) {
    final origin = Offset(size.width * 0.5, size.height * 0.46);
    final tw = size.width * 0.78;
    final th = size.height * 0.42;
    final plate = Path()
      ..moveTo(origin.dx, origin.dy - th * 0.55)
      ..lineTo(origin.dx + tw * 0.55, origin.dy)
      ..lineTo(origin.dx, origin.dy + th * 0.62)
      ..lineTo(origin.dx - tw * 0.55, origin.dy)
      ..close();

    canvas.drawPath(
      plate,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF2A4A48).withValues(alpha: 0.95),
            const Color(0xFF16322F),
            const Color(0xFF0C1E1C),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Cara inferior (volumen del terreno).
    final depth = size.height * 0.07;
    final skirt = Path()
      ..moveTo(origin.dx - tw * 0.55, origin.dy)
      ..lineTo(origin.dx, origin.dy + th * 0.62)
      ..lineTo(origin.dx + tw * 0.55, origin.dy)
      ..lineTo(origin.dx + tw * 0.55, origin.dy + depth)
      ..lineTo(origin.dx, origin.dy + th * 0.62 + depth)
      ..lineTo(origin.dx - tw * 0.55, origin.dy + depth)
      ..close();
    canvas.drawPath(skirt, Paint()..color = const Color(0xFF081416));

    // Borde brillante del plato.
    canvas.drawPath(
      plate,
      Paint()
        ..color = const Color(0xFF66E0C2).withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _paintGrid(Canvas canvas, Size size) {
    final origin = Offset(size.width * 0.5, size.height * 0.46);
    final tw = size.width * 0.16;
    final th = size.height * 0.095;
    final paint = Paint()
      ..color = const Color(0xFF66E0C2).withValues(alpha: 0.07)
      ..strokeWidth = 1;

    for (var i = -4; i <= 4; i++) {
      final a = _project(Offset(i.toDouble(), -3.2), origin, tw, th);
      final b = _project(Offset(i.toDouble(), 3.2), origin, tw, th);
      canvas.drawLine(a, b, paint);
      final c = _project(Offset(-3.2, i.toDouble()), origin, tw, th);
      final d = _project(Offset(3.2, i.toDouble()), origin, tw, th);
      canvas.drawLine(c, d, paint);
    }
  }

  void _paintAtmosphere(Canvas canvas, Size size) {
    final travel = phase * math.pi * 2;
    for (var i = 0; i < 5; i++) {
      final t = (phase + i * 0.18) % 1;
      final x = size.width * (0.15 + 0.7 * ((i * 0.37) % 1));
      final y = size.height * (0.22 + 0.18 * math.sin(travel + i));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: 40 + t * 30,
          height: 8 + t * 4,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.03 + 0.02 * math.sin(t * math.pi)),
      );
    }
  }

  void _drawCapture(
    Canvas canvas,
    Size size,
    Offset anchor,
    Map<String, dynamic> point,
    int index,
    bool lit,
  ) {
    final link = pointLinkOf(point);
    final color = switch (link) {
      PointLink.connected => _mint,
      PointLink.gap => _amber,
      PointLink.incident => _coral,
    };
    final surface = _isSurface(point);
    final bob = math.sin(phase * math.pi * 2 + index * 0.9) * 1.2;
    final base = anchor.translate(0, bob);

    // Sombra en el terreno.
    canvas.drawOval(
      Rect.fromCenter(
        center: base.translate(0, 6),
        width: surface ? 46 : 34,
        height: surface ? 16 : 12,
      ),
      Paint()..color = Colors.black.withValues(alpha: lit ? 0.35 : 0.22),
    );

    if (surface) {
      _drawIsoSurface(canvas, base, color, link, index);
    } else {
      _drawIsoWell(canvas, base, color, link, index);
    }

    if (link == PointLink.incident) {
      _drawTension(canvas, base.translate(0, surface ? -8 : -28), color);
    } else if (link == PointLink.gap) {
      final pulse = (math.sin(phase * math.pi * 2 + index) + 1) / 2;
      canvas.drawCircle(
        base.translate(0, surface ? -10 : -30),
        10 + pulse * 4,
        Paint()
          ..color = _amber.withValues(alpha: 0.18 - pulse * 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    _drawLabel(canvas, base, point, color, lit);
  }

  void _drawIsoWell(
    Canvas canvas,
    Offset base,
    Color accent,
    PointLink link,
    int index,
  ) {
    const rx = 11.0;
    const ry = 5.0;
    const shaft = 26.0;
    final top = base.translate(0, -shaft);

    // Pad isométrico.
    final pad = Path()
      ..moveTo(base.dx, base.dy - 10)
      ..lineTo(base.dx + 18, base.dy)
      ..lineTo(base.dx, base.dy + 10)
      ..lineTo(base.dx - 18, base.dy)
      ..close();
    canvas.drawPath(pad, Paint()..color = const Color(0xFF3A524C));
    canvas.drawPath(
      pad,
      Paint()
        ..color = accent.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Caras del pozo (volumen).
    final leftFace = Path()
      ..moveTo(base.dx - rx, base.dy - 2)
      ..lineTo(top.dx - rx, top.dy)
      ..lineTo(top.dx, top.dy + ry)
      ..lineTo(base.dx, base.dy + ry - 2)
      ..close();
    final rightFace = Path()
      ..moveTo(base.dx + rx, base.dy - 2)
      ..lineTo(top.dx + rx, top.dy)
      ..lineTo(top.dx, top.dy + ry)
      ..lineTo(base.dx, base.dy + ry - 2)
      ..close();
    canvas.drawPath(leftFace, Paint()..color = const Color(0xFF8FA39A));
    canvas.drawPath(rightFace, Paint()..color = const Color(0xFF5F726A));

    // Agua en el interior (nivel).
    final fill = 0.35 + 0.2 * math.sin(phase * math.pi * 2 + index);
    final waterCenter = Offset(
      top.dx,
      top.dy + (1 - fill) * shaft * 0.35 + ry * 0.2,
    );
    canvas.drawOval(
      Rect.fromCenter(center: top, width: rx * 2, height: ry * 2),
      Paint()..color = const Color(0xFFD5E4DC),
    );
    canvas.drawOval(
      Rect.fromCenter(center: top, width: rx * 1.55, height: ry * 1.55),
      Paint()..color = const Color(0xFF071114),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: waterCenter,
        width: rx * 1.25,
        height: ry * 1.15,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: link == PointLink.gap ? 0.55 : 0.95),
            const Color(0xFF0C3140),
          ],
        ).createShader(
          Rect.fromCenter(
            center: waterCenter,
            width: rx * 1.25,
            height: ry * 1.15,
          ),
        ),
    );

    // Borde del brocal.
    canvas.drawOval(
      Rect.fromCenter(center: top, width: rx * 2, height: ry * 2),
      Paint()
        ..color = const Color(0xFFE8F2F1).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    // Faro de estado.
    final lamp = top.translate(0, -ry - 7);
    canvas.drawLine(
      top.translate(0, -ry),
      lamp,
      Paint()
        ..color = accent.withValues(alpha: 0.7)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(lamp, 3.2, Paint()..color = const Color(0xFF0C1F24));
    canvas.drawCircle(lamp, 2.1, Paint()..color = accent);
    if (link == PointLink.connected) {
      canvas.drawCircle(
        lamp,
        5.5,
        Paint()..color = accent.withValues(alpha: 0.18),
      );
    }
  }

  void _drawIsoSurface(
    Canvas canvas,
    Offset base,
    Color accent,
    PointLink link,
    int index,
  ) {
    final basin = Path()
      ..moveTo(base.dx, base.dy - 16)
      ..lineTo(base.dx + 28, base.dy - 2)
      ..lineTo(base.dx + 10, base.dy + 12)
      ..lineTo(base.dx - 22, base.dy + 4)
      ..close();
    canvas.drawPath(basin, Paint()..color = const Color(0xFF24362F));
    canvas.drawPath(
      basin,
      Paint()
        ..color = accent.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final water = Rect.fromCenter(
      center: base.translate(2, -1),
      width: 36,
      height: 16,
    );
    canvas.drawOval(
      water,
      Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: link == PointLink.gap ? 0.5 : 0.85),
            const Color(0xFF0C3140),
          ],
        ).createShader(water),
    );

    // Cresta animada.
    final crest = Path();
    for (var i = 0; i <= 8; i++) {
      final t = i / 8;
      final x = water.left + water.width * t;
      final y =
          water.center.dy -
          2 +
          math.sin(t * math.pi * 2 + phase * math.pi * 2 + index) * 1.4;
      i == 0 ? crest.moveTo(x, y) : crest.lineTo(x, y);
    }
    canvas.drawPath(
      crest,
      Paint()
        ..color = const Color(0xFFEFFFFA).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    // Mástil de captación.
    final mast = base.translate(-8, -22);
    canvas.drawLine(
      mast,
      base.translate(-4, 2),
      Paint()
        ..color = const Color(0xFFE8F2F1).withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(mast, 3, Paint()..color = accent);
  }

  void _drawTension(Canvas canvas, Offset center, Color color) {
    final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
    for (var ring = 0; ring < 3; ring++) {
      final travel = (phase * 1.4 + ring / 3) % 1;
      final fade = math.sin(travel * math.pi);
      if (fade < 0.05) continue;
      canvas.drawCircle(
        center,
        8 + travel * 18,
        Paint()
          ..color = color.withValues(alpha: 0.28 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }
    // Marcas de tensión (rayos cortos).
    for (var i = 0; i < 4; i++) {
      final angle = phase * math.pi * 2 + i * math.pi / 2;
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * 5;
      final outer =
          center + Offset(math.cos(angle), math.sin(angle)) * (9 + pulse * 3);
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawLabel(
    Canvas canvas,
    Offset base,
    Map<String, dynamic> point,
    Color color,
    bool lit,
  ) {
    final title = point['title']?.toString() ?? 'Punto';
    final short = title.length > 11 ? '${title.substring(0, 10)}…' : title;
    final text = TextPainter(
      text: TextSpan(
        text: short,
        style: TextStyle(
          color: lit ? const Color(0xFFF4FBF8) : const Color(0xFFE2F3EE),
          fontSize: lit ? 10.5 : 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 78);

    final badgeCenter = base.translate(0, -48);
    final badge = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: badgeCenter,
        width: text.width + 14,
        height: text.height + 8,
      ),
      const Radius.circular(9),
    );

    // Glass badge.
    canvas.drawRRect(
      badge,
      Paint()..color = const Color(0xFF081619).withValues(alpha: lit ? 0.92 : 0.78),
    );
    canvas.drawRRect(
      badge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: lit ? 0.14 : 0.06),
            Colors.transparent,
          ],
        ).createShader(badge.outerRect),
    );
    canvas.drawRRect(
      badge,
      Paint()
        ..color = color.withValues(alpha: lit ? 0.65 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lit ? 1.2 : 1,
    );
    text.paint(
      canvas,
      Offset(badgeCenter.dx - text.width / 2, badgeCenter.dy - text.height / 2),
    );
  }

  static bool _isSurface(Map<String, dynamic> point) {
    final dga = point['dga'];
    if (dga is Map) {
      final type = '${dga['type_dga']}'.toUpperCase();
      if (type == 'SUPERFICIAL') return true;
    }
    final direct = '${point['type_dga']}'.toUpperCase();
    return direct == 'SUPERFICIAL';
  }

  @override
  bool shouldRepaint(covariant _IsoPortfolioPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.points != points ||
      oldDelegate.highlight != highlight;
}
