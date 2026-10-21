import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/shared/ui/capture_point_picker.dart';

void main() {
  const points = [
    {'id': 7, 'title': 'Pozo Norte', 'code_dga': 'OB-1603-392'},
    {
      'id': 9,
      'title': 'Canal Sur',
      'dga': {'code_dga': 'OB-11'},
    },
    {'id': 3, 'title': 'Estero Viejo'},
  ];

  test('filtra por nombre y por código DGA', () {
    expect(filterCapturePoints(points, 'norte').single['id'], 7);
    expect(filterCapturePoints(points, 'OB-11').single['id'], 9);
    expect(filterCapturePoints(points, '1603').single['title'], 'Pozo Norte');
    expect(filterCapturePoints(points, '  ').length, 3);
    expect(capturePointCode(points[2]), isNull);
    expect(capturePointCode(points[0]), 'OB-1603-392');
    expect(capturePointCode(points[1]), 'OB-11');
  });

  testWidgets('el modal busca y elige el punto con su código DGA', (
    tester,
  ) async {
    var selected = 3;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CapturePointFilter(
                points: points,
                selectedId: selected,
                onChanged: (id) => setState(() => selected = id),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Estero Viejo'), findsOneWidget);
    expect(find.text('OB-1603-392'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('capture-point-filter')));
    await tester.pumpAndSettle();

    expect(find.text('Elegir punto de captación'), findsOneWidget);
    expect(find.text('Pozo Norte'), findsOneWidget);
    expect(find.text('OB-1603-392'), findsOneWidget);
    expect(find.text('OB-11'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('capture-point-search')),
      'ob-11',
    );
    await tester.pump();
    expect(find.text('Canal Sur'), findsOneWidget);
    expect(find.text('Pozo Norte'), findsNothing);

    await tester.tap(find.text('Canal Sur'));
    await tester.pumpAndSettle();
    expect(selected, 9);
    expect(find.text('Elegir punto de captación'), findsNothing);
    expect(find.text('Canal Sur'), findsOneWidget);
    expect(find.text('OB-11'), findsOneWidget);
  });

  testWidgets('el chip del punto es una sola línea: nombre y código', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CapturePointFilter(
            points: points,
            selectedId: 7,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    final name = tester.getRect(find.text('Pozo Norte'));
    final code = tester.getRect(find.text('OB-1603-392'));
    expect(code.left, greaterThan(name.right));
    expect(code.center.dy, closeTo(name.center.dy, 4));
  });
}
