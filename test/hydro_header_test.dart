import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
