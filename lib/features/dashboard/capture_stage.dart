import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import 'point_link.dart';

/// Tipo de captación. Expone la figura mínima para que otras presentaciones
/// (hoy el lienzo 2D; mañana el render 3D Three.js) puedan reutilizarla.
enum CaptureKind { well, surface }

CaptureKind captureKindOf(Map<String, dynamic> data) {
  final dga = data['dga'];
  final type = dga is Map
      ? (dga['type_dga'] as String? ?? '').toUpperCase()
      : '';
  return type == 'SUPERFICIAL' ? CaptureKind.surface : CaptureKind.well;
}

/// Vista singular del punto: una sola figura limpia, legible y mínima.
///
/// La escena es intencionalmente simple: un plano de agua, una figura que
/// representa el tipo de captación y una única lectura de nivel. La capa de
/// escena (este CustomPaint) queda aislada para poder sustituirse por una
/// versión 3D (Three.js) sin tocar el resto de la pantalla.
class CaptureStage extends StatefulWidget {
  const CaptureStage({
    required this.levelMeters,
    required this.levelFill,
    required this.flowLitersPerSecond,
    required this.isSurface,
    required this.link,
    this.levelMin,
    this.levelMax,
    this.onInteract,
    this.playing = false,
    super.key,
  });

  final double? levelMeters;
  final double? levelFill;
  final double? levelMin;
  final double? levelMax;
  final double? flowLitersPerSecond;
  final bool isSurface;
  final PointLink link;
  final VoidCallback? onInteract;

  /// Verdadero mientras el replay corre: la figura "cobra vida" con una
  /// respiración/oleaje más marcada para reforzar que está en movimiento.
  final bool playing;

  @override
  State<CaptureStage> createState() => _CaptureStageState();
}

