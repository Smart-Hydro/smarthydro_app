import 'dart:async';

import 'package:flutter/material.dart';

class HydroEntrance extends StatefulWidget {
  const HydroEntrance({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final shown = reduceMotion || _visible;
    final duration = reduceMotion ? Duration.zero : widget.duration;
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: shown ? Offset.zero : const Offset(0, 0.045),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
