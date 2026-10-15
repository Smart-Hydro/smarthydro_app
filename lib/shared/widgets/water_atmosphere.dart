import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Movimiento ambiental de agua; se detiene cuando el sistema reduce animaciones.
///
/// El ciclo es continuo: todos los términos temporales son múltiplos enteros
/// de 2π, por lo que el reinicio del controlador no produce saltos visibles.
class WaterAtmosphere extends StatefulWidget {
  const WaterAtmosphere({this.opacity = 1, super.key});

  final double opacity;

  @override
  State<WaterAtmosphere> createState() => _WaterAtmosphereState();
}

class _WaterAtmosphereState extends State<WaterAtmosphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );
  final _AtmosphereShaders _shaders = _AtmosphereShaders();
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldReduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion == shouldReduceMotion &&
        _controller.isAnimating == !shouldReduceMotion) {
      return;
    }
    _reduceMotion = shouldReduceMotion;
    if (_reduceMotion) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _BackdropPainter()),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _WaterMotionPainter(
                  phase: _controller.value,
                  opacity: widget.opacity,
                  shaders: _shaders,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fondo estático: degradado y halos. Se pinta una sola vez por tamaño.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF071820),
            Color(0xFF0E3A40),
            Color(0xFF123840),
            Color(0xFF08161C),
          ],
          stops: [0, 0.34, 0.68, 1],
        ).createShader(bounds),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.18, size.height * 0.16),
        width: size.width * 0.9,
        height: size.height * 0.42,
      ),
      Paint()..color = const Color(0xFF1AA18C).withValues(alpha: 0.09),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.82, size.height * 0.78),
        width: size.width * 1.05,
        height: size.height * 0.5,
      ),
      Paint()..color = const Color(0xFF2E5EA8).withValues(alpha: 0.07),
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}

/// Cachea shaders costosos para no recrearlos en cada cuadro.
class _AtmosphereShaders {
  final Map<String, Shader> _sheets = {};

  Shader sheet({
    required Rect rect,
    required double opacity,
    required int index,
  }) {
    final key =
        '${rect.size.width.toStringAsFixed(1)}x'
        '${rect.size.height.toStringAsFixed(1)}|$opacity|$index';
    if (_sheets.length > 8) _sheets.clear();
    return _sheets.putIfAbsent(key, () {
      const tops = [Color(0xFF3C9F9C), Color(0xFF348FA0), Color(0xFF287A84)];
      const bottoms = [Color(0xFF10272B), Color(0xFF0E2229), Color(0xFF081316)];
      final topAlpha = [0.2, 0.16, 0.12][index] * opacity;
      final bottomAlpha = [0.05, 0.04, 0.03][index] * opacity;
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          tops[index % tops.length].withValues(alpha: topAlpha),
          bottoms[index % bottoms.length].withValues(alpha: bottomAlpha),
        ],
      ).createShader(rect);
    });
  }
}

class _WaterMotionPainter extends CustomPainter {
  _WaterMotionPainter({
    required this.phase,
    required this.opacity,
    required this.shaders,
  });

  final double phase;
  final double opacity;
  final _AtmosphereShaders shaders;

  static const double _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final temporal = _tau * phase;
    final drift = math.sin(temporal);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-0.6 + drift * 0.22, -1),
          end: Alignment(0.8, 1.1 - drift * 0.1),
          colors: [
            const Color(0xFF1A9A94).withValues(alpha: 0.14 * opacity),
            const Color(0xFF0C3036).withValues(alpha: 0.02 * opacity),
            const Color(0xFF245888).withValues(alpha: 0.12 * opacity),
          ],
        ).createShader(Offset.zero & size),
    );

    // Una ola lenta y baja. Textura de agua, sin ocupar la vista.
    _drawLiquidSheet(
      canvas,
      size,
      baseline: 0.62,
      amplitude: size.height * 0.018,
      phaseOffset: 0.6,
      index: 1,
      temporal: temporal,
    );
  }

  void _drawLiquidSheet(
    Canvas canvas,
    Size size, {
    required double baseline,
    required double amplitude,
    required double phaseOffset,
    required int index,
    required double temporal,
  }) {
    final steps = _stepsFor(size);
    double waveY(double progress) {
      final primary = math.sin(progress * _tau + temporal + phaseOffset);
      return size.height * baseline + primary * amplitude;
    }

    final surface = Path();
    for (var step = 0; step <= steps; step++) {
      final progress = step / steps;
      final x = progress * size.width;
      if (step == 0) {
        surface.moveTo(x, waveY(progress));
      } else {
        surface.lineTo(x, waveY(progress));
      }
    }
    surface
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final sheetBounds = Rect.fromLTWH(
      0,
      size.height * (baseline - 0.05),
      size.width,
      size.height * (1 - baseline + 0.05),
    );
    canvas.drawPath(
      surface,
      Paint()
        ..shader = shaders.sheet(
          rect: sheetBounds,
          opacity: opacity * 0.55,
          index: index,
        ),
    );
    final crest = Path();
    for (var step = 0; step <= steps; step++) {
      final progress = step / steps;
      final x = progress * size.width;
      if (step == 0) {
        crest.moveTo(x, waveY(progress));
      } else {
        crest.lineTo(x, waveY(progress));
      }
    }
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0xFF8EE6D8).withValues(alpha: 0.14 * opacity),
    );
  }

  int _stepsFor(Size size) => (size.width / 28).clamp(24, 48).round();

  @override
  bool shouldRepaint(covariant _WaterMotionPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.opacity != opacity;
}
