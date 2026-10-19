import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hydro_ui.dart';

/// Ancla la paleta a un panel (la columna de la red), no a toda la ventana.
class WellPaletteHost extends StatefulWidget {
  const WellPaletteHost({required this.child, super.key});

  final Widget child;

  static WellPaletteHostState? of(BuildContext context) =>
      context.findAncestorStateOfType<WellPaletteHostState>();

  @override
  State<WellPaletteHost> createState() => WellPaletteHostState();
}

class WellPaletteHostState extends State<WellPaletteHost> {
  Widget? _sheet;

  void show(Widget? sheet) {
    if (!mounted) return;
    if (identical(_sheet, sheet)) return;
    setState(() => _sheet = sheet);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        widget.child,
        if (_sheet != null) Positioned.fill(child: _sheet!),
      ],
    );
  }
}

/// Paleta sobre el pozo. En escritorio va al centro del panel; en el teléfono
/// es una hoja inferior como Historial.
class PointToolSheet extends StatelessWidget {
  const PointToolSheet({
    required this.title,
    required this.child,
    required this.onClose,
    this.subtitle,
    this.fromBottom = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback onClose;

  /// Hoja tipo Historial: se ancla abajo, mango y radio solo arriba.
  final bool fromBottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: fromBottom ? 0.55 : 0.38),
              ),
            ),
            fromBottom
                ? _bottomSheet(constraints)
                : _centeredCard(constraints),
          ],
        );
      },
    );
  }

  Widget _centeredCard(BoxConstraints constraints) {
    final wide = constraints.maxWidth >= 520;
    final width = math.min(
      constraints.maxWidth - (wide ? 32 : 16),
      640.0,
    );
    final height = math.min(
      constraints.maxHeight * 0.9,
      constraints.maxHeight - (wide ? 28 : 12),
    );
    return Center(
      child: _card(
        width: width.clamp(0, constraints.maxWidth),
        height: height.clamp(0, constraints.maxHeight),
        radius: BorderRadius.circular(22),
        handle: false,
      ),
    );
  }

  Widget _bottomSheet(BoxConstraints constraints) {
    final height = math.min(
      constraints.maxHeight * 0.9,
      math.max(0.0, constraints.maxHeight - 8),
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: _card(
        width: constraints.maxWidth,
        height: height,
        radius: const BorderRadius.vertical(top: Radius.circular(26)),
        handle: true,
      ),
    );
  }

  Widget _card({
    required double width,
    required double height,
    required BorderRadius radius,
    required bool handle,
  }) {
    return SizedBox(
      key: const Key('point-tool-sheet-card'),
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF12292F), Color(0xFF0B1B20)],
            ),
            borderRadius: radius,
            border: Border.all(
              color: HydroTone.accent.withValues(alpha: 0.16),
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x99000000), blurRadius: 30),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              children: [
                if (handle)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: SizedBox(
                      key: Key('point-tool-sheet-handle'),
                      width: 36,
                      height: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x29E8F2F1),
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, handle ? 10 : 14, 6, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: HydroTone.fog,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty)
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: HydroTone.faint,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('point-tool-sheet-close'),
                        tooltip: 'Cerrar',
                        onPressed: onClose,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: HydroTone.faint,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
