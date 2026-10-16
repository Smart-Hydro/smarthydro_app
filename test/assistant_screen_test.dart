import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/core/n1/n1_api.dart';
import 'package:smarthydro_app/core/n1/n1_config.dart';
import 'package:smarthydro_app/core/n1/n1_models.dart';
import 'package:smarthydro_app/features/assistant/assistant_screen.dart';

class _FakeN1Api extends N1Api {
  _FakeN1Api()
    : super(config: const N1Config(webAppUrl: 'https://example.test/exec'));

  N1Response askResult = const N1Response(ok: true, text: 'Respuesta N1');
  N1Response? pendingAsk;
  int askCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<N1Response> ask({
    required String token,
    required String requester,
    required String text,
    String? sessionId,
    List<int>? pointsAllowed,
  }) async {
    askCalls += 1;
    if (pendingAsk != null && askCalls == 1) return pendingAsk!;
    return askResult;
  }

  @override
  Future<N1Response> listFiles({
    required String token,
    required String requester,
    String? client,
    String? type,
    int limit = 20,
  }) async {
    return N1Response.fromJson({
      'ok': true,
      'files': [
        {
          'client': 'Iansa',
          'type': 'mensual',
          'period': '2026-09',
          'url': 'https://drive.google.com/file/d/demo',
        },
      ],
    });
  }

  @override
  Future<N1Response> createTicket({
    required String token,
    required String requester,
    required String title,
    required String description,
    required List<int> points,
    String priority = 'MEDIA',
    int? category,
    List<int>? pointsAllowed,
    bool dryRun = false,
  }) async {
    return N1Response.fromJson({'ok': true, 'ticket_id': 77});
  }
}

void main() {
  testWidgets('muestra chat y responde ask', (tester) async {
    final api = _FakeN1Api();
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantScreen(
          n1Api: api,
          session: const SmartHydroSession(
            token: 'tok',
            user: {'email': 'cliente@empresa.cl', 'first_name': 'Ana'},
          ),
          points: const [
            {'id': 4, 'title': 'P4'},
          ],
        ),
      ),
    );

    expect(find.textContaining('SmartHydro N1'), findsOneWidget);
    expect(find.byKey(const ValueKey('n1-buddy')), findsOneWidget);
    expect(find.text('N1 · SmartHydro'), findsOneWidget);
    expect(find.text('Pedir reporte'), findsOneWidget);
    expect(find.text('Listar archivos'), findsOneWidget);
    expect(find.text('Crear ticket'), findsOneWidget);
    expect(find.text('Pregunta a N1…'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'cómo está P4');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('cómo está P4'), findsOneWidget);
    expect(find.text('Respuesta N1'), findsOneWidget);
    expect(api.askCalls, 1);
  });

  testWidgets('job pending muestra estado ⏳ y permite reconsultar', (
    tester,
  ) async {
    final api = _FakeN1Api()
      ..pendingAsk = const N1Response(
        ok: true,
        text: '⏳ cargando datos, reintenta en un momento',
        pending: true,
        async: true,
      )
      ..askResult = const N1Response(ok: true, text: 'Listo: todo OK');

    await tester.pumpWidget(
      MaterialApp(
        home: AssistantScreen(
          n1Api: api,
          session: const SmartHydroSession(
            token: 'tok',
            user: {'email': 'cliente@empresa.cl'},
          ),
          points: const [],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'estado');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('⏳'), findsWidgets);
    expect(find.text('Reconsultar'), findsOneWidget);

    // El auto-reconsulta programa un Timer de 8s.
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Listo: todo OK'), findsOneWidget);
    expect(api.askCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('listar archivos muestra chip de link', (tester) async {
    final api = _FakeN1Api();
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantScreen(
          n1Api: api,
          session: const SmartHydroSession(
            token: 'tok',
            user: {'email': 'cliente@empresa.cl'},
          ),
          points: const [],
        ),
      ),
    );

    await tester.tap(find.text('Listar archivos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Archivos'), findsOneWidget);
    expect(find.textContaining('Iansa'), findsOneWidget);
  });
}
