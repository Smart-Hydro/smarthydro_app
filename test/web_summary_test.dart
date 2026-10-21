import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthydro_app/core/prefs/web_summary.dart';
import 'package:smarthydro_app/features/dashboard/widgets/web_summary_dock.dart';

void main() {
  test('sin preferencia el resumen de escritorio queda abierto', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(webSummaryProvider), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(webSummaryProvider), isTrue);
  });

  test('ocultar el resumen queda guardado para la próxima vez', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    await first.read(webSummaryProvider.notifier).set(false);
    first.dispose();

    final next = ProviderContainer();
    addTearDown(next.dispose);
    next.read(webSummaryProvider);
    await Future<void>.delayed(Duration.zero);
    expect(next.read(webSummaryProvider), isFalse);
  });

  testWidgets('ocultar el resumen ensancha el mapa', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var open = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return WebSummaryDock(
                  open: open,
                  onOpenChanged: (value) => setState(() => open = value),
                  map: const ColoredBox(
                    key: ValueKey('web-summary-map'),
                    color: Color(0xFF102226),
                    child: SizedBox.expand(child: Text('MAPA')),
                  ),
                  summary: const ColoredBox(
                    color: Color(0xFF081216),
                    child: SizedBox.expand(child: Text('RESUMEN')),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('RESUMEN'), findsOneWidget);
    final openWidth = tester
        .getSize(find.byKey(const ValueKey('web-summary-map')))
        .width;
    expect(openWidth, closeTo(1200 - WebSummaryDock.panelWidth, 2));

    await tester.tap(find.byKey(const ValueKey('web-summary-toggle')));
    await tester.pump();

    expect(find.text('RESUMEN'), findsNothing);
    expect(find.byTooltip('Resumen'), findsOneWidget);
    final closedWidth = tester
        .getSize(find.byKey(const ValueKey('web-summary-map')))
        .width;
    expect(closedWidth, closeTo(1200, 2));
    expect(closedWidth, greaterThan(openWidth + 200));

    await tester.tap(find.byKey(const ValueKey('web-summary-toggle')));
    await tester.pump();
    expect(find.text('RESUMEN'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('web-summary-map'))).width,
      closeTo(openWidth, 2),
    );
  });

  testWidgets('el resumen se desliza a la derecha sin corte', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var open = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return WebSummaryDock(
                open: open,
                onOpenChanged: (value) => setState(() => open = value),
                map: const ColoredBox(
                  color: Color(0xFF102226),
                  child: SizedBox.expand(child: Text('MAPA')),
                ),
                summary: const ColoredBox(
                  color: Color(0xFF081216),
                  child: SizedBox.expand(child: Text('RESUMEN')),
                ),
              );
            },
          ),
        ),
      ),
    );

    final openLeft = tester.getTopLeft(find.text('RESUMEN')).dx;
    expect(openLeft, closeTo(1200 - WebSummaryDock.panelWidth, 2));

    await tester.tap(find.byKey(const ValueKey('web-summary-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    final midLeft = tester.getTopLeft(find.text('RESUMEN')).dx;
    expect(midLeft, greaterThan(openLeft + 40));
    expect(midLeft, lessThan(1180));

    await tester.pumpAndSettle();
    expect(find.text('RESUMEN'), findsNothing);
  });
}
