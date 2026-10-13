import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../point_link.dart';

/// Ciudad de telemetría: corte de terreno con pozos al estilo [CaptureStage].
/// Full ancho, sin cards; cada captación es un pozo con nivel, caudal y caída.
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
    duration: const Duration(seconds: 4),
  );
  final TransformationController _transform = TransformationController();

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
    _transform.dispose();
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
    final stageHeight = (MediaQuery.sizeOf(context).height * 0.62).clamp(
      420.0,
      720.0,
    );
    final textScaler = MediaQuery.textScalerOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
          child: Row(
            children: [
              const Text(
                'Ciudad de telemetría',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$connected en línea',
                style: const TextStyle(
                  color: Color(0xFF66E0C2),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Restablecer vista',
                visualDensity: VisualDensity.compact,
                onPressed: () => _transform.value = Matrix4.identity(),
                icon: const Icon(Icons.center_focus_strong_rounded, size: 20),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Text(
            gaps + incidents == 0
                ? 'Corte de pozos · pellizca para explorar · toca un logger'
                : '$gaps advertencias · $incidents incidencias · toca un pozo',
            style: const TextStyle(color: Color(0xFF91A8AA), fontSize: 11),
          ),
        ),
        SizedBox(
          height: stageHeight,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final city = _WellCityLayout.plan(
                count: nodes.length,
                viewport: viewport,
              );
              return InteractiveViewer(
                transformationController: _transform,
                minScale: 0.65,
                maxScale: 3.6,
                boundaryMargin: const EdgeInsets.all(200),
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: city.canvas.width,
                  height: city.canvas.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final index = city.hitTest(details.localPosition);
                      if (index != null) {
                        widget.onPointSelected(nodes[index]);
                      }
                    },
                    child: AnimatedBuilder(
                      animation: _animation,
                      builder: (context, _) => CustomPaint(
                        painter: _WellCityPainter(
                          points: nodes,
                          layout: city,
                          phase: _animation.value,
                          textScaler: textScaler,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (extraCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '+$extraCount puntos en el listado',
                    style: const TextStyle(
                      color: Color(0xFF91A8AA),
                      fontSize: 10,
                    ),
                  ),
                ),
              const Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _Legend(color: Color(0xFF66E0C2), label: 'Conectado'),
                  _Legend(color: Color(0xFFFFC46B), label: 'Advertencia'),
                  _Legend(color: Color(0xFFFF847A), label: 'Incidencia'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

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

class _WellCityLayout {
  const _WellCityLayout({
    required this.canvas,
    required this.wells,
    required this.groundY,
    required this.aquiferY,
  });

  final Size canvas;
  final List<_WellSlot> wells;
  final double groundY;
  final double aquiferY;

  static _WellCityLayout plan({required int count, required Size viewport}) {
    final n = math.max(count, 0);
    // Una sola fila centrada: skyline de pozos.
    final columns = math.max(n, 1);
    final boreWidth = (viewport.width / columns * 0.38).clamp(48.0, 92.0);
    final slotW = viewport.width / columns;
    final canvas = Size(viewport.width, viewport.height);
    final groundY = canvas.height * 0.14;
    final aquiferY = canvas.height * 0.86;
    final originX = 0.0;

    final wells = <_WellSlot>[];
    for (var index = 0; index < n; index++) {
      final cx = originX + index * slotW + slotW / 2;
      wells.add(
        _WellSlot(
          centerX: cx,
          top: groundY,
          bottom: aquiferY - 10,
          width: boreWidth,
        ),
      );
    }

    return _WellCityLayout(
      canvas: canvas,
      wells: wells,
      groundY: groundY,
      aquiferY: aquiferY,
    );
  }

  int? hitTest(Offset position) {
    for (var index = 0; index < wells.length; index++) {
      final well = wells[index];
      final hit = Rect.fromLTRB(
        well.centerX - well.width,
        well.top - 40,
        well.centerX + well.width,
        well.bottom + 12,
      );
      if (hit.contains(position)) return index;
    }
    return null;
  }
}

class _WellSlot {
  const _WellSlot({
    required this.centerX,
    required this.top,
    required this.bottom,
    required this.width,
  });

  final double centerX;
  final double top;
  final double bottom;
  final double width;

  Rect get bore =>
      Rect.fromLTRB(centerX - width / 2, top, centerX + width / 2, bottom);
}

class _WellCityPainter extends CustomPainter {
  const _WellCityPainter({
    required this.points,
    required this.layout,
    required this.phase,
    required this.textScaler,
  });

  final List<Map<String, dynamic>> points;
  final _WellCityLayout layout;
  final double phase;
  final TextScaler textScaler;

  static const _mint = Color(0xFF66E0C2);
  static const _amber = Color(0xFFFFC46B);
  static const _coral = Color(0xFFFF847A);

  @override
  void paint(Canvas canvas, Size size) {
    _paintTerrain(canvas, size);
    if (points.isEmpty) {
      _paintEmptyHint(canvas, size);
      return;
    }
    _paintPipeNetwork(canvas);
    for (var index = 0; index < points.length; index++) {
      _paintWell(canvas, size, layout.wells[index], points[index], index);
    }
    _paintAquifer(canvas, size);
    // Caídas por encima del acuífero para que se lean.
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final link = pointLinkOf(point);
      final flow = _number(_telemetry(point)['flow']);
      if (link == PointLink.connected && flow != null && flow > 0.01) {
        _paintFall(canvas, layout.wells[index].bore.deflate(8), index, flow);
      }
    }
  }

  void _paintEmptyHint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'Sin puntos asignados',
        style: TextStyle(
          color: Color(0xFF91A8AA),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset((size.width - painter.width) / 2, size.height * 0.45),
    );
  }

  void _paintTerrain(Canvas canvas, Size size) {
    final sky = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16343C), Color(0xFF0C1C21), Color(0xFF071114)],
        ).createShader(sky),
    );

    final groundY = layout.groundY;
    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
      Paint()
        ..shader =
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3A4C43), Color(0xFF1A2C2A), Color(0xFF0C1818)],
            ).createShader(
              Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
            ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, groundY - 8, size.width, 12),
      Paint()..color = const Color(0xFF6D7C74),
    );
  }

  void _paintAquifer(Canvas canvas, Size size) {
    final travel = phase * math.pi * 2;
    final top = layout.aquiferY;
    final body = Path()..moveTo(0, top);
    for (var x = 0.0; x <= size.width; x += 5) {
      final along = x / math.max(size.width, 1);
      final y =
          top +
          math.sin(along * math.pi * 2 + travel) * 4 +
          math.sin(along * math.pi * 4 - travel * 1.4) * 1.8;
      body.lineTo(x, y);
    }
    body
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF8EF0D8).withValues(alpha: 0.4),
            const Color(0xFF1B7C86).withValues(alpha: 0.78),
            const Color(0xFF0C3140),
          ],
        ).createShader(Rect.fromLTWH(0, top, size.width, size.height - top)),
    );
    final crest = Path();
    for (var x = 0.0; x <= size.width; x += 4) {
      final along = x / math.max(size.width, 1);
      final y =
          top +
          math.sin(along * math.pi * 2 + travel) * 4 +
          math.sin(along * math.pi * 4 - travel * 1.4) * 1.8;
      x == 0 ? crest.moveTo(x, y) : crest.lineTo(x, y);
    }
    canvas.drawPath(
      crest,
      Paint()
        ..color = const Color(0xFFEFFFFA).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintPipeNetwork(Canvas canvas) {
    if (layout.wells.length < 2) return;
    final y = layout.groundY - 1;
    canvas.drawLine(
      Offset(layout.wells.first.centerX, y),
      Offset(layout.wells.last.centerX, y),
      Paint()
        ..color = const Color(0xFFB7C6BE).withValues(alpha: 0.65)
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < 5; i++) {
      final t = (phase + i / 5) % 1;
      final fade = math.sin(t * math.pi);
      final x =
          layout.wells.first.centerX +
          (layout.wells.last.centerX - layout.wells.first.centerX) * t;
      canvas.drawLine(
        Offset(x - 7, y),
        Offset(x + 7, y),
        Paint()
          ..color = _mint.withValues(alpha: 0.2 + fade * 0.5)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintWell(
    Canvas canvas,
    Size size,
    _WellSlot slot,
    Map<String, dynamic> point,
    int index,
  ) {
    final link = pointLinkOf(point);
    final color = switch (link) {
      PointLink.connected => _mint,
      PointLink.gap => _amber,
      PointLink.incident => _coral,
    };
    final telemetry = _telemetry(point);
    final flow = _number(telemetry['flow']);
    final level = _number(telemetry['water_table'] ?? telemetry['nivel']);
    final total = _number(
      telemetry['total'] ?? telemetry['total_raw'] ?? telemetry['consumption'],
    );
    final isSurface = _isSurface(point);
    final fill = _levelFill(level);

    final bore = slot.bore;
    // Camisa (CaptureStage).
    canvas.drawRRect(
      RRect.fromRectAndRadius(bore, const Radius.circular(14)),
      Paint()..color = const Color(0xFFD5E4DC),
    );
    // Boca rectangular.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bore.center.dx, bore.top + 2),
          width: bore.width + 16,
          height: 13,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFB7C6BE),
    );
    // Faro estado.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bore.center.dx, bore.top - 12),
          width: 11,
          height: 11,
        ),
        const Radius.circular(2.5),
      ),
      Paint()..color = color,
    );

    final shaft = bore.deflate(9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shaft, const Radius.circular(10)),
      Paint()..color = const Color(0xFF071114),
    );

    // Escala lateral como CaptureStage.
    final tick = Paint()
      ..color = const Color(0xFF0C1C21).withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var i = 0; i <= 8; i++) {
      final y = shaft.top + shaft.height * i / 8;
      canvas.drawLine(
        Offset(shaft.left - 1, y),
        Offset(shaft.left - (i % 4 == 0 ? 8 : 5), y),
        tick,
      );
    }

    if (isSurface) {
      _paintSurfaceIntake(canvas, bore, shaft, fill, color);
    } else {
      _paintWellWater(canvas, shaft, fill, index);
    }

    // Identidad + lecturas pegadas al cabezal (no cards laterales).
    final title = point['title']?.toString() ?? 'Logger';
    final short = title.length > 11 ? '${title.substring(0, 10)}…' : title;
    final q = flow == null ? '—' : _compact(flow);
    final n = level == null ? '—' : _compact(level);
    final s = total == null ? '—' : _compact(total);
    _headLabel(
      canvas,
      size,
      Offset(bore.center.dx, bore.top - 34),
      short,
      'Q $q  ·  N $n  ·  Σ $s',
      color,
    );
  }

  void _paintWellWater(Canvas canvas, Rect shaft, double fill, int index) {
    final waterTop = shaft.bottom - shaft.height * fill;
    final water = Rect.fromLTRB(
      shaft.left + 3,
      waterTop,
      shaft.right - 3,
      shaft.bottom - 3,
    );
    if (water.height <= 2) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(water, const Radius.circular(7)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8EF0D8), Color(0xFF1B7C86), Color(0xFF0C3140)],
        ).createShader(water),
    );

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(water, const Radius.circular(7)));
    canvas.drawRect(
      Rect.fromLTWH(
        water.left + water.width * 0.18,
        water.top,
        5,
        water.height,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(water),
    );
    for (var i = 0; i < 4; i++) {
      final seed = (i * 0.37 + index * 0.13) % 1;
      final progress = (phase + seed) % 1;
      final bx = water.left + water.width * (0.22 + 0.55 * seed);
      final by = water.bottom - water.height * progress;
      final fade = math.sin(progress * math.pi);
      canvas.drawLine(
        Offset(bx, by + 6),
        Offset(bx, by - 4),
        Paint()
          ..color = const Color(0xFFDFFFF6).withValues(alpha: 0.32 * fade)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();

    final wave = Path()..moveTo(water.left, water.top + 2);
    for (var x = water.left; x <= water.right; x += 3) {
      final y =
          water.top + math.sin((x / 11) + phase * math.pi * 2 + index) * 1.5;
      wave.lineTo(x, y);
    }
    canvas.drawPath(
      wave,
      Paint()
        ..color = const Color(0xFFEFFFFA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Línea de nivel.
    canvas.drawLine(
      Offset(shaft.left, waterTop),
      Offset(shaft.right + 6, waterTop),
      Paint()
        ..color = const Color(0xFFEFFFFA).withValues(alpha: 0.85)
        ..strokeWidth = 1.2,
    );
  }

  void _paintSurfaceIntake(
    Canvas canvas,
    Rect bore,
    Rect shaft,
    double fill,
    Color color,
  ) {
    final bankY = shaft.top + shaft.height * (0.32 - fill * 0.06);
    final water = Rect.fromLTRB(
      shaft.left + 2,
      bankY,
      shaft.right - 2,
      shaft.bottom - 2,
    );
    canvas.drawRect(
      Rect.fromLTRB(shaft.left, shaft.top, shaft.right, bankY),
      Paint()..color = const Color(0xFF24362F),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(water, const Radius.circular(6)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7EE8D0), Color(0xFF14616C), Color(0xFF0A2832)],
        ).createShader(water),
    );
    canvas.drawLine(
      Offset(bore.center.dx, bore.top - 2),
      Offset(bore.center.dx, bankY),
      Paint()
        ..color = const Color(0xFFE8F2F1)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bore.center.dx, bankY),
          width: 9,
          height: 9,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
  }

  void _paintFall(Canvas canvas, Rect shaft, int index, double flow) {
    final strength = (flow / 18).clamp(0.4, 1.0);
    final count = 4 + (strength * 3).round();
    final startY = shaft.bottom;
    final endY = layout.aquiferY + 8;
    // Columna de descarga.
    canvas.drawLine(
      Offset(shaft.center.dx, startY),
      Offset(shaft.center.dx, endY),
      Paint()
        ..color = _mint.withValues(alpha: 0.16 + strength * 0.14)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < count; i++) {
      final travel =
          (phase * (1.2 + strength * 0.5) + i / count + index * 0.08) % 1;
      final fade = math.sin(travel * math.pi);
      if (fade < 0.08) continue;
      final x =
          shaft.center.dx +
          (i - count / 2) * 3.4 +
          math.sin((travel + i) * math.pi * 2) * 1.4;
      final y = startY + (endY - startY) * travel;
      canvas.drawLine(
        Offset(x, y - 7),
        Offset(x, y + 8),
        Paint()
          ..color = const Color(0xFFBFF7EA).withValues(alpha: 0.22 + fade * 0.6)
          ..strokeWidth = 1.6 + strength * 0.7
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _headLabel(
    Canvas canvas,
    Size size,
    Offset center,
    String title,
    String metrics,
    Color accent,
  ) {
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Color(0xFFF4FBF8),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: 120);
    final metricsPainter = TextPainter(
      text: TextSpan(
        text: metrics,
        style: TextStyle(
          color: accent.withValues(alpha: 0.95),
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: 140);

    final w = math.max(titlePainter.width, metricsPainter.width) + 12;
    final h = titlePainter.height + metricsPainter.height + 8;
    final left = (center.dx - w / 2)
        .clamp(2.0, math.max(2.0, size.width - w - 2))
        .toDouble();
    final top = (center.dy - h / 2)
        .clamp(2.0, math.max(2.0, size.height - h - 2))
        .toDouble();
    // Fondo mínimo, sin “card” pesada.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, h),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF071114).withValues(alpha: 0.72),
    );
    titlePainter.paint(
      canvas,
      Offset(left + (w - titlePainter.width) / 2, top + 3),
    );
    metricsPainter.paint(
      canvas,
      Offset(
        left + (w - metricsPainter.width) / 2,
        top + 3 + titlePainter.height + 1,
      ),
    );
  }

  static Map<String, dynamic> _telemetry(Map<String, dynamic> point) {
    final value = point['latest_telemetry'];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
    return const {};
  }

  static bool _isSurface(Map<String, dynamic> point) {
    final dga = point['dga'];
    if (dga is Map) {
      final type = dga['type_dga']?.toString().toUpperCase();
      if (type == 'SUPERFICIAL') return true;
    }
    return point['type_dga']?.toString().toUpperCase() == 'SUPERFICIAL';
  }

  static double? _number(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static String _compact(double value) {
    if (value.abs() >= 1000) return value.toStringAsFixed(0);
    if (value.abs() >= 100) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  double _levelFill(double? level) {
    if (level == null) return 0.28;
    final levels = points
        .map((p) {
          final t = _telemetry(p);
          return _number(t['water_table'] ?? t['nivel']);
        })
        .whereType<double>()
        .toList();
    if (levels.isEmpty) return 0.48;
    final min = levels.reduce(math.min);
    final max = levels.reduce(math.max);
    if ((max - min).abs() < 0.0001) return 0.5;
    return 0.28 + ((level - min) / (max - min)).clamp(0, 1) * 0.52;
  }

  @override
  bool shouldRepaint(covariant _WellCityPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.points != points ||
      oldDelegate.layout != layout ||
      oldDelegate.textScaler != textScaler;
}
