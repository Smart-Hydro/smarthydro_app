import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../point_link.dart';
import '../point_meta.dart';

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
    final compliance = _hasCompliance(point);
    final link = pointLinkOf(point);
    final kind = surface ? 'superficial' : 'pozo';
    final mark = compliance ? ', con cumplimiento' : '';

    Widget plate(double glow) {
      final edge = selected ? 0.78 + 0.18 * glow : 0.22 + 0.28 * glow;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: edge.clamp(0.0, 1.0).toDouble()),
            width: selected ? 1.6 : 1,
          ),
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
          padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CustomPaint(
                  painter: _BeaconPainter(
                    color: color,
                    selected: selected,
                    surface: surface,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _title(point),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: captureLoggerNameStyle,
                ),
              ),
              const SizedBox(width: 4),
              if (compliance) ...[
                Icon(
                  Icons.verified_outlined,
                  size: 12,
                  color: _complianceMarkColor(_complianceLevel(point)),
                ),
                const SizedBox(width: 3),
              ],
              _LinkLamp(
                color: color,
                live: clock != null && link == PointLink.connected,
                clock: clock,
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      container: true,
      label: '${_title(point)}, $kind, ${pointLinkLabel(link)}$mark',
      child: GestureDetector(
        key: tapKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: clock == null
            ? plate(0.45)
            : ValueListenableBuilder<double>(
                valueListenable: clock!,
                builder: (context, seconds, _) {
                  final glow = 0.5 + 0.5 * math.sin(seconds * 1.7);
                  return plate(glow);
                },
              ),
      ),
    );
  }
}

/// Misma medida que la placa del esquema.
const captureLoggerPlateWidth = 80.0;
const captureLoggerPlateHeight = 32.0;

/// Dibujo del logger, sin marco. Es la marca del punto en el mapa.
const captureLoggerMarkSize = 28.0;

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

class _LinkLamp extends StatelessWidget {
  const _LinkLamp({
    required this.color,
    required this.live,
    required this.clock,
  });

  final Color color;
  final bool live;
  final ValueNotifier<double>? clock;

  @override
  Widget build(BuildContext context) {
    if (!live || clock == null) return _dot(1);
    return ValueListenableBuilder<double>(
      valueListenable: clock!,
      builder: (context, seconds, _) {
        final wave = math.sin(seconds * 5);
        return _dot(0.25 + 0.75 * (0.5 + 0.5 * wave));
      },
    );
  }

  Widget _dot(double opacity) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55 * opacity),
            blurRadius: 3,
          ),
        ],
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

  static const _hole = Color(0xFF0B1418);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.45 : 1.15
      ..color = selected
          ? color.withValues(alpha: 0.92)
          : const Color(0xFFD5E4E2).withValues(alpha: 0.82);
    if (surface) {
      final side = math.min(size.width, size.height) * 0.62;
      final cell = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: size.center(Offset.zero),
          width: side,
          height: side,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(cell, Paint()..color = _hole);
      canvas.drawRRect(cell, stroke);
      canvas.drawLine(
        size.center(const Offset(-4, 0)),
        size.center(const Offset(4, 0)),
        stroke..strokeWidth = 1,
      );
      return;
    }
    final mouth = Offset(size.width / 2, size.height * 0.64);
    final housing = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: mouth,
        width: size.width * 0.78,
        height: size.height * 0.34,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(housing, Paint()..color = const Color(0xFF1A282E));
    canvas.drawRRect(housing, stroke);
    final tip = Offset(mouth.dx, size.height * 0.08);
    canvas.drawLine(
      Offset(mouth.dx, mouth.dy - size.height * 0.16),
      tip,
      Paint()
        ..color = const Color(0xFFD5E4E2)
        ..strokeWidth = 1.1,
    );
    canvas.drawCircle(tip, 1.7, Paint()..color = const Color(0xFFD5E4E2));
    canvas.drawCircle(
      mouth.translate(size.width * 0.18, 0),
      1.15,
      Paint()..color = const Color(0xFF9CC8C2),
    );
  }

  @override
  bool shouldRepaint(covariant _BeaconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.surface != surface;
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

bool _hasCompliance(Map<String, dynamic> point) {
  final nested = point['dga'];
  if (nested is Map) {
    final info = DgaInfo.tryParse(Map<String, dynamic>.from(nested));
    if (info != null) return true;
  }
  return DgaInfo.tryParse(point) != null;
}

String? _complianceLevel(Map<String, dynamic> point) {
  final raw = point['compliance_warning'];
  if (raw is! Map) return null;
  final level = raw['level']?.toString();
  if (level == null || level.isEmpty || level == 'null') return null;
  return level;
}

Color _complianceMarkColor(String? level) => switch (level) {
  'critical' => IkoluColors.incident,
  'warning' => IkoluColors.warning,
  'safe' => IkoluColors.connected,
  _ => const Color(0xFF9CC8C2),
};
