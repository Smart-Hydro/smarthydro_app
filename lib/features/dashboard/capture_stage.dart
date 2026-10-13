import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'point_link.dart';

/// Vista del punto: nivel en el pozo/canal y caudal como flujo lineal.
/// Sin óvalos flotantes; pensada para explorar con zoom.
class CaptureStage extends StatefulWidget {
  const CaptureStage({
    required this.levelMeters,
    required this.levelFill,
    required this.flowLitersPerSecond,
    required this.isSurface,
    required this.link,
    this.levelMin,
    this.levelMax,
    super.key,
  });

  final double? levelMeters;
  final double? levelFill;
  final double? levelMin;
  final double? levelMax;
  final double? flowLitersPerSecond;
  final bool isSurface;
  final PointLink link;

  @override
  State<CaptureStage> createState() => _CaptureStageState();
}

class _CaptureStageState extends State<CaptureStage>
    with TickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  late final AnimationController _surge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  final TransformationController _transform = TransformationController();
  double? _previousFlow;

  @override
  void initState() {
    super.initState();
    _previousFlow = widget.flowLitersPerSecond;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _flow.stop();
      _flow.value = 0;
    } else if (!_flow.isAnimating) {
      _flow.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CaptureStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.flowLitersPerSecond;
    final previous = _previousFlow;
    if (next != null && previous != null && (next - previous).abs() >= 0.05) {
      _surge.forward(from: 0);
    }
    _previousFlow = next;
  }

  @override
  void dispose() {
    _flow.dispose();
    _surge.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final kind = widget.isSurface ? 'Agua superficial' : 'Pozo';
    final level = widget.levelMeters == null
        ? 'sin lectura de nivel'
        : 'nivel ${widget.levelMeters!.toStringAsFixed(2)} metros';
    final flow = widget.flowLitersPerSecond == null
        ? 'sin lectura de caudal'
        : 'caudal ${widget.flowLitersPerSecond!.toStringAsFixed(2)} litros por segundo';
    return Semantics(
      container: true,
      label: '$kind: $level, $flow, ${pointLinkLabel(widget.link)}',
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              transformationController: _transform,
              minScale: 0.75,
              maxScale: 3.2,
              boundaryMargin: const EdgeInsets.all(80),
              child: AnimatedBuilder(
                animation: Listenable.merge([_flow, _surge]),
                builder: (context, _) {
                  final surge = _surge.isDismissed ? 0.0 : (1 - _surge.value);
                  return CustomPaint(
                    painter: _CaptureStagePainter(
                      phase: _flow.value,
                      surge: surge,
                      levelMeters: widget.levelMeters,
                      levelFill: widget.levelFill,
                      levelMin: widget.levelMin,
                      levelMax: widget.levelMax,
                      textScaler: textScaler,
                      flow: widget.flowLitersPerSecond,
                      isSurface: widget.isSurface,
                      link: widget.link,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: const Color(0xFF0C1C21).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                child: IconButton(
                  tooltip: 'Restablecer vista',
                  onPressed: () => _transform.value = Matrix4.identity(),
                  icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureStagePainter extends CustomPainter {
  const _CaptureStagePainter({
    required this.phase,
    required this.surge,
    required this.levelMeters,
    required this.levelFill,
    required this.levelMin,
    required this.levelMax,
    required this.textScaler,
    required this.flow,
    required this.isSurface,
    required this.link,
  });

  final double phase;
  final double surge;
  final double? levelMeters;
  final double? levelFill;
  final double? levelMin;
  final double? levelMax;
  final TextScaler textScaler;
  final double? flow;
  final bool isSurface;
  final PointLink link;

  @override
  void paint(Canvas canvas, Size size) {
    final backdrop = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      backdrop,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16343C), Color(0xFF0C1C21), Color(0xFF071114)],
        ).createShader(backdrop),
    );
    if (isSurface) {
      _paintSurface(canvas, size);
    } else {
      _paintWell(canvas, size);
    }
  }

  void _paintWell(Canvas canvas, Size size) {
    final groundY = size.height * 0.16;
    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
      Paint()
        ..shader =
            const LinearGradient(
              colors: [Color(0xFF3A4C43), Color(0xFF1A2C2A), Color(0xFF0C1818)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(
              Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
            ),
    );
    // Franja de terreno (rectilínea, sin óvalo).
    canvas.drawRect(
      Rect.fromLTWH(0, groundY - 8, size.width, 12),
      Paint()..color = const Color(0xFF6D7C74),
    );

    final boreWidth = math.min(168.0, size.width * 0.42);
    final bore = Rect.fromCenter(
      center: Offset(
        size.width * 0.46,
        groundY + (size.height - groundY) * 0.5,
      ),
      width: boreWidth,
      height: (size.height - groundY) * 0.86,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bore, const Radius.circular(16)),
      Paint()..color = const Color(0xFFD5E4DC),
    );
    // Boca del pozo: placa rectangular, no óvalo flotante.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bore.center.dx, groundY + 2),
          width: boreWidth + 18,
          height: 14,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFB7C6BE),
    );
    final shaft = bore.deflate(12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shaft, const Radius.circular(12)),
      Paint()..color = const Color(0xFF071114),
    );

    final fill = _visibleFill(levelFill);
    final waterTop = shaft.bottom - shaft.height * fill;
    final water = Rect.fromLTRB(
      shaft.left + 4,
      waterTop,
      shaft.right - 4,
      shaft.bottom - 4,
    );
    if (water.height > 2) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(water, const Radius.circular(8)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF8EF0D8), Color(0xFF1B7C86), Color(0xFF0C3140)],
          ).createShader(water),
      );
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(water, const Radius.circular(8)),
      );
      final back = Path()..moveTo(water.left, water.bottom);
      for (var x = water.left; x <= water.right + 4; x += 4) {
        final y =
            water.top +
            2 +
            math.sin((x / 11) - phase * math.pi * 2 * 2) * (1.8 + surge * 2.5);
        back.lineTo(x, y);
      }
      back
        ..lineTo(water.right, water.bottom)
        ..close();
      canvas.drawPath(
        back,
        Paint()..color = const Color(0xFF0C3140).withValues(alpha: 0.55),
      );
      // Reflejo de luz vertical (línea, no burbujas).
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
              Colors.white.withValues(alpha: 0.2),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(water),
      );
      // Filamentos de caudal ascendentes (trazos, no óvalos).
      for (var i = 0; i < 5; i++) {
        final seed = (i * 0.6180339) % 1;
        final progress = (phase * (1 + i % 2) + seed) % 1;
        final bx = water.left + water.width * (0.2 + 0.6 * ((seed * 5.3) % 1));
        final by = water.bottom - water.height * progress;
        final fade = math.sin(progress * math.pi);
        canvas.drawLine(
          Offset(bx, by + 6),
          Offset(bx, by - 4),
          Paint()
            ..color = const Color(0xFFDFFFF6).withValues(alpha: 0.28 * fade)
            ..strokeWidth = 1.2
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.restore();

      final wave = Path()..moveTo(water.left, water.top + 3);
      for (var x = water.left; x <= water.right; x += 4) {
        final y =
            water.top +
            math.sin((x / 14) + phase * math.pi * 2) * (1.6 + surge * 2) +
            math.sin((x / 6) - phase * math.pi * 2 * 3) * 0.6;
        wave.lineTo(x, y);
      }
      canvas.drawPath(
        wave,
        Paint()
          ..color = const Color(0xFFEFFFFA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawRect(
        Rect.fromLTWH(water.left, water.top - 3, water.width, 8),
        Paint()
          ..shader =
              LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF8EF0D8).withValues(alpha: 0),
                  const Color(0xFF8EF0D8).withValues(alpha: 0.28),
                ],
              ).createShader(
                Rect.fromLTWH(water.left, water.top - 3, water.width, 8),
              ),
      );
    }

    _paintRuler(canvas, size, shaft, waterTop);
    _paintFlow(canvas, size, Offset(shaft.right, groundY - 6), true);
  }

  void _paintSurface(Canvas canvas, Size size) {
    final fill = _visibleFill(levelFill);
    final bankY = size.height * (0.46 - fill * 0.12);
    final shore = Path()
      ..moveTo(0, bankY - 36)
      ..quadraticBezierTo(
        size.width * 0.25,
        bankY + 8,
        size.width * 0.5,
        bankY - 6,
      )
      ..quadraticBezierTo(size.width * 0.75, bankY - 20, size.width, bankY - 4)
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(shore, Paint()..color = const Color(0xFF24362F));
    final channel = Path()..moveTo(0, bankY);
    for (var x = 0.0; x <= size.width; x += 8) {
      final y =
          bankY +
          math.sin((x / size.width) * math.pi * 2 + phase * math.pi * 2) * 5;
      channel.lineTo(x, y);
    }
    channel
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      channel,
      Paint()
        ..shader =
            const LinearGradient(
              colors: [Color(0xFF7EE8D0), Color(0xFF14616C), Color(0xFF0A2832)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(
              Rect.fromLTWH(0, bankY, size.width, size.height - bankY),
            ),
    );
    final foam = Path();
    for (var x = 0.0; x <= size.width; x += 6) {
      final y =
          bankY +
          math.sin((x / size.width) * math.pi * 2 + phase * math.pi * 2) * 5 +
          math.sin((x / 9) - phase * math.pi * 2 * 3) * 0.9;
      x == 0 ? foam.moveTo(x, y) : foam.lineTo(x, y);
    }
    canvas.drawPath(
      foam,
      Paint()
        ..color = const Color(0xFFEFFFFA).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < 9; i++) {
      final seed = (i * 0.6180339) % 1;
      final t = (phase + seed) % 1;
      final sx = size.width * t;
      final sy = bankY + 16 + (size.height - bankY - 24) * ((seed * 3.7) % 1);
      final fade = math.sin(t * math.pi);
      canvas.drawLine(
        Offset(sx, sy),
        Offset(sx + 14 + (i % 3) * 8, sy),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.22 * fade)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }
    final intake = Offset(size.width * 0.32, bankY + 4);
    canvas.drawLine(
      Offset(intake.dx, bankY - 56),
      intake,
      Paint()
        ..color = const Color(0xFFE8F2F1)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    // Cabezal cuadrado del logger, no círculo.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(intake.dx, bankY - 56),
          width: 12,
          height: 12,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF16343A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: intake, width: 10, height: 10),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF66E0C2),
    );
    _paintFlow(canvas, size, intake, false);
    final label = levelMeters == null
        ? 'Sin nivel'
        : 'Nivel ${levelMeters!.toStringAsFixed(2)} m';
    _pill(
      canvas,
      size,
      label,
      Offset(size.width - 150, bankY + 40),
      const Color(0xFF66E0C2),
    );
  }

  void _paintFlow(Canvas canvas, Size size, Offset origin, bool fromWell) {
    final moving = (flow ?? 0) > 0.01 && link != PointLink.gap;
    if (!moving) return;
    final count = 5;
    final length = fromWell ? size.width * 0.22 : size.width * 0.5;
    for (var index = 0; index < count; index++) {
      final travel = (phase + index / count) % 1;
      final fade = math.sin(travel * math.pi);
      if (fade < 0.05) continue;
      final dx = origin.dx + length * travel;
      final dy =
          origin.dy + math.sin(travel * math.pi * 2 + index) * (2 + surge * 4);
      // Trazo de corriente (línea), no óvalo flotante.
      canvas.drawLine(
        Offset(dx - 4, dy),
        Offset(dx + 5, dy),
        Paint()
          ..color = const Color(
            0xFFBFF7EA,
          ).withValues(alpha: 0.25 + fade * 0.55)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintRuler(Canvas canvas, Size size, Rect shaft, double waterTop) {
    final tick = Paint()
      ..color = const Color(0xFF0C1C21).withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final y = shaft.top + shaft.height * i / 10;
      final long = i % 5 == 0;
      canvas.drawLine(
        Offset(shaft.left - 2, y),
        Offset(shaft.left - (long ? 10 : 6), y),
        tick,
      );
    }
    canvas.drawLine(
      Offset(shaft.left, waterTop),
      Offset(shaft.right + 10, waterTop),
      Paint()
        ..color = const Color(0xFFEFFFFA)
        ..strokeWidth = 1.4,
    );
    final label = levelMeters == null
        ? 'Sin nivel'
        : '${levelMeters!.toStringAsFixed(2)} m';
    _pill(
      canvas,
      size,
      label,
      Offset(shaft.right + 14, waterTop),
      const Color(0xFF66E0C2),
    );
    if (levelMin != null && levelMax != null && levelMax! > levelMin!) {
      _pill(
        canvas,
        size,
        'Máx ${levelMax!.toStringAsFixed(2)} m',
        Offset(shaft.right + 14, shaft.top + 10),
        null,
        small: true,
      );
      _pill(
        canvas,
        size,
        'Mín ${levelMin!.toStringAsFixed(2)} m',
        Offset(shaft.right + 14, shaft.bottom - 10),
        null,
        small: true,
      );
    }
  }

  void _pill(
    Canvas canvas,
    Size size,
    String text,
    Offset anchor,
    Color? accent, {
    bool small = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFFF4FBF8),
          fontSize: small ? 11 : 14,
          fontWeight: small ? FontWeight.w600 : FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: size.width * 0.5);
    final w = painter.width + 16;
    final h = painter.height + 8;
    final left = anchor.dx
        .clamp(4.0, math.max(4.0, size.width - w - 4))
        .toDouble();
    final top = (anchor.dy - h / 2)
        .clamp(4.0, math.max(4.0, size.height - h - 4))
        .toDouble();
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xFF0C1C21).withValues(alpha: 0.88),
    );
    if (accent != null) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    painter.paint(canvas, Offset(left + 8, top + 4));
  }

  double _visibleFill(double? levelFill) {
    if (levelMeters == null || levelFill == null) return 0.06;
    return (0.2 + levelFill.clamp(0, 1) * 0.68);
  }

  @override
  bool shouldRepaint(covariant _CaptureStagePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.surge != surge ||
      oldDelegate.levelMeters != levelMeters ||
      oldDelegate.levelFill != levelFill ||
      oldDelegate.levelMin != levelMin ||
      oldDelegate.levelMax != levelMax ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.flow != flow ||
      oldDelegate.isSurface != isSurface ||
      oldDelegate.link != link;
}
