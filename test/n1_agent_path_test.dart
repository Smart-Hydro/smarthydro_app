import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/core/n1/n1_api.dart';
import 'package:smarthydro_app/core/n1/n1_config.dart';
import 'package:smarthydro_app/core/n1/n1_identity.dart';
import 'package:smarthydro_app/features/assistant/assistant_screen.dart';
import 'package:smarthydro_app/features/assistant/quick_ask.dart';

/// Los 13 puntos del caso Riego Chile (el blob que N1 no ubicaba).
const _riegoTitles = [
  'Selva Negra',
  'Matias Fischer',
  'San Jose 2',
  'Pomuyeto',
  'Pivote',
  'Lecheria',
  'Santa Marta',
  'Santa Cecilia',
  'Santa Macarena',
  'Santa Clara',
  'Tata',
  'Santa Adriana',
  'Y1',
];

List<Map<String, dynamic>> _riegoPoints() => [
  for (var i = 0; i < _riegoTitles.length; i++)
    {
      'id': i + 10,
      'title': _riegoTitles[i],
      'client_name': 'Riego Chile',
    },
];

/// Réplica del lookup de N1: `text` es un solo nombre de punto.
/// Si la app pega el listado, N1 responde «No ubiqué … en el panel.»
String n1PanelReply(String text) {
  final lower = text.toLowerCase();
  final hits = _riegoTitles
      .where((title) => lower.contains(title.toLowerCase()))
      .length;
  final stuffed =
      hits >= 3 ||
      lower.contains('y 1 más') ||
      lower.contains('y 1 mas') ||
      lower.contains(' y1');
  if (stuffed) {
    final quoted = lower
        .replaceAll(RegExp(r'[();,]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return 'No ubiqué «$quoted» en el panel.';
  }
  return '''*Riego Chile* · 13 puntos
• Riego Chile – Agricola Bayona – Matias Fischer · activo · sin ticket SLA
• Riego Chile – Lecheria · activo
Desconectados: 0
Tickets abiertos: 0
''';
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

Map<String, dynamic> _bodyOf(RequestOptions options) {
  final data = options.data;
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return data.map((k, v) => MapEntry('$k', v));
  if (data is String && data.trim().isNotEmpty) {
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
  }
  return <String, dynamic>{};
}

N1Api _capturingApi(void Function(Map<String, dynamic> body) onAsk) {
  final dio = Dio();
  dio.httpClientAdapter = _Adapter((options) async {
    final body = _bodyOf(options);
    onAsk(body);
    return _json({'ok': true, 'text': n1PanelReply('${body['text'] ?? ''}')});
  });
  return N1Api(
    config: const N1Config(webAppUrl: 'https://script.google.com/macros/s/test/exec'),
    dio: dio,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('el blob viejo es lo que N1 no ubica; el texto limpio sí entra al panel', () {
    const old =
        'cómo están mis puntos (cliente Riego Chile; soy Riego Chile; puntos Selva Negra, Matias Fischer, San Jose 2, Pomuyeto, Pivote, Lecheria, Santa Marta, Santa Cecilia, Santa Macarena, Santa Clara, Tata, Santa Adriana y 1 más)';
    expect(n1PanelReply(old).toLowerCase(), contains('no ubiqué'));
    expect(n1PanelReply(old).toLowerCase(), contains('en el panel'));

    final clean = n1DecorateAskText(
      'cómo están mis puntos',
      name: 'Riego Chile',
      clients: const ['Riego Chile'],
      points: _riegoTitles,
    );
    expect(clean, 'cómo están mis puntos (cliente Riego Chile)');
    expect(clean.toLowerCase(), isNot(contains('selva negra')));
    expect(clean.toLowerCase(), isNot(contains('matias fischer')));
    expect(n1PanelReply(clean).toLowerCase(), isNot(contains('no ubiqué')));
    expect(n1PanelReply(clean), contains('13 puntos'));
    expect(n1PanelReply(clean), contains('Matias Fischer'));
  });

  test('ask de la API manda ids y texto limpio, y el panel no dice No ubiqué', () async {
    late Map<String, dynamic> sent;
    final api = _capturingApi((body) => sent = body);
    final points = _riegoPoints();

    final result = await api.ask(
      token: 'tok',
      requester: 'felipe@riegochile.cl',
      text: 'cómo están mis puntos',
      name: 'Riego Chile',
      clients: n1ClientNamesOf(points),
      pointNames: n1PointNamesOf(points),
      pointsAllowed: points.map((p) => p['id'] as int).toList(),
    );

    expect(sent['op'], 'ask');
    expect(sent['text'], 'cómo están mis puntos (cliente Riego Chile)');
    expect(sent['text'], isNot(contains('Selva Negra')));
    expect(sent['client'], 'Riego Chile');
    expect(sent['points_allowed'], hasLength(13));
    expect(sent['points_allowed'], containsAll([10, 22]));
    expect(result.ok, isTrue);
    expect(result.text.toLowerCase(), isNot(contains('no ubiqué')));
    expect(result.text, contains('Matias Fischer'));
    expect(result.text, contains('13 puntos'));
  });

  testWidgets('Asistente pregunta y pinta el panel, no el No ubiqué', (
    tester,
  ) async {
    late Map<String, dynamic> sent;
    final api = _capturingApi((body) => sent = body);
    final points = _riegoPoints();

    await tester.pumpWidget(
      MaterialApp(
        home: AssistantScreen(
          n1Api: api,
          session: const SmartHydroSession(
            token: 'tok',
            user: {
              'email': 'felipe@riegochile.cl',
              'first_name': 'Riego Chile',
            },
          ),
          points: points,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Veo 13 puntos'), findsOneWidget);
    expect(find.textContaining('de Riego Chile'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'cómo están mis puntos');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sent['text'], 'cómo están mis puntos (cliente Riego Chile)');
    expect(sent['text'], isNot(contains('Matias Fischer')));
    expect(sent['points_allowed'], hasLength(13));
    expect(find.textContaining('No ubiqué'), findsNothing);
    expect(find.textContaining('Matias Fischer'), findsWidgets);
    expect(find.textContaining('Riego Chile · 13 puntos'), findsOneWidget);
  });

  testWidgets('QuickAsk manda el mismo ask limpio y muestra Matias Fischer', (
    tester,
  ) async {
    late Map<String, dynamic> sent;
    final api = _capturingApi((body) => sent = body);
    final points = _riegoPoints();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: QuickAsk(
              peek: true,
              n1Api: api,
              token: 'tok',
              email: 'felipe@riegochile.cl',
              name: 'Riego Chile',
              clients: n1ClientNamesOf(points),
              pointNames: n1PointNamesOf(points),
              pointIds: points.map((p) => p['id'] as int).toList(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Asistente N1'));
    await tester.pump();
    expect(find.textContaining('Veo 13 puntos'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'cómo están mis puntos');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sent['text'], 'cómo están mis puntos (cliente Riego Chile)');
    expect(sent['points_allowed'], hasLength(13));
    expect(find.textContaining('No ubiqué'), findsNothing);
    expect(find.textContaining('Matias Fischer'), findsWidgets);
  });
}
