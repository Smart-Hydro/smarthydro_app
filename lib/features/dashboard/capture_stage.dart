import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'point_link.dart';

/// Vista única del punto: el nivel ocupa el pozo y el caudal mueve el flujo.
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
    _paintTypeBadge(canvas, size);
    _paintStatusChip(canvas, size);
  }

  /// Etiqueta de tipo de captación: distingue de un vistazo pozo vs. superficial.
  void _paintTypeBadge(Canvas canvas, Size size) {
    final label = isSurface ? 'AGUA SUPERFICIAL' : 'POZO SUBTERRÁNEO';
    final icon = isSurface ? '〰' : '⌄';
    final accent = isSurface
        ? const Color(0xFF69B9FF)
        : const Color(0xFF66E0C2);
    final iconPainter = TextPainter(
      text: TextSpan(
        text: icon,
        style: TextStyle(
          color: accent,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFF4FBF8),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: size.width * 0.6);

    const padH = 12.0;
    const padV = 8.0;
    const gap = 8.0;
    final w = iconPainter.width + gap + labelPainter.width + padH * 2;
    final h = math.max(iconPainter.height, labelPainter.height) + padV * 2;
    const left = 14.0;
    const top = 14.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xFF071114).withValues(alpha: 0.82),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Barra de acento a la izquierda del badge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top + 4, 3, h - 8),
        const Radius.circular(2),
      ),
      Paint()..color = accent,
    );
    iconPainter.paint(canvas, Offset(left + padH, top + padV));
    labelPainter.paint(
      canvas,
      Offset(left + padH + iconPainter.width + gap, top + padV),
    );
  }

  /// Chip de estado de enlace en la esquina superior derecha.
  void _paintStatusChip(Canvas canvas, Size size) {
    final color = switch (link) {
      PointLink.connected => const Color(0xFF66E0C2),
      PointLink.gap => const Color(0xFFFFC46B),
      PointLink.incident => const Color(0xFFFF847A),
    };
    final label = pointLinkLabel(link).toUpperCase();
    final dot = TextPainter(
      text: TextSpan(
        text: '●',
        style: TextStyle(color: color, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFF4FBF8),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: size.width * 0.4);
    const padH = 10.0;
    const padV = 7.0;
    const gap = 6.0;
    final w = dot.width + gap + text.width + padH * 2;
    final h = math.max(dot.height, text.height) + padV * 2;
    final left = (size.width - w - 14).clamp(4.0, size.width - 4);
    const top = 14.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(11),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xFF071114).withValues(alpha: 0.82),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    dot.paint(canvas, Offset(left + padH, top + padV));
    text.paint(canvas, Offset(left + padH + dot.width + gap, top + padV));
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
    canvas.drawRect(
      Rect.fromLTWH(0, groundY - 10, size.width, 16),
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
    // Cabezal del pozo: caseta de bombeo sobre la superficie.
    final headW = boreWidth + 36;
    final headH = 42.0;
    final head = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bore.center.dx - headW / 2,
        groundY - headH - 6,
        headW,
        headH,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      head,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A4A4A), Color(0xFF1E2A2A)],
        ).createShader(head.outerRect),
    );
    canvas.drawRRect(
      head,
      Paint()
        ..color = const Color(0xFF66E0C2).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Teja/techo del cabezal.
    final roof = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bore.center.dx - headW / 2 - 6,
        groundY - headH - 12,
        headW + 12,
        10,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(roof, Paint()..color = const Color(0xFF0C1C21));
    // Luz de estado del cabezal.
    final lampColor = switch (link) {
      PointLink.connected => const Color(0xFF66E0C2),
      PointLink.gap => const Color(0xFFFFC46B),
      PointLink.incident => const Color(0xFFFF847A),
    };
    canvas.drawCircle(
      Offset(bore.center.dx + headW / 2 - 12, groundY - headH / 2 - 6),
      3.5,
      Paint()..color = lampColor,
    );
    canvas.drawCircle(
      Offset(bore.center.dx + headW / 2 - 12, groundY - headH / 2 - 6),
      7,
      Paint()
        ..color = lampColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bore.center.dx - headW / 2 + 8,
          groundY - headH + 8,
          14,
          8,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF66E0C2).withValues(alpha: 0.5),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bore.center.dx - 2, groundY - headH - 2, 4, headH + 4),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF0C1C21),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(bore.center.dx, groundY + 2),
        width: boreWidth + 28,
        height: 18,
      ),
      Paint()..color = const Color(0xFFB7C6BE),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bore, const Radius.circular(22)),
      Paint()..color = const Color(0xFFD5E4DC),
    );
    final shaft = bore.deflate(12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shaft, const Radius.circular(14)),
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
      // Ola trasera (más oscura) para dar volumen.
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
      // Reflejo vertical de luz.
      canvas.drawRect(
        Rect.fromLTWH(
          water.left + water.width * 0.18,
          water.top,
          6,
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
      // Burbujas ascendentes (ciclo entero => sin saltos).
      for (var i = 0; i < 7; i++) {
        final seed = (i * 0.6180339) % 1;
        final progress = (phase * (1 + i % 2) + seed) % 1;
        final bx =
            water.left +
            water.width * (0.15 + 0.7 * ((seed * 5.3) % 1)) +
            math.sin(progress * math.pi * 4 + i) * 3;
        final by = water.bottom - water.height * progress;
        final fade = math.sin(progress * math.pi);
        canvas.drawCircle(
          Offset(bx, by),
          1.4 + (i % 3) * 0.8,
          Paint()
            ..color = const Color(0xFFDFFFF6).withValues(alpha: 0.35 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      canvas.restore();
      // Ola frontal con brillo especular.
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
      // Menisco: halo suave sobre la superficie.
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
    // Línea de espuma/brillo sobre la superficie.
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
    // Destellos horizontales que derivan con la corriente.
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
    // Flechas de sentido de corriente para interpretar el flujo superficial.
    _paintFlowArrows(canvas, size, bankY);
    // Orillas del canal (márgenes) para reforzar la lectura de cauce.
    canvas.drawPath(
      Path()
        ..moveTo(0, bankY)
        ..lineTo(0, bankY + 18)
        ..lineTo(size.width * 0.18, bankY + 6)
        ..lineTo(size.width * 0.18, bankY - 2)
        ..close(),
      Paint()..color = const Color(0xFF2A3D34),
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width, bankY)
        ..lineTo(size.width, bankY + 18)
        ..lineTo(size.width * 0.82, bankY + 6)
        ..lineTo(size.width * 0.82, bankY - 2)
        ..close(),
      Paint()..color = const Color(0xFF2A3D34),
    );
    final intake = Offset(size.width * 0.32, bankY + 4);
    // Soporte/pértiga de la toma.
    canvas.drawLine(
      Offset(intake.dx, bankY - 64),
      intake,
      Paint()
        ..color = const Color(0xFFE8F2F1)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    // Base del soporte en tierra.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(intake.dx, bankY - 64),
        width: 18,
        height: 8,
      ),
      Paint()..color = const Color(0xFF1E2A2A),
    );
    canvas.drawCircle(
      Offset(intake.dx, bankY - 64),
      6,
      Paint()..color = const Color(0xFF16343A),
    );
    // Cuerpo sumergido de la toma.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: intake, width: 16, height: 14),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF0C1C21),
    );
    canvas.drawCircle(intake, 5, Paint()..color = const Color(0xFF66E0C2));
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

  /// Chevrones que indican el sentido del flujo superficial, animados con la fase.
  void _paintFlowArrows(Canvas canvas, Size size, double bankY) {
    final moving = (flow ?? 0) > 0.01 && link != PointLink.gap;
    final baseY = bankY + (size.height - bankY) * 0.55;
    final arrowColor = moving
        ? const Color(0xFF66E0C2).withValues(alpha: 0.85)
        : const Color(0xFF8FA8A8).withValues(alpha: 0.5);
    for (var row = 0; row < 2; row++) {
      final y = baseY + row * 26;
      for (var i = 0; i < 4; i++) {
        final travel = (phase * 0.6 + i / 4 + row * 0.25) % 1;
        final x = size.width * (0.18 + travel * 0.64);
        final fade = moving ? math.sin(travel * math.pi) : 0.6;
        final chevron = Path()
          ..moveTo(x, y)
          ..lineTo(x + 10, y - 6)
          ..lineTo(x + 10, y + 6)
          ..close();
        canvas.drawPath(
          chevron,
          Paint()
            ..color = arrowColor.withValues(alpha: fade)
            ..style = PaintingStyle.fill,
        );
      }
    }
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
      canvas.drawOval(
        Rect.fromCenter(center: Offset(dx, dy), width: 3, height: 6 + fade * 4),
        Paint()
          ..color = const Color(
            0xFFBFF7EA,
          ).withValues(alpha: 0.25 + fade * 0.6),
      );
    }
  }

  void _paintRuler(Canvas canvas, Size size, Rect shaft, double waterTop) {
    // Marcas de escala a la izquierda del pozo (referencia visual).
    final tick = Paint()
      ..color = const Color(0xFFE8F2F1).withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final y = shaft.top + shaft.height * i / 10;
      final long = i % 5 == 0;
      canvas.drawLine(
        Offset(shaft.left - 2, y),
        Offset(shaft.left - (long ? 12 : 6), y),
        tick,
      );
    }
    // Barra de la regla con resalte para contraste.
    canvas.drawLine(
      Offset(shaft.left - 2, shaft.top),
      Offset(shaft.left - 2, shaft.bottom),
      Paint()
        ..color = const Color(0xFF66E0C2).withValues(alpha: 0.35)
        ..strokeWidth = 1.4,
    );
    // Línea de nivel actual cruzando el pozo.
    canvas.drawLine(
      Offset(shaft.left, waterTop),
      Offset(shaft.right + 10, waterTop),
      Paint()
        ..color = const Color(0xFFEFFFFA)
        ..strokeWidth = 1.6,
    );
    // Marcador triangular del nivel actual a la derecha.
    final arrow = Path()
      ..moveTo(shaft.right + 12, waterTop)
      ..lineTo(shaft.right + 4, waterTop - 5)
      ..lineTo(shaft.right + 4, waterTop + 5)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFF66E0C2));
    final label = levelMeters == null
        ? 'Sin nivel'
        : '${levelMeters!.toStringAsFixed(2)} m';
    _pill(
      canvas,
      size,
      label,
      Offset(shaft.right + 22, waterTop),
      const Color(0xFF66E0C2),
    );
    if (levelMin != null && levelMax != null && levelMax! > levelMin!) {
      _minMaxMarker(
        canvas,
        size,
        shaft.right + 4,
        shaft.top + 10,
        'Máx',
        levelMax!,
        const Color(0xFF69B9FF),
      );
      _minMaxMarker(
        canvas,
        size,
        shaft.right + 4,
        shaft.bottom - 10,
        'Mín',
        levelMin!,
        const Color(0xFFFFC46B),
      );
    }
  }

  void _minMaxMarker(
    Canvas canvas,
    Size size,
    double x,
    double y,
    String prefix,
    double value,
    Color color,
  ) {
    canvas.drawCircle(Offset(x, y), 3, Paint()..color = color);
    _pill(
      canvas,
      size,
      '$prefix ${value.toStringAsFixed(2)} m',
      Offset(x + 18, y),
      color,
      small: true,
    );
  }

  /// Etiqueta con fondo para asegurar contraste sobre cualquier zona del lienzo.
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
      const Radius.circular(10),
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

  /// [levelFill] es la posición relativa al período visible (0 vacío, 1 lleno).
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
