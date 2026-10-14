import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/brand.dart';
import '../point_link.dart';

/// Mapa de agua del inicio. Los puntos reposan sobre la lámina,
/// emiten ripples según caudal/estado y se unen a su etiqueta.
class CaptureNetworkMap extends StatelessWidget {
  const CaptureNetworkMap({
    required this.points,
    required this.onPointSelected,
    this.bottomInset = 0,
    this.topInset = 0,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onPointSelected;

  /// Margen inferior solo para puntos/tags (el agua pinta todo el rect).
  final double bottomInset;

  /// Margen superior solo para puntos/tags (el agua pinta todo el rect).
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return _WaterView(
      points: points,
      onOpen: onPointSelected,
      topInset: topInset,
      bottomInset: bottomInset,
    );
  }
}

class _WaterView extends StatefulWidget {
  const _WaterView({
    required this.points,
    required this.onOpen,
    required this.topInset,
    required this.bottomInset,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final double topInset;
  final double bottomInset;

  @override
  State<_WaterView> createState() => _WaterViewState();
}

class _WaterViewState extends State<_WaterView>
    with TickerProviderStateMixin {
  /// Tiempo continuo en segundos: la onda no “reinicia” al llegar a 1.
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);
  Ticker? _ticker;
  late final AnimationController _approach = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 920),
  );
  late List<Offset> _ground = layoutWaterField(widget.points);
  double _yaw = 0.12;
  double _tilt = 0.64;
  int? _selected;
  bool _motion = true;
  bool _opening = false;

  _WaterCamera get _camera => _WaterCamera(yaw: _yaw, tilt: _tilt);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _seconds.value = elapsed.inMicroseconds / 1e6;
    });
    _ticker!.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = !MediaQuery.disableAnimationsOf(context);
    if (!_motion) {
      _ticker?.stop();
      _seconds.value = 2.4;
    } else if (_ticker != null && !_ticker!.isActive) {
      _ticker!.start();
    }
  }

  @override
  void didUpdateWidget(covariant _WaterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ground = layoutWaterField(widget.points);
    if (_selected != null && _selected! >= widget.points.length) {
      _selected = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _seconds.dispose();
    _approach.dispose();
    super.dispose();
  }

  void _orbit(Offset delta) {
    if (_opening) return;
    setState(() {
      _yaw += delta.dx * 0.007;
      _tilt = (_tilt + delta.dy * 0.0032).clamp(0.34, 0.92);
    });
  }

  void _select(int index) {
    if (_opening) return;
    setState(() {
      // Segundo click en la misma tarjeta: se cierra con el mismo gesto.
      _selected = _selected == index ? null : index;
    });
  }

  void _clearSelection() {
    if (_opening) return;
    setState(() => _selected = null);
  }

  Future<void> _openSelected() async {
    final index = _selected;
    if (index == null || _opening) return;
    setState(() => _opening = true);
    if (_motion) {
      await _approach.forward(from: 0);
    } else {
      _approach.value = 1;
    }
    if (!mounted) return;
    widget.onOpen(widget.points[index]);
    _approach.reset();
    if (mounted) {
      setState(() {
        _opening = false;
        _selected = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        // Agua = pantalla completa. Puntos/tags viven en el rect útil.
        final contentH = math.max(
          120.0,
          size.height - widget.topInset - widget.bottomInset,
        );
        final content = Size(size.width, contentH);
        final localAnchors = [
          for (final ground in _ground) _camera.project(ground, content),
        ];
        final anchors = [
          for (final a in localAnchors) a.translate(0, widget.topInset),
        ];
        final localChips = placeCaptureChips(localAnchors, content);
        final baseChips = [
          for (final c in localChips) c.shift(Offset(0, widget.topInset)),
        ];
        final expandedW = math.min(236.0, size.width - 20);
        const expandedH = 176.0;
        final chips = repelCaptureChips(
          chips: baseChips,
          selected: _selected,
          size: size,
          expandedWidth: expandedW,
          expandedHeight: expandedH,
        );
        final maxFlow = captureMaxFlow(widget.points);
        final focus = _selected == null ? null : anchors[_selected!];
        // Activa al frente: se pinta al final del Stack.
        final chipOrder = [
          for (var i = 0; i < widget.points.length; i++)
            if (i != _selected) i,
          ?_selected,
        ];

        return AnimatedBuilder(
          animation: _approach,
          builder: (context, _) {
            final approachT = Curves.easeInOutCubic.transform(_approach.value);
            final zoom = 1.0 + approachT * 0.85;
            final diving = _opening || _approach.value > 0;
            final selected = _selected;

            Widget waterLayer = Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onPanUpdate: (details) => _orbit(details.delta),
                    onTap: _clearSelection,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _seconds,
                      builder: (context, seconds, _) => CustomPaint(
                        painter: _LivingWaterPainter(
                          seconds: seconds,
                          motion: _motion,
                          points: widget.points,
                          anchors: anchors,
                          chips: chips,
                          selected: selected,
                          maxFlow: maxFlow,
                          approach: _approach.value,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                for (var index = 0; index < widget.points.length; index++)
                  Positioned(
                    left: anchors[index].dx - 22,
                    top: anchors[index].dy - 26,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: !diving || index == selected ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: diving && index != selected,
                        child: _Beacon(
                          point: widget.points[index],
                          selected: selected == index,
                          onTap: () => _select(index),
                        ),
                      ),
                    ),
                  ),
              ],
            );

            // El zoom de agua es profundo; la tarjeta abierta vive aparte y no se “cierra”.
            if (focus != null && approachT > 0) {
              waterLayer = Transform(
                alignment: Alignment(
                  ((focus.dx / size.width) * 2) - 1,
                  ((focus.dy / size.height) * 2) - 1,
                ),
                transform: Matrix4.diagonal3Values(zoom, zoom, 1),
                child: waterLayer,
              );
            }

            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                waterLayer,
                // Otras tarjetas: se van al hacer Ver.
                for (final index in chipOrder)
                  if (index != selected)
                    AnimatedPositioned(
                      key: ValueKey('capture-chip-pos-$index'),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      left: chips[index].left,
                      top: chips[index].top,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: diving ? 0 : 1,
                        child: IgnorePointer(
                          ignoring: diving,
                          child: _StatusChip(
                            point: widget.points[index],
                            active: false,
                            maxWidth: baseChips[index].width,
                            overWater: true,
                            onTap: () => _select(index),
                          ),
                        ),
                      ),
                    ),
                // Tarjeta abierta: se queda al frente durante el ingreso.
                if (selected != null)
                  AnimatedPositioned(
                    key: ValueKey('capture-chip-pos-$selected'),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    left: chips[selected].left,
                    top: chips[selected].top,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: 1,
                      child: AnimatedScale(
                        scale: diving ? 1.0 - approachT * 0.08 : 1.0,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOut,
                        child: _StatusChip(
                          point: widget.points[selected],
                          active: true,
                          maxWidth: chips[selected].width,
                          overWater: true,
                          onTap: () => _select(selected),
                          onVer: diving ? null : _openSelected,
                        ),
                      ),
                    ),
                  ),
                if (widget.points.isEmpty) const _EmptyNetwork(),
              ],
            );
          },
        );
      },
    );
  }
}

