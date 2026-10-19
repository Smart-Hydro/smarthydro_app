import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/assistant/n1_buddy.dart';

void main() {
  testWidgets('N1Buddy es un cristal de agua sin cara', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: N1Buddy(size: 56))),
      ),
    );

    expect(find.byKey(const ValueKey('n1-buddy')), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('n1-buddy')),
        matching: find.byType(DecoratedBox),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('n1-buddy')),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('n1-buddy')),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
  });

  testWidgets('N1Buddy cambia acento según mood', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: N1Buddy(size: 40, mood: N1BuddyMood.error)),
      ),
    );

    final deco = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('n1-buddy')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final box = deco.decoration as BoxDecoration;
    expect(box.shape, BoxShape.circle);
    // Error usa borde/anillo más marcado (warning tint).
    expect(box.border, isNotNull);
  });
}
