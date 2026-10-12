import 'package:flutter/material.dart';

/// Identidad de marca Ikolu (ikolu.smarthydro.app).
///
/// Paleta extraída del sitio y del logo: navy profundo + cyan de agua.
/// El menta histórico de la app se reserva para el estado "conectado"
/// (semántica de estado), mientras el cyan es el acento de marca e
/// interacción.
class IkoluColors {
  const IkoluColors._();

  /// Acento de marca e interacción (botones, links, nav, loaders).
  static const cyan = Color(0xFF00C8FF);

  /// Cyan suavizado para tintes y brillos sobre fondos oscuros.
  static const cyanSoft = Color(0xFF6FDFFF);

  /// Azul navy del logo: superficies de marca y gradientes.
  static const navy = Color(0xFF1F3461);

  /// Navy profundo del ícono de la app.
  static const navyDeep = Color(0xFF10213A);

  /// Estado "conectado/en línea" (semántico, no de marca).
  static const connected = Color(0xFF66E0C2);

  static const warning = Color(0xFFFFC46B);
  static const incident = Color(0xFFFF847A);
  static const info = Color(0xFF69B9FF);
}

/// La gota Ikolu como marca gráfica (transparente, lista para fondos oscuros).
class IkoluMark extends StatelessWidget {
  const IkoluMark({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ikolu Smart Hydro',
      child: Image.asset(
        'assets/branding/ikolu_drop.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Marca compacta para cabeceras: gota + wordmark "ikolu".
class IkoluBrand extends StatelessWidget {
  const IkoluBrand({this.size = 26, this.showTagline = false, super.key});

  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IkoluMark(size: size),
        SizedBox(width: size * 0.34),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ikolu',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: size * 0.62,
                letterSpacing: -0.4,
                height: 1,
              ),
            ),
            if (showTagline)
              Text(
                'SMART HYDRO',
                style: TextStyle(
                  color: IkoluColors.cyanSoft.withValues(alpha: 0.75),
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: size * 0.09,
                  height: 1.2,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
