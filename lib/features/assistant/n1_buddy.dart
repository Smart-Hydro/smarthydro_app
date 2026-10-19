import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../shared/widgets/hydro_glyph.dart';

/// Estado visual del compañero N1.
enum N1BuddyMood { idle, thinking, error, proud }

/// Misma marca que el atajo Asistente del rail y del hub Apps.
class N1Buddy extends StatelessWidget {
  const N1Buddy({
    this.size = 56,
    this.mood = N1BuddyMood.idle,
    this.keyPrefix = 'n1-buddy',
    super.key,
  });

  final double size;
  final N1BuddyMood mood;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final accent = switch (mood) {
      N1BuddyMood.error => IkoluColors.warning,
      N1BuddyMood.thinking => IkoluColors.info,
      N1BuddyMood.proud => IkoluColors.connected,
      N1BuddyMood.idle => IkoluColors.cyanSoft,
    };
    final markAlpha = switch (mood) {
      N1BuddyMood.thinking => 0.62,
      N1BuddyMood.error => 0.95,
      _ => 0.94,
    };

    return Semantics(
      label: 'N1',
      child: HydroGlyph(
        kind: HydroGlyphKind.asistente,
        color: accent.withValues(alpha: markAlpha),
        size: size,
        keyPrefix: keyPrefix,
      ),
    );
  }
}
