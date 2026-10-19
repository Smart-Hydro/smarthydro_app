import 'package:flutter/material.dart';

import '../ui/hydro_ui.dart';

/// Los Scaffold son transparentes sobre el fondo de la app: la página que
/// sale se desvanece para no verse encimada con la que entra.
PageRoute<T> hydroPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: HydroMotion.page,
    reverseTransitionDuration: HydroMotion.pageReverse,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final enter = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: ReverseAnimation(
          CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOut),
        ),
        child: FadeTransition(
          opacity: enter,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(enter),
            child: child,
          ),
        ),
      );
    },
  );
}
