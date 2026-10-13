import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/hydro_glass.dart';
import '../point_link.dart';

/// Visor isométrico de la cartera: todos los puntos, con giro y zoom.
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

class _IsoCamera {
  const _IsoCamera({
    this.zoom = 1,
    this.yaw = 0,
    this.pitch = 0,
    this.pan = Offset.zero,
  });

  final double zoom;
  final double yaw;
  final double pitch;
  final Offset pan;
}

class _PortfolioNetworkState extends State<PortfolioNetwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );
  int? _hovered;
  double _zoom = 1;
  double _yaw = 0;
  double _pitch = 0;
  Offset _pan = Offset.zero;
  double _zoomStart = 1;
  Offset _panStart = Offset.zero;
  Offset _drag = Offset.zero;
  Offset? _pointer;

  _IsoCamera get _camera =>
      _IsoCamera(zoom: _zoom, yaw: _yaw, pitch: _pitch, pan: _pan);

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

  void _setZoom(double next) {
    setState(() => _zoom = next.clamp(0.55, 2.8));
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.points;
    final connected = nodes
        .where((point) => pointLinkOf(point) == PointLink.connected)
        .length;
    final gaps = nodes
        .where((point) => pointLinkOf(point) == PointLink.gap)
        .length;
    final incidents = nodes
        .where((point) => pointLinkOf(point) == PointLink.incident)
        .length;

    return HydroGlass(
      padding: EdgeInsets.zero,
      radius: 24,
      intensity: HydroGlassIntensity.strong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    nodes.isEmpty
                        ? 'Sin captaciones en cartera'
                        : 'Captaciones sobre acuífero vivo',
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Color(0xFFF4FBF8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const _StatusPill(
                  label: 'Acuífero',
                  color: Color(0xFF3AD4C8),
                ),
                const SizedBox(width: 8),
                _StatusPill(
                  label: '$connected en línea',
                  color: const Color(0xFF66E0C2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final height = (constraints.maxWidth * 0.52).clamp(400.0, 540.0);
              return SizedBox(
                height: height,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, canvasConstraints) {
                    final size = Size(
                      canvasConstraints.maxWidth,
                      canvasConstraints.maxHeight,
                    );
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: MouseRegion(
                            cursor: _hovered == null
                                ? SystemMouseCursors.grab
                                : SystemMouseCursors.click,
                            onHover: (event) {
                              final index = _IsoPortfolioPainter.nearestIntake(
                                size,
                                nodes,
                                event.localPosition,
                                _camera,
                              );
                              if (index != _hovered) {
                                setState(() => _hovered = index);
                              }
                            },
                            onExit: (_) {
                              if (_hovered != null) {
                                setState(() => _hovered = null);
                              }
                            },
                            child: Listener(
                              onPointerSignal: (event) {
                                if (event is! PointerScrollEvent) return;
                                GestureBinding.instance.pointerSignalResolver
                                    .register(event, (signal) {
                                      if (signal is! PointerScrollEvent) return;
                                      final delta = signal.scrollDelta.dy;
                                      if (delta == 0) return;
                                      _setZoom(_zoom * (delta > 0 ? 0.9 : 1.1));
                                    });
                              },
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: (details) {
                                  _zoomStart = _zoom;
                                  _panStart = _pan;
                                  _drag = Offset.zero;
                                  _pointer = details.localFocalPoint;
                                },
                                onScaleUpdate: (details) {
                                  setState(() {
                                    _drag += details.focalPointDelta;
                                    _pointer = details.localFocalPoint;
                                    if (details.pointerCount >= 2) {
                                      _zoom = (_zoomStart * details.scale)
                                          .clamp(0.55, 2.8);
                                      _pan = Offset(
                                        (_panStart.dx + _drag.dx).clamp(
                                          -160.0,
                                          160.0,
                                        ),
                                        (_panStart.dy + _drag.dy).clamp(
                                          -110.0,
                                          110.0,
                                        ),
                                      );
                                    } else {
                                      _yaw +=
                                          details.focalPointDelta.dx * 0.007;
                                      _pitch =
                                          (_pitch -
                                                  details.focalPointDelta.dy *
                                                      0.0018)
                                              .clamp(-0.35, 0.55);
                                    }
                                  });
                                },
                                onScaleEnd: (_) {
                                  final pointer = _pointer;
                                  if (pointer == null || _drag.distance > 12) {
                                    return;
                                  }
                                  final index =
                                      _IsoPortfolioPainter.nearestIntake(
                                        size,
                                        nodes,
                                        pointer,
                                        _camera,
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
                                      camera: _camera,
                                      highlight: _hovered,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Column(
                            children: [
                              _ViewButton(
                                icon: Icons.add_rounded,
                                tooltip: 'Acercar',
                                onTap: () => _setZoom(_zoom * 1.15),
                              ),
                              const SizedBox(height: 6),
                              _ViewButton(
                                icon: Icons.remove_rounded,
                                tooltip: 'Alejar',
                                onTap: () => _setZoom(_zoom / 1.15),
                              ),
                              const SizedBox(height: 6),
                              _ViewButton(
                                icon: Icons.filter_center_focus_rounded,
                                tooltip: 'Recentrar',
                                onTap: () => setState(() {
                                  _zoom = 1;
                                  _yaw = 0;
                                  _pitch = 0;
                                  _pan = Offset.zero;
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Wrap(
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
                const _NetworkLegend(
                  color: Color(0xFF3AD4C8),
                  label: 'Acuífero',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF081619).withValues(alpha: 0.72),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: const Color(0xFF66E0C2).withValues(alpha: 0.35),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 18, color: const Color(0xFFBFF7EA)),
          ),
        ),
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
    canvas.drawCircle(top.translate(0, -ry - 4), 2.2, Paint()..color = accent);
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
    required this.camera,
    this.highlight,
  });

  final List<Map<String, dynamic>> points;
  final double phase;
  final _IsoCamera camera;
  final int? highlight;

  static const _mint = Color(0xFF66E0C2);
  static const _amber = Color(0xFFFFC46B);
  static const _coral = Color(0xFFFF847A);
  static const _slotGap = 1.4;

  static int _columns(int count) {
    if (count <= 1) return 1;
    return math.max(2, math.sqrt(count).ceil());
  }

  static Offset _slot(int index, int count) {
    if (count <= 1) return Offset.zero;
    final cols = _columns(count);
    final rows = (count + cols - 1) ~/ cols;
    final col = index % cols;
    final row = index ~/ cols;
    return Offset(
      (col - (cols - 1) / 2) * _slotGap,
      (row - (rows - 1) / 2) * _slotGap,
    );
  }

  static double _halfExtent(int count) {
    if (count <= 1) return 1.8;
    final cols = _columns(count);
    final rows = (count + cols - 1) ~/ cols;
    final hx = (cols - 1) / 2 * _slotGap;
    final hy = (rows - 1) / 2 * _slotGap;
    return math.max(hx, hy) + 1.25;
  }

  static const _slab = 128.0;

  static ({double tw, double th, Offset origin, double mark}) _metrics(
    Size size,
    int count,
    _IsoCamera camera,
  ) {
    final half = math.max(_halfExtent(count), 0.001);
    final slab = _slab * camera.zoom.clamp(0.75, 1.45);
    final maxW = size.width * 0.96 * camera.zoom;
    final maxH =
        (size.height - slab - 24) *
        0.92 *
        camera.zoom *
        (1 + camera.pitch * 0.55);
    final diaW = maxW;
    final diaH = math.min(math.max(maxH, 1), diaW * 0.48);
    final tw = diaW / half;
    final th = diaH / half;
    final origin =
        Offset(size.width * 0.5, (size.height - slab) * 0.46) + camera.pan;
    final cell = _slotGap * tw * 0.5;
    final mark = (cell / 72).clamp(1.05, 2.6);
    return (tw: tw, th: th, origin: origin, mark: mark);
  }

  static Offset _project(Offset grid, Size size, int count, _IsoCamera camera) {
    final frame = _metrics(size, count, camera);
    final yaw = camera.yaw;
    final x = grid.dx * math.cos(yaw) - grid.dy * math.sin(yaw);
    final y = grid.dx * math.sin(yaw) + grid.dy * math.cos(yaw);
    return Offset(
      frame.origin.dx + (x - y) * frame.tw * 0.5,
      frame.origin.dy + (x + y) * frame.th * 0.5,
    );
  }

  static List<Offset> _anchors(Size size, int count, _IsoCamera camera) {
    return List<Offset>.generate(count, (index) {
      return _project(_slot(index, count), size, count, camera);
    }, growable: false);
  }

  static int? nearestIntake(
    Size size,
    List<Map<String, dynamic>> points,
    Offset position,
    _IsoCamera camera,
  ) {
    final anchors = _anchors(size, points.length, camera);
    final scale = camera.zoom.clamp(0.75, 1.7);
    for (var index = 0; index < anchors.length; index++) {
      final hit = Rect.fromCenter(
        center: anchors[index].translate(0, -18 * scale),
        width: 54 * scale,
        height: 78 * scale,
      );
      if (hit.contains(position)) return index;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    _paintSky(canvas, size);
    _paintPlatform(canvas, size);
    _paintGrid(canvas, size);
    _paintAtmosphere(canvas, size);

    final anchors = _anchors(size, points.length, camera);
    _paintNetwork(canvas, anchors);
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
        ..shader =
            RadialGradient(
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

  List<Offset> _plateVerts(Size size) {
    final half = _halfExtent(points.length);
    final count = points.length;
    return [
      _project(Offset(0, -half), size, count, camera),
      _project(Offset(half, 0), size, count, camera),
      _project(Offset(0, half), size, count, camera),
      _project(Offset(-half, 0), size, count, camera),
    ];
  }

  void _paintPlatform(Canvas canvas, Size size) {
    final top = _plateVerts(size);
    final depth = _slab * camera.zoom.clamp(0.75, 1.45);
    final center = top.fold(Offset.zero, (sum, point) => sum + point) / 4;
    final front = List<int>.generate(4, (index) => index)
      ..sort((a, b) {
        final ma = (top[a] + top[(a + 1) % 4]) / 2;
        final mb = (top[b] + top[(b + 1) % 4]) / 2;
        return mb.dy.compareTo(ma.dy);
      });

    final footprint = Path()..addPolygon(top, true);
    // Sombra de volumen bajo el acuífero.
    canvas.drawPath(
      footprint.shift(Offset(0, depth + 14)),
      Paint()
        ..color = const Color(0xFF021014).withValues(alpha: 0.55)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 22),
    );

    // Tres caras visibles del bloque de agua (ordenadas de atrás a adelante).
    for (final index in front.take(3).toList().reversed) {
      _paintWaterFace(canvas, top[index], top[(index + 1) % 4], depth, center);
    }

    // Etiqueta grande en la cara frontal: imposible de no ver.
    final frontEdge = front.first;
    _paintAquiferLabel(
      canvas,
      top[frontEdge],
      top[(frontEdge + 1) % 4],
      depth,
    );

    final bounds = footprint.getBounds();
    // Superficie del terreno: húmeda, con tinte de acuífero debajo.
    canvas.drawPath(
      footprint,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2F5550).withValues(alpha: 0.98),
            const Color(0xFF183832),
            const Color(0xFF0F2C32),
          ],
        ).createShader(bounds.inflate(4)),
    );
    canvas.drawPath(
      footprint,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.1, -0.2),
          radius: 1.05,
          colors: [
            const Color(0xFF66E0C2).withValues(alpha: 0.16),
            const Color(0xFF1A4A52).withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0, 0.45, 1],
        ).createShader(bounds.inflate(8)),
    );
    // Brillo de waterline en el borde superior.
    canvas.drawPath(
      footprint,
      Paint()
        ..color = const Color(0xFFE8FFF8).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1,
    );
    canvas.drawPath(
      footprint,
      Paint()
        ..color = const Color(0xFF66E0C2).withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _paintWaterFace(
    Canvas canvas,
    Offset a,
    Offset b,
    double depth,
    Offset center,
  ) {
    final down = Offset(0, depth);
    final face = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(b.dx + down.dx, b.dy + down.dy)
      ..lineTo(a.dx + down.dx, a.dy + down.dy)
      ..close();
    final bounds = face.getBounds();
    final mid = (a + b) / 2;
    final shade = (mid - center).dx;
    final lit = shade <= 0;
    final surface = Color.lerp(
      const Color(0xFF7CFFE8),
      const Color(0xFF2FE0C8),
      lit ? 0.05 : 0.4,
    )!;
    final body = Color.lerp(
      const Color(0xFF1498A8),
      const Color(0xFF0A6A78),
      lit ? 0.1 : 0.55,
    )!;
    final deep = Color.lerp(
      const Color(0xFF053038),
      const Color(0xFF02181E),
      lit ? 0.15 : 0.6,
    )!;

    canvas.save();
    canvas.clipPath(face);

    // Cuerpo del acuífero: superficie → cuerpo → sedimento.
    canvas.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surface, body, deep],
          stops: const [0, 0.38, 1],
        ).createShader(bounds),
    );

    // Halo interno cerca de la waterline.
    canvas.drawRect(
      Rect.fromLTWH(bounds.left, bounds.top, bounds.width, depth * 0.22),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFD7FFF4).withValues(alpha: lit ? 0.34 : 0.18),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromLTWH(bounds.left, bounds.top, bounds.width, depth * 0.22),
        ),
    );

    // Bandas caústicas animadas.
    final span = (b - a).distance;
    final steps = math.max(8, (span / 14).round());
    for (var row = 1; row <= 6; row++) {
      final travel = (phase * (0.7 + row * 0.08) + row * 0.13) % 1;
      final yLift =
          depth * (0.12 + row * 0.12) +
          math.sin(travel * math.pi * 2) * (1.8 + row * 0.15);
      final alpha = (lit ? 0.22 : 0.12) * (1 - row / 8);
      final scan = Paint()
        ..color = Color.lerp(
          const Color(0xFFEFFFFA),
          const Color(0xFF7BE8D4),
          row / 6,
        )!.withValues(alpha: alpha)
        ..strokeWidth = row == 1 ? 1.6 : 1.05
        ..style = PaintingStyle.stroke;
      final wave = Path();
      for (var step = 0; step <= steps; step++) {
        final t = step / steps;
        final along = Offset.lerp(a, b, t)!;
        final ripple =
            math.sin(t * math.pi * (3.2 + row * 0.35) + phase * math.pi * 2 + row) *
            (2.2 - row * 0.18);
        final point = along + Offset(0, yLift + ripple);
        step == 0
            ? wave.moveTo(point.dx, point.dy)
            : wave.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(wave, scan);
    }

    // Partículas de turbidez / burbujas suaves.
    for (var i = 0; i < 5; i++) {
      final t = ((phase * 0.55 + i * 0.19) % 1);
      final along = Offset.lerp(a, b, (i + 0.35) / 5.5)!;
      final bubble = along + Offset(
        math.sin(phase * math.pi * 2 + i) * 3,
        depth * (0.25 + t * 0.55),
      );
      canvas.drawCircle(
        bubble,
        1.2 + (i % 3) * 0.5,
        Paint()..color = const Color(0xFFBFF7EA).withValues(alpha: 0.12 + t * 0.08),
      );
    }

    // Base sedimentaria más oscura.
    canvas.drawRect(
      Rect.fromLTWH(
        bounds.left,
        bounds.bottom - depth * 0.18,
        bounds.width,
        depth * 0.18,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF021014).withValues(alpha: 0.55),
          ],
        ).createShader(
          Rect.fromLTWH(
            bounds.left,
            bounds.bottom - depth * 0.18,
            bounds.width,
            depth * 0.18,
          ),
        ),
    );
    canvas.restore();

    // Contorno del bloque de agua.
    canvas.drawPath(
      face,
      Paint()
        ..color = const Color(0xFF66E0C2).withValues(alpha: lit ? 0.28 : 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = const Color(0xFFF4FFFB).withValues(alpha: 0.82)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      a + down,
      b + down,
      Paint()
        ..color = const Color(0xFF04161C).withValues(alpha: 0.65)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintAquiferLabel(Canvas canvas, Offset a, Offset b, double depth) {
    final mid = Offset.lerp(a, b, 0.5)! + Offset(0, depth * 0.42);
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 13,
        fontWeight: FontWeight.w900,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: const Color(0xFFE8FFFB).withValues(alpha: 0.95),
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.8,
        ),
      )
      ..addText('ACUÍFERO');
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 140));
    final origin = Offset(mid.dx - 70, mid.dy - paragraph.height / 2);
    final chip = RRect.fromRectAndRadius(
      Rect.fromCenter(center: mid, width: 118, height: 26),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      chip,
      Paint()..color = const Color(0xFF042028).withValues(alpha: 0.72),
    );
    canvas.drawRRect(
      chip,
      Paint()
        ..color = const Color(0xFF66E0C2).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawParagraph(paragraph, origin);
  }

  void _paintNetwork(Canvas canvas, List<Offset> anchors) {
    if (anchors.length < 2) return;
    final pulse = 0.34 + 0.08 * math.sin(phase * math.pi * 2);
    for (var i = 0; i < anchors.length; i++) {
      for (var j = i + 1; j < anchors.length; j++) {
        final lit = highlight == i || highlight == j;
        canvas.drawLine(
          anchors[i],
          anchors[j],
          Paint()
            ..color = _mint.withValues(alpha: lit ? 0.85 : pulse)
            ..strokeWidth = lit ? 2.2 : 1.35
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final half = _halfExtent(points.length);
    final plate = Path()
      ..addPolygon([
        _project(Offset(0, -half), size, points.length, camera),
        _project(Offset(half, 0), size, points.length, camera),
        _project(Offset(0, half), size, points.length, camera),
        _project(Offset(-half, 0), size, points.length, camera),
      ], true);
    canvas.save();
    canvas.clipPath(plate);
    final steps = (half * 2).round().clamp(4, 12);
    final paint = Paint()
      ..color = const Color(0xFF66E0C2).withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final span = half * 0.92;

    for (var i = 0; i <= steps; i++) {
      final t = -span + span * 2 * i / steps;
      canvas.drawLine(
        _project(Offset(t, -span), size, points.length, camera),
        _project(Offset(t, span), size, points.length, camera),
        paint,
      );
      canvas.drawLine(
        _project(Offset(-span, t), size, points.length, camera),
        _project(Offset(span, t), size, points.length, camera),
        paint,
      );
    }
    canvas.restore();
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
          ..color = Colors.white.withValues(
            alpha: 0.03 + 0.02 * math.sin(t * math.pi),
          ),
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
    final lift = lit ? 18.0 : 0.0;
    final base = anchor.translate(0, bob - lift);

    canvas.drawOval(
      Rect.fromCenter(
        center: anchor.translate(0, 8),
        width: (surface ? 46 : 34) * (lit ? 0.7 : 1),
        height: (surface ? 16 : 12) * (lit ? 0.65 : 1),
      ),
      Paint()..color = Colors.black.withValues(alpha: lit ? 0.32 : 0.22),
    );

    final mark =
        _metrics(size, points.length, camera).mark * (lit ? 1.12 : 1.0);

    canvas.save();
    if (lit) {
      canvas.drawCircle(
        base.translate(0, surface ? -8 : -24),
        30 * mark,
        Paint()
          ..color = color.withValues(alpha: 0.18)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14),
      );
    }
    canvas.translate(base.dx, base.dy);
    canvas.scale(mark);
    canvas.translate(-base.dx, -base.dy);

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

    canvas.restore();
    _drawLabel(canvas, base, point, color, lit, mark);
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
      Rect.fromCenter(center: waterCenter, width: rx * 1.25, height: ry * 1.15),
      Paint()
        ..shader =
            RadialGradient(
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
    double mark,
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

    final badgeCenter = base.translate(0, -30 * mark - 16);
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
      Paint()
        ..color = const Color(0xFF081619).withValues(alpha: lit ? 0.92 : 0.78),
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
      oldDelegate.highlight != highlight ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.yaw != camera.yaw ||
      oldDelegate.camera.pitch != camera.pitch ||
      oldDelegate.camera.pan != camera.pan;
}
