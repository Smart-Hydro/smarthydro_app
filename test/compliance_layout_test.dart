import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/features/compliance/compliance_screen.dart';
import 'package:smarthydro_app/features/compliance/compliance_store.dart';
import 'package:smarthydro_app/shared/ui/hydro_ui.dart';
import 'package:smarthydro_app/shared/widgets/chile_shield.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ComplianceStore.instance = ComplianceStore();
  });

  const points = [
    {
      'point_id': 1,
      'point_name': 'Pozo Norte',
      'client_name': 'Agrícola',
      'code': 'OB-10',
      'compliance_type': ['DGA'],
      'type_dga': 'SUBTERRANEO',
      'authorized_flow': 20,
      'flow': 12,
      'water_table': 8,
      'pct_consumed': 40,
      'annual_consumption': 1000,
      'compliance_warning': {'level': 'safe'},
    },
    {
      'point_id': 2,
      'point_name': 'Canal Sur',
      'client_name': 'Riego',
      'code': 'OB-11',
      'compliance_type': ['DGA'],
      'type_dga': 'SUPERFICIAL',
      'authorized_flow': 10,
      'flow': 14,
      'water_table': 2.5,
      'pct_consumed': 110,
      'annual_consumption': 5000,
      'compliance_warning': {'level': 'critical'},
    },
    {
      'point_id': 3,
      'point_name': 'Estero Este',
      'client_name': 'Fundo',
      'code': 'OB-12',
      'compliance_type': ['DGA'],
      'type_dga': 'SUPERFICIAL',
      'authorized_flow': 10,
      'flow': 9,
      'water_table': 6.1,
      'pct_consumed': 80,
      'annual_consumption': 2000,
      'compliance_warning': {'level': 'warning'},
    },
  ];

  SmartHydroApi api() {
    final dio = Dio();
    dio.httpClientAdapter = _Adapter(points);
    return SmartHydroApi(dio: dio);
  }

  Future<void> pump(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ComplianceScreen(api: api(), token: 'token', showBack: false),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('en web los puntos van lado a lado y sin bandera', (
    tester,
  ) async {
    await pump(tester, const Size(1400, 900));

    expect(find.byKey(const Key('compliance-layout-wide')), findsOneWidget);
    expect(find.byType(ChileShield), findsNothing);
    final sur = tester.getTopLeft(find.text('Canal Sur'));
    final este = tester.getTopLeft(find.text('Estero Este'));
    final norte = tester.getTopLeft(find.text('Pozo Norte'));
    expect(este.dx, greaterThan(sur.dx + 180));
    expect(norte.dx, greaterThan(este.dx + 180));
    expect((este.dy - sur.dy).abs(), lessThan(8));
    expect((norte.dy - sur.dy).abs(), lessThan(8));
    expect(find.text('Cumplimiento DGA'), findsNothing);
    expect(find.text('Dentro'), findsWidgets);
    expect(find.text('Excede'), findsWidgets);
    expect(find.text('Caudal'), findsWidgets);
    expect(find.text('Volumen'), findsWidgets);
    expect(find.text('Nivel'), findsWidgets);
    expect(find.text('2.50'), findsOneWidget);
    expect(find.text('m freático'), findsOneWidget);
    expect(find.text('m'), findsWidgets);
    expect(find.byKey(const Key('compliance-refresh')), findsOneWidget);
    expect(find.text('Actualizar'), findsOneWidget);
  });

  testWidgets('en el teléfono cumplimiento sigue en una columna', (
    tester,
  ) async {
    await pump(tester, const Size(400, 900));

    expect(find.byKey(const Key('compliance-layout-narrow')), findsOneWidget);
    expect(find.byType(ChileShield), findsNothing);
    final sur = tester.getTopLeft(find.text('Canal Sur'));
    final este = tester.getTopLeft(find.text('Estero Este'));
    final norte = tester.getTopLeft(find.text('Pozo Norte'));
    expect((este.dx - sur.dx).abs(), lessThan(8));
    expect((norte.dx - sur.dx).abs(), lessThan(8));
    expect(este.dy, greaterThan(sur.dy + 24));
    expect(norte.dy, greaterThan(este.dy + 24));
  });

  testWidgets('en web el punto se abre en la misma vista, ficha arriba', (
    tester,
  ) async {
    await pump(tester, const Size(1400, 900));

    await tester.tap(find.text('Canal Sur'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compliance-point-detail')), findsOneWidget);
    expect(find.byType(HydroBackButton), findsNothing);
    expect(find.text('Lista'), findsNothing);
    expect(find.text('Cumplimiento DGA'), findsNothing);
    expect(find.text('Volver'), findsOneWidget);
    expect(find.text('OB-11'), findsOneWidget);
    final back = tester.getTopLeft(find.text('Volver'));
    final name = tester.getTopLeft(find.text('Canal Sur'));
    final code = tester.getTopLeft(find.text('OB-11'));
    final rest = tester.getTopLeft(
      find.text('No pudimos leer la planilla del mes'),
    );
    expect(back.dx, lessThan(name.dx));
    expect((back.dy - name.dy).abs(), lessThan(24));
    expect(code.dy, greaterThan(name.dy));
    expect(rest.dy, greaterThan(code.dy + 24));

    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compliance-layout-wide')), findsOneWidget);
  });

  testWidgets('en el teléfono el punto sigue en su propia ruta', (
    tester,
  ) async {
    await pump(tester, const Size(400, 900));

    await tester.tap(find.text('Canal Sur'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compliance-point-detail')), findsOneWidget);
    expect(find.byType(HydroBackButton), findsOneWidget);
    expect(find.text('Lista'), findsNothing);
    expect(find.text('Volver'), findsNothing);
    expect(find.text('Cumplimiento DGA'), findsNothing);
  });

  testWidgets(
    'reentrar cumplimiento usa el cache y no pide el listado otra vez',
    (tester) async {
      final adapter = _Adapter(points);
      final store = ComplianceStore();
      final dio = Dio()..httpClientAdapter = adapter;
      final api = SmartHydroApi(dio: dio);

      Future<void> mount() async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: ComplianceScreen(
              api: api,
              token: 'token',
              showBack: false,
              store: store,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      expect(adapter.complianceGets, 1);
      expect(find.text('Pozo Norte'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mount();
      expect(adapter.complianceGets, 1);
      expect(find.text('Pozo Norte'), findsOneWidget);

      await tester.tap(find.byKey(const Key('compliance-refresh')));
      await tester.pumpAndSettle();
      expect(adapter.complianceGets, 2);
    },
  );
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.points);

  final List<Map<String, dynamic>> points;
  int complianceGets = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.endsWith('/compliance/')) complianceGets++;
    final Object body = path.endsWith('/compliance/')
        ? {'points': points}
        : path.contains('catchment_point')
        ? {
            'title': 'Canal Sur',
            'frecuency': 60,
            'dga': {
              'code_dga': 'OB-11',
              'standard': 'MAYOR',
              'send_dga': true,
              'type_dga': 'SUBTERRANEO',
              'flow_granted_dga': 10,
            },
            'modules': {'m2': []},
          }
        : const <String, dynamic>{};
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
