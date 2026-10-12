import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/capture_stage.dart';
import 'package:smarthydro_app/features/dashboard/point_link.dart';

Widget _stage({required bool surface, double? flow = 8.2}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 390,
      height: 520,
      child: CaptureStage(
        levelMeters: surface ? 0.45 : 12.45,
        levelFill: 0.5,
        flowLitersPerSecond: flow,
        isSurface: surface,
        link: PointLink.connected,
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
}
