import 'package:flutter/material.dart';

/// Paso de la cuadrícula base. Coincide con el esquema de telemetría.
const workstationGridStep = 16.0;

/// Línea fina y liviana: se lee como estación de trabajo, sin adornos.
const workstationGridLine = Color(0x0AE7F4F2);

/// Fondo base de toda la app: tono oscuro limpio + cuadrícula fina.
/// Sin halos, óvalos ni olas.
class WorkstationBackdrop extends StatelessWidget {
  const WorkstationBackdrop({super.key});

  static const base = Color(0xFF081216);

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _WorkstationGridPainter(),
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}

class _WorkstationGridPainter extends CustomPainter {
  const _WorkstationGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = WorkstationBackdrop.base);

    final line = Paint()
      ..color = workstationGridLine
      ..strokeWidth = 1;
    const step = workstationGridStep;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkstationGridPainter oldDelegate) => false;
}
