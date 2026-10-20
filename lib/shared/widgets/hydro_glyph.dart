import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/brand.dart';

/// Glifo hidráulico animado. Mismo orden que los atajos de [liquidDesktopApps].
enum HydroGlyphKind {
  analisis,
  cumplimiento,
  asistente,
  soporte,
  registros,
  informes,
}

/// Índice alineado con [liquidDesktopApps] y las cards del hub.
HydroGlyphKind hydroGlyphKindAt(int index) =>
    HydroGlyphKind.values[index.clamp(0, HydroGlyphKind.values.length - 1)];

/// Icono de agua con movimiento continuo. Lo usan el hub Apps y el rail.
class HydroGlyph extends StatefulWidget {
  const HydroGlyph({
    required this.kind,
    required this.color,
    this.size = 64,
    this.keyPrefix = 'hydro-glyph',
    super.key,
  });

  final HydroGlyphKind kind;
  final Color color;
  final double size;

  /// Prefijo de la clave. El hub usa hydro-glyph; el rail, rail-glyph.
  final String keyPrefix;

  @override
  State<HydroGlyph> createState() => _HydroGlyphState();
}

/// El reloj no reconstruye el widget: solo repinta el [RepaintBoundary] del
/// glifo. Hay ~15 a la vez (rail, Apps, N1) y el movimiento es lento, así que
/// ~30 fps basta.
class _HydroGlyphState extends State<HydroGlyph>
    with SingleTickerProviderStateMixin {
  static const _frame = 1 / 30;

  Ticker? _ticker;

  /// Segundos acumulados (nunca vuelve a 0) → líquido continuo.
  final _seconds = ValueNotifier<double>(0);
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce == _reduce && _ticker != null) return;
    _reduce = reduce;
    _ticker?.dispose();
    _ticker = null;
    if (reduce) {
      _seconds.value = 1.2;
      return;
    }
    _ticker = createTicker((elapsed) {
      final next = elapsed.inMicroseconds / 1e6;
      if (next - _seconds.value < _frame) return;
      _seconds.value = next;
    })..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyName = '${widget.keyPrefix}-${widget.kind.name}';
    return SizedBox(
      key: ValueKey(keyName),
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: HydroGlyphPainter(
            kind: widget.kind,
            color: widget.color,
            clock: _seconds,
          ),
        ),
      ),
    );
  }
}

class HydroGlyphPainter extends CustomPainter {
  HydroGlyphPainter({
    required this.kind,
    required this.color,
    required this.clock,
  }) : super(repaint: clock);

  final HydroGlyphKind kind;
  final Color color;

  /// Tiempo continuo en segundos (sin wrap 0→1).
  final ValueListenable<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = clock.value;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    // Velocidades suaves distintas; sin periodo que “cierre” de golpe.
    final turn = seconds * 0.55;
    final drift = seconds * 0.38;

    // Borde orgánico tipo gota/agua, flujo continuo.
    final blob = _waterBlobPath(c, r * 0.86, turn, drift);

