import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/widgets/apps_hub.dart';
import 'package:smarthydro_app/shared/widgets/liquid_nav.dart';

Widget _hubApp({
  required Widget child,
  Size size = const Size(1200, 1200),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: true),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

const _summary = AppsHubSummary(
  pointCount: 12,
  onlineCount: 9,
  attentionCount: 3,
  complianceWatchCount: 2,
  openTicketCount: 4,
);

void main() {
  testWidgets('el hub no muestra el título Apps ni gota Material', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _hubApp(
        size: const Size(1200, 800),
        child: AppsHub(summary: _summary, onOpenApp: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.text('Herramientas para tu red hídrica'), findsOneWidget);
    expect(find.text('Apps'), findsNothing);
    expect(find.byIcon(Icons.water_drop_outlined), findsNothing);
    expect(find.byKey(const ValueKey('apps-hub-tip')), findsOneWidget);
    expect(find.textContaining('filtrable por punto'), findsWidgets);
  });

  testWidgets('las cards muestran conteos de red', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _hubApp(
        size: const Size(1200, 900),
        child: AppsHub(summary: _summary, onOpenApp: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.textContaining('12 puntos'), findsWidgets);
    expect(find.textContaining('9 en línea'), findsOneWidget);
    expect(find.textContaining('3 con aviso'), findsOneWidget);
    expect(find.textContaining('2 en vigilancia'), findsOneWidget);
    expect(find.textContaining('4 abiertos'), findsOneWidget);
    expect(find.byKey(const ValueKey('apps-hub-wide')), findsOneWidget);
    expect(
      find.textContaining('Mapa vivo de captaciones'),
      findsOneWidget,
    );
    expect(find.text('por punto'), findsWidgets);
    expect(find.text('DGA'), findsOneWidget);
  });

  testWidgets('usa glyphs hidráulicos, no Icon Material genérico en cards', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _hubApp(
        size: const Size(1200, 900),
        child: AppsHub(summary: _summary, onOpenApp: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('hydro-glyph-ubicaciones')), findsOneWidget);
    expect(find.byKey(const ValueKey('hydro-glyph-analisis')), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('Informes queda como pronto y abre índice correcto', (
    tester,
  ) async {
    var opened = -1;
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _hubApp(
        child: AppsHub(
          summary: _summary,
          onOpenApp: (i) => opened = i,
        ),
      ),
    );
    await tester.pump();

    final informesIndex = liquidDesktopApps.indexWhere(
      (a) => a.label == 'Informes',
    );
    expect(informesIndex, greaterThanOrEqualTo(0));

    await tester.scrollUntilVisible(
      find.text('Informes'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.textContaining('Pronto'), findsWidgets);
    await tester.tap(find.text('Informes'));
    await tester.pump();
    expect(opened, informesIndex);
  });
}
