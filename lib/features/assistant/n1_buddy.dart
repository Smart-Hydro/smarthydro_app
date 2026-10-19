import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/brand.dart';

/// Estado visual del compañero N1.
enum N1BuddyMood { idle, thinking, error, proud }

/// Marca de N1: disco de vidrio oscuro y un cristal de agua.
/// Sin cara, ojos ni icono de aplicación.
class N1Buddy extends StatelessWidget {
  const N1Buddy({this.size = 56, this.mood = N1BuddyMood.idle, super.key});

  final double size;
  final N1BuddyMood mood;

  @override
  Widget build(BuildContext context) {
    final accent = switch (mood) {
      N1BuddyMood.error => IkoluColors.warning,
      N1BuddyMood.thinking => IkoluColors.info,
      N1BuddyMood.proud => IkoluColors.connected,
      N1BuddyMood.idle => IkoluColors.cyan,
    };
    final markAlpha = switch (mood) {
      N1BuddyMood.thinking => 0.62,
      N1BuddyMood.error => 0.95,
      _ => 0.9,
    };

    return Semantics(
      label: 'N1',
      child: SizedBox(
        key: const ValueKey('n1-buddy'),
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A3038), Color(0xFF0C1A20)],
            ),
            border: Border.all(
              color: accent.withValues(
                alpha: mood == N1BuddyMood.error ? 0.95 : 0.72,
              ),
              width: mood == N1BuddyMood.error ? 1.8 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.16),
                blurRadius: size * 0.12,
                offset: Offset(0, size * 0.04),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _N1MarkPainter(accent.withValues(alpha: markAlpha)),
          ),
        ),
      ),
    );
  }
}

/// Cristal de agua. Dos aristas, sin puntos que se lean como ojos.
class _N1MarkPainter extends CustomPainter {
  _N1MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.shortestSide * 0.065)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;
    final c = size.center(Offset.zero);
    final w = size.width * 0.22;
    final h = size.height * 0.18;
    final crystal = Path()
      ..moveTo(c.dx, c.dy - h * 1.65)
      ..lineTo(c.dx + w, c.dy - h * 0.05)
      ..lineTo(c.dx, c.dy + h * 1.2)
      ..lineTo(c.dx - w, c.dy - h * 0.05)
      ..close();
    canvas.drawPath(crystal, stroke);
    canvas.drawLine(
      Offset(c.dx - w * 0.62, c.dy - h * 0.15),
      Offset(c.dx + w * 0.62, c.dy + h * 0.22),
      stroke..strokeWidth = math.max(1, size.shortestSide * 0.04),
    );
  }

  @override
  bool shouldRepaint(covariant _N1MarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
