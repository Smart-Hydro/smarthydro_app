import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum HydroGlassIntensity { soft, standard, strong }

/// Superficie translúcida con glassmorphism. El brillo superior separa la pieza.
class HydroGlass extends StatelessWidget {
  const HydroGlass({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.intensity = HydroGlassIntensity.standard,
    this.accent,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final HydroGlassIntensity intensity;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? const Color(0xFF66E0C2);
    final blur = switch (intensity) {
      HydroGlassIntensity.soft => 6.0,
      HydroGlassIntensity.standard => 12.0,
      HydroGlassIntensity.strong => 18.0,
    };
    final fillAlpha = switch (intensity) {
      HydroGlassIntensity.soft => 0.55,
      HydroGlassIntensity.standard => 0.68,
      HydroGlassIntensity.strong => 0.78,
    };
    final borderAlpha = switch (intensity) {
      HydroGlassIntensity.soft => 0.1,
      HydroGlassIntensity.standard => 0.16,
      HydroGlassIntensity.strong => 0.22,
    };

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: tint.withValues(alpha: borderAlpha), width: 1),
    );

    final surface = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF17343C).withValues(alpha: fillAlpha),
                const Color(0xFF09171B).withValues(alpha: fillAlpha + 0.08),
              ],
            ),
            border: Border.all(
              color: tint.withValues(alpha: borderAlpha),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 1.2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(radius),
                    ),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.18),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );

    final body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: tint.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: surface,
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        splashColor: tint.withValues(alpha: 0.1),
        highlightColor: tint.withValues(alpha: 0.05),
        onTap: onTap,
        child: body,
      ),
    );
  }
}

/// Columna de contenido. El fondo puede seguir a ancho completo.
class HydroFrame extends StatelessWidget {
  const HydroFrame({required this.child, super.key});

  final Widget child;

  static const maxWidth = 1080.0;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Línea de agua en lugar de un indicador circular.
class HydroLoading extends StatefulWidget {
  const HydroLoading({super.key});

  @override
  State<HydroLoading> createState() => _HydroLoadingState();
}

class _HydroLoadingState extends State<HydroLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 0.5;
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
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final travel = _controller.value;
          return SizedBox(
            width: 120,
            height: 8,
            child: CustomPaint(painter: _LoadingLinePainter(travel: travel)),
          );
        },
      ),
    );
  }
}

class _LoadingLinePainter extends CustomPainter {
  const _LoadingLinePainter({required this.travel});

  final double travel;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = const Color(0xFF66E0C2).withValues(alpha: 0.16)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final head = travel * size.width;
    canvas.drawLine(
      Offset(head - 28, y),
      Offset(head, y),
      Paint()
        ..color = const Color(0xFF66E0C2).withValues(alpha: 0.85)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LoadingLinePainter oldDelegate) =>
      oldDelegate.travel != travel;
}
