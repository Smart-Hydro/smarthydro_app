import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../point_link.dart';

/// Placa del logger, la misma del esquema del inicio.
///
/// [tapKey] distingue el nodo del esquema (`capture-node`).
/// En el mapa de ubicaciones va solo el dibujo, [CaptureLoggerMark].
class CaptureLoggerPlate extends StatelessWidget {
  const CaptureLoggerPlate({
    required this.point,
    required this.selected,
    required this.onTap,
    this.clock,
    this.tapKey,
    super.key,
  });

  final Map<String, dynamic> point;
  final bool selected;
  final VoidCallback? onTap;
  final ValueNotifier<double>? clock;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final color = _linkColor(point);
    final surface = _isSurface(point);
    final link = pointLinkOf(point);
    final kind = surface ? 'superficial' : 'pozo';
    final title = _title(point);

    // El reloj solo repinta el borde y la antena: el nombre, su medida y el
    // fondo se arman una vez y no por frame.
    final plate = CustomPaint(
      foregroundPainter: _PlateEdgePainter(
        color: color,
        selected: selected,
        clock: clock,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF7FBFA).withValues(alpha: 0.20),
              const Color(0xFF1A343C).withValues(alpha: 0.78),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(3, 2, 4, 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const beaconW = captureLoggerBeaconRow;
              final inner = math.max(8.0, constraints.maxWidth - beaconW - 3);
              final textRoom = math.max(8.0, constraints.maxHeight);
              final fit = captureLoggerNameFit(
                title,
                inner,
                maxHeight: textRoom,
                maxLines: 2,
              );
              return Row(
                children: [
                  SizedBox(
                    width: beaconW,
                    height: constraints.maxHeight,
                    child: CustomPaint(
                      painter: _BeaconPainter(
                        color: color,
                        selected: selected,
                        surface: surface,
                        antenna: captureLoggerAntennaGlow(
                          0,
                          motion: false,
                          link: link,
                        ),
                        link: link,
                        clock: clock,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: fit.maxLines,
                      overflow: fit.ellipsis
                          ? TextOverflow.ellipsis
                          : TextOverflow.clip,
                      softWrap: true,
                      textAlign: TextAlign.center,
                      style: captureLoggerNameStyle.copyWith(
                        fontSize: fit.fontSize,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      container: true,
      label: '${_title(point)}, $kind, ${pointLinkLabel(link)}',
      child: GestureDetector(
        key: tapKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: clock == null ? plate : RepaintBoundary(child: plate),
      ),
    );
  }
}

/// Borde de la placa. Late con el reloj del esquema; sin reloj queda fijo.
class _PlateEdgePainter extends CustomPainter {
  _PlateEdgePainter({required this.color, required this.selected, this.clock})
    : super(repaint: clock);

  final Color color;
  final bool selected;
  final ValueNotifier<double>? clock;

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = clock?.value;
    final glow = seconds == null ? 0.45 : 0.5 + 0.5 * math.sin(seconds * 1.7);
    final edge = selected ? 0.78 + 0.18 * glow : 0.22 + 0.28 * glow;
    final width = selected ? 1.6 : 1.0;
    final rect = (Offset.zero & size).deflate(width / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(8 - width / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color.withValues(alpha: edge.clamp(0.0, 1.0).toDouble()),
    );
  }

  @override
  bool shouldRepaint(covariant _PlateEdgePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.clock != clock;
}

/// Misma medida que la placa del esquema.
const captureLoggerPlateWidth = 80.0;
const captureLoggerPlateHeight = 32.0;

/// Dibujo del logger, sin marco. Es la marca del punto en el mapa.
const captureLoggerMarkSize = 28.0;

/// Altura de la luz de la antena desde el borde superior del dibujo.
const captureLoggerAntennaTipY = 3.2;

/// El mismo logger de la placa, solo el dibujo. La ficha lo usa igual.
class CaptureLoggerGlyph extends StatelessWidget {
  const CaptureLoggerGlyph({
    required this.color,
    required this.surface,
    required this.link,
    this.selected = false,
    this.antenna = 0.85,
    super.key,
  });

  final Color color;
  final bool surface;
  final PointLink link;
  final bool selected;
  final double antenna;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BeaconPainter(
        color: color,
        selected: selected,
        surface: surface,
        antenna: antenna,
        link: link,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class CaptureLoggerMark extends StatelessWidget {
  const CaptureLoggerMark({
    required this.point,
    required this.selected,
    required this.onTap,
    this.tapKey,
    super.key,
  });

  final Map<String, dynamic> point;
  final bool selected;
  final VoidCallback? onTap;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final color = _linkColor(point);
    final surface = _isSurface(point);
    final kind = surface ? 'superficial' : 'pozo';
    return Semantics(
      button: true,
      selected: selected,
      label: '${_title(point)}, $kind, ${pointLinkLabel(pointLinkOf(point))}',
      child: GestureDetector(
        key: tapKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: _BeaconPainter(
            color: color,
            selected: selected,
            surface: surface,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

const captureLoggerNameStyle = TextStyle(
  color: Color(0xFFF4F8F6),
  fontSize: 11.5,
  fontWeight: FontWeight.w600,
  height: 1.05,
);

/// Ancho de la antena dentro de la placa compacta. El nombre va al lado.
const captureLoggerBeaconRow = 14.0;

/// Brillo de la pelotita de la antena.
/// Solo el conectado late. Gap e incidencia quedan marcados y quietos.
double captureLoggerAntennaGlow(
  double seconds, {
  required bool motion,
  PointLink link = PointLink.gap,
}) {
  if (link == PointLink.connected) {
    if (!motion) return 0.85;
    final wave = 0.5 + 0.5 * math.sin(seconds * math.pi * 2 / 1.5);
    return 0.25 + 0.75 * wave;
  }
  if (link == PointLink.incident) return 1;
  return 0.62;
}

/// Cómo entra el nombre en el ancho (y alto) libre de su lugar.
/// Baja el cuerpo y parte líneas antes de recortar.
({double fontSize, int maxLines, double textHeight, bool ellipsis})
captureLoggerNameFit(
  String title,
  double maxWidth, {
  double maxHeight = 28,
  int maxLines = 2,
}) {
  final text = title.trim().isEmpty ? 'Punto' : title.trim();
  final width = math.max(8.0, maxWidth);
  final lineCap = maxLines.clamp(1, 2);
  const sizes = [11.5, 10.5, 9.5, 9.0, 8.5];
  final lineCounts = [for (var lines = 1; lines <= lineCap; lines++) lines];
  for (final size in sizes) {
    for (final lines in lineCounts) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: _nameStyle(size)),
        maxLines: lines,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      final fits =
          !painter.didExceedMaxLines &&
          painter.width <= width + 0.5 &&
          painter.height <= maxHeight + 0.5;
      final height = painter.height;
      painter.dispose();
      if (fits) {
        return (
          fontSize: size,
          maxLines: lines,
          textHeight: math.max(height, size),
          ellipsis: false,
        );
      }
    }
  }
  final fallbackLines = maxLines.clamp(1, 2);
  final fallback = TextPainter(
    text: TextSpan(text: text, style: _nameStyle(8.5)),
    maxLines: fallbackLines,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  final height = math.min(fallback.height, maxHeight);
  fallback.dispose();
  return (
    fontSize: 8.5,
    maxLines: fallbackLines,
    textHeight: height,
    ellipsis: true,
  );
}

TextStyle _nameStyle(double size) =>
    captureLoggerNameStyle.copyWith(fontSize: size, height: 1.05);

class _BeaconPainter extends CustomPainter {
  _BeaconPainter({
    required this.color,
    required this.selected,
    required this.surface,
    this.antenna = 0,
    this.link = PointLink.connected,
    this.clock,
  }) : super(repaint: clock);

  final Color color;
  final bool selected;
  final bool surface;
  final PointLink link;

  /// 0 apaga la pelotita. 1 la deja encendida. Con [clock] late solo.
  final double antenna;
  final ValueNotifier<double>? clock;

  static const _hole = Color(0xFF0B1418);
  static const _metal = Color(0xFFD5E4E2);
  static const _gap = Color(0xFFFF847A);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.45 : 1.15
      ..color = selected
          ? color.withValues(alpha: 0.92)
          : _metal.withValues(alpha: 0.82);
    final seconds = clock?.value;
    final level = seconds == null
        ? antenna
        : captureLoggerAntennaGlow(seconds, motion: true, link: link);
    final glow = level.clamp(0.0, 1.0).toDouble();
    final steady = link != PointLink.connected;
    final tipColor = link == PointLink.gap ? _gap : color;
    if (surface) {
      final side = math.min(size.width * 0.72, size.height * 0.52);
      final cell = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.66),
          width: side,
          height: side,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(cell, Paint()..color = _hole);
      canvas.drawRRect(cell, stroke);
      canvas.drawLine(
        Offset(cell.left + 2, cell.center.dy),
        Offset(cell.right - 2, cell.center.dy),
        stroke..strokeWidth = 1,
      );
      _antenna(
        canvas,
        Offset(size.width / 2, captureLoggerAntennaTipY),
        cell.top,
        tipColor,
        glow,
        steady,
      );
      return;
    }
    final mouth = Offset(size.width / 2, size.height * 0.68);
    final housing = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: mouth,
        width: size.width * 0.78,
        height: size.height * 0.30,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(housing, Paint()..color = const Color(0xFF1A282E));
    canvas.drawRRect(housing, stroke);
    final tip = Offset(mouth.dx, captureLoggerAntennaTipY);
    _antenna(
      canvas,
      tip,
      mouth.dy - size.height * 0.14,
      tipColor,
      glow,
      steady,
    );
  }

  void _antenna(
    Canvas canvas,
    Offset tip,
    double mastEnd,
    Color tipColor,
    double glow,
    bool steady,
  ) {
    canvas.drawLine(
      Offset(tip.dx, mastEnd),
      tip,
      Paint()
        ..color = _metal
        ..strokeWidth = 1.15,
    );
    final radius = steady ? 2.05 : 1.7 + glow * 0.65;
    if (!steady && glow > 0.2) {
      canvas.drawCircle(
        tip,
        radius + 1.5,
        Paint()..color = tipColor.withValues(alpha: 0.16 * glow),
      );
    }
    canvas.drawCircle(
      tip,
      radius,
      Paint()
        ..color = tipColor.withValues(alpha: steady ? 0.95 : 0.3 + 0.7 * glow),
    );
  }

  @override
  bool shouldRepaint(covariant _BeaconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.surface != surface ||
      oldDelegate.link != link ||
      oldDelegate.antenna != antenna ||
      oldDelegate.clock != clock;
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

bool _isSurface(Map<String, dynamic> point) {
  final dga = point['dga'];
  if (dga is Map && '${dga['type_dga']}'.toUpperCase() == 'SUPERFICIAL') {
    return true;
  }
  return '${point['type_dga']}'.toUpperCase() == 'SUPERFICIAL';
}
