import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/widgets/hydraulic_board.dart';

void main() {
  testWidgets('scroll hacia abajo sube el resumen y luego vuelve', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HydraulicBoard(
            map: (context, toSummary) => GestureDetector(
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 200) toSummary();
              },
              child: const SizedBox.expand(child: Text('MAPA')),
            ),
            summary: (context, toMap) => ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: const [
                SizedBox(height: 40, child: Text('RESUMEN')),
                SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('MAPA'), findsOneWidget);
    expect(find.text('RESUMEN'), findsNothing);

    await tester.fling(find.text('MAPA'), const Offset(0, 280), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('RESUMEN'), findsOneWidget);
    final travel = tester
        .widgetList<Transform>(find.byType(Transform))
        .map((item) => item.transform.getTranslation().y)
        .reduce((a, b) => a > b ? a : b);
    final height = tester.getSize(find.byType(HydraulicBoard)).height;
    expect(travel, greaterThan(12));
    expect(travel, lessThan(height - 12));

    await tester.pumpAndSettle();
    expect(find.text('MAPA'), findsNothing);
    expect(find.text('RESUMEN'), findsOneWidget);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.text('RESUMEN')),
        scrollDelta: const Offset(0, -48),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('MAPA'), findsOneWidget);
  });
}
