import 'package:flutter/material.dart';

PageRoute<T> hydroPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      final enter = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final leave = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.72).animate(leave),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.018, 0),
          ).animate(leave),
          child: FadeTransition(
            opacity: enter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.035, 0.012),
                end: Offset.zero,
              ).animate(enter),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
