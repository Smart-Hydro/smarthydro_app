import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../portfolio3d_view.dart';

/// Pase de cartel entre el mapa y el resumen.
///
/// El iframe no se deja debajo del resumen: mientras el cartel entra,
/// el visor se apaga para que el gesto llegue a la lista.
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
    duration: const Duration(milliseconds: 620),
  );
  var _covered = false;
  var _atTop = true;

  @override
  void initState() {
    super.initState();
    _board.addListener(_onTick);
    _board.addStatusListener((status) {
      final covered = status == AnimationStatus.completed;
      if (covered == _covered || !mounted) return;
      setState(() => _covered = covered);
      if (covered) portfolio3dDim(0);
    });
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
      setState(() => _covered = true);
      portfolio3dDim(0);
      return;
    }
    _board.forward();
  }

  void _toMap() {
    if (_board.value == 0 || _board.status == AnimationStatus.reverse) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _board.value = 0;
      setState(() => _covered = false);
      portfolio3dDim(1);
      return;
    }
    portfolio3dDim(0);
    setState(() => _covered = false);
    _board.reverse();
  }

  double _rise(double raw) {
    const start = 0.12;
    if (raw <= start) return 0;
    final span = (raw - start) / (1 - start);
    return Curves.easeOutCubic.transform(span);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = constraints.maxHeight;
        return Stack(
          children: [
            if (!_covered)
              Positioned.fill(child: widget.map(context, _toSummary)),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _board,
                builder: (context, _) {
                  final rise = _rise(_board.value);
                  if (rise == 0 && _board.value == 0) {
                    return const SizedBox.shrink();
                  }
                  return Transform.translate(
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
                          decoration: BoxDecoration(
                            color: Color(
                              0xFF102226,
                            ).withValues(alpha: rise > 0.98 ? 0.16 : 0.94),
                            boxShadow: rise > 0.98
                                ? const []
                                : const [
                                    BoxShadow(
                                      color: Color(0x66000000),
                                      blurRadius: 28,
                                      offset: Offset(0, -10),
                                    ),
                                  ],
                          ),
                          child: widget.summary(context, _toMap),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
