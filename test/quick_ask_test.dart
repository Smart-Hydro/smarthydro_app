import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthydro_app/core/n1/n1_api.dart';
import 'package:smarthydro_app/core/n1/n1_config.dart';
import 'package:smarthydro_app/core/n1/n1_models.dart';
import 'package:smarthydro_app/features/assistant/n1_buddy.dart';
import 'package:smarthydro_app/features/assistant/quick_ask.dart';
import 'package:smarthydro_app/shared/widgets/hydro_glyph.dart';

class _FakeN1Api extends N1Api {
  _FakeN1Api({this.reply = 'ok'})
    : super(config: const N1Config(webAppUrl: 'https://example.test/exec'));

  final String reply;

  @override
  bool get isConfigured => true;

  @override
  Future<N1Response> ask({
    required String token,
    required String requester,
    required String text,
    String? sessionId,
    List<int>? pointsAllowed,
    String? name,
    String? client,
    List<String>? clients,
    List<String>? pointNames,
  }) async {
    return N1Response(ok: true, text: reply);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('el peek flotante muestra la mascota N1', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: QuickAsk(
              peek: true,
              n1Api: _FakeN1Api(),
              token: 'tok',
              email: 'ana@empresa.cl',
              pointIds: const [4],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('n1-quick-buddy')), findsOneWidget);
    expect(find.byType(N1Buddy), findsOneWidget);
    final glyph = tester.widget<HydroGlyph>(find.byType(HydroGlyph));
    expect(glyph.kind, HydroGlyphKind.asistente);
    expect(find.byTooltip('Asistente N1'), findsOneWidget);
    final idle = tester.getSize(find.byKey(const ValueKey('n1-quick-buddy')));
    expect(idle.shortestSide, lessThan(42));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('n1-quick-buddy'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    final hot = tester.getSize(find.byKey(const ValueKey('n1-quick-buddy')));
    expect(hot.shortestSide, greaterThan(idle.shortestSide + 4));
  });

  testWidgets('el panel abierto cubre el fondo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColoredBox(
            color: const Color(0xFF00FF00),
            child: Align(
              alignment: Alignment.bottomRight,
              child: QuickAsk(
                peek: true,
                n1Api: _FakeN1Api(),
                token: 'tok',
                email: 'ana@empresa.cl',
                pointIds: const [4],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Asistente N1'));
    await tester.pump();
    final material = tester.widget<Material>(
      find.byKey(const ValueKey('n1-quick-panel')),
    );
    expect(material.color, isNotNull);
    expect(material.color!.a, greaterThan(0.9));
    final size = tester.getSize(find.byKey(const ValueKey('n1-quick-panel')));
    expect(size.width, greaterThanOrEqualTo(340));
    expect(size.height, greaterThanOrEqualTo(320));
    expect(find.text('N1 · SmartHydro'), findsOneWidget);
    expect(find.text('Pregunta a N1…'), findsOneWidget);
    expect(find.text('Pregunta rápida'), findsNothing);
  });

  testWidgets('el chat flotante muestra el hilo y responde', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: QuickAsk(
              peek: true,
              n1Api: _FakeN1Api(reply: 'P4 está en línea'),
              token: 'tok',
              email: 'ana@empresa.cl',
              name: 'Ana',
              pointIds: const [4],
              pointNames: const ['P4'],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Asistente N1'));
    await tester.pump();
    expect(find.textContaining('Veo 1 punto'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'cómo está P4');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('cómo está P4'), findsOneWidget);
    expect(find.text('P4 está en línea'), findsOneWidget);
  });

  testWidgets('la barra de pregunta rápida usa el glifo Asistente', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickAsk(
            n1Api: _FakeN1Api(),
            token: 'tok',
            email: 'ana@empresa.cl',
            pointIds: const [4],
          ),
        ),
      ),
    );

    expect(find.byType(N1Buddy), findsOneWidget);
    final glyph = tester.widget<HydroGlyph>(find.byType(HydroGlyph));
    expect(glyph.kind, HydroGlyphKind.asistente);
  });
}
