import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/avisos_inbox.dart';

void main() {
  final now = DateTime(2026, 10, 15, 16);

  Map<String, dynamic> event({
    required int id,
    required String severity,
    String type = 'DISCONNECTION',
    String title = 'Corte',
    String created = '2026-10-15T13:00:00',
    int pointId = 7,
    String pointName = 'Pozo Norte',
  }) => {
    'id': id,
    'severity': severity,
    'event_type': type,
    'title': title,
    'message': 'Detalle $title',
    'created': created,
    'point': {'id': pointId, 'name': pointName},
  };

  Future<void> pump(
    WidgetTester tester, {
    List<Map<String, dynamic>> events = const [],
    Map<String, dynamic> summary = const {'period_days': 7},
    String? eventsError,
    ValueChanged<int>? onOpenPoint,
    int? lockedPointId,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AvisosInbox(
            summary: summary,
            events: events,
            loading: false,
            eventsError: eventsError,
            onRefresh: () async {},
            onOpenPoint: onOpenPoint,
            lockedPointId: lockedPointId,
            now: now,
          ),
        ),
      ),
    );
  }

  test('el titular cuenta incidencias', () {
    expect(
      avisosHeadline(critical: 0, attention: 0),
      'Sin incidencias en estos registros',
    );
    expect(
      avisosHeadline(critical: 1, attention: 3),
      '1 crítica · 3 en atención',
    );
    expect(avisoShare(2, 3), 67);
    expect(avisoShare(0, 4), 0);
    final many = [
      for (var index = 0; index < 120; index++)
        event(
          id: index + 1,
          severity: 'INFO',
          title: 'Token',
          type: 'TOKEN_REFRESH',
          created:
              '2026-10-${(index % 9 + 1).toString().padLeft(2, '0')}T12:00:00',
        ),
    ];
    final sample = avisoLatestRecords(many);
    expect(sample, hasLength(avisoRecordLimit));
    DateTime stamp(Map<String, dynamic> item) =>
        DateTime.parse('${item['created']}');
    final oldestKept = sample
        .map(stamp)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final newestDropped = many
        .where((item) => !sample.contains(item))
        .map(stamp)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    expect(oldestKept.isBefore(newestDropped), isFalse);
  });

  test('la hora es relativa al reloj', () {
    expect(avisoWhen(DateTime(2026, 10, 15, 14), now: now), 'hace 2 h');
    expect(avisoWhen(DateTime(2026, 10, 14, 9, 5), now: now), 'Ayer 09:05');
    expect(
      avisoWhen(now.subtract(const Duration(seconds: 20)), now: now),
      'Ahora',
    );
  });

  test('el punto se lee aunque venga anidado', () {
    expect(
      avisoPointId({
        'ticket': {'catchment_point_id': 4},
      }),
      4,
    );
    expect(
      avisoPointName({
        'point': {'name': 'Estero'},
      }),
      'Estero',
    );
    expect(avisoEventLabel('DISCONNECTION'), 'Desconexión');
  });

  test('la etiqueta del gráfico de días incluye el mes', () {
    expect(avisoChartDayLabel(DateTime(2026, 10, 15)), '15 oct');
    expect(avisoChartDayLabel(DateTime(2026, 1, 3)), '3 ene');
  });

  testWidgets('en desktop el contenido queda centrado y no a todo el ancho', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pump(
      tester,
      events: [
        event(id: 1, severity: 'CRITICAL', created: '2026-10-15T10:00:00'),
        event(id: 2, severity: 'WARNING', created: '2026-10-15T11:00:00'),
      ],
    );

    expect(find.byKey(const ValueKey('avisos-stage')), findsOneWidget);
    final stage = tester.getSize(find.byKey(const ValueKey('avisos-stage')));
    expect(stage.width, lessThanOrEqualTo(880));
    expect(stage.width, greaterThan(320));
  });

  testWidgets('las barras de actividad tienen altura y color visibles', (
    tester,
  ) async {
    await pump(
      tester,
      events: [
        event(id: 1, severity: 'CRITICAL', created: '2026-10-13T10:00:00'),
        event(id: 2, severity: 'CRITICAL', created: '2026-10-14T10:00:00'),
        event(id: 3, severity: 'CRITICAL', created: '2026-10-15T10:00:00'),
        event(
          id: 4,
          severity: 'CRITICAL',
          created: '2026-10-15T12:00:00',
          title: 'Otro',
        ),
      ],
    );

    expect(find.text('Actividad'), findsOneWidget);
    final bars = find.byKey(const ValueKey('aviso-day-bar'));
    expect(bars, findsWidgets);
    for (final element in bars.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.height, greaterThan(24), reason: 'barra sin altura: $size');
      expect(size.width, greaterThan(8), reason: 'barra sin ancho: $size');
    }
    expect(find.byKey(const ValueKey('aviso-day-bar-fill')), findsWidgets);
    for (final element
        in find.byKey(const ValueKey('aviso-day-bar-fill')).evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(
        size.height,
        greaterThan(24),
        reason: 'relleno de barra invisible: $size',
      );
    }
  });

  test('los repetidos del mismo punto se ponderan', () {
    final clusters = avisoClusters([
      event(id: 2, severity: 'CRITICAL', title: 'Sin enlace'),
      event(
        id: 5,
        severity: 'CRITICAL',
        title: 'Sin enlace',
        created: '2026-10-15T11:00:00',
      ),
      event(
        id: 4,
        severity: 'WARNING',
        title: 'Salto de caudal',
        type: 'MASSIVE_JUMP_BLOCKED',
        pointId: 8,
        pointName: 'Pozo Sur',
        created: '2026-10-15T12:00:00',
      ),
    ]);

    expect(clusters, hasLength(2));
    expect(clusters.first.title, 'Sin enlace');
    expect(clusters.first.weight, 2);
    expect(clusters.first.pointName, 'Pozo Norte');
    expect(clusters.last.weight, 1);
  });

  testWidgets('críticas, el peso y el punto separan el historial', (
    tester,
  ) async {
    await pump(
      tester,
      events: [
        event(id: 2, severity: 'CRITICAL', title: 'Sin enlace'),
        event(
          id: 5,
          severity: 'CRITICAL',
          title: 'Sin enlace',
          created: '2026-10-15T11:00:00',
        ),
        event(
          id: 3,
          severity: 'INFO',
          title: 'Reconectado',
          type: 'RECONNECTION',
          created: '2026-10-15T10:00:00',
        ),
        event(
          id: 4,
          severity: 'WARNING',
          title: 'Salto de caudal',
          type: 'MASSIVE_JUMP_BLOCKED',
          pointId: 8,
          pointName: 'Pozo Sur',
          created: '2026-10-15T12:00:00',
        ),
      ],
    );

    expect(find.text('Soporte'), findsNothing);
    expect(find.text('Todos'), findsNothing);
    expect(find.text('Todo'), findsNothing);
    expect(find.text('Eventos'), findsNothing);
    expect(find.textContaining('últimos'), findsNothing);
    expect(find.text('Días de la muestra'), findsNothing);
    expect(find.text('En estos registros'), findsNothing);
    expect(find.text('Sin enlace'), findsOneWidget);
    expect(find.text('Salto de caudal'), findsNothing);
    expect(find.text('Reconectado'), findsNothing);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('15 oct'), findsOneWidget);
    expect(find.text('Severidad'), findsOneWidget);
    expect(find.text('Actividad'), findsOneWidget);
    expect(find.text('eventos'), findsOneWidget);
    expect(find.text('Críticas'), findsWidgets);
    expect(find.text('Atención'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('aviso-point-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('aviso-point-id:8')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Salto de caudal'), findsOneWidget);
    expect(find.text('Sin enlace'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('aviso-lens-critical')));
    await tester.pump();
    expect(find.text('Salto de caudal'), findsNothing);
    expect(find.text('No hay críticas'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('aviso-lens-attention')));
    await tester.pump();
    expect(find.text('Salto de caudal'), findsOneWidget);
    expect(find.text('Sin enlace'), findsNothing);
  });

  testWidgets('abrir un registro muestra el historial y el punto', (
    tester,
  ) async {
    int? opened;
    await pump(
      tester,
      events: [
        event(id: 2, severity: 'CRITICAL', title: 'Sin enlace'),
        event(
          id: 5,
          severity: 'CRITICAL',
          title: 'Sin enlace',
          created: '2026-10-15T11:00:00',
        ),
      ],
      onOpenPoint: (id) => opened = id,
    );

    expect(find.text('última hace 3 h'), findsOneWidget);
    expect(find.text('Ver punto'), findsNothing);

    await tester.tap(find.text('Sin enlace'));
    await tester.pump();

    expect(find.text('hace 3 h'), findsWidgets);
    expect(find.text('hace 5 h'), findsOneWidget);
    await tester.ensureVisible(find.text('Ver punto'));
    await tester.pump();
    await tester.tap(find.text('Ver punto'));
    await tester.pump();
    expect(opened, 7);
  });

  testWidgets('un punto fijo no mezcla el resto', (tester) async {
    await pump(
      tester,
      lockedPointId: 7,
      events: [
        event(id: 2, severity: 'CRITICAL', title: 'Sin enlace'),
        event(
          id: 4,
          severity: 'WARNING',
          title: 'Salto de caudal',
          pointId: 8,
          pointName: 'Pozo Sur',
        ),
      ],
    );

    expect(find.text('Sin enlace'), findsOneWidget);
    expect(find.text('Salto de caudal'), findsNothing);
    expect(find.text('Punto de captación'), findsNothing);
  });

  testWidgets('un error no se disfraza de calma', (tester) async {
    await pump(tester, eventsError: 'No se pudo cargar esta sección.');

    expect(find.text('No se pudo cargar esta sección.'), findsOneWidget);
    expect(find.text('La consola está en calma'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('aviso-lens-critical')));
    await tester.pump();
    expect(find.text('No se pudo cargar esta sección.'), findsOneWidget);
    expect(find.text('No hay críticas'), findsNothing);
  });
}
