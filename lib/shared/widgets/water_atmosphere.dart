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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B171B), Color(0xFF10272B), Color(0xFF081316)],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      Offset(size.width * 0.14, size.height * 0.2),
      size.shortestSide * 0.42,
      Paint()..color = const Color(0xFF1AA18C).withValues(alpha: 0.07),
    );
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.84),
      size.shortestSide * 0.47,
      Paint()..color = const Color(0xFF4C7CDD).withValues(alpha: 0.055),
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
      final topAlpha = [0.16, 0.13, 0.1][index] * opacity;
      final bottomAlpha = [0.08, 0.07, 0.06][index] * opacity;
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

    // Solo dos capas profundas, oscuras y suaves. Cero rayos de luz duros ni burbujas de fiesta.
    _drawLiquidSheet(
      canvas,
      size,
      baseline: 0.72,
      amplitude: size.height * 0.02,
      phaseOffset: 0.8,
      index: 0,
      temporal: temporal * 0.7,
    );
    _drawLiquidSheet(
      canvas,
      size,
      baseline: 0.82,
      amplitude: size.height * 0.015,
      phaseOffset: 2.1,
      index: 1,
      temporal: temporal * 1.2,
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
          opacity: opacity * 0.5,
          index: index,
        ),
    );
  }


  int _stepsFor(Size size) => (size.width / 8).clamp(80, 180).round();

  @override
  bool shouldRepaint(covariant _WaterMotionPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.opacity != opacity;
}
