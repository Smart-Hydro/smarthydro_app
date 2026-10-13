import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../point_link.dart';

/// Ciudad de telemetría: loggers alineados al centro, con caudal / nivel /
/// totalizado a la vista y zoom libre para recorrer la arquitectura.
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
    duration: const Duration(seconds: 14),
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

  void _resetView() {
    _transform.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.points.take(12).toList(growable: false);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
              onPressed: _resetView,
              icon: const Icon(Icons.center_focus_strong_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          gaps + incidents == 0
              ? 'Pellizca o arrastra para explorar · toca un logger'
              : '$gaps advertencias · $incidents incidencias · pellizca para explorar',
          style: const TextStyle(color: Color(0xFF91A8AA), fontSize: 11),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 380,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF122A30),
                    Color(0xFF0B1A1E),
                    Color(0xFF071114),
                  ],
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final city = _TelemetryCityLayout.plan(
                    count: nodes.length,
                    viewport: viewport,
                  );
                  return InteractiveViewer(
                    transformationController: _transform,
                    minScale: 0.65,
                    maxScale: 2.8,
                    boundaryMargin: const EdgeInsets.all(120),
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
                            painter: _TelemetryCityPainter(
                              points: nodes,
                              layout: city,
                              phase: _animation.value,
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
          ),
        ),
        if (extraCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '+$extraCount puntos en el listado',
              style: const TextStyle(color: Color(0xFF91A8AA), fontSize: 10),
            ),
          ),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _NetworkLegend(color: Color(0xFF66E0C2), label: 'Conectado'),
            _NetworkLegend(color: Color(0xFFFFC46B), label: 'Advertencia'),
            _NetworkLegend(color: Color(0xFFFF847A), label: 'Incidencia'),
          ],
        ),
      ],
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

/// Rejilla centrada: filas equilibradas y columnas alineadas al eje medio.
class _TelemetryCityLayout {
  const _TelemetryCityLayout({
    required this.canvas,
    required this.nodes,
    required this.columns,
    required this.rows,
  });

  final Size canvas;
  final List<Offset> nodes;
  final int columns;
  final int rows;

  static const double cellWidth = 118;
  static const double cellHeight = 108;
  static const double padX = 48;
  static const double padY = 56;

  static _TelemetryCityLayout plan({
    required int count,
    required Size viewport,
  }) {
    final n = math.max(count, 1);
    final columns = n <= 1
        ? 1
        : n <= 4
        ? 2
        : n <= 9
        ? 3
        : 4;
    final rows = (n / columns).ceil();
    final contentW = columns * cellWidth;
    final contentH = rows * cellHeight;
    final canvas = Size(
      math.max(viewport.width, contentW + padX * 2),
      math.max(viewport.height, contentH + padY * 2),
    );
    final originX = (canvas.width - contentW) / 2;
    final originY = (canvas.height - contentH) / 2 + 8;

    final nodes = <Offset>[];
    for (var index = 0; index < count; index++) {
      final col = index % columns;
      final row = index ~/ columns;
      final itemsInRow = index ~/ columns == rows - 1
          ? (count - (rows - 1) * columns)
          : columns;
      // Última fila incompleta: centrar el bloque restante.
      final rowOffset = itemsInRow < columns
          ? (columns - itemsInRow) * cellWidth / 2
          : 0.0;
      nodes.add(
        Offset(
          originX + rowOffset + col * cellWidth + cellWidth / 2,
          originY + row * cellHeight + cellHeight / 2,
        ),
      );
    }
    return _TelemetryCityLayout(
      canvas: canvas,
      nodes: nodes,
      columns: columns,
      rows: rows,
    );
  }

  int? hitTest(Offset position) {
    for (var index = 0; index < nodes.length; index++) {
      final center = nodes[index];
      final hit = Rect.fromCenter(center: center, width: 104, height: 92);
      if (hit.contains(position)) return index;
    }
    return null;
  }
}

class _TelemetryCityPainter extends CustomPainter {
  const _TelemetryCityPainter({
    required this.points,
    required this.layout,
    required this.phase,
  });

