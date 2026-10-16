import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/shared/widgets/liquid_nav.dart';
import 'package:smarthydro_app/shared/widgets/workstation_backdrop.dart';

void main() {
  testWidgets('el conteo de no leídos queda en Avisos', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidNavBar(
            selectedIndex: 0,
            unreadCount: 3,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('Eventos'), matching: find.byType(Column))
            .first,
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('Apps'), matching: find.byType(Column))
            .first,
        matching: find.text('3'),
      ),
      findsNothing,
    );
  });

  testWidgets('el rail desktop muestra destinos y badge en Eventos', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidNavRail(
            selectedIndex: 1,
            unreadCount: 2,
            onSelect: (_) {},
            onOpenApp: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('IoT'), findsOneWidget);
    expect(find.text('Eventos'), findsOneWidget);
    expect(find.text('Apps'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-nav-rail')), findsOneWidget);
  });

  testWidgets('el rail desktop mide múltiplo de la grilla workstation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LiquidNavRail(
              selectedIndex: 0,
              unreadCount: 0,
              onSelect: (_) {},
              onOpenApp: (_) {},
            ),
          ),
        ),
      ),
    );

    final box = tester.getSize(find.byKey(const ValueKey('liquid-nav-rail')));
    expect(box.width, liquidNavRailWidth);
    expect(liquidNavRailWidth % workstationGridStep, 0);
    expect(liquidNavRailSlot % workstationGridStep, 0);
    expect(liquidNavRailAppSlot % workstationGridStep, 0);
    // Más grande que el rail chato anterior (80).
    expect(liquidNavRailWidth, greaterThanOrEqualTo(workstationGridStep * 6));
    expect(liquidNavRailSlot, greaterThanOrEqualTo(workstationGridStep * 5));
  });

  testWidgets('el rail desktop muestra iconos de apps', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 1200)),
        child: MaterialApp(
          home: Scaffold(
            body: LiquidNavRail(
              selectedIndex: 0,
              unreadCount: 0,
              onSelect: (_) {},
              onOpenApp: (_) {},
            ),
          ),
        ),
      ),
    );

    for (final app in liquidDesktopApps) {
      expect(find.text(app.label), findsWidgets);
      expect(find.byIcon(app.icon), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('liquid-nav-rail-apps')), findsOneWidget);
    expect(find.text('Ver todas'), findsNothing);
  });

  testWidgets('el rail desktop abre la app al tocar su icono', (tester) async {
    var opened = -1;
    await tester.binding.setSurfaceSize(const Size(1200, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 1100)),
        child: MaterialApp(
          home: Scaffold(
            body: LiquidNavRail(
              selectedIndex: 0,
              unreadCount: 0,
              onSelect: (_) {},
              onOpenApp: (index) => opened = index,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Análisis'));
    await tester.pump();
    expect(opened, 1);

    await tester.ensureVisible(find.text('Asistente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asistente'));
    await tester.pump();
    expect(opened, 3);
  });

  testWidgets('si el rail no cabe muestra Ver todas y no hace scroll', (
    tester,
  ) async {
    FlutterError.onError = (details) {
      final text = details.toString();
      if (text.contains('overflowed') || text.contains('OVERFLOW')) {
        fail(text);
      }
      FlutterError.presentError(details);
    };

    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: LiquidNavRail(
              selectedIndex: 0,
              unreadCount: 0,
              onSelect: (index) => selected = index,
              onOpenApp: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('IoT'), findsOneWidget);
    expect(find.text('Eventos'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Ver todas'), findsOneWidget);
    expect(find.text('Registros'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Ver todas'));
    await tester.pump();
    expect(selected, liquidAppsIndex);
  });

  testWidgets('el rail desktop responde al tap de destino', (tester) async {
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidNavRail(
            selectedIndex: 0,
            unreadCount: 0,
            onSelect: (index) => selected = index,
            onOpenApp: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Perfil'));
    await tester.pump();
    expect(selected, liquidProfileIndex);
  });

  testWidgets('en desktop el rail flota también sobre Home', (tester) async {
    var tab = 0;
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                final wide = MediaQuery.sizeOf(context).width >= 980;
                final isHome = tab == 0;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isHome)
                      const ColoredBox(
                        color: Color(0xFF071820),
                        child: Center(child: Text('HOME_MAP')),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.only(
                          left: wide ? liquidNavRailExtent : 0,
                        ),
                        child: const Center(child: Text('OTHER_TAB')),
                      ),
                    if (wide)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: LiquidNavRail(
                          selectedIndex: tab,
                          unreadCount: 0,
                          onSelect: (index) => setState(() => tab = index),
                          onOpenApp: (_) {},
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('HOME_MAP'), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-nav-rail')), findsOneWidget);
    expect(find.text('Ubicaciones'), findsOneWidget);

    await tester.tap(find.text('Eventos'));
    await tester.pump();
    expect(find.text('OTHER_TAB'), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-nav-rail')), findsOneWidget);
  });
}
