import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/shared/widgets/liquid_nav.dart';

void main() {
  testWidgets('el conteo de no leídos queda en Avisos', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidNavBar(
            selectedIndex: 0,
            unreadCount: 3,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('Eventos'), matching: find.byType(Column))
            .first,
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('Apps'), matching: find.byType(Column))
            .first,
        matching: find.text('3'),
      ),
      findsNothing,
    );
  });
}
