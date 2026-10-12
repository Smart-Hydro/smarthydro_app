import 'dart:async';

import 'package:flutter/material.dart';

class HydroEntrance extends StatefulWidget {
  const HydroEntrance({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.slideOffset = const Offset(0, 0.045),
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Desplazamiento relativo antes de aparecer (p. ej. lateral en tabs).
  final Offset slideOffset;

  @override
  State<HydroEntrance> createState() => _HydroEntranceState();
}

class _HydroEntranceState extends State<HydroEntrance> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final shown = reduceMotion || _visible;
    final duration = reduceMotion ? Duration.zero : widget.duration;
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: shown ? Offset.zero : widget.slideOffset,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
