import 'package:flutter/material.dart';

/// Superficie translúcida. Sin borde: el brillo superior separa la pieza del fondo.
class HydroGlass extends StatelessWidget {
  const HydroGlass({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color: const Color(0xFF66E0C2).withValues(alpha: 0.12),
        width: 1,
      ),
    );
    final body = Ink(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF132E35).withValues(alpha: 0.78),
            const Color(0xFF09171B).withValues(alpha: 0.88),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF66E0C2).withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFF66E0C2).withValues(alpha: 0.03),
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
        splashColor: const Color(0xFF66E0C2).withValues(alpha: 0.1),
        highlightColor: const Color(0xFF66E0C2).withValues(alpha: 0.05),
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
