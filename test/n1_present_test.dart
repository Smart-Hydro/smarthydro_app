import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/n1/n1_identity.dart';
import 'package:smarthydro_app/core/n1/n1_models.dart';
import 'package:smarthydro_app/core/n1/n1_present.dart';

void main() {
  test('limpia el panel crudo de N1 para el chat', () {
    const raw = '''
*Riego Chile* · 13 puntos

*Por punto:*
• Riego Chile – Agricola Bayona – Matias Fischer · activo · últ. 2026-10-19 07:00 · sin ticket SLA · DGA no reporta DGA
• Riego Chile – Agricola E Inversiones El Roble Limitada – Lecheria · activo · últ. 2026-10-19 07:00 · sin ticket SLA · DGA no reporta DGA
… quedan 8 ítems · usa los botones de abajo o pídemelos en Excel

*Desconectados: 0*

*Tickets abiertos: 0*

*Cumplimiento DGA:* 100% (2/2 cumplen) · Cumple 2
_Detalle de un punto: /estado Agricola Bayona Matias Fischer_

_Panel: 2026-10-20 17:12 hora Chile_

ℹ️ _DGA Mayor: es el estándar más exigente de la DGA; el punto debe enviar sus datos todos los días (con 2 días sin envío ya queda en riesgo)._
ℹ️ _sin ticket SLA: el punto está caído y todavía nadie abrió un ticket, o sea, nadie lo está gestionando._

 *Te sugiero:* Sin acciones pendientes con estos datos; vuelve a revisar después del próximo refresco del panel.
''';
    final shown = n1PresentText(raw);
    expect(shown, contains('Riego Chile · 13 puntos'));
    expect(shown, contains('Matias Fischer'));
    expect(shown, contains('Lecheria'));
    expect(shown, isNot(contains('Agricola Bayona')));
    expect(shown, isNot(contains('ℹ️')));
    expect(shown, isNot(contains('*Por punto*')));
    expect(shown, isNot(contains('usa los botones')));
    expect(shown, contains('quedan 8 ítems'));
    expect(shown, isNot(contains('/estado')));
    expect(shown, isNot(contains('_Panel:')));
    expect(shown, isNot(contains('sin ticket SLA')));
    expect(shown, contains('sin ticket'));
    expect(shown, contains('Desconectados: 0'));
    expect(shown, contains('Sugerencia'));
    expect(shown, isNot(contains('*')));
    expect(shown, isNot(contains('•')));

    final blocks = n1PresentBlocks(raw);
    expect(blocks.first.kind, N1BlockKind.heading);
    expect(blocks.first.text, 'Riego Chile · 13 puntos');
    final points = blocks.where((b) => b.kind == N1BlockKind.point).toList();
    expect(points, hasLength(2));
    expect(points.first.text, 'Matias Fischer');
    expect(points.first.tags, containsAll(['activo', 'sin ticket']));
    expect(blocks.any((b) => b.kind == N1BlockKind.stat), isTrue);
    expect(
      blocks.where((b) => b.kind == N1BlockKind.suggest).single.text,
      contains('Sin acciones pendientes'),
    );
  });

  test('una respuesta larga con async ya no se trata como pendiente', () {
    final pending = N1Response.fromJson({
      'ok': true,
      'async': true,
      'text': '⏳ cargando datos, reintenta en un momento',
    });
    expect(pending.isPending, isTrue);

    final done = N1Response.fromJson({
      'ok': true,
      'async': true,
      'pending': true,
      'text':
          'Riego Chile · 13 puntos\nDesconectados: 0\nTickets abiertos: 0\nCumplimiento DGA 100%',
    });
    expect(done.isPending, isFalse);
  });

  test('la pregunta no pega los nombres de puntos: N1 los toma como un solo punto', () {
    expect(
      n1DecorateAskText(
        'cómo están mis puntos',
        name: 'Felipe',
        clients: const ['Riego Chile'],
        points: const ['Matias Fischer', 'Lecheria', 'Pivote'],
      ),
      'cómo están mis puntos (cliente Riego Chile; soy Felipe)',
    );
    expect(
      n1PointNamesOf([
        {'title': 'Matias Fischer'},
        {'name': 'Lecheria'},
        {'title': 'Matias Fischer'},
      ]),
      ['Matias Fischer', 'Lecheria'],
    );
  });
}