class _WaterCamera {
  const _WaterCamera({required this.yaw, required this.tilt});

  final double yaw;
  final double tilt;

  (double x, double z) _rotated(Offset ground) {
    return (
      ground.dx * math.cos(yaw) - ground.dy * math.sin(yaw),
      ground.dx * math.sin(yaw) + ground.dy * math.cos(yaw),
    );
  }

  /// Perspectiva suave: lo cercano baja y se abre, sin recortar una lámina.
  Offset project(Offset ground, Size size) {
    final (x, z) = _rotated(ground);
    final depth = ((z + 1.15) / 2.3).clamp(0.0, 1.0);
    final spread = 0.84 + depth * (0.16 + tilt * 0.22);
    final yNorm = 0.16 + depth * (0.36 + tilt * 0.26);
    return Offset(size.width * (0.50 + x * 0.44 * spread), size.height * yNorm);
  }
}

class _LivingWaterPainter extends CustomPainter {
  _LivingWaterPainter({
    required this.seconds,
    required this.motion,
    required this.points,
    required this.anchors,
    required this.chips,
    required this.selected,
    required this.maxFlow,
    required this.approach,
  });

  final double seconds;
  final bool motion;
  final List<Map<String, dynamic>> points;
  final List<Offset> anchors;
  final List<Rect> chips;
  final int? selected;
  final double maxFlow;
  final double approach;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final t = motion ? seconds : 2.4;

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16363F), Color(0xFF0E242A), Color(0xFF061114)],
          stops: [0, 0.42, 1],
        ).createShader(bounds),
    );

    _paintWaterTexture(canvas, size, t);

    // Transición “sumergirse”: el agua se abre hacia el punto elegido.
    if (selected != null && approach > 0) {
      _paintDiveWash(canvas, size, anchors[selected!], approach);
    }

    // Red bajo el agua: energía muy sutil entre puntos.
    if (approach < 0.55) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 1 - approach * 1.4),
      );
      _paintUnderwaterLinks(canvas);
      canvas.restore();
    }

    // Waves en el fondo (lámina), no en el “punto parpadeante”.
    for (var index = 0; index < points.length; index++) {
      if (approach > 0.35 && selected != null && index != selected) continue;
      final strength = captureRippleStrength(
        point: points[index],
        selected: selected == index,
        maxFlow: maxFlow,
      );
      _paintWaterImpact(
        canvas,
        anchors[index],
        _linkColor(points[index]),
        strength: strength * 0.72 +
            (selected == index ? approach * 0.55 : 0),
        seed: index,
        seconds: t,
        active: selected == index,
      );
    }

    // Tags como nodos marcados: línea sutil ficha → punto.
    for (var index = 0; index < points.length; index++) {
      if (approach > 0.25 && selected != null && index != selected) continue;
      final active = selected == index;
      final color = _linkColor(points[index]);
      final path = captureLeaderPath(chips[index], anchors[index]);
      final fade = active ? 1.0 : (1 - approach).clamp(0.0, 1.0);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: (active ? 0.38 : 0.16) * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 1.0 : 0.7
          ..strokeCap = StrokeCap.round,
      );
      final attach = captureChipAttach(chips[index], anchors[index]);
      canvas.drawCircle(
        attach,
        active ? 2.2 : 1.6,
        Paint()
          ..color = color.withValues(alpha: (active ? 0.55 : 0.28) * fade),
      );
    }
  }

  void _paintDiveWash(
    Canvas canvas,
    Size size,
    Offset center,
    double approach,
  ) {
    final t = Curves.easeInOutCubic.transform(approach.clamp(0.0, 1.0));
    final maxDim = math.max(size.width, size.height);
    final radius = maxDim * (0.18 + t * 1.25);

    // Oscurece el resto: sensación de sumergirse.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF02080A).withValues(alpha: 0.42 * t),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFB8F3E8).withValues(alpha: 0.22 * t),
            const Color(0xFF2A6A74).withValues(alpha: 0.14 * t),
            const Color(0xFF0A1C20).withValues(alpha: 0.35 * t),
            const Color(0xFF02080A).withValues(alpha: 0.72 * t),
          ],
          stops: const [0, 0.22, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // Anillos de impacto más densos y profundos.
    for (var ring = 0; ring < 7; ring++) {
      final local = ((t * 1.05 + ring * 0.11) % 1.0);
      final r = 12 + local * radius * 0.85;
      final fade = math.pow(1 - local, 1.25).toDouble();
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(0, 2),
          width: r * 2.15,
          height: r * 1.05,
        ),
        Paint()
          ..color = const Color(0xFF8EE6D8).withValues(
            alpha: (0.20 * fade * t).clamp(0.0, 0.32),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1.2 + (1 - local) * 2.2).clamp(1.0, 3.0)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(0, 2),
          width: r * 1.95,
          height: r * 0.95,
        ),
        Paint()
          ..color = const Color(0xFF041014).withValues(
            alpha: (0.10 * fade * t).clamp(0.0, 0.18),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
      );
    }
  }

  void _paintUnderwaterLinks(Canvas canvas) {
    if (anchors.length < 2) return;
    final projects = [
      for (final point in points) captureProjectKey(point),
    ];
    final edges = captureNetworkEdges(
      projects: projects,
      positions: anchors,
    );
    for (final edge in edges) {
      final a = anchors[edge.$1];
      final b = anchors[edge.$2];
      final sameProject =
          projects[edge.$1].isNotEmpty &&
          projects[edge.$1] == projects[edge.$2];
      final mid = Offset.lerp(a, b, 0.5)!;
      final bend = mid.translate(0, sameProject ? 10 : 16);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, b.dx, b.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF7FD9CB).withValues(
            alpha: sameProject ? 0.10 : 0.06,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = sameProject ? 1.15 : 0.9
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
      );
    }
  }

  /// Textura de lámina: waves concéntricas tenues + caústicas (referencia).
  void _paintWaterTexture(Canvas canvas, Size size, double seconds) {
    final origin = Offset(size.width * 0.52, size.height * 0.46);
    final maxR = math.max(size.width, size.height) * 0.72;
    for (var ring = 0; ring < 10; ring++) {
      final local = ((seconds * 0.08 + ring * 0.11) % 1.0);
      final radius = 24 + local * maxR;
      final fade = (1 - local);
      canvas.drawOval(
        Rect.fromCenter(
          center: origin,
          width: radius * 2.05,
          height: radius * 1.05,
        ),
        Paint()
          ..color = const Color(0xFF7FD9CB).withValues(alpha: 0.035 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    final drift = math.sin(seconds * 0.35) * 0.02;
    final sheen = Rect.fromCenter(
      center: Offset(size.width * (0.5 + drift), size.height * 0.4),
      width: size.width * 1.15,
      height: size.height * 0.65,
    );
    canvas.drawOval(
      sheen,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF2A6A74).withValues(alpha: 0.26),
            const Color(0xFF2A6A74).withValues(alpha: 0),
          ],
        ).createShader(sheen),
    );
  }

  /// Onda suave en la lámina: luminosa, sin parpadeo agresivo.
  void _paintWaterImpact(
    Canvas canvas,
    Offset center,
    Color color, {
    required double strength,
    required int seed,
    required double seconds,
    required bool active,
  }) {
    final rings = active ? 4 : 2;
    final maxR = (38 + strength * (active ? 78 : 48)).clamp(34.0, 120.0);
    const aspect = 0.5;
    final speed = 0.12 + strength * 0.06;

    for (var ring = 0; ring < rings; ring++) {
      final local = (seconds * speed + seed * 0.37 + ring * 0.31) % 1.0;
      final radius = 14 + local * maxR;
      final fade = math.pow(1 - local, 1.55).toDouble().clamp(0.0, 1.0);
      final oval = Rect.fromCenter(
        center: center.translate(0, 2),
        width: radius * 2,
        height: radius * 2 * aspect,
      );

      canvas.drawOval(
        oval.inflate(4),
        Paint()
          ..color = const Color(0xFF9BE8DC).withValues(
            alpha: (0.045 + strength * 0.07) * fade * (active ? 1.15 : 0.75),
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      canvas.drawOval(
        oval,
        Paint()
          ..color = color.withValues(
            alpha: (0.10 + strength * 0.16) * fade * (active ? 1.1 : 0.8),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1.0 + (1 - local) * 1.1).clamp(0.8, 2.0)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LivingWaterPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.motion != motion ||
      oldDelegate.selected != selected ||
      oldDelegate.maxFlow != maxFlow ||
      oldDelegate.approach != approach ||
      oldDelegate.points != points ||
      oldDelegate.anchors != anchors ||
      oldDelegate.chips != chips;
}

/// Puntos sobre el plano de agua, separados para que las fichas no se monten.
@visibleForTesting
List<Offset> layoutWaterField(List<Map<String, dynamic>> points) {
  if (points.isEmpty) return const [];
  final coords = [for (final point in points) captureLatLng(point)];
  final raw = coords.every((coord) => coord != null)
      ? _groundFromGps([for (final coord in coords) coord!])
      : _groundFromLayout(points);
  _separateGround(raw);
  return raw;
}

List<Offset> _groundFromGps(List<LatLng> coords) {
  if (coords.length == 1) return const [Offset.zero];
  var minLat = coords.first.latitude;
  var maxLat = minLat;
  var minLon = coords.first.longitude;
  var maxLon = minLon;
  for (final coord in coords) {
    minLat = math.min(minLat, coord.latitude);
    maxLat = math.max(maxLat, coord.latitude);
    minLon = math.min(minLon, coord.longitude);
    maxLon = math.max(maxLon, coord.longitude);
  }
  final latSpan = math.max(maxLat - minLat, 0.0008);
  final lonSpan = math.max(maxLon - minLon, 0.0008);
  return [
    for (final coord in coords)
      Offset(
        ((coord.longitude - minLon) / lonSpan - 0.5) * 1.35,
        (0.5 - (coord.latitude - minLat) / latSpan) * 1.35,
      ),
  ];
}

List<Offset> _groundFromLayout(List<Map<String, dynamic>> points) {
  const board = Size(1000, 1000);
  final laid = layoutCaptureNodes(board, [
    for (final point in points) captureProjectKey(point),
  ]);
  return [
    for (final spot in laid)
      Offset(
        (spot.dx / board.width - 0.5) * 1.5,
        (spot.dy / board.height - 0.5) * 1.5,
      ),
  ];
}

void _separateGround(List<Offset> spots) {
  // Un poco más de aire para que los ripples no se monten.
  const minDist = 0.44;
  for (var pass = 0; pass < 28; pass++) {
    for (var i = 0; i < spots.length; i++) {
      for (var j = i + 1; j < spots.length; j++) {
        var delta = spots[j] - spots[i];
        var dist = delta.distance;
        if (dist < 0.001) {
          delta = Offset(minDist, 0.05 * (j - i));
          dist = delta.distance;
        }
        if (dist >= minDist) continue;
        final push = delta / dist * (minDist - dist) * 0.5;
        spots[i] -= push;
        spots[j] += push;
      }
    }
    for (var i = 0; i < spots.length; i++) {
      spots[i] = Offset(
        spots[i].dx.clamp(-0.86, 0.86),
        spots[i].dy.clamp(-0.86, 0.86),
      );
    }
  }
}

/// Coloca fichas arriba/abajo, alejadas de los puntos (arquitectura de nodos).
@visibleForTesting
List<Rect> placeCaptureChips(List<Offset> anchors, Size size) {
  const gap = 10.0;
  const pad = 12.0;
  final width = size.width < 420 ? 136.0 : 168.0;
  const height = 48.0;
  // Holgura para que la ficha no tape el beacon ni su ripple cercano.
  const clearR = 56.0;

  bool overlapsBeacon(Rect rect) {
    final hit = rect.inflate(8);
    return anchors.any(
      (a) => hit.overlaps(Rect.fromCircle(center: a, radius: clearR)),
    );
  }

  bool overlapsAny(Rect rect, List<Rect> placed) =>
      placed.any((other) => other.inflate(4).overlaps(rect));

  List<Rect> bandSlots({required bool top}) {
    final slots = <Rect>[];
    final maxLeft = math.max(pad, size.width - width - pad);
    // Hasta 3 filas por banda para muchos puntos, sin entrar al núcleo.
    final rows = size.height < 560 ? 2 : 3;
    for (var row = 0; row < rows; row++) {
      final y = top
          ? pad + row * (height + gap)
          : math.max(pad, size.height - height - pad) - row * (height + gap);
      if (y < pad || y + height > size.height - pad) continue;
      // Evita filas que caigan en la franja central de puntos.
      final ny = (y + height / 2) / size.height;
      if (ny > 0.32 && ny < 0.68) continue;
      final stagger = row.isOdd ? (width + gap) * 0.5 : 0.0;
      for (var left = pad + stagger; left <= maxLeft + 0.1; left += width + gap) {
        slots.add(Rect.fromLTWH(left, y, width, height));
      }
    }
    return slots;
  }

  final slots = [...bandSlots(top: true), ...bandSlots(top: false)];
  final used = List<bool>.filled(slots.length, false);
  final assigned = List<Rect?>.filled(anchors.length, null);

  final order = List<int>.generate(anchors.length, (i) => i)
    ..sort((a, b) {
      // Primero los más centrados: necesitan tag en el borde con más cuidado.
      final ca = (anchors[a] - Offset(size.width / 2, size.height / 2)).distance;
      final cb = (anchors[b] - Offset(size.width / 2, size.height / 2)).distance;
      return cb.compareTo(ca);
    });

  for (final index in order) {
    final anchor = anchors[index];
    final preferTop = anchor.dy >= size.height * 0.5;
    var best = -1;
    var bestScore = double.infinity;
    for (var s = 0; s < slots.length; s++) {
      if (used[s]) continue;
      final slot = slots[s];
      if (overlapsBeacon(slot)) continue;
      final onTop = slot.top < size.height * 0.35;
      final bandBias = (preferTop == onTop) ? 0.0 : 90.0;
      final dist = (slot.center - anchor).distance;
      final score = dist + bandBias;
      if (score < bestScore) {
        bestScore = score;
        best = s;
      }
    }
    if (best >= 0) {
      used[best] = true;
      assigned[index] = slots[best];
    }
  }

  final placed = <Rect>[];
  for (var index = 0; index < anchors.length; index++) {
    if (assigned[index] != null) {
      placed.add(assigned[index]!);
      continue;
    }
    // Reservas libres aunque toquen menos; luego se empujan.
    final preferTop = anchors[index].dy >= size.height * 0.5;
    final y = preferTop
        ? pad
        : math.max(pad, size.height - height - pad);
    var left = pad;
    var rect = Rect.fromLTWH(left, y, width, height);
    var guard = 0;
    while ((overlapsAny(rect, placed) || overlapsBeacon(rect)) &&
        guard < 40) {
      left += width + gap;
      if (left > size.width - width - pad) {
        left = pad;
        final altY = preferTop
            ? pad + height + gap
            : math.max(pad, y - height - gap);
        rect = Rect.fromLTWH(left, altY, width, height);
      } else {
        rect = Rect.fromLTWH(left, y, width, height);
      }
      guard++;
    }
    placed.add(rect);
  }

  // Empuje sutil: fichas lejos de beacons y entre sí.
  final separated = _separateChipsFromBeacons(placed, anchors, size);
  return _dedupeChipSlots(separated, size, width, height);
}

List<Rect> _dedupeChipSlots(
  List<Rect> chips,
  Size size,
  double width,
  double height,
) {
  const pad = 10.0;
  const gap = 8.0;
  final result = [for (final c in chips) c];
  for (var i = 0; i < result.length; i++) {
    for (var j = 0; j < i; j++) {
      if (!result[i].inflate(2).overlaps(result[j])) continue;
      // Busca hueco libre en bandas.
      var placed = false;
      for (final topBand in [true, false]) {
        final rows = 4;
        for (var row = 0; row < rows && !placed; row++) {
          final y = topBand
              ? pad + row * (height + gap)
              : math.max(pad, size.height - height - pad) -
                  row * (height + gap);
          if (y < pad || y + height > size.height - pad) continue;
          final ny = (y + height / 2) / size.height;
          if (ny > 0.34 && ny < 0.66) continue;
          for (var left = pad;
              left <= size.width - width - pad + 0.1;
              left += width + gap) {
            final candidate = Rect.fromLTWH(left, y, width, height);
            final hits = result.asMap().entries.any(
              (e) => e.key != i && e.value.inflate(2).overlaps(candidate),
            );
            if (hits) continue;
            result[i] = candidate;
            placed = true;
            break;
          }
        }
      }
    }
  }
  return result;
}

List<Rect> _separateChipsFromBeacons(
  List<Rect> chips,
  List<Offset> anchors,
  Size size,
) {
  const pad = 10.0;
  const clearR = 52.0;
  final result = [for (final c in chips) c];
  for (var round = 0; round < 10; round++) {
    for (var i = 0; i < result.length; i++) {
      var rect = result[i];
      for (final anchor in anchors) {
        final zone = Rect.fromCircle(center: anchor, radius: clearR);
        if (!rect.overlaps(zone)) continue;
        final delta = rect.center - anchor;
        final dir = delta.distance < 0.001
            ? const Offset(0, -1)
            : delta / delta.distance;
        final vertical = Offset(dir.dx * 0.2, dir.dy >= 0 ? 1.0 : -1.0);
        final norm = vertical.distance < 0.001
            ? const Offset(0, -1)
            : vertical / vertical.distance;
        rect = rect.shift(norm * 14);
      }
      for (var j = 0; j < result.length; j++) {
        if (i == j) continue;
        if (!rect.inflate(4).overlaps(result[j])) continue;
        final delta = rect.center - result[j].center;
        final dir = delta.distance < 0.001
            ? Offset(i.isEven ? 1.0 : -1.0, 0)
            : delta / delta.distance;
        rect = rect.shift(Offset(dir.dx * 12, dir.dy * 8));
      }
      final left =
          rect.left.clamp(pad, math.max(pad, size.width - pad - rect.width));
      var top =
          rect.top.clamp(pad, math.max(pad, size.height - pad - rect.height));
      // Si quedó en el núcleo, mándala a la banda más cercana.
      final ny = (top + rect.height / 2) / size.height;
      if (ny > 0.34 && ny < 0.66) {
        top = ny < 0.5
            ? pad.toDouble()
            : math.max(pad, size.height - pad - rect.height).toDouble();
      }
      result[i] = Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        rect.width,
        rect.height,
      );
    }
  }
  return result;
}

/// Al abrir una ficha, crece y empuja las demás para que no se pisen.
@visibleForTesting
List<Rect> repelCaptureChips({
  required List<Rect> chips,
  required int? selected,
  required Size size,
  required double expandedWidth,
  required double expandedHeight,
}) {
  if (chips.isEmpty) return const [];
  final result = [for (final chip in chips) chip];
  if (selected == null || selected < 0 || selected >= chips.length) {
    return result;
  }

  const pad = 8.0;
  final focusW =
      expandedWidth.clamp(80.0, math.max(80.0, size.width - pad * 2)).toDouble();
  final focusH = expandedHeight
      .clamp(50.0, math.max(50.0, size.height - pad * 2))
      .toDouble();
  var focusLeft = chips[selected].left;
  var focusTop = chips[selected].top;
  if (focusLeft + focusW > size.width - pad) {
    focusLeft = size.width - pad - focusW;
  }
  if (focusTop + focusH > size.height - pad) {
    focusTop = size.height - pad - focusH;
  }
  focusLeft = focusLeft
      .clamp(pad, math.max(pad, size.width - pad - focusW))
      .toDouble();
  focusTop = focusTop
      .clamp(pad, math.max(pad, size.height - pad - focusH))
      .toDouble();
  final focus = Rect.fromLTWH(focusLeft, focusTop, focusW, focusH);
  result[selected] = focus;

  Offset clampOrigin(Rect rect) {
    return Offset(
      rect.left.clamp(pad, math.max(pad, size.width - pad - rect.width)),
      rect.top.clamp(pad, math.max(pad, size.height - pad - rect.height)),
    );
  }

  for (var round = 0; round < 14; round++) {
    for (var i = 0; i < result.length; i++) {
      if (i == selected) continue;
      var rect = result[i];
      final blockers = <Rect>[
        focus.inflate(12),
        for (var j = 0; j < result.length; j++)
          if (j != i && j != selected) result[j].inflate(5),
      ];
      for (final blocker in blockers) {
        if (!rect.overlaps(blocker)) continue;
        var delta = rect.center - blocker.center;
        if (delta.distance < 0.001) {
          delta = Offset(i.isEven ? 1.0 : -1.0, rect.center.dy < focus.center.dy ? -1.0 : 1.0);
        }
        // Empuja más en vertical para mantener bandas arriba/abajo.
        final push = Offset(
          (delta.dx / delta.distance) * 10,
          (delta.dy / delta.distance) * 16,
        );
        rect = rect.shift(push);
        final origin = clampOrigin(rect);
        rect = Rect.fromLTWH(origin.dx, origin.dy, rect.width, rect.height);
      }
      result[i] = rect;
    }
  }
  return result;
}

class _Beacon extends StatelessWidget {
  const _Beacon({
    required this.point,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> point;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _linkColor(point);
    return Semantics(
      button: true,
      label: _title(point),
      child: GestureDetector(
        key: ValueKey('capture-node-${_pointKey(point)}'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 34,
          child: CustomPaint(
            painter: _BeaconPainter(
              color: color,
              selected: selected,
              surface: captureIsSurface(point),
            ),
          ),
        ),
      ),
    );
  }
}

class _BeaconPainter extends CustomPainter {
  _BeaconPainter({
    required this.color,
    required this.selected,
    required this.surface,
  });

  final Color color;
  final bool selected;
  final bool surface;

  @override
  void paint(Canvas canvas, Size size) {
    // Marca quieta apoyada en el agua: sombra + lente de contacto + núcleo.
    final seat = Offset(size.width / 2, size.height * 0.7);

    canvas.drawOval(
      Rect.fromCenter(
        center: seat.translate(0, 4),
        width: surface ? 28 : 20,
        height: surface ? 8 : 6,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: seat.translate(0, 2),
        width: surface ? 20 : 15,
        height: surface ? 6 : 4.5,
      ),
      Paint()
        ..color = color.withValues(alpha: selected ? 0.28 : 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    final coreR = selected ? 5.0 : 4.2;
    canvas.drawOval(
      Rect.fromCenter(center: seat, width: coreR * 2.1, height: coreR * 1.55),
      Paint()..color = color.withValues(alpha: 0.94),
    );
    canvas.drawOval(
      Rect.fromCenter(center: seat, width: coreR * 2.1, height: coreR * 1.55),
      Paint()
        ..color = const Color(0xFF061214).withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );
  }

  @override
  bool shouldRepaint(covariant _BeaconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.surface != surface;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.point,
    required this.onTap,
    required this.active,
    required this.maxWidth,
    required this.overWater,
    this.onVer,
  });

  final Map<String, dynamic> point;
  final VoidCallback onTap;
  final bool active;
  final double maxWidth;
  final bool overWater;
  final Future<void> Function()? onVer;

  @override
  Widget build(BuildContext context) {
    final status = _linkColor(point);
    final link = pointLinkOf(point);
    final flow = captureFlowOf(point);
    final project = captureProjectKey(point);
    final kind = captureIsSurface(point) ? 'Superficial' : 'Subterráneo';

    final body = AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 8, 11, active ? 10 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: status,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      _title(point),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: active
                            ? const Color(0xFFF2FAF8)
                            : const Color(0xFFE2EEEC),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                pointLinkLabel(link),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: status.withValues(alpha: 0.92),
                ),
              ),
              if (active) ...[
                const SizedBox(height: 8),
                _chipMeta('Tipo', kind),
                if (project.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _chipMeta('Proyecto', project),
                ],
                if (flow != null) ...[
                  const SizedBox(height: 4),
                  _chipMeta('Caudal', '${flow.toStringAsFixed(2)} L/s'),
                ],
                const SizedBox(height: 4),
                _chipMeta('Ubicación', captureLocationLabel(point)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const ValueKey('capture-quick-ver'),
                    onPressed: onVer,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE7F4F2),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                      minimumSize: const Size.fromHeight(34),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: const Text(
                      'Ver',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final radius = BorderRadius.circular(active ? 16 : 14);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: active
              ? status.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
        color: active
            ? const Color(0xC4121C1E)
            : const Color(0xB10E1618),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: active ? 0.4 : 0.22),
            blurRadius: active ? 18 : 10,
            offset: Offset(0, active ? 8 : 4),
          ),
          if (active)
            BoxShadow(
              color: status.withValues(alpha: 0.14),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: body,
    );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: active ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: active ? 12 : 8,
              sigmaY: active ? 12 : 8,
            ),
            child: card,
          ),
        ),
      ),
    );
  }

  Widget _chipMeta(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8FA3A4)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: Color(0xFFD5E4E2),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyNetwork extends StatelessWidget {
  const _EmptyNetwork();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Cuando tu cuenta tenga puntos de captación, la red aparecerá aquí.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFB7C8C7), height: 1.35),
        ),
      ),
    );
  }
}

