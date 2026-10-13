import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/capture_stage.dart';
import 'package:smarthydro_app/features/dashboard/point_link.dart';
import 'package:smarthydro_app/features/dashboard/point_meta.dart';

Widget _stage({
  required bool surface,
  double? flow = 8.2,
  double? total,
  LoggerInfo? loggerInfo,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 390,
      height: 520,
      child: CaptureStage(
        levelMeters: surface ? 0.45 : 12.45,
        levelFill: 0.5,
        flowLitersPerSecond: flow,
        totalCubicMeters: total,
        flowMax: 10,
        isSurface: surface,
        link: PointLink.connected,
        loggerInfo: loggerInfo,
        profile: surface
            ? const CaptureProfile()
            : const CaptureProfile(
                depth: 80,
                pumpDepth: 55,
                sensorDepth: 60,
                ductInches: 4,
                flowmeterInches: 4,
                maxFlow: 20,
              ),
      ),
    ),
  ),
);

/// Toca una grilla sobre la escena hasta que aparezca la explicación.
Future<bool> _tapUntil(WidgetTester tester, String text) async {
  final box = tester.getRect(find.byType(CaptureStage));
  for (var y = box.top + 60; y < box.bottom - 80; y += 14) {
    for (var x = box.left + 20; x < box.right - 20; x += 14) {
      await tester.tapAt(Offset(x, y));
      await tester.pump(const Duration(milliseconds: 400));
      if (find.textContaining(text).evaluate().isNotEmpty) return true;
      // Cierra lo que se haya fijado antes de seguir buscando.
      await tester.tapAt(Offset(x, y));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }
  return false;
}

void main() {
  testWidgets('el pozo gira 360° y explica sus partes al tocarlas', (
    tester,
  ) async {
    await tester.pumpWidget(_stage(surface: false));
    await tester.pump(const Duration(milliseconds: 100));
    final center = tester.getCenter(find.byType(CaptureStage));
    for (var i = 0; i < 8; i++) {
      await tester.dragFrom(center, const Offset(-90, 0));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(CaptureStage));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(CaptureStage));
    await tester.pump(const Duration(seconds: 1));

    expect(await _tapUntil(tester, 'Extrae el agua'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('superficial sin caudal no dibuja toma ni flujómetro', (
    tester,
  ) async {
    await tester.pumpWidget(_stage(surface: true, flow: null));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(await _tapUntil(tester, 'Mide el caudal'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('acerca, aleja y explica que es una representación', (
    tester,
  ) async {
    await tester.pumpWidget(_stage(surface: false, total: 12345.6));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Acercar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Alejar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Centrar vista'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Qué estoy viendo'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Representación de tu instalación'), findsOneWidget);

    expect(await _tapUntil(tester, 'total 12.345,6 m³'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('al tocar el tablero acerca y muestra token, modelo y DGA', (
    tester,
  ) async {
    await tester.pumpWidget(
      _stage(
        surface: false,
        loggerInfo: LoggerInfo(
          token: 'abc-token-9',
          model: 'Twin',
          frequency: '15',
          telemetry: true,
          variables: const [
            PointVariable(
              type: 'CAUDAL',
              strVariable: 'ai1ActualValue',
              label: 'Caudal',
              displayKey: 'caudal',
            ),
            PointVariable(
              type: 'NIVEL',
              strVariable: 'ai2ActualValue',
              label: 'Nivel',
              displayKey: 'nivel',
            ),
          ],
          dga: const DgaInfo(
            type: 'SUBTERRANEO',
            code: 'OB-123',
            standard: 'MEDIO',
            flowGranted: 20,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(await _tapUntil(tester, 'abc-token-9'), isTrue);
    expect(find.textContaining('Twin'), findsWidgets);
    expect(find.textContaining('Variables del esquema'), findsOneWidget);
    expect(find.textContaining('ai1ActualValue'), findsOneWidget);
    expect(find.textContaining('ai2ActualValue'), findsOneWidget);
    expect(find.textContaining('Caudal'), findsWidgets);
    expect(find.textContaining('Cumplimiento DGA'), findsOneWidget);
    expect(find.textContaining('OB-123'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pasar el mouse no abre la ficha; solo el click', (tester) async {
    await tester.pumpWidget(_stage(surface: false));
    await tester.pump(const Duration(milliseconds: 100));
    final box = tester.getRect(find.byType(CaptureStage));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: box.center);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(Offset(box.left + 40, box.top + 80));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Zona no saturada'), findsNothing);
    expect(find.textContaining('Acuífero'), findsNothing);
    expect(find.text('Representación de tu instalación'), findsNothing);
    // Click en un equipo sí abre ficha con datos.
    expect(await _tapUntil(tester, 'Extrae el agua'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('el corte se centra y no se estira en una vista alta', () {
    const yaw = 0.66;
    const pitch = 0.46;
    ({double half, double depth, Offset origin, Size footprint}) fit(
      Size size,
      double depthFactor,
    ) => captureSceneLayout(
      size: size,
      yaw: yaw,
      pitch: pitch,
      topInset: 56,
      depthFactor: depthFactor,
      headroom: 36,
    );

    final tall = fit(const Size(1100, 1400), 2.4);
    final short = fit(const Size(900, 480), 2.4);
    final tallAspect = tall.footprint.height / tall.footprint.width;
    final shortAspect = short.footprint.height / short.footprint.width;
    expect(tallAspect, inInclusiveRange(0.95, 1.5));
    expect((tallAspect - shortAspect).abs(), lessThan(0.12));
    expect(tall.footprint.height, lessThanOrEqualTo((1400 - 56 - 76) * 0.95));
    expect(short.footprint.height, lessThanOrEqualTo((480 - 56 - 76) * 0.95));
    expect(tall.origin.dx, closeTo(1100 / 2, 12));

    final deep = fit(const Size(1100, 900), 2.85);
    final shallow = fit(const Size(1100, 900), 2.15);
    expect(
      deep.footprint.height / deep.footprint.width,
      greaterThan(shallow.footprint.height / shallow.footprint.width),
    );
    expect(deep.footprint.height / deep.footprint.width, lessThan(1.55));
  });

  test('formatea el flujómetro con miles chilenos', () {
    expect(formatCubicMeters(12345.6), '12.345,6 m³');
    expect(formatCubicMeters(1000000), '1.000.000,0 m³');
    expect(formatCubicMeters(812.44), '812,4 m³');
    expect(formatLitersPerSecond(1234.567), '1.234,57 L/s');
    expect(formatLitersPerSecond(8.2), '8,20 L/s');
    expect(formatCl(-1234.5, 1), '-1.234,5');
    expect(flowNormOf(5, 10), 0.5);
    expect(flowNormOf(30, 10), 1);
  });
}
