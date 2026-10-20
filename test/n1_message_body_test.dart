import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/assistant/n1_message_body.dart';

void main() {
  testWidgets('pinta el panel con aire, sin markdown ni viñetas', (tester) async {
    const raw = '''
*Riego Chile* · 13 puntos
*Por punto:*
• Riego Chile – Agricola Bayona – Matias Fischer · activo · sin ticket SLA · DGA no reporta DGA
*Desconectados: 0*
 *Te sugiero:* Sin acciones pendientes con estos datos.
''';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: N1MessageBody(text: raw),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('n1-msg-body')), findsOneWidget);
    expect(find.text('Riego Chile · 13 puntos'), findsOneWidget);
    expect(find.text('Matias Fischer'), findsOneWidget);
    expect(find.text('activo'), findsOneWidget);
    expect(find.text('sin ticket'), findsOneWidget);
    expect(find.text('Desconectados'), findsOneWidget);
    expect(find.text('Sugerencia'), findsOneWidget);
    expect(find.textContaining('*'), findsNothing);
    expect(find.textContaining('•'), findsNothing);
    expect(find.textContaining('sin ticket SLA'), findsNothing);

    final heading = tester.getRect(find.text('Riego Chile · 13 puntos'));
    final point = tester.getRect(find.text('Matias Fischer'));
    final suggest = tester.getRect(find.text('Sugerencia'));
    expect(point.top - heading.bottom, greaterThan(8));
    expect(suggest.top - point.bottom, greaterThan(12));
  });
}