/// Encuadre para que todos los puntos quepan, dejando aire al título.
@visibleForTesting
({LatLng center, double zoom}) captureCameraFor(
  Size size,
  List<LatLng> points,
) {
  if (points.isEmpty || size.width < 32 || size.height < 32) {
    return (center: const LatLng(-33.45, -70.66), zoom: 5);
  }
  var minLat = points.first.latitude;
  var maxLat = minLat;
  var minLon = points.first.longitude;
  var maxLon = minLon;
  for (final point in points) {
    minLat = math.min(minLat, point.latitude);
    maxLat = math.max(maxLat, point.latitude);
    minLon = math.min(minLon, point.longitude);
    maxLon = math.max(maxLon, point.longitude);
  }
  final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
  if ((maxLat - minLat).abs() < 0.0008 && (maxLon - minLon).abs() < 0.0008) {
    return (center: center, zoom: 13);
  }

  final padX = math.min(56.0, size.width * 0.12);
  final padTop = math.min(128.0, size.height * 0.24);
  final padBottom = math.min(80.0, size.height * 0.14);
  final availW = math.max(48.0, size.width - padX * 2);
  final availH = math.max(48.0, size.height - padTop - padBottom);
  final dx = math.max((maxLon - minLon).abs() / 360, 1e-9);
  final dy = math.max((_mercatorY(minLat) - _mercatorY(maxLat)).abs(), 1e-9);
  final zoomX = math.log(availW / (256 * dx)) / math.ln2;
  final zoomY = math.log(availH / (256 * dy)) / math.ln2;
  // Un nivel de aire para que la red no quede pegada al borde del visor.
  final zoom = (math.min(zoomX, zoomY) - 1.1).clamp(3.0, 13.0);
  return (center: center, zoom: zoom);
}

