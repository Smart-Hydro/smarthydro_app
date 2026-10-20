import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/core/n1/n1_api.dart';
import 'package:smarthydro_app/core/n1/n1_config.dart';
import 'package:smarthydro_app/core/n1/n1_memory.dart';
import 'package:smarthydro_app/core/n1/n1_models.dart';
import 'package:smarthydro_app/features/assistant/assistant_screen.dart';
import 'package:smarthydro_app/features/assistant/n1_buddy.dart';

class _FakeN1Api extends N1Api {
  _FakeN1Api()
    : super(config: const N1Config(webAppUrl: 'https://example.test/exec'));

  N1Response askResult = const N1Response(ok: true, text: 'Respuesta N1');
  N1Response? pendingAsk;
  int askCalls = 0;
  List<String>? lastPointNames;

  @override
  bool get isConfigured => true;

  @override
  Future<N1Response> ask({
    required String token,
    required String requester,
    required String text,
    String? sessionId,
    List<int>? pointsAllowed,
    String? name,
    String? client,
    List<String>? clients,
    List<String>? pointNames,
  }) async {
    askCalls += 1;
    lastPointNames = pointNames;
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

    expect(find.textContaining('Hola Ana'), findsOneWidget);
    expect(find.textContaining('Veo 1 punto'), findsOneWidget);
    expect(find.textContaining('SmartHydro N1'), findsOneWidget);
    expect(find.byType(N1Buddy), findsAtLeastNWidgets(1));
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
    expect(api.lastPointNames, ['P4']);
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

    expect(find.textContaining('Consultando tus puntos'), findsWidgets);
    expect(find.text('Reconsultar'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
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

  testWidgets('recuerda la conversación al volver a abrir', (tester) async {
    SharedPreferences.setMockInitialValues({
      N1Memory.storageKeyFor(7):
          '[{"role":"user","text":"cómo está P4"},'
          '{"role":"assistant","text":"P4 está en línea"}]',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantScreen(
          n1Api: _FakeN1Api(),
          session: const SmartHydroSession(
            token: 'tok',
            user: {
              'id': 7,
              'email': 'cliente@empresa.cl',
              'first_name': 'Ana',
            },
          ),
          points: const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('cómo está P4'), findsOneWidget);
    expect(find.text('P4 está en línea'), findsOneWidget);
    expect(find.textContaining('Hola Ana'), findsNothing);
  });

  testWidgets('limpia el panel de puntos y no se queda reconsultando', (
    tester,
  ) async {
    const dump = '''
*Riego Chile* · 13 puntos
• Riego Chile – Agricola Bayona – Matias Fischer · activo · sin ticket SLA
… quedan 8 ítems · usa los botones de abajo o pídemelos en Excel
_Panel: 2026-10-20 17:12 hora Chile_
ℹ️ _DGA Mayor: nota larga._
''';
    final api = _FakeN1Api()
      ..askResult = const N1Response(ok: true, async: true, text: dump);

    await tester.pumpWidget(
      MaterialApp(
        home: AssistantScreen(
          n1Api: api,
          session: const SmartHydroSession(
            token: 'tok',
            user: {'email': 'cliente@empresa.cl', 'first_name': 'Ana'},
          ),
          points: const [
            {'id': 1, 'title': 'Matias Fischer'},
            {'id': 2, 'title': 'Lecheria'},
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'cómo están mis puntos');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Matias Fischer'), findsWidgets);
    expect(find.textContaining('Riego Chile · 13 puntos'), findsOneWidget);
    expect(find.textContaining('usa los botones'), findsNothing);
    expect(find.textContaining('ℹ️'), findsNothing);
    expect(find.textContaining('sin ticket SLA'), findsNothing);
    expect(api.lastPointNames, ['Matias Fischer', 'Lecheria']);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(api.askCalls, 1);
  });
}
