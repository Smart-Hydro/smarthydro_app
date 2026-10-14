import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/brand.dart';

/// Superficie translúcida. Sin borde: el brillo superior separa la pieza del fondo.
class HydroGlass extends StatelessWidget {
  const HydroGlass({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.frosted = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;

  /// Vidrio claro y sobrio. El fondo de la app se lee a través.
  final bool frosted;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final body = Ink(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: frosted
              ? [
                  const Color(0xFFF7FBFA).withValues(alpha: 0.16),
                  const Color(0xFF1A3C44).withValues(alpha: 0.42),
                ]
              : [
                  const Color(0xFF132E35).withValues(alpha: 0.78),
                  const Color(0xFF09171B).withValues(alpha: 0.88),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: frosted ? 0.12 : 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: IkoluColors.cyan.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        splashColor: IkoluColors.cyan.withValues(alpha: 0.1),
        highlightColor: IkoluColors.cyan.withValues(alpha: 0.05),
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
        ..color = IkoluColors.cyan.withValues(alpha: 0.16)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final head = travel * size.width;
    canvas.drawLine(
      Offset(head - 28, y),
      Offset(head, y),
      Paint()
        ..color = IkoluColors.cyan.withValues(alpha: 0.85)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LoadingLinePainter oldDelegate) =>
      oldDelegate.travel != travel;
}

/// Barra lineal de carga con identidad Ikolu: una gota cyan que
/// recorre una pista fina. Reemplaza al LinearProgressIndicator genérico
/// en cabeceras y listas mientras se cargan datos.
class HydroLinearBar extends StatefulWidget {
  const HydroLinearBar({this.height = 3, super.key});

  final double height;

  @override
  State<HydroLinearBar> createState() => _HydroLinearBarState();
}

class _HydroLinearBarState extends State<HydroLinearBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
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
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _LinearBarPainter(travel: _controller.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _LinearBarPainter extends CustomPainter {
  const _LinearBarPainter({required this.travel});

  final double travel;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    // Pista fina cyan muy tenue.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = IkoluColors.cyan.withValues(alpha: 0.12)
        ..strokeWidth = size.height
        ..strokeCap = StrokeCap.round,
    );
    // Estela: degradado que sigue a la gota.
    final head = travel * size.width;
    final tailLen = size.width * 0.28;
    final tailStart = (head - tailLen).clamp(0.0, size.width);
    canvas.drawLine(
      Offset(tailStart, y),
      Offset(head, y),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(tailStart, y),
          end: Alignment(head, y),
          colors: [
            IkoluColors.cyan.withValues(alpha: 0),
            IkoluColors.cyan.withValues(alpha: 0.9),
          ],
        ).createShader(Rect.fromPoints(Offset(tailStart, y), Offset(head, y)))
        ..strokeWidth = size.height
        ..strokeCap = StrokeCap.round,
    );
    // Gota cabeza brillante.
    canvas.drawCircle(
      Offset(head, y),
      size.height * 0.9,
      Paint()..color = const Color(0xFFEFFFFA),
    );
  }

  @override
  bool shouldRepaint(covariant _LinearBarPainter oldDelegate) =>
      oldDelegate.travel != travel;
}

/// Spinner circular de marca Ikolu: anillo cyan con una gota
/// brillante en cabeza, para botones en estado de envío. Reemplaza al
/// CircularProgressIndicator genérico.
class HydroSpinner extends StatefulWidget {
  const HydroSpinner({this.size = 20, this.strokeWidth = 2.4, super.key});

  final double size;
  final double strokeWidth;

  @override
  State<HydroSpinner> createState() => _HydroSpinnerState();
}

class _HydroSpinnerState extends State<HydroSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 0.25;
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
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: CustomPaint(
            painter: _SpinnerPainter(stroke: widget.strokeWidth),
            size: Size(widget.size, widget.size),
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.stroke});

  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;
    // Anillo base tenue.
    canvas.drawArc(
      rect.deflate(stroke / 2),
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = IkoluColors.cyan.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    // Arco cyan (~270°) que da la sensación de giro.
    canvas.drawArc(
      rect.deflate(stroke / 2),
      -math.pi / 2,
      math.pi * 1.5,
      false,
      Paint()
        ..color = IkoluColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    // Gota brillante en la cabeza del arco.
    canvas.drawCircle(
      Offset(center.dx, center.dy - radius),
      stroke * 0.55,
      Paint()..color = const Color(0xFFEFFFFA),
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter oldDelegate) =>
      oldDelegate.stroke != stroke;
}
