import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/shared/widgets/workstation_backdrop.dart';

void main() {
  test('la cuadrícula base es fina y liviana', () {
    expect(workstationGridStep, 16);
    expect(workstationGridLine.a, lessThan(0.08));
    expect(workstationGridLine.a, greaterThan(0));
  });

  testWidgets('el fondo base pinta la cuadrícula sin WaterAtmosphere', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [WorkstationBackdrop(), SizedBox.expand()],
          ),
        ),
      ),
    );

    expect(find.byType(WorkstationBackdrop), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
