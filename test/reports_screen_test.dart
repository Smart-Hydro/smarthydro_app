import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/features/reports/reports_screen.dart';
import 'package:smarthydro_app/shared/ui/hydro_ui.dart';
import 'package:smarthydro_app/shared/widgets/hydro_glyph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final samples = [
    {
      'date_time': today.add(const Duration(hours: 8)).toIso8601String(),
      'flow': 12.5,
      'total': 100.0,
    },
    {
      'date_time': today.add(const Duration(hours: 9)).toIso8601String(),
      'flow': 11.0,
      'total': 140.0,
    },
    {
      'date_time': today
          .subtract(const Duration(days: 1, hours: -10))
          .toIso8601String(),
      'flow': 9.0,
      'total': 80.0,
    },
  ];

  SmartHydroApi api() {
    final dio = Dio();
    dio.httpClientAdapter = _Adapter(samples: samples);
    return SmartHydroApi(dio: dio);
  }

  Future<void> pumpReports(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: true),
        child: MaterialApp(
          home: ReportsScreen(
            api: api(),
            token: 'tok',
            points: const [
              {'id': 7, 'title': 'Pozo Norte'},
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
  }

  test('agrupa lecturas por día', () {
    final groups = reportsGroupByDay(samples);
    expect(groups, hasLength(2));
    expect(groups.first.value, hasLength(greaterThanOrEqualTo(1)));
  });

  testWidgets('vacío de puntos usa el glifo, no la gota Material', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800), disableAnimations: true),
        child: MaterialApp(
          home: ReportsScreen(
            api: SmartHydroApi(),
            token: 'tok',
            points: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Registros'), findsOneWidget);
    expect(find.byType(HydroGlyph), findsWidgets);
    expect(find.byIcon(Icons.water_drop_outlined), findsNothing);
  });

  testWidgets('en web el resumen queda al lado de la tabla de vidrio', (
    tester,
  ) async {
    await pumpReports(tester, const Size(1400, 900));

    expect(find.byKey(const ValueKey('reports-layout-wide')), findsOneWidget);
    expect(find.byType(HydroGlassLight), findsWidgets);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('7 días'), findsOneWidget);
    expect(find.text('Descargar Excel'), findsOneWidget);
    expect(find.text('CSV'), findsOneWidget);
    expect(find.textContaining('Lecturas'), findsWidgets);
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    final pulse = tester.getTopLeft(find.byKey(const ValueKey('reports-pulse')));
    final table = tester.getTopLeft(
      find.byKey(const ValueKey('reports-table')),
    );
    expect(table.dx, greaterThan(pulse.dx + 120));
  });

  testWidgets('en el teléfono todo va en una columna de vidrio', (tester) async {
    await pumpReports(tester, const Size(400, 900));

    expect(find.byKey(const ValueKey('reports-layout-narrow')), findsOneWidget);
    expect(find.byKey(const ValueKey('reports-layout-wide')), findsNothing);
    expect(find.byType(HydroGlassLight), findsWidgets);
    expect(find.text('Descargar Excel'), findsOneWidget);
    expect(find.byIcon(Icons.event_busy_rounded), findsNothing);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter({required this.samples});

  final List<Map<String, dynamic>> samples;

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
    if (path.endsWith('/variables/')) {
      body = {
        'variables': [
          {'type_variable': 'CAUDAL'},
          {'type_variable': 'TOTALIZADO'},
        ],
      };
    } else if (path.endsWith('/records/')) {
      body = {'records': samples};
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
