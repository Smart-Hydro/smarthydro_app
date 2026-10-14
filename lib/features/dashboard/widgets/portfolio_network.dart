import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../point_link.dart';
import '../portfolio3d_view.dart';

/// Visor isométrico de la cartera: todos los puntos, con giro y zoom.
class PortfolioNetwork extends StatefulWidget {
  const PortfolioNetwork({
    required this.points,
    required this.onPointSelected,
    this.stageHeight,
    this.belowStage,
    this.mapFill = false,
    this.onPageDown,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onPointSelected;

  /// En web el visor ocupa el alto del padre. El toque abre la ficha
  /// dentro del iframe; «Entrar» abre el detalle. El iframe no cambia de alto.
  final bool mapFill;

  /// Scroll hacia abajo sobre el mapa general. Pasa al resumen.
  final VoidCallback? onPageDown;

  /// Alto fijo del iframe en web. Si cambia al scrollear, el slot del
  /// platform view parpadea blanco.
  final double? stageHeight;

  /// Lista que scrollea debajo del visor. La ficha va aquí para no
  /// achicar el iframe al abrirla.
  final Widget Function(BuildContext context, Widget? brief)? belowStage;

  @override
  State<PortfolioNetwork> createState() => _PortfolioNetworkState();
}

/// Punto de la ciudad que cae bajo [position]. Sirve al test del toque.
@visibleForTesting
int? debugPortfolioHit(
  Size size,
  List<Map<String, dynamic>> points,
  Offset position,
) {
  return _IsoPortfolioPainter.nearestIntake(
    size,
    points,
    position,
    const _IsoCamera(),
  );
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
  int? _selected;
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
    setState(() => _zoom = next.clamp(0.45, 3.4));
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.points;
    if (widget.mapFill && portfolio3dSupported) {
      return PortfolioCityView(
        points: nodes,
        onPageDown: widget.onPageDown,
        onSelect: (index) {
          if (index == null || index < 0 || index >= nodes.length) return;
          widget.onPointSelected(nodes[index]);
        },
      );
    }
    final gaps = nodes
        .where((point) => pointLinkOf(point) == PointLink.gap)
        .length;
    final motion = !MediaQuery.of(context).disableAnimations;
    final selected = _selected != null && _selected! < nodes.length
        ? _selected
        : null;

    final city = PortfolioCityView(
      points: nodes,
      selected: selected,
      onSelect: (index) {
        setState(() {
          if (index == null || index == _selected) {
            _selected = null;
          } else {
            _selected = index;
          }
        });
      },
    );
    final legend = Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
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
          const _NetworkLegend(
            color: Color(0xFF7EB8C4),
            label: 'Pozo / superficial',
            diamond: true,
          ),
        ],
      ),
    );
    final brief = selected == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _PointBrief(
              point: nodes[selected],
              onClose: () => setState(() => _selected = null),
              onOpen: () => widget.onPointSelected(nodes[selected]),
            ),
          );

    // La leyenda va dentro del iframe. Afuera se pierde y le roba
    // alto al visor. La ficha scrollea con la lista.
    if (portfolio3dSupported) {
      final stage = widget.stageHeight;
      final below = widget.belowStage;
      if (stage != null && below != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: stage, child: city),
            Expanded(child: below(context, brief)),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: city),
          ?brief,
          legend,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final height = _IsoPortfolioPainter.stageHeight(
              constraints.maxWidth,
            );
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
                                    _zoom = (_zoomStart * details.scale).clamp(
                                      0.45,
                                      3.4,
                                    );
                                    _pan = Offset(
                                      (_panStart.dx + _drag.dx).clamp(
                                        -260.0,
                                        260.0,
                                      ),
                                      (_panStart.dy + _drag.dy).clamp(
                                        -180.0,
                                        180.0,
                                      ),
                                    );
                                  } else {
                                    _yaw += details.focalPointDelta.dx * 0.007;
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
                                setState(() {
                                  if (index == null || index == _selected) {
                                    _selected = null;
                                  } else {
                                    _selected = index;
                                  }
                                });
                              },
                              child: AnimatedBuilder(
                                animation: _animation,
                                builder: (context, _) => CustomPaint(
                                  painter: _IsoPortfolioPainter(
                                    points: nodes,
                                    phase: motion ? _animation.value : 0,
                                    camera: _camera,
                                    highlight: _hovered,
                                    selected: selected,
                                    motion: motion,
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
                      if (selected != null)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: _PointBrief(
                            point: nodes[selected],
                            onClose: () => setState(() => _selected = null),
                            onOpen: () =>
                                widget.onPointSelected(nodes[selected]),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
        legend,
      ],
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
        color: const Color(0xFFF7FBFA).withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

class _PointBrief extends StatelessWidget {
  const _PointBrief({
    required this.point,
    required this.onClose,
    required this.onOpen,
  });

  final Map<String, dynamic> point;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final link = pointLinkOf(point);
    final color = switch (link) {
      PointLink.connected => const Color(0xFF66E0C2),
      PointLink.gap => const Color(0xFFFFC46B),
      PointLink.incident => const Color(0xFFFF847A),
    };
    final telemetry = _IsoPortfolioPainter._telemetry(point);
    final flow = _IsoPortfolioPainter._number(telemetry['flow']);
    final when = telemetry['date_time_medition'];
    final project =
        point['project_name']?.toString() ??
        point['client_name']?.toString() ??
        'Proyecto';
    return Material(
      color: const Color(0xFF071114).withValues(alpha: 0.92),
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    point['title']?.toString() ?? 'Punto',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF4FBF8),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            Text(
              project,
              style: const TextStyle(color: Color(0xFFA9BFC0), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _BriefStat(
                  label: 'Estado',
                  value: pointLinkLabel(link),
                  color: color,
                ),
                _BriefStat(
                  label: 'Caudal',
                  value: _flowLabel(flow),
                  color: color,
                ),
                if (_IsoPortfolioPainter._number(
                      telemetry['water_table'] ?? telemetry['nivel'],
                    ) !=
                    null)
                  _BriefStat(
                    label: 'Nivel',
                    value:
                        '${_IsoPortfolioPainter._compact(_IsoPortfolioPainter._number(telemetry['water_table'] ?? telemetry['nivel'])!)} m',
                    color: color,
                  ),
                if (_IsoPortfolioPainter._number(
                      telemetry['total'] ??
                          telemetry['total_raw'] ??
                          telemetry['consumption'],
                    ) !=
                    null)
                  _BriefStat(
                    label: 'Acumulado',
                    value: _IsoPortfolioPainter._compact(
                      _IsoPortfolioPainter._number(
                        telemetry['total'] ??
                            telemetry['total_raw'] ??
                            telemetry['consumption'],
                      )!,
                    ),
                    color: color,
                  ),
                _BriefStat(
                  label: 'Lectura',
                  value: _whenLabel(when),
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Ir al detalle'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _flowLabel(double? flow) {
  if (flow == null) return 'sin caudal';
  final digits = flow.abs() >= 10 ? 0 : 1;
  return '${flow.toStringAsFixed(digits)} L/s';
}

String _whenLabel(dynamic value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty || raw == 'null') return 'sin lectura';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}

class _BriefStat extends StatelessWidget {
  const _BriefStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8EA0AE), fontSize: 9),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF4FBF8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    final ry = rx * 0.42;
    final mouth = origin.translate(0, -shaft * 0.15);
    canvas.drawOval(
      Rect.fromCenter(center: mouth, width: rx * 2.4, height: ry * 2.2),
      Paint()..color = const Color(0xFFB7C3CC),
    );
    canvas.drawOval(
      Rect.fromCenter(center: mouth, width: rx * 1.7, height: ry * 1.6),
      Paint()..color = const Color(0xFFF7FAFB),
    );
    canvas.drawOval(
      Rect.fromCenter(center: mouth, width: rx * 1.05, height: ry),
      Paint()..color = accent,
    );
    final box = Rect.fromCenter(
      center: origin.translate(rx * 0.9, -shaft * 0.35),
      width: rx * 0.7,
      height: ry * 0.9,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(1)),
      Paint()..color = const Color(0xFF2C3A42),
    );
    canvas.drawCircle(
      box.center.translate(0, -ry),
      rx * 0.16,
      Paint()..color = accent,
    );
  }

  void _drawSurface(Canvas canvas, Offset origin, double rx, Color accent) {
    final ry = rx * 0.42;
    final banks = Path()
      ..moveTo(origin.dx, origin.dy - ry)
      ..lineTo(origin.dx + rx, origin.dy)
      ..lineTo(origin.dx, origin.dy + ry)
      ..lineTo(origin.dx - rx, origin.dy)
      ..close();
    canvas.drawPath(banks, Paint()..color = const Color(0xFFD5DEE4));
    canvas.drawOval(
      Rect.fromCenter(center: origin, width: rx * 0.9, height: ry * 0.7),
      Paint()..color = accent,
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
    this.selected,
    this.motion = true,
  });

  final List<Map<String, dynamic>> points;
  final double phase;
  final _IsoCamera camera;
  final int? highlight;
  final int? selected;
  final bool motion;

  static const _mint = Color(0xFF66E0C2);
  static const _amber = Color(0xFFFFC46B);
  static const _coral = Color(0xFFFF847A);
  static const _slotGap = 1.55;

  static int _columns(int count) {
    if (count <= 1) return 1;
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    return 4;
  }

  /// Rejilla centrada: última fila incompleta también al medio.
  static Offset _slot(int index, int count) {
    if (count <= 1) return Offset.zero;
    final cols = _columns(count);
    final rows = (count + cols - 1) ~/ cols;
    final col = index % cols;
    final row = index ~/ cols;
    final itemsInRow = row == rows - 1 ? count - (rows - 1) * cols : cols;
    final rowOffset = (cols - itemsInRow) / 2;
    return Offset(
      (col + rowOffset - (cols - 1) / 2) * _slotGap,
      (row - (rows - 1) / 2) * _slotGap,
    );
  }

  static double _halfExtent(int count) {
    if (count <= 1) return 1.8;
    final cols = _columns(count);
    final rows = (count + cols - 1) ~/ cols;
    final hx = (cols - 1) / 2 * _slotGap;
    final hy = (rows - 1) / 2 * _slotGap;
    return math.max(hx, hy) + 2.35;
  }

  static const _slab = 52.0;

  /// Alto del visor según el ancho. El bloque queda centrado, no pegado abajo.
  static double stageHeight(double width) {
    final dia = (width * 0.58).clamp(190.0, 320.0);
    return 48 + dia + _slab + 36;
  }

  static ({double tw, double th, Offset origin, double mark}) _metrics(
    Size size,
    int count,
    _IsoCamera camera,
  ) {
    final half = math.max(_halfExtent(count), 0.001);
    final slab = _slab * camera.zoom.clamp(0.75, 1.45);
    final maxW = size.width * 0.74 * camera.zoom;
    const head = 28.0;
    const foot = 16.0;
    final available = math.max(size.height - head - foot - slab, 80.0);
    final pitch = 1 + camera.pitch * 0.22;
    final diaW = maxW;
    final diaH = math.min(available, diaW * 0.56) * pitch.clamp(0.86, 1.18);
    final usedH = math.min(diaH, available);
    final tw = diaW / half;
    final th = usedH / half;
    final block = usedH + slab + head;
    final top = ((size.height - block) / 2).clamp(8.0, size.height * 0.28);
    final originY = top + head + usedH / 2;
    final origin = Offset(size.width * 0.5, originY) + camera.pan;
    final cell = _slotGap * tw * 0.5;
    final mark = (cell / 110).clamp(0.72, 1.0);
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

    _paintPlatform(canvas, size);
    _paintGrid(canvas, size);

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
        selected == index,
      );
    }
    final occupied = <Rect>[];
    for (final index in order.reversed) {
      _drawLabel(
        canvas,
        size,
        anchors[index],
        points[index],
        index,
        highlight == index,
        selected == index,
        occupied,
      );
    }

    canvas.restore();
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
    canvas.drawPath(
      footprint.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0xFF04161C).withValues(alpha: 0.22)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );

    for (final index in front.take(2).toList().reversed) {
      _paintSideFace(canvas, top[index], top[(index + 1) % 4], depth, center);
    }

    final bounds = footprint.getBounds();
    canvas.drawPath(
      footprint,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F9FB), Color(0xFFE6EDF1), Color(0xFFD5DEE6)],
        ).createShader(bounds.inflate(4)),
    );
    canvas.drawPath(
      footprint,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  void _paintSideFace(
    Canvas canvas,
    Offset a,
    Offset b,
    double depth,
    Offset center,
  ) {
    final face = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(b.dx, b.dy + depth)
      ..lineTo(a.dx, a.dy + depth)
      ..close();
    final lit = ((a + b) / 2 - center).dx > 0;
    canvas.drawPath(
      face,
      Paint()..color = lit ? const Color(0xFFC9D3DC) : const Color(0xFFA9B6C2),
    );
  }

  void _paintNetwork(Canvas canvas, List<Offset> anchors) {
    if (anchors.length < 2) return;
    final cols = _columns(anchors.length);

    Color tone(int index) => switch (pointLinkOf(points[index])) {
      PointLink.connected => _mint,
      PointLink.gap => _amber,
      PointLink.incident => _coral,
    };

    void link(int from, int to, int seed) {
      final a = anchors[from];
      final b = anchors[to];
      final color = Color.lerp(tone(from), tone(to), 0.5)!;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xFFB7C3CE)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = color.withValues(alpha: 0.95)
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round,
      );
      if (!motion) return;
      final drop = Offset.lerp(a, b, (phase + seed * 0.17) % 1)!;
      canvas.drawCircle(drop, 2.2, Paint()..color = color);
    }

    for (var i = 0; i < anchors.length; i++) {
      final right = i + 1;
      if (right < anchors.length && i ~/ cols == right ~/ cols) {
        link(i, right, i);
      }
      final below = i + cols;
      if (below < anchors.length) {
        link(i, below, i + 3);
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
      ..color = const Color(0xFF8EA0AE).withValues(alpha: 0.35)
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

  void _drawCapture(
    Canvas canvas,
    Size size,
    Offset anchor,
    Map<String, dynamic> point,
    int index,
    bool lit,
    bool raised,
  ) {
    final link = pointLinkOf(point);
    final color = switch (link) {
      PointLink.connected => _mint,
      PointLink.gap => _amber,
      PointLink.incident => _coral,
    };
    final surface = _isSurface(point);
    final bob = motion
        ? math.sin(phase * math.pi * 2 + index * 0.9) * 1.2
        : 0.0;
    final lift = !motion
        ? 0.0
        : raised
        ? 10.0
        : lit
        ? 3.0
        : 0.0;
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
        _metrics(size, points.length, camera).mark *
        (raised
            ? 1.2
            : lit
            ? 1.08
            : 1.0);

    canvas.save();
    canvas.drawCircle(
      base,
      (raised ? 16 : 11) * mark,
      Paint()
        ..color = color.withValues(alpha: raised ? 0.28 : 0.12)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );
    canvas.translate(base.dx, base.dy);
    canvas.scale(mark);
    canvas.translate(-base.dx, -base.dy);

    if (surface) {
      _drawIsoSurface(canvas, base, color, link, index);
    } else {
      _drawIsoWell(canvas, base, color, link, index);
    }

    if (link == PointLink.gap && motion) {
      final pulse = (math.sin(phase * math.pi * 2 + index) + 1) / 2;
      canvas.drawCircle(
        base,
        8 + pulse * 2,
        Paint()
          ..color = _amber.withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    canvas.restore();
  }

  void _drawIsoWell(
    Canvas canvas,
    Offset base,
    Color accent,
    PointLink link,
    int index,
  ) {
    final pad = Path()
      ..moveTo(base.dx, base.dy - 7)
      ..lineTo(base.dx + 15, base.dy)
      ..lineTo(base.dx, base.dy + 7)
      ..lineTo(base.dx - 15, base.dy)
      ..close();
    canvas.drawPath(pad, Paint()..color = const Color(0xFFD7E0E6));

    const rx = 7.5;
    const ry = 3.2;
    final mouth = base.translate(-1, -1);
    canvas.drawOval(
      Rect.fromCenter(center: mouth, width: rx * 2.5, height: ry * 2.5),
      Paint()..color = const Color(0xFFB7C3CC),
    );
    canvas.drawOval(
      Rect.fromCenter(center: mouth, width: rx * 2.0, height: ry * 2.0),
      Paint()..color = const Color(0xFFF7FAFB),
    );
    canvas.drawOval(
      Rect.fromCenter(center: mouth, width: rx * 1.35, height: ry * 1.3),
      Paint()..color = const Color(0xFF1A242C),
    );
    final fill = _levelFill(points[index]);
    final water = Rect.fromCenter(
      center: mouth.translate(0, (1 - fill) * 1.1),
      width: rx * 1.05,
      height: ry * 0.9,
    );
    canvas.drawOval(
      water,
      Paint()
        ..color = accent.withValues(alpha: link == PointLink.gap ? 0.75 : 1),
    );
    canvas.drawOval(
      Rect.fromCenter(center: mouth, width: rx * 2.0, height: ry * 2.0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    final box = Rect.fromCenter(
      center: base.translate(11, -5),
      width: 7,
      height: 5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(1.2)),
      Paint()..color = const Color(0xFF2C3A42),
    );
    final poleTop = box.center.translate(0, -6);
    canvas.drawLine(
      box.topCenter,
      poleTop,
      Paint()
        ..color = const Color(0xFF2C3A42)
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(poleTop, 1.7, Paint()..color = accent);
  }

  void _drawIsoSurface(
    Canvas canvas,
    Offset base,
    Color accent,
    PointLink link,
    int index,
  ) {
    final banks = Path()
      ..moveTo(base.dx, base.dy - 9)
      ..lineTo(base.dx + 16, base.dy)
      ..lineTo(base.dx, base.dy + 9)
      ..lineTo(base.dx - 16, base.dy)
      ..close();
    canvas.drawPath(banks, Paint()..color = const Color(0xFFD5DEE4));
    canvas.drawPath(
      banks,
      Paint()
        ..color = const Color(0xFF8EA0AE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );
    final channel = Path()
      ..moveTo(base.dx, base.dy - 4.5)
      ..lineTo(base.dx + 9, base.dy)
      ..lineTo(base.dx, base.dy + 4.5)
      ..lineTo(base.dx - 9, base.dy)
      ..close();
    canvas.drawPath(
      channel,
      Paint()
        ..color = accent.withValues(alpha: link == PointLink.gap ? 0.7 : 0.95),
    );
    final shift = (index % 3) - 1.0;
    canvas.drawLine(
      base.translate(-5, shift),
      base.translate(5, shift + 0.6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawLabel(
    Canvas canvas,
    Size size,
    Offset anchor,
    Map<String, dynamic> point,
    int index,
    bool lit,
    bool raised,
    List<Rect> occupied,
  ) {
    final color = switch (pointLinkOf(point)) {
      PointLink.connected => _mint,
      PointLink.gap => _amber,
      PointLink.incident => _coral,
    };
    final bob = motion
        ? math.sin(phase * math.pi * 2 + index * 0.9) * 1.2
        : 0.0;
    final lift = !motion
        ? 0.0
        : raised
        ? 10.0
        : lit
        ? 3.0
        : 0.0;
    final base = anchor.translate(0, bob - lift);
    final telemetry = _telemetry(point);
    final title = point['title']?.toString() ?? 'Punto';
    final short = title.length > 12 ? '${title.substring(0, 11)}…' : title;
    final showMetrics = lit || raised;
    final metrics = showMetrics ? _metricsLine(telemetry) : null;

    final titlePainter = TextPainter(
      text: TextSpan(
        text: short,
        style: TextStyle(
          color: lit ? const Color(0xFFF4FBF8) : const Color(0xFFE7F6F1),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 78);
    final metricsPainter = metrics == null
        ? null
        : (TextPainter(
            text: TextSpan(
              text: metrics,
              style: TextStyle(
                color: color.withValues(alpha: 0.95),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout(maxWidth: 92));

    final w = math.max(titlePainter.width, metricsPainter?.width ?? 0) + 12;
    final h =
        titlePainter.height +
        (metricsPainter?.height ?? 0) +
        (metricsPainter == null ? 6 : 8);
    final prefer = base.translate(0, metricsPainter == null ? -24 : -32);
    final settled = _settleLabel(
      Rect.fromCenter(center: prefer, width: w, height: h),
      occupied,
      size,
    );
    final left = settled.left;
    final top = settled.top;
    final plate = RRect.fromRectAndRadius(settled, const Radius.circular(5));
    canvas.drawRRect(
      plate,
      Paint()
        ..color = const Color(0xFF071114).withValues(alpha: lit ? 0.9 : 0.82),
    );
    canvas.drawRRect(
      plate,
      Paint()
        ..color = color.withValues(alpha: lit ? 0.75 : 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lit ? 1.2 : 1,
    );
    titlePainter.paint(
      canvas,
      Offset(left + (w - titlePainter.width) / 2, top + 3),
    );
    if (metricsPainter != null) {
      metricsPainter.paint(
        canvas,
        Offset(
          left + (w - metricsPainter.width) / 2,
          top + 4 + titlePainter.height,
        ),
      );
    }
  }

  String _metricsLine(Map<String, dynamic> telemetry) {
    final flow = _number(telemetry['flow']);
    final level = _number(telemetry['water_table'] ?? telemetry['nivel']);
    final total = _number(
      telemetry['total'] ?? telemetry['total_raw'] ?? telemetry['consumption'],
    );
    final q = flow == null ? '—' : _compact(flow);
    final n = level == null ? '—' : _compact(level);
    final s = total == null ? '—' : _compact(total);
    return 'Q $q  N $n  Σ $s';
  }

  Rect _settleLabel(Rect box, List<Rect> occupied, Size size) {
    var rect = box;
    for (var attempt = 0; attempt < 12; attempt++) {
      Rect? hit;
      for (final other in occupied) {
        if (rect.inflate(2).overlaps(other)) {
          hit = other;
          break;
        }
      }
      if (hit == null) break;
      final dx = rect.center.dx - hit.center.dx;
      if (attempt.isEven || dx.abs() < 6) {
        rect = rect.shift(const Offset(0, -6));
      } else {
        rect = rect.shift(Offset(dx >= 0 ? 8 : -8, -2));
      }
    }
    var dx = 0.0;
    var dy = 0.0;
    if (rect.left < 4) dx = 4 - rect.left;
    if (rect.right > size.width - 4) dx = size.width - 4 - rect.right;
    if (rect.top < 2) dy = 2 - rect.top;
    final settled = rect.shift(Offset(dx, dy));
    occupied.add(settled);
    return settled;
  }

  static Map<String, dynamic> _telemetry(Map<String, dynamic> point) {
    final value = point['latest_telemetry'];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
    return const {};
  }

  static double? _number(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static String _compact(double value) {
    final abs = value.abs();
    if (abs >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (abs >= 1000) {
      return '${(value / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)}k';
    }
    if (abs >= 10) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  double _levelFill(Map<String, dynamic> point) {
    final level = _number(
      _telemetry(point)['water_table'] ?? _telemetry(point)['nivel'],
    );
    if (level == null) return 0.42;
    final levels = points
        .map((p) {
          final t = _telemetry(p);
          return _number(t['water_table'] ?? t['nivel']);
        })
        .whereType<double>()
        .toList();
    if (levels.length < 2) return 0.5;
    final min = levels.reduce(math.min);
    final max = levels.reduce(math.max);
    if ((max - min).abs() < 0.0001) return 0.5;
    return 0.28 + ((level - min) / (max - min)).clamp(0, 1) * 0.55;
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
      oldDelegate.selected != selected ||
      oldDelegate.motion != motion ||
      oldDelegate.camera.zoom != camera.zoom ||
      oldDelegate.camera.yaw != camera.yaw ||
      oldDelegate.camera.pitch != camera.pitch ||
      oldDelegate.camera.pan != camera.pan;
}
