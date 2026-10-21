import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/shared/ui/capture_point_picker.dart';
import 'package:smarthydro_app/shared/ui/hydro_ui.dart';

void main() {
  testWidgets('la cabecera de escritorio no muestra Volver', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HydroPage(
          title: 'Ubicaciones',
          showBack: false,
          body: SizedBox.shrink(),
        ),
      ),
    );

    expect(find.byType(HydroBackButton), findsNothing);
    expect(find.text('Ubicaciones'), findsOneWidget);
    expect(find.byTooltip('Volver'), findsNothing);
  });

  testWidgets('la ruta de teléfono conserva Volver', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HydroPage(title: 'Registros', body: SizedBox.shrink()),
      ),
    );

    expect(find.byType(HydroBackButton), findsOneWidget);
    expect(find.byTooltip('Volver'), findsOneWidget);
  });

  testWidgets('en escritorio ancho la pagina queda en 1080 y centrada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: HydroPage(
          title: 'Análisis',
          showBack: false,
          body: SizedBox(key: Key('page-body'), width: double.infinity),
        ),
      ),
    );

    final body = tester.getRect(find.byKey(const Key('page-body')));
    expect(body.width, 1080);
    expect(body.center.dx, closeTo(800, 1));
  });

  testWidgets('el selector de punto queda al lado del título, no debajo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HydroPage(
          title: 'Registros',
          showBack: false,
          subtitle: CapturePointFilter(
            points: const [
              {'id': 7, 'title': 'Selva Negra', 'code_dga': 'OB-0801-720'},
            ],
            selectedId: 7,
            onChanged: (_) {},
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    final title = tester.getRect(find.text('Registros'));
    final filter = tester.getRect(find.byKey(const ValueKey('capture-point-filter')));
    expect(filter.left, greaterThan(title.right));
    expect(filter.center.dy, closeTo(title.center.dy, 8));
  });

  testWidgets('en teléfono título, punto y trailing caben en una fila', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(400, 800), disableAnimations: true),
        child: MaterialApp(
          home: HydroPage(
            title: 'Análisis',
            subtitle: Text('Selva Negra · OB-0801-720'),
            trailing: Text('7d'),
            body: SizedBox.shrink(),
          ),
        ),
      ),
    );

    final title = tester.getRect(find.text('Análisis'));
    final point = tester.getRect(find.text('Selva Negra · OB-0801-720'));
    expect(point.left, greaterThan(title.right));
    expect(point.center.dy, closeTo(title.center.dy, 8));
    expect(tester.takeException(), isNull);
  });
}