double _mercatorY(double latitude) {
  final sine = math.sin(latitude * math.pi / 180);
  return 0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi);
}

/// Coordenada del punto. Cero o ausente no cuenta como GPS.
@visibleForTesting
LatLng? captureLatLng(Map<String, dynamic> point) {
  final lat =
      _coordinate(point['lat']) ??
      _coordinate(point['latitude']) ??
      _nestedCoordinate(point, 'lat');
  final lon =
      _coordinate(point['lon']) ??
      _coordinate(point['lng']) ??
      _coordinate(point['longitude']) ??
      _nestedCoordinate(point, 'lon') ??
      _nestedCoordinate(point, 'lng');
  if (lat == null || lon == null || lat == 0 || lon == 0) return null;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
  return LatLng(lat, lon);
}

double? _nestedCoordinate(Map<String, dynamic> point, String key) {
  for (final nest in ['location', 'dga', 'geo']) {
    final value = point[nest];
    if (value is Map) {
      final parsed = _coordinate(value[key]);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double? _coordinate(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
  return null;
}

/// Nombre de proyecto usado para agrupar la red. Vacío si no hay.
@visibleForTesting
String captureProjectKey(Map<String, dynamic> point) {
  final name = point['project_name']?.toString().trim();
  if (name == null || name.isEmpty || name == 'null') return '';
  return name;
}

@visibleForTesting
bool captureIsSurface(Map<String, dynamic> point) {
  final dga = point['dga'];
  if (dga is Map && '${dga['type_dga']}'.toUpperCase() == 'SUPERFICIAL') {
    return true;
  }
  return '${point['type_dga']}'.toUpperCase() == 'SUPERFICIAL';
}

/// Árbol de la red: primero une cada proyecto, después une los proyectos.
@visibleForTesting
List<(int, int)> captureNetworkEdges({
  required List<String> projects,
  required List<Offset> positions,
}) {
  final groups = <String, List<int>>{};
  for (var index = 0; index < projects.length; index++) {
    groups.putIfAbsent(projects[index], () => []).add(index);
  }
  double distance(int a, int b) {
    final delta = positions[a] - positions[b];
    return delta.dx * delta.dx + delta.dy * delta.dy;
  }

  final links = <(int, int)>[];
  final reps = <int>[];
  for (final members in groups.values) {
    links.addAll(_spanningTree(members, distance));
    reps.add(_representative(members, positions));
  }
  if (reps.length > 1) links.addAll(_spanningTree(reps, distance));
  return links;
}

/// Posiciones de la vista esquemática, agrupadas por proyecto.
@visibleForTesting
List<Offset> layoutCaptureNodes(Size size, List<String> projects) {
  final offsets = List<Offset>.filled(projects.length, Offset.zero);
  if (projects.isEmpty || size.isEmpty) return offsets;

  final groups = <String, List<int>>{};
  for (var index = 0; index < projects.length; index++) {
    groups.putIfAbsent(projects[index], () => []).add(index);
  }
  final keys = groups.keys.toList(growable: false);
  // El título ocupa arriba y las etiquetas necesitan aire abajo.
  final insetX = math.min(40.0, size.width * 0.12);
  final top = math.min(118.0, size.height * 0.24);
  final insetBottom = math.min(84.0, size.height * 0.18);
  final safe = Rect.fromLTRB(
    insetX,
    top,
    math.max(insetX + 1, size.width - insetX),
    math.max(top + 1, size.height - insetBottom),
  );
  final center = safe.center;
  final clusterPad = groups.values.map(_clusterRadius).reduce(math.max);
  final room = math.min(safe.width, safe.height);
  final fit = room / 2 - clusterPad - 8;
  // La red queda en el centro, sin estirarse hasta los bordes.
  final orbit = keys.length <= 1
      ? math.min(math.max(52.0, fit), room * 0.34)
      : math.min(math.max(72.0, fit * 0.45), room * 0.28);

  if (keys.length == 1) {
    _placeRing(offsets, groups[keys.first]!, center, orbit);
  } else {
    for (var group = 0; group < keys.length; group++) {
      final angle = -math.pi / 2 + group * 2 * math.pi / keys.length;
      final hub = center + Offset(math.cos(angle), math.sin(angle)) * orbit;
      final members = groups[keys[group]]!;
      _placeRing(offsets, members, hub, _clusterRadius(members));
    }
  }

  for (var index = 0; index < offsets.length; index++) {
    offsets[index] = Offset(
      offsets[index].dx.clamp(safe.left, safe.right),
      offsets[index].dy.clamp(safe.top, safe.bottom),
    );
  }
  return offsets;
}

double _clusterRadius(List<int> members) {
  if (members.length <= 1) return 0;
  return 36 / math.sin(math.pi / members.length);
}

void _placeRing(
  List<Offset> out,
  List<int> members,
  Offset center,
  double radius,
) {
  if (members.length == 1 || radius == 0) {
    out[members.first] = center;
    return;
  }
  for (var index = 0; index < members.length; index++) {
    final angle = -math.pi / 2 + index * 2 * math.pi / members.length;
    out[members[index]] =
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }
}

int _representative(List<int> members, List<Offset> positions) {
  if (members.length == 1) return members.first;
  var cx = 0.0;
  var cy = 0.0;
  for (final index in members) {
    cx += positions[index].dx;
    cy += positions[index].dy;
  }
  final centroid = Offset(cx / members.length, cy / members.length);
  var best = members.first;
  var bestDistance = double.infinity;
  for (final index in members) {
    final distance = (positions[index] - centroid).distanceSquared;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = index;
    }
  }
  return best;
}

List<(int, int)> _spanningTree(
  List<int> nodes,
  double Function(int a, int b) distance,
) {
  if (nodes.length < 2) return const [];
  final edges = <(double, int, int)>[];
  for (var i = 0; i < nodes.length; i++) {
    for (var j = i + 1; j < nodes.length; j++) {
      edges.add((distance(nodes[i], nodes[j]), nodes[i], nodes[j]));
    }
  }
  edges.sort((a, b) => a.$1.compareTo(b.$1));

  final parent = <int, int>{for (final node in nodes) node: node};
  int find(int node) {
    var root = node;
    while (parent[root] != root) {
      root = parent[root]!;
    }
    var current = node;
    while (parent[current] != root) {
      final next = parent[current]!;
      parent[current] = root;
      current = next;
    }
    return root;
  }

  final links = <(int, int)>[];
  for (final edge in edges) {
    final left = find(edge.$2);
    final right = find(edge.$3);
    if (left == right) continue;
    parent[left] = right;
    links.add((edge.$2, edge.$3));
    if (links.length == nodes.length - 1) break;
  }
  return links;
}

/// Texto de ubicación para la ficha: coords o aviso sin GPS.
@visibleForTesting
String captureLocationLabel(Map<String, dynamic> point) {
  final gps = captureLatLng(point);
  if (gps == null) return 'Sin ubicación GPS';
  return '${gps.latitude.toStringAsFixed(5)}, ${gps.longitude.toStringAsFixed(5)}';
}

/// Intensidad visual del ripple: caudal normalizado + boost si está activo.
@visibleForTesting
double captureRippleStrength({
  required Map<String, dynamic> point,
  required bool selected,
  double? maxFlow,
}) {
  final flow = captureFlowOf(point) ?? 0;
  final ceiling = (maxFlow == null || maxFlow <= 0) ? 1.0 : maxFlow;
  final normalized = (flow / ceiling).clamp(0.0, 1.0);
  var strength = 0.18 + normalized * 0.42;
  if (selected) strength = (strength + 0.32).clamp(0.0, 1.0);
  return strength;
}

@visibleForTesting
double? captureFlowOf(Map<String, dynamic> point) {
  final telemetry = point['latest_telemetry'];
  if (telemetry is! Map) return null;
  final raw = telemetry['flow'];
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    return double.tryParse(raw.trim().replaceAll(',', '.'));
  }
  return null;
}

@visibleForTesting
double captureMaxFlow(List<Map<String, dynamic>> points) {
  var max = 0.0;
  for (final point in points) {
    final flow = captureFlowOf(point);
    if (flow != null && flow > max) max = flow;
  }
  return max;
}

/// Línea recta desde el borde del chip hasta el beacon (arquitectura de nodos).
@visibleForTesting
Path captureLeaderPath(Rect chip, Offset beacon) {
  final attach = captureChipAttach(chip, beacon);
  return Path()
    ..moveTo(attach.dx, attach.dy)
    ..lineTo(beacon.dx, beacon.dy);
}

@visibleForTesting
Offset captureChipAttach(Rect chip, Offset beacon) {
  final center = chip.center;
  final delta = beacon - center;
  if (delta.distance < 0.001) return center;
  final nx = delta.dx / delta.distance;
  final ny = delta.dy / delta.distance;
  final halfW = chip.width / 2;
  final halfH = chip.height / 2;
  final tx = nx.abs() < 1e-9 ? double.infinity : halfW / nx.abs();
  final ty = ny.abs() < 1e-9 ? double.infinity : halfH / ny.abs();
  final t = math.min(tx, ty);
  return Offset(center.dx + nx * t, center.dy + ny * t);
}

int _pointKey(Map<String, dynamic> point) {
  final raw = point['id'];
  if (raw is int) return raw;
  final parsed = int.tryParse('$raw');
  if (parsed != null) return parsed;
  return identityHashCode(point);
}

String _title(Map<String, dynamic> point) {
  final title = point['title']?.toString().trim();
  if (title == null || title.isEmpty || title == 'null') return 'Punto';
  return title;
}

Color _linkColor(Map<String, dynamic> point) => switch (pointLinkOf(point)) {
  PointLink.connected => IkoluColors.connected,
  PointLink.gap => IkoluColors.warning,
  PointLink.incident => IkoluColors.incident,
};
