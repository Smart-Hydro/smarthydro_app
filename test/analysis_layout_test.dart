import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/features/analysis/analysis_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final periodStart = today.subtract(const Duration(days: 6));
  final samples = [
    for (var i = 0; i < 8; i++)
      {
        'date_time': periodStart
            .add(Duration(hours: 8, minutes: 15 * i))
            .toIso8601String(),
        'flow': i < 2 || i > 3 ? 12.0 : 0.0,
      },
  ];

  SmartHydroApi api() {
    final dio = Dio();
    dio.httpClientAdapter = _Adapter(
      periodStart: _dateOnly(periodStart),
      samples: samples,
    );
    return SmartHydroApi(dio: dio);
  }

  Future<void> pumpAnalysis(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AnalysisScreen(
          api: api(),
          token: 'token',
          points: const [
            {'id': 7, 'title': 'Pozo Norte', 'frecuency': 15},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('en web el rendimiento queda al lado y la serie abajo', (
    tester,
  ) async {
    await pumpAnalysis(tester, const Size(1400, 1700));

    expect(find.byKey(const Key('analysis-layout-wide')), findsOneWidget);
    expect(find.byKey(const Key('analysis-charts-wide')), findsOneWidget);
    final hallazgos = tester.getTopLeft(find.text('Hallazgos'));
    final rendimiento = tester.getTopLeft(find.text('Rendimiento'));
    final serie = tester.getRect(find.text('Línea de tiempo'));
    final perfil = tester.getRect(find.text('Perfil horario'));
    final timeline = tester.getRect(find.byKey(const Key('analysis-timeline')));
    final hourly = tester.getRect(find.byKey(const Key('analysis-hourly')));
    final charts = tester.getRect(
      find.byKey(const Key('analysis-charts-wide')),
    );

    expect(rendimiento.dx, greaterThan(hallazgos.dx + 200));
    expect(serie.top, greaterThan(hallazgos.dy));
    expect(serie.top, greaterThan(rendimiento.dy));
    expect(perfil.left, greaterThan(serie.right));
    expect(perfil.top, greaterThan(rendimiento.dy));
    expect(
      (timeline.bottom - hourly.bottom).abs(),
      lessThan(2),
      reason: 'en escritorio las dos series deben compartir el mismo piso',
    );
    expect(
      (serie.center.dx - (charts.left + charts.width / 4)).abs(),
      lessThan(48),
    );
    expect(
      (perfil.center.dx - (charts.left + charts.width * 0.75)).abs(),
      lessThan(48),
    );

    final scroll = tester.getRect(
      find.byKey(const Key('analysis-layout-wide')),
    );
    final topGap = tester.getTopLeft(find.text('de 100')).dy - scroll.top;
    final bottomGap =
        scroll.bottom -
        tester.getBottomLeft(find.textContaining('cobertura')).dy;
    expect((topGap - bottomGap).abs(), lessThan(80));
  });

  testWidgets('en el teléfono análisis sigue en una columna', (tester) async {
    await pumpAnalysis(tester, const Size(400, 1600));

    expect(find.byKey(const Key('analysis-layout-narrow')), findsOneWidget);
    expect(find.byKey(const Key('analysis-charts-wide')), findsNothing);
    final hallazgos = tester.getTopLeft(find.text('Hallazgos'));
    final rendimiento = tester.getTopLeft(find.text('Rendimiento'));
    final serie = tester.getTopLeft(find.text('Línea de tiempo'));
    final perfil = tester.getTopLeft(find.text('Perfil horario'));

    expect((rendimiento.dx - hallazgos.dx).abs(), lessThan(8));
    expect(rendimiento.dy, greaterThan(hallazgos.dy + 24));
    expect((perfil.dx - serie.dx).abs(), lessThan(8));
    expect(perfil.dy, greaterThan(serie.dy + 24));
  });
}

String _dateOnly(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class _Adapter implements HttpClientAdapter {
  _Adapter({required this.periodStart, required this.samples});

  final String periodStart;
  final List<Map<String, dynamic>> samples;

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
        ],
      };
    } else if (path.endsWith('/records/')) {
      final start = options.queryParameters['start_date']?.toString();
      body = {'records': start == periodStart ? samples : const <Object>[]};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