  final List<Map<String, dynamic>> points;
  final _TelemetryCityLayout layout;
  final double phase;

  static const _mint = Color(0xFF66E0C2);
  static const _amber = Color(0xFFFFC46B);
  static const _coral = Color(0xFFFF847A);
  static const _fog = Color(0xFFE8F2F1);

  @override
  void paint(Canvas canvas, Size size) {
    _paintWaterFloor(canvas, size);
    _paintGridLines(canvas);
    for (var index = 0; index < points.length; index++) {
      _paintLogger(canvas, layout.nodes[index], points[index], index);
    }
  }

  void _paintWaterFloor(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16343A), Color(0xFF0E2429), Color(0xFF071316)],
        ).createShader(bounds),
    );

    // Lámina de agua baja, sin óvalos: crestas suaves y caústicas lineales.
    final travel = phase * math.pi * 2;
    final waterTop = size.height * 0.52;
    final body = Path()..moveTo(0, waterTop);
    for (var x = 0.0; x <= size.width; x += 6) {
      final along = x / math.max(size.width, 1);
      final y =
          waterTop +
          math.sin(along * math.pi * 2 + travel) * 6 +
          math.sin(along * math.pi * 4 - travel * 1.5) * 2.4;
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
            const Color(0xFF2A8F8F).withValues(alpha: 0.42),
            const Color(0xFF1C6E74).withValues(alpha: 0.62),
            const Color(0xFF0A242C).withValues(alpha: 0.92),
          ],
        ).createShader(Rect.fromLTWH(0, waterTop, size.width, size.height)),
    );

    // Segunda lámina más clara bajo la cresta.
    final skin = Path()..moveTo(0, waterTop);
    for (var x = 0.0; x <= size.width; x += 6) {
      final along = x / math.max(size.width, 1);
      final y =
          waterTop +
          math.sin(along * math.pi * 2 + travel) * 6 +
          math.sin(along * math.pi * 4 - travel * 1.5) * 2.4;
      skin.lineTo(x, y);
    }
    for (var x = size.width; x >= 0; x -= 6) {
      final along = x / math.max(size.width, 1);
      final y =
          waterTop +
          22 +
          math.sin(along * math.pi * 3 - travel * 2) * 3 +
          math.sin(along * math.pi * 2 + travel) * 6;
      skin.lineTo(x, y);
    }
    skin.close();
    canvas.drawPath(
      skin,
      Paint()..color = const Color(0xFF66E0C2).withValues(alpha: 0.08),
    );

    final crest = Path();
    for (var x = 0.0; x <= size.width; x += 5) {
      final along = x / math.max(size.width, 1);
      final y =
          waterTop +
          math.sin(along * math.pi * 2 + travel) * 6 +
          math.sin(along * math.pi * 4 - travel * 1.5) * 2.4;
      x == 0 ? crest.moveTo(x, y) : crest.lineTo(x, y);
    }
    canvas.drawPath(
      crest,
      Paint()
        ..color = const Color(0xFFD8FFF4).withValues(alpha: 0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );

    // Destellos lineales bajo la superficie (sin óvalos).
    for (var i = 0; i < 6; i++) {
      final seed = (i * 0.6180339) % 1;
      final t = (phase + seed) % 1;
      final fade = math.sin(t * math.pi);
      final y = waterTop + 18 + (size.height - waterTop - 28) * seed;
      canvas.drawLine(
        Offset(size.width * t - 20, y),
        Offset(size.width * t + 18, y),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.08 * fade)
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintGridLines(Canvas canvas) {
    if (layout.nodes.length < 2) return;
    final paint = Paint()
      ..color = _mint.withValues(alpha: 0.32)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    // Conectar filas (calles horizontales) y columnas (avenidas).
    final byRow = <int, List<int>>{};
    for (var i = 0; i < layout.nodes.length; i++) {
      final row = i ~/ layout.columns;
      byRow.putIfAbsent(row, () => []).add(i);
    }
    for (final row in byRow.values) {
      for (var i = 0; i < row.length - 1; i++) {
        canvas.drawLine(layout.nodes[row[i]], layout.nodes[row[i + 1]], paint);
      }
    }
    for (var col = 0; col < layout.columns; col++) {
      final vertical = <int>[];
      for (var i = col; i < layout.nodes.length; i += layout.columns) {
        vertical.add(i);
      }
      for (var i = 0; i < vertical.length - 1; i++) {
        canvas.drawLine(
          layout.nodes[vertical[i]],
          layout.nodes[vertical[i + 1]],
          paint,
        );
      }
    }

    // Pulso suave sobre las aristas principales.
    final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
    final glow = Paint()
      ..color = _mint.withValues(alpha: 0.08 + pulse * 0.1)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    if (layout.nodes.length >= 2) {
      canvas.drawLine(layout.nodes.first, layout.nodes[1], glow);
    }
  }

  void _paintLogger(
    Canvas canvas,
    Offset center,
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
    final title = point['title']?.toString() ?? 'Logger';
    final short = title.length > 14 ? '${title.substring(0, 13)}…' : title;

    // Placa del logger (bloque urbano, no óvalo).
    final plate = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 96, height: 78),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      plate,
      Paint()..color = const Color(0xFF0A171B).withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      plate,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    // Faro de estado (cuadrado suave, no óvalo flotante).
    final lamp = RRect.fromRectAndRadius(
      Rect.fromLTWH(center.dx - 42, center.dy - 33, 8, 8),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(lamp, Paint()..color = color);
    if (link == PointLink.connected) {
      final breath = (math.sin(phase * math.pi * 2 + index) + 1) / 2;
      canvas.drawRRect(
        lamp.inflate(2 + breath),
        Paint()
          ..color = color.withValues(alpha: 0.18 * (1 - breath))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    _drawText(
      canvas,
      short,
      Offset(center.dx - 30, center.dy - 34),
      const TextStyle(color: _fog, fontSize: 10, fontWeight: FontWeight.w800),
      maxWidth: 68,
    );

    // Tres lecturas rápidas: caudal · nivel · totalizado.
    _drawMetricRow(
      canvas,
      Offset(center.dx - 40, center.dy - 12),
      'Q',
      flow == null ? '—' : _compact(flow),
      'L/s',
      _mint,
    );
    _drawMetricRow(
      canvas,
      Offset(center.dx - 40, center.dy + 6),
      'N',
      level == null ? '—' : _compact(level),
      'm',
      const Color(0xFFB39DDB),
    );
    _drawMetricRow(
      canvas,
      Offset(center.dx - 40, center.dy + 24),
      'Σ',
      total == null ? '—' : _compact(total),
      'm³',
      const Color(0xFF69B9FF),
    );

    // Flujo vivo: trazo descendente lineal (sin gotas óvalo).
    if (link == PointLink.connected && flow != null && flow > 0.01) {
      final travel = (phase + index * 0.13) % 1;
      final fade = math.sin(travel * math.pi);
      final y0 = center.dy + 42;
      final y1 = y0 + 10 + travel * 16;
      canvas.drawLine(
        Offset(center.dx, y0),
        Offset(center.dx, y1),
        Paint()
          ..color = _mint.withValues(alpha: 0.35 * fade)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawMetricRow(
    Canvas canvas,
    Offset origin,
    String key,
    String value,
    String unit,
    Color accent,
  ) {
    _drawText(
      canvas,
      key,
      origin,
      TextStyle(
        color: accent.withValues(alpha: 0.9),
        fontSize: 9,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: 12,
    );
    _drawText(
      canvas,
      value,
      origin.translate(14, -1),
      const TextStyle(
        color: Color(0xFFF4FBF8),
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
      maxWidth: 42,
    );
    _drawText(
      canvas,
      unit,
      origin.translate(56, 0),
      TextStyle(
        color: accent.withValues(alpha: 0.75),
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: 24,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
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
    if (value.abs() >= 1000) return value.toStringAsFixed(0);
    if (value.abs() >= 100) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(covariant _TelemetryCityPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.points != points ||
      oldDelegate.layout != layout;
}
