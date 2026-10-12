import 'package:flutter/material.dart';

/// Colores institucionales de Chile, atenuados para UI (no bandera literal).
abstract final class ChilePalette {
  static const blue = Color(0xFF0039A6);
  static const red = Color(0xFFD52B1E);
  static const white = Color(0xFFF5F5F5);
  static const gold = Color(0xFFC9A227);

  /// Azul institucional suavizado sobre fondos oceánicos.
  static const inkBlue = Color(0xFF4A7BC8);

  /// Rojo institucional suavizado (acentos, nunca estado crítico).
  static const inkRed = Color(0xFFE07068);

  static Color blueWash([double alpha = 0.12]) => blue.withValues(alpha: alpha);
  static Color redWash([double alpha = 0.10]) => red.withValues(alpha: alpha);
  static Color goldWash([double alpha = 0.18]) => gold.withValues(alpha: alpha);
}

/// Franja sutil azul → blanco → rojo para contexto normativo DGA/SMA.
class ChileAccentBar extends StatelessWidget {
  const ChileAccentBar({
    this.height = 3,
    this.radius = 999,
    this.opacity = 0.55,
    super.key,
  });

  final double height;
  final double radius;
  final double opacity;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [
            ChilePalette.blue,
            ChilePalette.white,
            ChilePalette.red,
          ],
          stops: [0.0, 0.48, 1.0],
        ),
      ),
      child: SizedBox(height: height, width: double.infinity),
    ),
  );
}