class _CaptureStageState extends State<CaptureStage>
    with TickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  /// Pulso suave que se enciende al pulsar play y decae al pausar.
  late final AnimationController _playPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _hovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _flow.stop();
      _flow.value = 0;
      _playPulse.stop();
      _playPulse.value = 0;
    } else if (!_flow.isAnimating) {
      _flow.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CaptureStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !oldWidget.playing) {
      _playPulse.repeat(reverse: true);
    } else if (!widget.playing && oldWidget.playing) {
      _playPulse.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    _playPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final kind = widget.isSurface ? 'Agua superficial' : 'Pozo subterráneo';
    final level = widget.levelMeters == null
        ? 'sin lectura de nivel'
        : 'nivel ${widget.levelMeters!.toStringAsFixed(2)} metros';
    final flow = widget.flowLitersPerSecond == null
        ? 'sin lectura de caudal'
        : 'caudal ${widget.flowLitersPerSecond!.toStringAsFixed(2)} litros por segundo';
    return Semantics(
      container: true,
      label: '$kind: $level, $flow, ${pointLinkLabel(widget.link)}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: Listenable.merge([_flow, _playPulse]),
            builder: (context, _) {
              // 0 en reposo, 1 en reproducción (respiración suave).
              final alive = widget.playing
                  ? 0.55 + _playPulse.value * 0.45
                  : _playPulse.value * 0.45;
              return CustomPaint(
                painter: _CaptureStagePainter(
                  phase: _flow.value,
                  levelMeters: widget.levelMeters,
                  levelFill: widget.levelFill,
                  levelMin: widget.levelMin,
                  levelMax: widget.levelMax,
                  textScaler: textScaler,
                  flow: widget.flowLitersPerSecond,
                  isSurface: widget.isSurface,
                  link: widget.link,
                  hovered: _hovered,
                  alive: alive,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CaptureStagePainter extends CustomPainter {
  const _CaptureStagePainter({
    required this.phase,
    required this.levelMeters,
    required this.levelFill,
    required this.levelMin,
    required this.levelMax,
    required this.textScaler,
    required this.flow,
    required this.isSurface,
    required this.link,
    required this.hovered,
    required this.alive,
  });

  final double phase;
  final double? levelMeters;
  final double? levelFill;
  final double? levelMin;
  final double? levelMax;
  final TextScaler textScaler;
  final double? flow;
  final bool isSurface;
  final PointLink link;
  final bool hovered;

  /// 0 en reposo, ~1 en reproducción: amplifica oleaje, flujo y halo.
  final double alive;

  static const _surfaceCard = Color(0xFF12252A);
  static const _mint = Color(0xFF66E0C2);
  static const _blue = Color(0xFF69B9FF);
  static const _fog = Color(0xFFE8F2F1);
  static const _faint = Color(0xFF9AB0B1);

  Color get _linkColor => switch (link) {
    PointLink.connected => _mint,
    PointLink.gap => const Color(0xFFFFC46B),
    PointLink.incident => const Color(0xFFFF847A),
  };

  Color get _accent => isSurface ? _blue : IkoluColors.cyan;

  double get _fill {
    if (levelMeters == null || levelFill == null) return 0.12;
    return 0.18 + levelFill!.clamp(0, 1) * 0.62;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final backdrop = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      backdrop,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF10222B), Color(0xFF0C181D), Color(0xFF081114)],
        ).createShader(backdrop),
    );
    // Marco sutil: un solo trazo, sin cajas ni paneles.
    final frame = RRect.fromRectAndRadius(
      backdrop.deflate(10),
      const Radius.circular(20),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = hovered
            ? _accent.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (alive > 0.01) _paintBreathHalo(canvas, size);
    if (isSurface) {
      _paintSurface(canvas, size);
    } else {
      _paintWell(canvas, size);
    }
    _paintHeader(canvas, size);
  }

  /// Halo radial que "respira" con el replay: da la sensación orgánica de
  /// que la figura cobra vida sin meter paneles ni sombras duras.
  void _paintBreathHalo(Canvas canvas, Size size) {
    final center = isSurface
        ? Offset(size.width * 0.5, size.height * 0.55)
        : Offset(size.width * 0.42, size.height * 0.52);
    final radius = size.shortestSide * (0.45 + alive * 0.18);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _accent.withValues(alpha: 0.24 * alive),
            _accent.withValues(alpha: 0.08 * alive),
            _accent.withValues(alpha: 0),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  /// Cabecera mínima: tipo de captación y estado, sin paneles ni sombras.
  void _paintHeader(Canvas canvas, Size size) {
    final label = isSurface ? 'AGUA SUPERFICIAL' : 'POZO SUBTERRÁNEO';
    final status = pointLinkLabel(link).toUpperCase();
    final left = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: label,
            style: TextStyle(
              color: _accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: size.width * 0.6);
    final right = TextPainter(
      text: TextSpan(
        text: status,
        style: TextStyle(
          color: _linkColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: size.width * 0.4);
    final top = 22.0;
    left.paint(canvas, Offset(24, top));
    // Punto de estado mínimo antes de la etiqueta.
    final dotX = size.width - 24 - right.width - 12;
    canvas.drawCircle(
      Offset(dotX, top + right.height / 2),
      3.5,
      Paint()..color = _linkColor,
    );
    right.paint(canvas, Offset(dotX + 12, top));
  }

  void _paintWell(Canvas canvas, Size size) {
    final groundY = size.height * 0.3;
    // Línea de superficie minimalista.
    canvas.drawLine(
      Offset(24, groundY),
      Offset(size.width - 24, groundY),
      Paint()
        ..color = _fog.withValues(alpha: 0.18)
        ..strokeWidth = 1.2,
    );

    final boreWidth = math.min(120.0, size.width * 0.3);
    final cx = size.width * 0.42;
    final bore = Rect.fromCenter(
      center: Offset(cx, groundY + (size.height - groundY) * 0.5),
      width: boreWidth,
      height: (size.height - groundY) * 0.82,
    );
    // Casco del pozo: un solo contorno fino.
    final casing = RRect.fromRectAndRadius(bore, const Radius.circular(14));
    canvas.drawRRect(casing, Paint()..color = _fog.withValues(alpha: 0.04));
    canvas.drawRRect(
      casing,
      Paint()
        ..color = _fog.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final shaft = bore.deflate(6);

    final waterTop = shaft.bottom - shaft.height * _fill;
    final water = Rect.fromLTRB(
      shaft.left + 3,
      waterTop,
      shaft.right - 3,
      shaft.bottom - 3,
    );
    if (water.height > 4) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(water, const Radius.circular(6)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _accent.withValues(alpha: 0.85),
              _accent.withValues(alpha: 0.3),
            ],
          ).createShader(water),
      );
      // Ola única y suave; crece cuando el replay está vivo.
      final waveAmp = 1.4 + alive * 2.4;
      final wave = Path()..moveTo(water.left, water.top + 3);
      for (var x = water.left; x <= water.right; x += 4) {
        final y =
            water.top +
            math.sin((x / 16) + phase * math.pi * (2 + alive * 2)) * waveAmp;
        wave.lineTo(x, y);
      }
      canvas.drawPath(
        wave,
        Paint()
          ..color = _fog.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
      // Menisco: la superficie del agua vista en perspectiva (refuerzo 3D);
      // respira con el replay.
      final meniscus = Rect.fromCenter(
        center: Offset(water.center.dx, water.top + 2),
        width: water.width,
        height: 5 + alive * 5,
      );
      canvas.drawOval(
        meniscus,
        Paint()..color = _fog.withValues(alpha: 0.26 + alive * 0.38),
      );
      // Burbujas ascendentes: solo cobran vida con el replay.
      if (alive > 0.05 && water.height > 24) {
        for (var i = 0; i < 6; i++) {
          final travel = (phase * (0.4 + alive * 0.6) + i / 6) % 1;
          final bx =
              water.left +
              water.width * (0.2 + 0.6 * (0.5 + math.sin(i * 2.3) / 2));
          final by = water.bottom - water.height * travel;
          final fade = math.sin(travel * math.pi);
          canvas.drawCircle(
            Offset(bx, by),
            1.4 + fade * 2.2,
            Paint()
              ..color = _fog.withValues(alpha: (0.16 + fade * 0.45) * alive),
          );
        }
      }
    }

    // Marca de nivel: línea fina y valor, sin pill ni flecha.
    canvas.drawLine(
      Offset(shaft.left, waterTop),
      Offset(shaft.right + 8, waterTop),
      Paint()
        ..color = _fog.withValues(alpha: 0.7)
        ..strokeWidth = 1.1,
    );
    _label(
      canvas,
      size,
      levelMeters == null
          ? 'sin nivel'
          : '${levelMeters!.toStringAsFixed(2)} m',
      Offset(shaft.right + 16, waterTop),
      _accent,
    );
    if (levelMin != null && levelMax != null && levelMax! > levelMin!) {
      _label(
        canvas,
        size,
        'máx ${levelMax!.toStringAsFixed(2)}',
        Offset(shaft.right + 16, shaft.top + 8),
        _faint,
        small: true,
      );
      _label(
        canvas,
        size,
        'mín ${levelMin!.toStringAsFixed(2)}',
        Offset(shaft.right + 16, shaft.bottom - 8),
        _faint,
        small: true,
      );
    }
    _paintFlowDrops(canvas, size, Offset(shaft.right, groundY - 4), true);
  }

  void _paintSurface(Canvas canvas, Size size) {
    final bankY = size.height * (0.42 - _fill * 0.1);
    // Línea de costa mínima.
    canvas.drawLine(
      Offset(24, bankY),
      Offset(size.width - 24, bankY),
      Paint()
        ..color = _fog.withValues(alpha: 0.14)
        ..strokeWidth = 1,
    );
    final surfaceAmp = 3.5 + alive * 4.5;
    final water = Path()..moveTo(0, bankY);
    for (var x = 0.0; x <= size.width; x += 6) {
      final y =
          bankY +
          math.sin(
                (x / size.width) * math.pi * 2 + phase * math.pi * (2 + alive),
              ) *
              surfaceAmp;
      water.lineTo(x, y);
    }
    water
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      water,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _accent.withValues(alpha: 0.55),
                _accent.withValues(alpha: 0.12),
              ],
            ).createShader(
              Rect.fromLTWH(0, bankY, size.width, size.height - bankY),
            ),
    );
    // Flechas de corriente mínimas, una sola fila.
    final moving = (flow ?? 0) > 0.01 && link != PointLink.gap;
    final arrowColor = moving
        ? _accent.withValues(alpha: 0.85)
        : _faint.withValues(alpha: 0.4);
    final y = bankY + (size.height - bankY) * 0.55;
    for (var i = 0; i < 4; i++) {
      final travel = (phase * (0.6 + alive * 0.5) + i / 4) % 1;
      final x = size.width * (0.2 + travel * 0.6);
      final fade = moving ? math.sin(travel * math.pi) : 0.5;
      final chevron = Path()
        ..moveTo(x, y)
        ..lineTo(x + 8, y - 5)
        ..lineTo(x + 8, y + 5)
        ..close();
      canvas.drawPath(
        chevron,
        Paint()..color = arrowColor.withValues(alpha: fade),
      );
    }
    // Toma: una sola línea fina hasta el agua.
    final intake = Offset(size.width * 0.3, bankY + 2);
    canvas.drawLine(
      Offset(intake.dx, bankY - 40),
      intake,
      Paint()
        ..color = _fog.withValues(alpha: 0.7)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(intake, 3.5 + alive * 2, Paint()..color = _accent);
    if (alive > 0.05) {
      canvas.drawCircle(
        intake,
        3.5 + alive * 7,
        Paint()
          ..color = _accent.withValues(alpha: 0.35 * alive)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    // Banda de brillo que cruza la lámina con el replay (refuerzo 3D).
    if (alive > 0.05) {
      final shimmerY =
          bankY +
          14 +
          (size.height - bankY - 28) *
              (0.5 + math.sin(phase * math.pi * 2) / 2);
      final shimmer = Rect.fromLTWH(0, shimmerY - 10, size.width, 20);
      canvas.drawRect(
        shimmer,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.10 * alive),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(shimmer),
      );
    }
    _paintFlowDrops(canvas, size, intake, false);
    _label(
      canvas,
      size,
      levelMeters == null
          ? 'sin nivel'
          : '${levelMeters!.toStringAsFixed(2)} m',
      Offset(size.width - 24, bankY + 34),
      _accent,
      alignRight: true,
    );
  }

  /// Gotas de flujo mínimas y discretas.
  void _paintFlowDrops(Canvas canvas, Size size, Offset origin, bool fromWell) {
    final moving = (flow ?? 0) > 0.01 && link != PointLink.gap;
    if (!moving) return;
    final length = fromWell ? size.width * 0.18 : size.width * 0.4;
    for (var index = 0; index < 4; index++) {
      final travel = (phase + index / 4) % 1;
      final fade = math.sin(travel * math.pi);
      if (fade < 0.05) continue;
      final dx = origin.dx + length * travel;
      final dy =
          origin.dy + math.sin(travel * math.pi * 2 + index) * (2 + alive * 2);
      canvas.drawCircle(
        Offset(dx, dy),
        1.6 + fade * (1 + alive * 0.6),
        Paint()
          ..color = _accent.withValues(
            alpha: 0.25 + fade * (0.55 + alive * 0.2),
          ),
      );
    }
  }

  /// Etiqueta mínima con fondo oscuro suave para legibilidad, sin borde duro.
  void _label(
    Canvas canvas,
    Size size,
    String text,
    Offset anchor,
    Color color, {
    bool small = false,
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: small ? 11 : 13,
          fontWeight: small ? FontWeight.w600 : FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: size.width * 0.5);
    final w = painter.width + 14;
    final h = painter.height + 6;
    var left = alignRight ? anchor.dx - w : anchor.dx;
    left = left.clamp(10.0, math.max(10.0, size.width - w - 10));
    final top = (anchor.dy - h / 2)
        .clamp(10.0, math.max(10.0, size.height - h - 10))
        .toDouble();
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = _surfaceCard.withValues(alpha: 0.85),
    );
    painter.paint(canvas, Offset(left + 7, top + 3));
  }

  @override
  bool shouldRepaint(covariant _CaptureStagePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.levelMeters != levelMeters ||
      oldDelegate.levelFill != levelFill ||
      oldDelegate.levelMin != levelMin ||
      oldDelegate.levelMax != levelMax ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.flow != flow ||
      oldDelegate.isSurface != isSurface ||
      oldDelegate.link != link ||
      oldDelegate.hovered != hovered ||
      oldDelegate.alive != alive;
}
