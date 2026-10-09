import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Arma del Estado de Chile (escudo estilizado con estrella) para dar
/// contexto normativo al módulo de cumplimiento DGA / SMA.
class ChileShield extends StatelessWidget {
  const ChileShield({this.size = 30, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * 1.12),
    painter: _ChileShieldPainter(),
  );
}

class _ChileShieldPainter extends CustomPainter {
  const _ChileShieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final shield = Path()
      ..moveTo(0, 0)
      ..lineTo(width, 0)
      ..lineTo(width, height * 0.55)
      ..quadraticBezierTo(width, height * 0.9, width / 2, height)
      ..quadraticBezierTo(0, height * 0.9, 0, height * 0.55)
      ..close();

    canvas.save();
    canvas.clipPath(shield);

    final white = Paint()..color = const Color(0xFFF5F5F5);
    final blue = Paint()..color = const Color(0xFF0039A6);
    final red = Paint()..color = const Color(0xFFD52B1E);

    canvas.drawRect(Rect.fromLTWH(0, 0, width, height / 2), white);
    canvas.drawRect(Rect.fromLTWH(0, height / 2, width, height / 2), red);
    canvas.drawRect(Rect.fromLTWH(0, 0, width / 2, height / 2), blue);
    canvas.drawPath(
      _star(Offset(width * 0.25, height * 0.25), width * 0.17),
      Paint()..color = const Color(0xFFF5F5F5),
    );
    canvas.restore();

    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, width * 0.05)
        ..color = const Color(0xFFC9A227),
    );
  }

  Path _star(Offset center, double radius) {
    const points = 5;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final currentRadius = i.isEven ? radius : radius * 0.42;
      final angle = -math.pi / 2 + i * math.pi / points;
      final point = Offset(
        center.dx + math.cos(angle) * currentRadius,
        center.dy + math.sin(angle) * currentRadius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _ChileShieldPainter oldDelegate) => false;
}