    // Halo con gradiente: un MaskFilter.blur por glifo y por frame pesa
    // demasiado en web y Android.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r,
          [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0),
          ],
          const [0, 0.78, 1],
        ),
    );

    final fill = Paint()
      ..shader = ui.Gradient.radial(
        Offset(c.dx - r * 0.2, c.dy - r * 0.25),
        r * 1.35,
        [
          Color.lerp(color, Colors.white, 0.32)!,
          color,
          Color.lerp(color, IkoluColors.navy, 0.2)!,
        ],
        const [0, 0.55, 1],
      );
    canvas.drawPath(blob, fill);

    // Ribete agua: trazo claro ondulado sobre el borde.
    canvas.drawPath(
      blob,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, r * 0.07)
        ..color = Colors.white.withValues(alpha: 0.38),
    );

    // Nivel interno continuo.
    final levelY = c.dy + r * (0.14 - 0.07 * math.sin(turn));
    final water = Path()
      ..moveTo(c.dx - r * 0.7, levelY)
      ..cubicTo(
        c.dx - r * 0.25,
        levelY - r * 0.12 * math.cos(turn),
        c.dx + r * 0.15,
        levelY + r * 0.12 * math.sin(turn),
        c.dx + r * 0.7,
        levelY - r * 0.03,
      )
      ..lineTo(c.dx + r * 0.7, c.dy + r * 0.7)
      ..lineTo(c.dx - r * 0.7, c.dy + r * 0.7)
      ..close();
    canvas.save();
    canvas.clipPath(blob);
    canvas.drawPath(
      water,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    canvas.restore();

    const glyph = Color(0xFFF4FFFC);
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.35, r * 0.09)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = glyph.withValues(alpha: 0.94);

    final fillInk = Paint()..color = glyph.withValues(alpha: 0.96);

    switch (kind) {
      case HydroGlyphKind.analisis:
        _paintWaveBars(canvas, c, r, ink, turn);
      case HydroGlyphKind.cumplimiento:
        _paintGauge(canvas, c, r, ink, fillInk, turn);
      case HydroGlyphKind.asistente:
        _paintPulseNode(canvas, c, r, ink, fillInk, turn);
      case HydroGlyphKind.soporte:
        _paintLifeline(canvas, c, r, ink, turn);
      case HydroGlyphKind.registros:
        _paintLayers(canvas, c, r, ink, turn);
      case HydroGlyphKind.informes:
        _paintSheetWave(canvas, c, r, ink, turn);
    }
  }

  Path _waterBlobPath(Offset c, double radius, double turn, double drift) {
    const steps = 48;
    final path = Path();
    Offset? first;
    Offset? prev;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final ang = t * math.pi * 2;
      // Armónicos lentos: flujo continuo, sin pop.
      final wobble =
          1 +
          0.055 * math.sin(ang * 2 + turn) +
          0.035 * math.cos(ang * 3 - drift) +
          0.02 * math.sin(ang + turn * 0.7);
      final p = Offset(
        c.dx + math.cos(ang) * radius * wobble,
        c.dy + math.sin(ang) * radius * wobble,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
        first = p;
        prev = p;
      } else {
        final mid = Offset((prev!.dx + p.dx) / 2, (prev.dy + p.dy) / 2);
        path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
        prev = p;
      }
    }
    if (first != null && prev != null) {
      path.quadraticBezierTo(prev.dx, prev.dy, first.dx, first.dy);
    }
    path.close();
    return path;
  }

  void _paintWaveBars(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    double turn,
  ) {
    final xs = [-0.34, -0.12, 0.12, 0.34];
    final hs = [0.22, 0.42, 0.3, 0.48];
    for (var i = 0; i < xs.length; i++) {
      final h = r * (hs[i] + 0.07 * math.sin(turn + i * 0.9));
      final x = c.dx + r * xs[i];
      canvas.drawLine(
        Offset(x, c.dy + r * 0.32),
        Offset(x, c.dy + r * 0.32 - h),
        ink,
      );
    }
    final wave = Path()
      ..moveTo(c.dx - r * 0.42, c.dy - r * 0.18)
      ..cubicTo(
        c.dx - r * 0.1,
        c.dy - r * (0.32 + 0.06 * math.sin(turn)),
        c.dx + r * 0.1,
        c.dy - r * (0.02 - 0.06 * math.cos(turn)),
        c.dx + r * 0.42,
        c.dy - r * 0.2,
      );
    canvas.drawPath(wave, ink);
  }

  void _paintGauge(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    Paint fill,
    double turn,
  ) {
    final rect = Rect.fromCircle(center: c, radius: r * 0.42);
    canvas.drawArc(rect, math.pi * 0.85, math.pi * 1.3, false, ink);
    // Aguja oscila suave (sin salto): 0.35±0.18
    final needle = 0.35 + 0.18 * math.sin(turn);
    final ang = math.pi * (0.85 + 1.3 * needle);
    canvas.drawLine(
      c,
      Offset(c.dx + math.cos(ang) * r * 0.32, c.dy + math.sin(ang) * r * 0.32),
      ink,
    );
    canvas.drawCircle(c, r * 0.07, fill);
  }

  void _paintPulseNode(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    Paint fill,
    double turn,
  ) {
    // Respiración continua (radio sin reinicio).
    final breath = 0.16 + 0.03 * math.sin(turn);
    canvas.drawCircle(
      c,
      r * (breath + 0.18),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(
          0xFFF4FFFC,
        ).withValues(alpha: 0.28 + 0.12 * math.cos(turn)),
    );
    canvas.drawCircle(c, r * breath, fill);
    final sat = Offset(
      c.dx + math.cos(turn) * r * 0.28,
      c.dy + math.sin(turn) * r * 0.18 - r * 0.05,
    );
    canvas.drawCircle(sat, r * 0.08, fill);
    canvas.drawLine(c, sat, ink);
  }

  void _paintLifeline(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    double turn,
  ) {
    final k = 0.06 * math.sin(turn);
    final path = Path()
      ..moveTo(c.dx - r * 0.42, c.dy + r * 0.06)
      ..lineTo(c.dx - r * 0.18, c.dy + r * 0.06)
      ..lineTo(c.dx - r * 0.06, c.dy - r * (0.28 + k))
      ..lineTo(c.dx + r * 0.08, c.dy + r * (0.3 - k))
      ..lineTo(c.dx + r * 0.2, c.dy - r * 0.08)
      ..lineTo(c.dx + r * 0.42, c.dy - r * 0.08);
    canvas.drawPath(path, ink);
  }

  void _paintLayers(Canvas canvas, Offset c, double r, Paint ink, double turn) {
    for (var i = 0; i < 3; i++) {
      final y = c.dy - r * 0.22 + i * r * 0.22 + r * 0.02 * math.sin(turn + i);
      final w = r * (0.5 - i * 0.04);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(c.dx, y),
            width: w * 2,
            height: r * 0.14,
          ),
          Radius.circular(r * 0.06),
        ),
        ink,
      );
    }
  }

  void _paintSheetWave(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    double turn,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: r * 0.7, height: r * 0.9),
        Radius.circular(r * 0.12),
      ),
      ink,
    );
    for (var i = 0; i < 3; i++) {
      final y = c.dy - r * 0.18 + i * r * 0.18;
      final path = Path()
        ..moveTo(c.dx - r * 0.22, y)
        ..cubicTo(
          c.dx - r * 0.05,
          y - r * 0.04 * math.sin(turn + i),
          c.dx + r * 0.05,
          y + r * 0.04 * math.cos(turn + i),
          c.dx + r * 0.22,
          y,
        );
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(covariant HydroGlyphPainter oldDelegate) =>
      oldDelegate.clock != clock ||
      oldDelegate.kind != kind ||
      oldDelegate.color != color;
}
