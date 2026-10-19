import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../portfolio3d_view.dart';

/// El mapa queda vivo debajo del resumen. El cartel entra y sale
/// en un solo deslizamiento, sin apagar la superficie ni cambiar de color.
class HydraulicBoard extends StatefulWidget {
  const HydraulicBoard({required this.map, required this.summary, super.key});

  final Widget Function(BuildContext context, VoidCallback toSummary) map;
  final Widget Function(BuildContext context, VoidCallback toMap) summary;

  @override
  State<HydraulicBoard> createState() => _HydraulicBoardState();
}

class _HydraulicBoardState extends State<HydraulicBoard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _board = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  var _atTop = true;

  @override
  void initState() {
    super.initState();
    _board.addListener(_onTick);
  }

  void _onTick() {
    final fade = _board.value < 0.18 ? 1 - _board.value / 0.18 : 0.0;
    portfolio3dDim(fade);
  }

  @override
  void dispose() {
    _board.removeListener(_onTick);
    portfolio3dDim(1);
    _board.dispose();
    super.dispose();
  }

  void _toSummary() {
    if (_board.value == 1 || _board.status == AnimationStatus.forward) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _board.value = 1;
      portfolio3dDim(0);
      return;
    }
    _board.forward();
  }

  void _toMap() {
    if (_board.value == 0 || _board.status == AnimationStatus.reverse) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _board.value = 0;
      portfolio3dDim(1);
      return;
    }
    _board.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = constraints.maxHeight;
        final map = widget.map(context, _toSummary);
        final summary = widget.summary(context, _toMap);
        return AnimatedBuilder(
          animation: _board,
          builder: (context, _) {
            final rise = Curves.easeInOutCubic.transform(_board.value);
            // Lo que queda tapado no anima: el mapa bajo el resumen abierto
            // y el resumen fuera de pantalla.
            final mapVisible = _board.value < 1;
            final summaryVisible = _board.value > 0;
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                TickerMode(
                  enabled: mapVisible,
                  child: RepaintBoundary(child: map),
                ),
                TickerMode(
                  enabled: summaryVisible,
                  child: Transform.translate(
                    offset: Offset(0, (1 - rise) * travel),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notice) {
                        if (notice.metrics.axis == Axis.vertical) {
                          _atTop = notice.metrics.pixels <= 1;
                        }
                        return false;
                      },
                      child: Listener(
                        onPointerSignal: (event) {
                          if (event is! PointerScrollEvent) return;
                          if (_board.value < 1 || !_atTop) return;
                          if (event.scrollDelta.dy < -24) _toMap();
                        },
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xFF102226),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 28,
                                offset: Offset(0, -10),
                              ),
                            ],
                          ),
                          child: summary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
