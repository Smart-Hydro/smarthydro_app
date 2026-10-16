import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/n1/n1_api.dart';
import 'package:smarthydro_app/core/n1/n1_config.dart';
import 'package:smarthydro_app/core/n1/n1_models.dart';
import 'package:smarthydro_app/features/assistant/n1_buddy.dart';
import 'package:smarthydro_app/features/assistant/quick_ask.dart';

class _FakeN1Api extends N1Api {
  _FakeN1Api()
    : super(config: const N1Config(webAppUrl: 'https://example.test/exec'));

  @override
  bool get isConfigured => true;

  @override
  Future<N1Response> ask({
    required String token,
    required String requester,
    required String text,
    String? sessionId,
    List<int>? pointsAllowed,
  }) async {
    return const N1Response(ok: true, text: 'ok');
  }
}

void main() {
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
    expect(find.byTooltip('Pregunta rápida'), findsOneWidget);
  });
}
