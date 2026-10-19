import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/shared/ui/hydro_ui.dart';
import 'package:smarthydro_app/shared/ui/point_tool_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la paleta se centra en el panel de la red, no en toda la ventana', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(width: 88, child: Center(child: Text('RAIL'))),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Color(0xFF081216),
                      child: Center(child: Text('POZO')),
                    ),
                    PointToolSheet(
                      title: 'Registros',
                      subtitle: 'P4',
                      onClose: _noop,
                      child: Center(child: Text('cuerpo-registros')),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 380, child: Center(child: Text('RESUMEN'))),
            ],
          ),
        ),
      ),
    );

    expect(find.text('POZO'), findsOneWidget);
    expect(find.text('Registros'), findsOneWidget);
    expect(find.text('cuerpo-registros'), findsOneWidget);
    expect(find.byType(HydroBackButton), findsNothing);
    expect(find.byKey(const Key('point-tool-sheet-handle')), findsNothing);

    final pozo = tester.getCenter(find.text('POZO'));
    final card = tester.getRect(find.byKey(const Key('point-tool-sheet-card')));
    final rail = tester.getRect(find.text('RAIL'));
    final summary = tester.getRect(find.text('RESUMEN'));
    final window = tester.getRect(find.byType(Scaffold).first);

    expect(card.center.dx, closeTo(pozo.dx, 24));
    expect(card.center.dx, isNot(closeTo(window.center.dx, 24)));
    expect(card.left, greaterThan(rail.right - 4));
    expect(card.right, lessThan(summary.left + 4));
  });

  testWidgets('WellPaletteHost deja el pozo montado y recorta al panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 88, child: Center(child: Text('RAIL'))),
              const Expanded(
                child: WellPaletteHost(
                  child: ColoredBox(
                    color: Color(0xFF081216),
                    child: Center(child: Text('POZO')),
                  ),
                ),
              ),
              const SizedBox(width: 380, child: Center(child: Text('RESUMEN'))),
            ],
          ),
        ),
      ),
    );

    final host = tester.state<WellPaletteHostState>(
      find.byType(WellPaletteHost),
    );
    host.show(
      const PointToolSheet(
        title: 'Registros',
        subtitle: 'P4',
        onClose: _noop,
        child: Center(child: Text('cuerpo-registros')),
      ),
    );
    await tester.pump();

    expect(find.text('POZO'), findsOneWidget);
    expect(find.text('cuerpo-registros'), findsOneWidget);

    final pozo = tester.getCenter(find.text('POZO'));
    final card = tester.getRect(find.byKey(const Key('point-tool-sheet-card')));
    final rail = tester.getRect(find.text('RAIL'));
    final summary = tester.getRect(find.text('RESUMEN'));
    final window = tester.getRect(find.byType(Scaffold).first);

    expect(card.center.dx, closeTo(pozo.dx, 24));
    expect((card.center.dx - window.center.dx).abs(), greaterThan(80));
    expect(card.left, greaterThan(rail.right - 4));
    expect(card.right, lessThan(summary.left + 4));
  });

  testWidgets('en el teléfono la paleta es una hoja inferior como Historial', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Color(0xFF081216),
                child: Center(child: Text('POZO')),
              ),
              PointToolSheet(
                title: 'Registros',
                subtitle: 'P4',
                fromBottom: true,
                onClose: _noop,
                child: Center(child: Text('cuerpo-registros')),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('POZO'), findsOneWidget);
    expect(find.byKey(const Key('point-tool-sheet-handle')), findsOneWidget);

    final card = tester.getRect(find.byKey(const Key('point-tool-sheet-card')));
    final screen = tester.getRect(find.byType(Scaffold).first);
    expect(card.bottom, closeTo(screen.bottom, 2));
    expect(card.left, closeTo(screen.left, 2));
    expect(card.right, closeTo(screen.right, 2));
    expect(card.top, greaterThan(screen.top + 40));
  });
}

void _noop() {}
