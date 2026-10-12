import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/point_link.dart';
import 'package:smarthydro_app/features/dashboard/widgets/portfolio_network.dart';

void main() {
  testWidgets('muestra saludo y mapa isométrico de cartera', (tester) async {
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
            userName: 'Camila',
            onPointSelected: (point) => selected = point,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Hola, Camila'), findsOneWidget);
    expect(find.textContaining('mapa isométrico'), findsOneWidget);
    expect(find.textContaining('en línea'), findsOneWidget);
    expect(find.textContaining('Tensión'), findsOneWidget);

    await tester.tapAt(const Offset(200, 220));
    await tester.pump();
    expect(tester.takeException(), isNull);
    if (selected != null) {
      expect(selected!['title'], isNotEmpty);
    }
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
