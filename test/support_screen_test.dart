import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/features/support/customer_support_screen.dart';
import 'package:smarthydro_app/shared/ui/capture_point_picker.dart';
import 'package:smarthydro_app/shared/ui/hydro_ui.dart';
import 'package:smarthydro_app/shared/widgets/hydro_glyph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const points = [
    {'id': 7, 'title': 'Pozo Norte', 'code_dga': 'OB-1603-392'},
    {'id': 9, 'title': 'Canal Sur'},
  ];

  SmartHydroApi api({
    List<Map<String, dynamic>> tickets = const [],
    List<Map<String, dynamic>> categories = const [],
  }) {
    final dio = Dio();
    dio.httpClientAdapter = _Adapter(tickets: tickets, categories: categories);
    return SmartHydroApi(dio: dio);
  }

  Future<void> pumpSupport(
    WidgetTester tester, {
    required SmartHydroApi api,
    Size size = const Size(1200, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: true),
        child: MaterialApp(
          home: CustomerSupportScreen(
            api: api,
            token: 'tok',
            points: points,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  test('etiquetas de estado y prioridad quedan en español corto', () {
    expect(supportStatusLabel('ABIERTO'), 'Abierta');
    expect(supportStatusLabel('EN_PROCESO'), 'En curso');
    expect(supportStatusLabel('CERRADO'), 'Cerrada');
    expect(supportPriorityLabel('ALTA'), 'Alta');
    expect(supportTicketIsOpen({'status': 'ABIERTO'}), isTrue);
    expect(supportTicketIsOpen({'status': 'CERRADO'}), isFalse);
    expect(
      supportTicketPointLabel({
        'points': [
          {'title': 'Pozo Norte'},
        ],
      }),
      'Pozo Norte',
    );
  });

  testWidgets('vacío usa el glifo y no el inbox Material', (tester) async {
    await pumpSupport(tester, api: api());

    expect(find.text('Soporte'), findsOneWidget);
    expect(find.textContaining('Tickets de tus puntos'), findsOneWidget);
    expect(find.byType(HydroGlyph), findsWidgets);
    expect(find.textContaining('Sin solicitudes'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsNothing);
    expect(find.byIcon(Icons.support_agent_rounded), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Nueva solicitud'), findsWidgets);
  });

  testWidgets('las solicitudes son cards de vidrio con chips y punto', (
    tester,
  ) async {
    await pumpSupport(
      tester,
      api: api(
        tickets: const [
          {
            'id': 41,
            'title': 'Logger sin datos',
            'status': 'ABIERTO',
            'priority': 'ALTA',
            'points': [
              {'id': 7, 'title': 'Pozo Norte'},
            ],
          },
          {
            'id': 42,
            'title': 'Caudal raro',
            'status': 'CERRADO',
            'priority': 'MEDIA',
            'points': [
              {'id': 9, 'title': 'Canal Sur'},
            ],
          },
        ],
      ),
    );

    expect(find.byKey(const ValueKey('support-pulse')), findsOneWidget);
    expect(find.textContaining('Abiertas'), findsWidgets);
    expect(find.text('Logger sin datos'), findsOneWidget);
    expect(find.text('Pozo Norte'), findsOneWidget);
    expect(find.text('Abierta'), findsWidgets);
    expect(find.text('Alta'), findsWidgets);
    expect(find.byType(HydroGlassLight), findsWidgets);
    expect(find.byIcon(Icons.support_agent_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('nueva solicitud elige punto con buscador y prioridad en chips', (
    tester,
  ) async {
    await pumpSupport(
      tester,
      api: api(
        categories: const [
          {'id': 1, 'name': 'Hardware', 'category_type': 'HARDWARE'},
        ],
      ),
      size: const Size(400, 900),
    );

    await tester.tap(find.text('Nueva solicitud').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Nueva solicitud'), findsWidgets);
    expect(find.byType(CapturePointFilter), findsOneWidget);
    expect(find.text('Baja'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Alta'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter({this.tickets = const [], this.categories = const []});

  final List<Map<String, dynamic>> tickets;
  final List<Map<String, dynamic>> categories;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    Object body = const <String, dynamic>{};
    if (path.contains('/ticket-categories')) {
      body = categories;
    } else if (path.contains('/tickets/')) {
      body = {'results': tickets};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
