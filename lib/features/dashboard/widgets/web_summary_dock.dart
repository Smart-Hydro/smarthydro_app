import 'package:flutter/material.dart';

import '../../../shared/ui/hydro_ui.dart';

/// Mapa a todo el ancho, con el resumen de escritorio que se desliza a la
/// derecha. El mango de cristal abre y cierra el panel.
class WebSummaryDock extends StatefulWidget {
  const WebSummaryDock({
    required this.open,
    required this.onOpenChanged,
    required this.map,
    required this.summary,
    super.key,
  });

  static const panelWidth = 380.0;
  static const _slide = Duration(milliseconds: 320);

  final bool open;
  final ValueChanged<bool> onOpenChanged;
  final Widget map;
  final Widget summary;

  @override
  State<WebSummaryDock> createState() => _WebSummaryDockState();
}

class _WebSummaryDockState extends State<WebSummaryDock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: WebSummaryDock._slide,
      value: widget.open ? 1 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _snapIfReduced();
  }

  @override
  void didUpdateWidget(WebSummaryDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = widget.open ? 1 : 0;
      return;
    }
    if (widget.open) {
      _slide.forward();
    } else {
      _slide.reverse();
    }
  }

  void _snapIfReduced() {
    if (!MediaQuery.disableAnimationsOf(context)) return;
    final target = widget.open ? 1.0 : 0.0;
    if (_slide.value != target) _slide.value = target;
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _slide,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) {
        final open = curve.value;
        final panel = WebSummaryDock.panelWidth * open;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              right: panel,
              child: widget.map,
            ),
            if (open > 0)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: WebSummaryDock.panelWidth,
                child: ClipRect(
                  child: Transform.translate(
                    offset: Offset(
                      WebSummaryDock.panelWidth * (1 - open),
                      0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(
                          width: 1,
                          child: ColoredBox(color: Color(0x1AFFFFFF)),
                        ),
                        Expanded(child: widget.summary),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              bottom: 0,
              right: panel,
              child: Center(
                child: _WebSummaryHandle(
                  open: widget.open,
                  onTap: () => widget.onOpenChanged(!widget.open),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WebSummaryHandle extends StatelessWidget {
  const _WebSummaryHandle({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: open ? 'Ocultar resumen' : 'Resumen',
      child: Material(
        key: const ValueKey('web-summary-toggle'),
        color: const Color(0xD6081216),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(14),
          ),
          child: HydroGlassLight(
            padding: EdgeInsets.fromLTRB(open ? 6 : 8, 12, 6, 12),
            radius: 14,
            strength: 1.05,
            child: open
                ? const Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: Color(0xFFB7C6C4),
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chevron_left_rounded,
                        size: 18,
                        color: Color(0xFF8EE6D8),
                      ),
                      SizedBox(height: 6),
                      RotatedBox(
                        quarterTurns: 3,
                        child: Text(
                          'Resumen',
                          style: TextStyle(
                            color: Color(0xFFF4FBFA),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
