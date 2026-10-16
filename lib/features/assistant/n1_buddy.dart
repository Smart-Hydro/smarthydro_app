import 'package:flutter/material.dart';

import '../../core/brand.dart';

/// Estado visual del compañero N1.
enum N1BuddyMood { idle, thinking, error, proud }

/// Avatar simple del tip N1: círculo cyan + icono smart_toy.
/// Sin cara, ojos ni pupilas que miren.
class N1Buddy extends StatelessWidget {
  const N1Buddy({
    this.size = 56,
    this.mood = N1BuddyMood.idle,
    super.key,
  });

  final double size;
  final N1BuddyMood mood;

  @override
  Widget build(BuildContext context) {
    final accent = switch (mood) {
      N1BuddyMood.error => IkoluColors.warning,
      N1BuddyMood.thinking => IkoluColors.info,
      N1BuddyMood.proud => IkoluColors.connected,
      N1BuddyMood.idle => IkoluColors.cyan,
    };
    final iconOpacity = switch (mood) {
      N1BuddyMood.thinking => 0.72,
      N1BuddyMood.error => 0.95,
      _ => 0.92,
    };

    return Semantics(
      label: 'N1',
      child: SizedBox(
        key: const ValueKey('n1-buddy'),
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.95),
                IkoluColors.cyan.withValues(alpha: 0.85),
                const Color(0xFF1A8FB8),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: mood == N1BuddyMood.error ? 0.42 : 0.22,
              ),
              width: mood == N1BuddyMood.error ? 2 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: size * 0.22,
                offset: Offset(0, size * 0.08),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.smart_toy_outlined,
              size: size * 0.48,
              color: Color(0xFF071416).withValues(alpha: iconOpacity),
            ),
          ),
        ),
      ),
    );
  }
}
