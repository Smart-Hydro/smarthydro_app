import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Charco de agua anclado a un punto de captación.
///
/// Sirve para ver dónde quedó el punto después de acercar la cámara.
/// Se queda quieto si el sistema reduce las animaciones.
class CaptureWaterMark extends StatefulWidget {
  const CaptureWaterMark({this.burst = 0, this.ground = 0.7, super.key});

  /// Cambia para repetir el oleaje desde el principio.
  final int burst;

  /// Aplana el charco sobre el suelo. 1 lo deja circular.
  final double ground;

  @override
  State<CaptureWaterMark> createState() => _CaptureWaterMarkState();
}

class _CaptureWaterMarkState extends State<CaptureWaterMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  var _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    _reduce = reduce;
    if (reduce) {
      _wave
        ..stop()
        ..value = 0;
      return;
    }
    if (!_wave.isAnimating) _wave.repeat();
  }

  @override
  void didUpdateWidget(covariant CaptureWaterMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.burst == oldWidget.burst || _reduce) return;
    _wave
      ..value = 0
      ..repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoringSemantics: false,
      child: Semantics(
        label: 'Agua en el punto',
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _wave,
            builder: (context, _) => CustomPaint(
              painter: _WaterPainter(
                phase: _reduce ? 0 : _wave.value,
                ground: widget.ground,
                still: _reduce,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaterPainter extends CustomPainter {
  const _WaterPainter({
    required this.phase,
    required this.ground,
    required this.still,
  });

  final double phase;
  final double ground;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final flatten = ground.isFinite ? ground.clamp(0.42, 1.0).toDouble() : 0.7;
    final center = size.center(Offset.zero);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, flatten);

    const pool = 52.0;
    canvas.drawCircle(
      Offset.zero,
      pool,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x667FEFFF), Color(0x333AD0E2), Color(0x000E3C46)],
          stops: [0, 0.42, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: pool)),
    );

    final rings = still ? 1 : 3;
    for (var index = 0; index < rings; index++) {
      final travel = still ? 0.35 : (phase + index / rings) % 1;
      final radius = 18 + travel * 74;
      final alpha = still ? 0.32 : (1 - travel) * (1 - travel) * 0.4;
      canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 - travel
          ..color = const Color(0xFFB8F6FF).withValues(alpha: alpha),
      );
    }

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: pool - 6)),
    );
    final wave = Path();
    for (var band = 0; band < 2; band++) {
      wave.reset();
      final shift = still ? 0.0 : phase * math.pi * 2;
      final base = -10.0 + band * 16;
      wave.moveTo(-40, base);
      for (var x = -40.0; x <= 40; x += 3) {
        final y = base + math.sin(x / 11 + shift + band * 1.4) * 3.2;
        wave.lineTo(x, y);
      }
      canvas.drawPath(
        wave,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.7
          ..color = Color.fromRGBO(231, 251, 255, still ? 0.4 : 0.45),
      );
    }
    canvas.restore();

    canvas.drawCircle(
      Offset.zero,
      5,
      Paint()..color = const Color(0x99F4FEFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaterPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.ground != ground ||
        oldDelegate.still != still;
  }
}
