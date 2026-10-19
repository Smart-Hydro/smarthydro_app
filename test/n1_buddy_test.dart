import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/brand.dart';
import 'package:smarthydro_app/features/assistant/n1_buddy.dart';
import 'package:smarthydro_app/shared/widgets/hydro_glyph.dart';

void main() {
  testWidgets('N1Buddy usa el glifo Asistente del rail, sin cara', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: N1Buddy(size: 56))),
      ),
    );

    expect(find.byType(N1Buddy), findsOneWidget);
    expect(find.byType(HydroGlyph), findsOneWidget);
    final glyph = tester.widget<HydroGlyph>(find.byType(HydroGlyph));
    expect(glyph.kind, HydroGlyphKind.asistente);
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
    expect(
      find.descendant(of: find.byType(N1Buddy), matching: find.byType(Icon)),
      findsNothing,
    );
  });

  testWidgets('N1Buddy cambia acento según mood', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: N1Buddy(size: 40, mood: N1BuddyMood.error)),
      ),
    );

    final glyph = tester.widget<HydroGlyph>(find.byType(HydroGlyph));
    expect(glyph.kind, HydroGlyphKind.asistente);
    expect(glyph.color.r, IkoluColors.warning.r);
    expect(glyph.color.g, IkoluColors.warning.g);
    expect(glyph.color.b, IkoluColors.warning.b);
  });
}
