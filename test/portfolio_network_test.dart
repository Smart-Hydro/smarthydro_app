import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/point_link.dart';
import 'package:smarthydro_app/features/dashboard/widgets/portfolio_network.dart';

void main() {
  testWidgets('muestra el visor isométrico de captaciones', (tester) async {
    Map<String, dynamic>? selected;
    final points = [
      {
        'title': 'Pozo Norte',
        'type_dga': 'SUBTERRANEO',
        'latest_telemetry': {
          'date_time_medition': DateTime.now().toIso8601String(),
          'days_not_connection': 0,
        },
      },
      {
        'title': 'Canal Sur',
        'type_dga': 'SUPERFICIAL',
        'latest_telemetry': {'is_error': true},
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortfolioNetwork(
            points: points,
            onPointSelected: (point) => selected = point,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Hola, Camila'), findsNothing);
    expect(find.text('Ciudad de telemetría'), findsNothing);
    expect(find.text('Puntos'), findsNothing);
    expect(find.text('Ir al detalle'), findsNothing);

    final canvas = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter != null,
    );
    final origin = tester.getTopLeft(canvas);
    final size = tester.getSize(canvas);
    Offset? hit;
    for (var y = 8.0; y < size.height && hit == null; y += 10) {
      for (var x = 8.0; x < size.width; x += 12) {
        final local = Offset(x, y);
        if (debugPortfolioHit(size, points, local) == 0) {
          hit = local;
          break;
        }
      }
    }
    expect(hit, isNotNull);
    await tester.tapAt(origin + hit!);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Pozo Norte'), findsOneWidget);
    expect(find.text('Ir al detalle'), findsOneWidget);
    expect(selected, isNull);

    await tester.tap(find.text('Ir al detalle'));
    await tester.pump();
    expect(selected?['title'], 'Pozo Norte');
    expect(tester.takeException(), isNull);
  });

  testWidgets('MiniIsoWell pinta sin errores', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MiniIsoWell(link: PointLink.connected, isSurface: false),
                MiniIsoWell(link: PointLink.incident, isSurface: true),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
