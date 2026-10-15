import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smarthydro_app/features/dashboard/widgets/capture_network_map.dart';

void main() {
  test('lee coordenadas y descarta el cero', () {
    expect(
      captureLatLng({'lat': -33.45, 'lon': -70.66}),
      const LatLng(-33.45, -70.66),
    );
    expect(
      captureLatLng({'latitude': '-33,45', 'longitude': '-70,66'}),
      const LatLng(-33.45, -70.66),
    );
    expect(captureLatLng({'lat': 0, 'lon': 0}), isNull);
    expect(captureLatLng({'title': 'Pozo'}), isNull);
  });

  test('layoutPointWindows con 0 no emite rects', () {
    expect(
      layoutPointWindows(area: const Size(1200, 800), count: 0),
      isEmpty,
    );
  });

  test('layoutPointWindows un panel abajo a la izquierda', () {
    final rects = layoutPointWindows(
      area: const Size(1200, 800),
      count: 1,
      bottomInset: 8,
    );
    expect(rects, hasLength(1));
    expect(rects.first.width, 340);
    expect(rects.first.height, 228);
    expect(rects.first.left, 0);
    expect(rects.first.bottom, 800 - 8);
  });

  test('layoutPointWindows tres paneles caben en una fila', () {
    final rects = layoutPointWindows(
      area: const Size(1200, 800),
      count: 3,
    );
    expect(rects, hasLength(3));
    expect(rects[0].top, rects[1].top);
    expect(rects[1].top, rects[2].top);
    expect(rects[0].left, lessThan(rects[1].left));
    expect(rects[1].left, lessThan(rects[2].left));
  });

  test('layoutPointWindows el cuarto pasa a la fila de arriba', () {
    final rects = layoutPointWindows(
      area: const Size(1200, 800),
      count: 4,
      windowWidth: 340,
      gap: 12,
    );
    expect(rects, hasLength(4));
    expect(rects[3].bottom, lessThanOrEqualTo(rects[0].top - 12));
  });

  test('layoutPointWindows nunca es más ancho que windowWidth', () {
    final rects = layoutPointWindows(
      area: const Size(900, 600),
      count: 5,
      windowWidth: 340,
    );
    for (final rect in rects) {
      expect(rect.width, 340);
      expect(rect.height, 228);
    }
  });

  test('el logger calza en la cuadrícula y cabe el nombre', () {
    final narrow = captureLoggerWidthFor('P4');
    final wide = captureLoggerWidthFor('Pozo Norte largo');
    final marked = captureLoggerWidthFor('P4', compliance: true);
    expect(wide, greaterThan(narrow));
    expect(marked, greaterThan(narrow));
    expect(captureGridSpan(narrow) % captureBoardStep, 0);
    final rects = placeNodeLabels(
      const [Offset(180, 280), Offset(190, 284), Offset(40, 40)],
      const Size(390, 700),
      top: 90,
      bottom: 80,
      widths: [narrow, wide, narrow],
      groups: const ['Norte', 'Norte', 'Sur'],
    );
    expect(rects[0].width, captureGridSpan(narrow));
    expect(rects[1].width, captureGridSpan(wide));
    expect(rects, hasLength(3));
    for (var i = 0; i < rects.length; i++) {
      expect(rects[i].height % captureBoardStep, 0);
      expect(rects[i].width % captureBoardStep, 0);
      expect(_onBoardLine(rects[i].left), closeTo(0, 0.01));
      expect(_onBoardLine(rects[i].top), closeTo(0, 0.01));
      expect(rects[i].top, greaterThanOrEqualTo(90));
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].inflate(2).overlaps(rects[j]), isFalse);
      }
    }
  });

  test('hay como máximo tres loggers por fila y la red los une', () {
    final rects = placeNodeLabels(
      const [Offset(0, 0), Offset(10, 0), Offset(20, 0), Offset(30, 0)],
      const Size(390, 700),
      top: 90,
      bottom: 40,
      widths: const [70, 70, 70, 90],
    );

    expect(rects[1].top, closeTo(rects[0].top, 0.01));
    expect(rects[2].top, closeTo(rects[0].top, 0.01));
    expect(rects[3].top, greaterThan(rects[0].bottom));
    expect(rects[3].left, closeTo(rects[0].left, 0.01));
    expect(rects[0].right, lessThanOrEqualTo(rects[1].left));
    final neighbors = captureGridNeighbors(rects);
    expect(neighbors, contains((0, 1)));
    expect(neighbors, contains((1, 2)));
    expect(neighbors, contains((0, 3)));
    expect(neighbors, isNot(contains((2, 3))));
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].inflate(2).overlaps(rects[j]), isFalse);
      }
    }
  });

  test('una página cabe y el resto espera al siguiente', () {
    final page = captureSchemePageSize(
      const Size(390, 640),
      top: 90,
      bottom: 220,
    );
    expect(page, lessThan(39));
    expect(page, greaterThanOrEqualTo(2));
    final scheme = placeCaptureScheme(
      page,
      const Size(390, 640),
      top: 90,
      bottom: 220,
    );
    expect(scheme.plates, hasLength(page));
    expect(scheme.hub.width, captureHubSize);
    for (final plate in scheme.plates) {
      expect(plate.overlaps(scheme.hub), isFalse);
      expect(plate.top, greaterThanOrEqualTo(90));
      expect(plate.bottom, lessThanOrEqualTo(640 - 220 + 1));
    }
    final link = captureHubLink(scheme.plates.first, scheme.hub);
    expect(link.length, greaterThanOrEqualTo(2));
    for (var i = 0; i < link.length - 1; i++) {
      final sameAxis =
          link[i].dx == link[i + 1].dx || link[i].dy == link[i + 1].dy;
      expect(sameAxis, isTrue);
    }
  });

  test('las placas del esquema miden igual y dejan ver el enlace', () {
    const plate = capturePlateWidth;
    final rects = placeNodeLabels(
      const [Offset(0, 0), Offset(10, 0), Offset(20, 0), Offset(30, 0)],
      const Size(390, 700),
      top: 90,
      bottom: 40,
      widths: const [plate, plate, plate, plate],
      heights: const [
        capturePlateHeight,
        capturePlateHeight,
        capturePlateHeight,
        capturePlateHeight,
      ],
    );

    expect(rects[2].top, closeTo(rects[0].top, 0.01));
    expect(rects[1].left - rects[0].right, closeTo(capturePlateGap, 0.01));
    expect(rects[3].top - rects[0].bottom, closeTo(capturePlateGap, 0.01));
    for (final rect in rects) {
      expect(rect.width, plate);
      expect(rect.height, capturePlateHeight);
    }
  });

  test('el bloque se sienta al medio y el nombre largo ensancha', () {
    final narrow = captureLoggerWidthFor('P4');
    const longName = 'Estación de bombeo Santa Macarena Norte';
    final wide = captureLoggerWidthFor(longName);
    expect(wide, greaterThan(narrow));
    expect(wide, greaterThan(220));
    expect(captureCenterShift(slack: 96), closeTo(48, 0.01));
    expect(captureCenterShift(slack: 10), 0);
    expect(captureCenterShift(slack: -96), closeTo(-48, 0.01));

    final rects = placeNodeLabels(
      const [Offset(10, 10)],
      const Size(390, 700),
      top: 90,
      bottom: 80,
      widths: [narrow],
    );
    final viewCenter = (captureEdgePad + (390 - captureEdgePad)) / 2;
    expect(rects.single.center.dx, closeTo(viewCenter, captureBoardStep));
    expect(rects.single.left, greaterThanOrEqualTo(captureEdgePad - 0.01));
    expect(rects.single.right, lessThanOrEqualTo(390 - captureEdgePad + 0.01));
    expect(
      rects.single.height,
      captureGridSpan(captureLoggerHeight, minSteps: 1),
    );
    expect(_onBoardLine(rects.single.top), closeTo(0, 0.01));
    expect(rects.single.top, greaterThanOrEqualTo(90));
    final windowMidY = (90 + (700 - 80)) / 2;
    expect(rects.single.center.dy, closeTo(windowMidY, captureBoardStep));
    final huge = captureLoggerWidthFor(
      'Estación de bombeo Santa Macarena Norte del valle central',
    );
    final grown = placeNodeLabels(
      const [Offset(10, 10)],
      const Size(390, 700),
      top: 90,
      bottom: 80,
      widths: [huge],
    );
    expect(huge, greaterThan(390 - 2 * captureEdgePad));
    expect(grown.single.center.dx, closeTo(viewCenter, captureBoardStep));
    expect(grown.single.right, greaterThan(390 - captureEdgePad));
    expect(grown.single.width, captureGridSpan(huge));
    expect(_onBoardLine(grown.single.left), closeTo(0, 0.01));
    final leftGap = grown.single.left - captureEdgePad;
    final rightGap = (390 - captureEdgePad) - grown.single.right;
    expect(
      (leftGap - rightGap).abs(),
      lessThanOrEqualTo(captureBoardStep + 0.01),
    );
  });

  test('la tag de variable solo usa datos reales', () {
    expect(captureVariableTags({'type_dga': 'SUBTERRANEO'}), isEmpty);
    expect(
      captureVariableTags({
        'latest_telemetry': {'flow': 1.2, 'nivel': 3},
      }),
      ['Caudal', 'Nivel'],
    );
    expect(
      captureVariableTags({
        'variables': [
          {'type_variable': 'CAUDAL', 'str_variable': 'ai1'},
          {'type_variable': 'NIVEL', 'str_variable': 'ai2'},
        ],
      }),
      ['Caudal', 'Nivel'],
    );
  });

  test('el enlace dobla en la cuadrícula', () {
    expect(captureGridLink(const Offset(20, 64), const Offset(180, 64)), [
      const Offset(20, 64),
      const Offset(180, 64),
    ]);
    expect(captureGridLink(const Offset(20, 64), const Offset(180, 128)), [
      const Offset(20, 64),
      const Offset(180, 64),
      const Offset(180, 128),
    ]);
  });

  test('los enlaces al hub llegan en puntos distintos y no se cruzan', () {
    final scheme = placeCaptureScheme(
      8,
      const Size(420, 720),
      top: 80,
      bottom: 48,
    );
    final links = captureHubLinks(scheme.plates, scheme.hub);
    expect(links, hasLength(8));
    final ends = <Offset>[];
    for (final link in links) {
      expect(link.length, greaterThanOrEqualTo(2));
      ends.add(link.last);
      for (var i = 0; i < link.length - 1; i++) {
        final sameAxis =
            link[i].dx == link[i + 1].dx || link[i].dy == link[i + 1].dy;
        expect(sameAxis, isTrue);
      }
    }
    expect(_orthogonalPolylinesCross(links), isFalse);
  });

  test('el cumplimiento solo aparece con ficha DGA', () {
    expect(captureHasCompliance({'type_dga': 'SUBTERRANEO'}), isFalse);
    expect(captureHasCompliance({'send_dga': true, 'code_dga': 'X1'}), isTrue);
    expect(
      captureHasCompliance({
        'dga': {'send_dga': true, 'code_dga': 'X1'},
      }),
      isTrue,
    );
    expect(captureComplianceLevel({'title': 'P'}), isNull);
    expect(
      captureComplianceLevel({
        'compliance_warning': {'level': 'warning'},
      }),
      'warning',
    );
  });

  test('el resumen cuenta lo que hay en la vista', () {
    expect(captureViewSummary(const []), 'Nada en esta vista');
    final sample = [
      {
        'latest_telemetry': {
          'date_time_medition': '2026-10-14T15:00:00Z',
          'days_not_connection': 0,
        },
      },
      {
        'latest_telemetry': {'days_not_connection': 3},
      },
      {
        'latest_telemetry': {
          'date_time_medition': '2026-10-14T15:00:00Z',
          'is_error': true,
        },
      },
    ];
    expect(captureLinkCounts(sample), (connected: 1, warning: 1, incident: 1));
    expect(
      captureViewSummary(sample),
      '1 conectado · 1 advertencia · 1 incidencia',
    );
  });

  test('el perfil del punto solo dice lo que viene', () {
    expect(captureKindLabel({'type_dga': 'SUPERFICIAL'}), 'Superficial');
    expect(captureKindLabel({'type_dga': 'SUBTERRANEO'}), 'Pozo');
    expect(captureProviderLabel({'provider': 'nettra'}), 'Nettra');
    expect(captureProviderLabel({'title': 'Pozo'}), 'Sin modelo');
    expect(captureComplianceLabel({'title': 'Pozo'}), 'Sin cumplimiento');
    expect(
      captureComplianceLabel({'send_dga': true, 'code_dga': 'X1'}),
      'Con cumplimiento',
    );
    expect(
      captureComplianceLabel(
        {'title': 'Pozo'},
        compliance: {
          'point_id': 4,
          'compliance_warning': {'level': 'warning'},
        },
      ),
      'Cerca del límite',
    );
    expect(
      captureComplianceLabel({'title': 'Pozo'}, compliance: {'point_id': 4}),
      'Sin caudal autorizado',
    );
    final tickets = captureTicketsForPoint(
      {'id': 4},
      [
        {'id': 9, 'title': 'Sensor mudo', 'status': 'ABIERTO', 'point_id': 4},
        {'id': 10, 'title': 'Otro fundo', 'status': 'ABIERTO', 'point_id': 8},
        {
          'id': 11,
          'title': 'Sensor mudo cliente',
          'status': 'ABIERTO',
          'origin': 'CLIENTE',
          'point_id': 4,
        },
        {
          'id': 12,
          'title': 'Alerta interna',
          'status': 'ABIERTO',
          'origin': 'SISTEMA',
          'point_id': 4,
        },
        {
          'id': 13,
          'title': 'Caída de enlace',
          'event_type': 'LINK_DOWN',
          'severity': 'WARNING',
          'point_id': 4,
        },
        {'id': 14, 'title': 'Sin caudal', 'severity': 'ALERT', 'point_id': 4},
      ],
    );
    expect(tickets, hasLength(2));
    expect(captureTicketLine(tickets.first), 'Sensor mudo · abierto');
    expect(captureTicketLine(tickets.last), 'Sensor mudo cliente · abierto');
    expect(
      tickets.any((ticket) => ticket['title'] == 'Alerta interna'),
      isFalse,
    );
    expect(
      tickets.any((ticket) => ticket['title'] == 'Caída de enlace'),
      isFalse,
    );
    expect(tickets.any((ticket) => ticket['title'] == 'Sin caudal'), isFalse);
    expect(captureTicketLine({'title': 'Sin estado'}), 'Sin estado');
    expect(
      captureComplianceFor(
        {'id': 4},
        [
          {'point_id': 8},
          {
            'point_id': 4,
            'compliance_warning': {'level': 'safe'},
          },
        ],
      )?['compliance_warning'],
      {'level': 'safe'},
    );
  });

  test('el logger dice frecuencia, próxima medición y variables', () {
    expect(captureFrequencyLabel({'frecuency': 15}), '15 min');
    expect(captureFrequencyLabel({'frequency': '30'}), '30 min');
    expect(captureFrequencyLabel({'title': 'Pozo'}), 'Sin frecuencia');
    expect(captureFrequencyLabel({'frecuency': 0}), 'Sin frecuencia');
    expect(captureNextReading({'frecuency': 15}), 'Sin programar');

    final point = {
      'frequency': 15,
      'latest_telemetry': {'date_time_medition': '2026-10-14T15:00:00Z'},
    };
    final next = DateTime.parse(
      '2026-10-14T15:00:00Z',
    ).toLocal().add(const Duration(minutes: 15));
    String two(int value) => value.toString().padLeft(2, '0');
    expect(
      captureNextReading(point),
      '${two(next.day)}/${two(next.month)} ${two(next.hour)}:${two(next.minute)}',
    );
    expect(
      captureVariableLabel({
        'variables': [
          {'type_variable': 'CAUDAL', 'str_variable': 'ai1ActualValue'},
          {'type_variable': 'NIVEL', 'str_variable': 'ai2'},
        ],
      }),
      'Caudal · ai1ActualValue, Nivel · ai2',
    );
    expect(
      captureVariableLabel({
        'latest_telemetry': {'flow': 1.2, 'total': 10},
      }),
      'Caudal · Acumulado',
    );
    expect(captureVariableLabel({'title': 'Pozo'}), 'Sin variables');
  });

  test('la ficha habla de ubicación o avisa sin GPS', () {
    expect(
      captureLocationLabel({'lat': -33.45, 'lon': -70.66}),
      '-33.45000, -70.66000',
    );
    expect(captureLocationLabel({'title': 'Pozo'}), 'Sin ubicación GPS');
  });

  test('la red une los puntos de un proyecto y después los proyectos', () {
    final edges = captureNetworkEdges(
      projects: const ['Norte', 'Norte', 'Sur', 'Sur'],
      positions: const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(10, 0),
        Offset(11, 0),
      ],
    );

    expect(edges, hasLength(3));
    expect(edges, contains((0, 1)));
    expect(edges, contains((2, 3)));
    expect(
      edges.where((edge) {
        final same =
            (edge.$1 < 2 && edge.$2 < 2) || (edge.$1 >= 2 && edge.$2 >= 2);
        return !same;
      }),
      hasLength(1),
    );
  });

  test('la vista esquemática deja los nodos bajo el título', () {
    final offsets = layoutCaptureNodes(const Size(390, 640), const [
      'Norte',
      'Norte',
      'Sur',
      'Este',
      'Este',
    ]);

    for (final offset in offsets) {
      expect(offset.dx, inInclusiveRange(40, 350));
      expect(offset.dy, inInclusiveRange(118, 556));
    }
  });

  test('el encuadre deja ver todos los puntos con GPS', () {
    final camera = captureCameraFor(const Size(420, 720), const [
      LatLng(-33.45, -70.66),
      LatLng(-33.52, -70.72),
      LatLng(-33.61, -70.58),
    ]);

    expect(camera.zoom, inInclusiveRange(7, 13));
    expect(camera.center.latitude, closeTo(-33.53, 0.02));
    expect(camera.center.longitude, closeTo(-70.65, 0.02));
  });

  test('la intensidad del ripple crece con el caudal y el activo', () {
    final quiet = _point(id: 1, title: 'Quiet', project: 'A', flow: 0);
    final flowing = _point(id: 2, title: 'Flow', project: 'A', flow: 12);
    final maxFlow = 12.0;

    final ambient = captureRippleStrength(
      point: quiet,
      selected: false,
      maxFlow: maxFlow,
    );
    final activeQuiet = captureRippleStrength(
      point: quiet,
      selected: true,
      maxFlow: maxFlow,
    );
    final flowingStrength = captureRippleStrength(
      point: flowing,
      selected: false,
      maxFlow: maxFlow,
    );
    final activeFlowing = captureRippleStrength(
      point: flowing,
      selected: true,
      maxFlow: maxFlow,
    );

    expect(ambient, inInclusiveRange(0.12, 0.35));
    expect(flowingStrength, greaterThan(ambient));
    expect(activeQuiet, greaterThan(ambient));
    expect(activeFlowing, greaterThan(flowingStrength));
    expect(activeFlowing, lessThanOrEqualTo(1.0));
  });

  test('el líder une el borde del chip con el beacon en línea recta', () {
    const chip = Rect.fromLTWH(20, 40, 148, 46);
    const beacon = Offset(220, 280);
    final path = captureLeaderPath(chip, beacon);

    expect(path.getBounds().width, greaterThan(40));
    expect(path.getBounds().height, greaterThan(40));
    final metrics = path.computeMetrics().toList();
    expect(metrics, isNotEmpty);
    final start = metrics.first.getTangentForOffset(0)!.position;
    final end = metrics.first
        .getTangentForOffset(metrics.first.length)!
        .position;
    expect((start - chip.center).distance, lessThan(90));
    expect((end - beacon).distance, lessThan(8));
    // Recta: el punto medio del trazo queda cerca del segmento start→end.
    final mid = metrics.first
        .getTangentForOffset(metrics.first.length * 0.5)!
        .position;
    final expected = Offset.lerp(start, end, 0.5)!;
    expect((mid - expected).distance, lessThan(2));
  });

  test('las fichas de puntos cercanos no se montan', () {
    final anchors = [
      for (var index = 0; index < 6; index++) Offset(180, 220 + index * 3),
    ];
    final chips = placeCaptureChips(anchors, const Size(390, 760));

    expect(chips, hasLength(6));
    for (var i = 0; i < chips.length; i++) {
      for (var j = i + 1; j < chips.length; j++) {
        expect(chips[i].inflate(2).overlaps(chips[j]), isFalse);
      }
    }
  });

  test('el paneo calza en un cuadro y respeta el margen', () {
    expect(snapBoardPan(const Offset(20, 50)), const Offset(16, 48));
    const view = Rect.fromLTRB(20, 80, 370, 700);
    const content = Rect.fromLTRB(40, 120, 300, 500);
    final pushed = clampBoardPan(
      pan: const Offset(-100, -80),
      content: content,
      view: view,
    );
    final moved = content.shift(pushed);
    expect(moved.left, greaterThanOrEqualTo(view.left - 0.01));
    expect(moved.top, greaterThanOrEqualTo(view.top - 0.01));
    expect(moved.right, lessThanOrEqualTo(view.right + 0.01));
    expect(moved.bottom, lessThanOrEqualTo(view.bottom + 0.01));
  });

  test('el resumen deja 10 px libres sobre el chip', () {
    final insets = captureResumenInsets(bottomInset: 88, handleHeight: 36);
    expect(insets.handleBottom, 88);
    expect(insets.cardClearance, 88 + 36 + 10);
  });

  test('una ficha baja se sienta sobre el resumen y una alta no', () {
    const floor = 800 - 134.0;
    final low = seatCaptureChipTop(
      preferredTop: 640,
      height: 176,
      maxBottom: floor,
      minTop: 8,
    );
    expect(low + 176, closeTo(floor, 0.01));
    expect(low, lessThan(640));

    final high = seatCaptureChipTop(
      preferredTop: 16,
      height: 176,
      maxBottom: floor,
      minTop: 8,
    );
    expect(high, 16);
  });

  test('al abrir una ficha baja el borde no pasa el margen', () {
    const size = Size(390, 800);
    const clearance = 134.0;
    final opened = repelCaptureChips(
      chips: const [Rect.fromLTWH(12, 640, 136, 48)],
      selected: 0,
      size: size,
      expandedWidth: 220,
      expandedHeight: 176,
      bottomClearance: clearance,
    );
    expect(opened.single.bottom, closeTo(size.height - clearance, 0.01));
    expect(opened.single.top, lessThan(640));
  });

  test('al abrir una ficha las demás se apartan', () {
    const size = Size(420, 720);
    final base = placeCaptureChips(const [
      Offset(80, 120),
      Offset(80, 180),
      Offset(80, 240),
      Offset(340, 200),
    ], size);
    final opened = repelCaptureChips(
      chips: base,
      selected: 1,
      size: size,
      expandedWidth: 220,
      expandedHeight: 176,
    );

    expect(opened, hasLength(base.length));
    expect(opened[1].width, greaterThan(base[1].width - 1));
    expect(opened[1].height, greaterThan(base[1].height - 1));
    for (var i = 0; i < opened.length; i++) {
      if (i == 1) continue;
      expect(
        opened[i].inflate(2).overlaps(opened[1]),
        isFalse,
        reason: 'ficha $i ${opened[i]} pisa la abierta ${opened[1]}',
      );
    }
  });

  test('las fichas se reparte por los bordes y dejan el centro libre', () {
    const size = Size(420, 720);
    final anchors = [
      const Offset(210, 360),
      const Offset(160, 300),
      const Offset(260, 400),
      const Offset(200, 340),
      const Offset(240, 380),
      const Offset(180, 420),
    ];
    final chips = placeCaptureChips(anchors, size);
    expect(chips, hasLength(anchors.length));

    for (final chip in chips) {
      final ny = chip.center.dy / size.height;
      final onBand = ny < 0.28 || ny > 0.72;
      expect(onBand, isTrue, reason: 'ficha $chip no está arriba/abajo');
      for (final anchor in anchors) {
        expect(
          chip.inflate(4).overlaps(Rect.fromCircle(center: anchor, radius: 40)),
          isFalse,
          reason: 'ficha $chip pisa el punto $anchor',
        );
      }
    }
  });

  test('muchas fichas en una pantalla angosta no se montan', () {
    final anchors = [
      for (var index = 0; index < 13; index++)
        Offset(48.0 + (index % 4) * 78, 64.0 + (index ~/ 4) * 40),
    ];
    final chips = placeCaptureChips(anchors, const Size(390, 760));

    expect(chips, hasLength(13));
    for (var i = 0; i < chips.length; i++) {
      for (var j = i + 1; j < chips.length; j++) {
        expect(chips[i].inflate(2).overlaps(chips[j]), isFalse);
      }
    }
  });

  test('un solo punto no dibuja enlaces', () {
    expect(
      captureNetworkEdges(
        projects: const ['Norte'],
        positions: const [Offset(0, 0)],
      ),
      isEmpty,
    );
  });

  testWidgets('sin GPS muestra la red y abre el punto', (tester) async {
    Map<String, dynamic>? opened;
    final points = [
      _point(id: 1, title: 'Pozo Norte', project: 'Fundo'),
      _point(id: 2, title: 'Canal Sur', project: 'Fundo', surface: true),
      _point(id: 3, title: 'Pozo Este', project: 'Valle', gap: true),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 640,
            child: _map(
              points: points,
              onPointSelected: (point) => opened = point,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Esquema de telemetría'), findsOneWidget);
    expect(find.text('En esta vista'), findsNothing);
    expect(find.textContaining('conectados'), findsOneWidget);
    expect(find.text('Pozo Norte'), findsWidgets);
    expect(find.text('Canal Sur'), findsWidgets);
    expect(find.text('Pozo Este'), findsWidgets);
    expect(find.text('Conectado'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('capture-node-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(opened, isNull);
    expect(find.text('En esta vista'), findsNothing);
    expect(find.text('1 punto'), findsNothing);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Logger'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('capture-quick-ver')));
    // Animación de ingreso (~920ms) + ticker continuo: no usar pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(opened?['title'], 'Pozo Norte');
    expect(tester.takeException(), isNull);
  });

  testWidgets('al elegir un punto se marca y la ficha muestra el perfil', (
    tester,
  ) async {
    Map<String, dynamic>? support;
    final point = {
      'id': 4,
      'title': 'Pozo Norte',
      'project_name': 'Fundo',
      'type_dga': 'SUBTERRANEO',
      'provider': 'nettra',
      'frecuency': 15,
      'send_dga': true,
      'code_dga': 'OB-1',
      'variables': [
        {'type_variable': 'CAUDAL', 'str_variable': 'ai1'},
      ],
      'latest_telemetry': {
        'date_time_medition': '2026-10-14T15:00:00Z',
        'days_not_connection': 0,
        'flow': 1.2,
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 640,
            child: _map(
              points: [
                point,
                _point(id: 5, title: 'Canal Sur', project: 'Fundo'),
              ],
              openTickets: const [
                {
                  'id': 9,
                  'title': 'Sensor mudo',
                  'status': 'ABIERTO',
                  'origin': 'CLIENTE',
                  'point_id': 4,
                },
                {
                  'id': 10,
                  'title': 'Otro fundo',
                  'status': 'ABIERTO',
                  'origin': 'CLIENTE',
                  'point_id': 8,
                },
                {
                  'id': 12,
                  'title': 'Alerta interna',
                  'status': 'ABIERTO',
                  'origin': 'SISTEMA',
                  'point_id': 4,
                },
                {
                  'id': 13,
                  'title': 'Caída de enlace',
                  'event_type': 'LINK_DOWN',
                  'severity': 'WARNING',
                  'point_id': 4,
                },
              ],
              compliance: const [
                {
                  'point_id': 4,
                  'compliance_warning': {'level': 'safe'},
                },
              ],
              onPointSelected: (_) {},
              onRequestSupport: (value) => support = value,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('capture-node-4')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));

    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('capture-node-4')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.selected, isTrue);
    final other = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('capture-node-5')),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(other.opacity, 0.38);
    expect(find.text('Pozo'), findsOneWidget);
    expect(find.text('Nettra'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('Dentro del límite'), findsOneWidget);
    expect(find.textContaining('1.20 L/s'), findsOneWidget);
    expect(find.text('Caudal · ai1'), findsOneWidget);
    expect(find.text('Soporte'), findsOneWidget);
    expect(find.text('Sensor mudo · abierto'), findsOneWidget);
    expect(find.textContaining('Alerta interna'), findsNothing);
    expect(find.textContaining('Caída de enlace'), findsNothing);
    expect(find.textContaining('Otro fundo'), findsNothing);
    expect(find.text('Siguiente medición'), findsOneWidget);
    expect(find.text('Pedir soporte'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('capture-quick-support')));
    await tester.pump();
    expect(support?['title'], 'Pozo Norte');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'la ficha del punto es alta, con estado al lado y caja de logger',
    (tester) async {
      final point = {
        'id': 4,
        'title': 'Pozo Norte',
        'project_name': 'Fundo',
        'type_dga': 'SUBTERRANEO',
        'provider': 'nettra',
        'frecuency': 15,
        'latest_telemetry': {
          'date_time_medition': '2026-10-14T15:00:00Z',
          'days_not_connection': 0,
          'flow': 1.2,
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 640,
              child: _map(
                points: [point],
                onPointSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('capture-node-4')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 280));

      final panel = tester.getRect(
        find.byKey(const ValueKey('capture-view-records')),
      );
      expect(panel.height, greaterThanOrEqualTo(220));
      expect(find.textContaining('Pozo Norte · Conectado'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('capture-focus-logger')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('con GPS muestra el mapa de la red', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 640,
            child: _map(
              points: [
                _point(
                  id: 7,
                  title: 'Pozo Norte',
                  project: 'Fundo',
                  lat: -33.45,
                  lon: -70.66,
                  flow: 1.2,
                ),
                _point(
                  id: 8,
                  title: 'Canal Sur',
                  project: 'Fundo',
                  lat: -33.50,
                  lon: -70.60,
                  surface: true,
                ),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Pozo Norte'), findsWidgets);
    expect(find.text('Canal Sur'), findsWidgets);
    expect(find.text('Caudal'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('capture-node-7')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(find.text('En esta vista'), findsNothing);
    expect(find.text('Entrar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el esquema queda fijo al tocar o arrastrar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 760,
            child: _map(
              points: [
                _point(
                  id: 1,
                  title:
                      'Estación de bombeo Santa Macarena Norte del valle central',
                  project: 'Fundo',
                ),
                _point(id: 2, title: 'Canal Sur', project: 'Fundo'),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('capture-minimap')), findsNothing);
    expect(find.text('Caudal'), findsNothing);
    final node = find.byKey(const ValueKey('capture-node-1'));
    final before = tester.getTopLeft(node);
    await tester.drag(node, const Offset(28, 16));
    await tester.pump();
    expect((tester.getTopLeft(node) - before).distance, lessThan(0.5));
    await tester.tap(node);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect((tester.getTopLeft(node) - before).distance, lessThan(0.5));
    expect(find.text('Entrar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la ficha abierta no cruza el margen inferior', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const clearance = 320.0;
    const titles = ['Pozo Norte', 'Canal Sur', 'Pozo Este', 'Pozo Bajo'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 760,
            child: _map(
              points: [
                for (var index = 0; index < titles.length; index++)
                  _point(
                    id: index + 1,
                    title: titles[index],
                    project: 'Fundo',
                    gap: index == 2,
                  ),
              ],
              openBottomClearance: clearance,
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    var lowest = titles.first;
    var top = tester.getTopLeft(_schemaTitle(lowest)).dy;
    for (final title in titles.skip(1)) {
      final y = tester.getTopLeft(_schemaTitle(title)).dy;
      if (y > top) {
        top = y;
        lowest = title;
      }
    }

    final map = tester.getRect(find.byType(CaptureNetworkMap));
    expect(find.byKey(const ValueKey('capture-view-records')), findsNothing);

    final node = find.byKey(
      ValueKey('capture-node-${titles.indexOf(lowest) + 1}'),
    );
    await tester.tap(node);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final panel = tester.getRect(
      find.byKey(const ValueKey('capture-view-records')),
    );
    final dock = clearance - 2 < 8 ? 8.0 : clearance - 2;
    expect(map.bottom - panel.bottom, greaterThanOrEqualTo(dock - 1));
    expect(find.text('Entrar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una ficha que cabe se queda junto a su punto', (tester) async {
    const clearance = 8.0;
    const titles = ['Pozo Norte', 'Canal Sur', 'Pozo Este', 'Pozo Bajo'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 760,
            child: _map(
              points: [
                for (var index = 0; index < titles.length; index++)
                  _point(id: index + 1, title: titles[index], project: 'Fundo'),
              ],
              openBottomClearance: clearance,
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    var highest = titles.first;
    var top = tester.getTopLeft(_schemaTitle(highest)).dy;
    for (final title in titles.skip(1)) {
      final y = tester.getTopLeft(_schemaTitle(title)).dy;
      if (y < top) {
        top = y;
        highest = title;
      }
    }

    await tester.tap(_schemaTitle(highest));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('En esta vista'), findsNothing);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text(highest), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('las fichas de muchos puntos no se pisan', (tester) async {
    const names = [
      'Selva Negra',
      'Santa Cecilia',
      'Santa Marta',
      'Lechería',
      'Santa Adriana',
      'Matias Fischer',
      'Pomuyeto',
      'Santa Macarena',
      'Pivote',
      'San Jose 2',
      'San Jose 1',
      'Santa Clara',
      'El Tata',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 760,
            child: _map(
              points: [
                for (var index = 0; index < names.length; index++)
                  _point(
                    id: index + 1,
                    title: names[index],
                    project: index.isEven ? 'Norte' : 'Sur',
                    lat: -33.40 - (index % 5) * 0.025,
                    lon: -70.70 + (index ~/ 5) * 0.03,
                    gap: index == 8,
                  ),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final seen = <String>{};
    for (var guard = 0; guard < 8; guard++) {
      final boxes = <Rect>[];
      final visible = <String>[];
      for (final name in names) {
        final title = _schemaTitle(name);
        if (title.evaluate().isEmpty) continue;
        visible.add(name);
        boxes.add(tester.getRect(title));
      }
      expect(visible, isNotEmpty);
      for (final name in visible) {
        expect(seen.contains(name), isFalse, reason: '$name se repite');
        seen.add(name);
      }
      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          expect(boxes[i].overlaps(boxes[j]), isFalse);
        }
      }
      final next = find.byKey(const ValueKey('capture-page-next'));
      if (next.evaluate().isEmpty) break;
      await tester.tap(next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(seen, names.toSet());
    expect(tester.takeException(), isNull);
  });

  testWidgets('con muchos loggers siguiente muestra el resto', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final points = [
      for (var index = 0; index < 39; index++)
        _point(id: index + 1, title: 'Pozo ${index + 1}', project: 'Fundo'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 640,
            child: _map(points: points, onPointSelected: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('capture-hub')), findsOneWidget);
    expect(find.text('Pozo 1'), findsWidgets);
    expect(find.text('Pozo 39'), findsNothing);
    final hub = tester.getRect(find.byKey(const ValueKey('capture-hub')));
    expect(find.byKey(const ValueKey('capture-page-next')), findsOneWidget);

    var guard = 0;
    while (find.text('Pozo 39').evaluate().isEmpty && guard < 8) {
      await tester.tap(find.byKey(const ValueKey('capture-page-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      guard++;
    }
    expect(find.text('Pozo 39'), findsWidgets);
    expect(tester.getRect(find.byKey(const ValueKey('capture-hub'))), hub);
    expect(tester.takeException(), isNull);
  });
}

/// Cruce propio entre polilíneas ortogonales (no cuenta T-joints en extremos).
bool _orthogonalPolylinesCross(List<List<Offset>> links) {
  bool proper(Offset a0, Offset a1, Offset b0, Offset b1) {
    final aHoriz = (a0.dy - a1.dy).abs() < 0.5;
    final bHoriz = (b0.dy - b1.dy).abs() < 0.5;
    if (aHoriz == bHoriz) return false;
    final h0 = aHoriz ? a0 : b0;
    final h1 = aHoriz ? a1 : b1;
    final v0 = aHoriz ? b0 : a0;
    final v1 = aHoriz ? b1 : a1;
    final y = h0.dy;
    final x = v0.dx;
    final minHx = math.min(h0.dx, h1.dx);
    final maxHx = math.max(h0.dx, h1.dx);
    final minVy = math.min(v0.dy, v1.dy);
    final maxVy = math.max(v0.dy, v1.dy);
    const eps = 0.6;
    if (x <= minHx + eps || x >= maxHx - eps) return false;
    if (y <= minVy + eps || y >= maxVy - eps) return false;
    return true;
  }

  for (var i = 0; i < links.length; i++) {
    for (var j = i + 1; j < links.length; j++) {
      final a = links[i];
      final b = links[j];
      for (var ai = 0; ai < a.length - 1; ai++) {
        for (var bi = 0; bi < b.length - 1; bi++) {
          if (proper(a[ai], a[ai + 1], b[bi], b[bi + 1])) return true;
        }
      }
    }
  }
  return false;
}

/// Distancia a la línea de la pizarra más cercana. Cero si cae encima.
double _onBoardLine(double value) {
  final step = captureBoardStep;
  final rem = ((value % step) + step) % step;
  final other = step - rem;
  return rem <= other ? rem : other;
}

Finder _schemaTitle(String title) {
  return find.descendant(
    of: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('capture-label-');
    }),
    matching: find.text(title),
  );
}

/// Evita timers de Dio en widget tests del esquema.
CaptureNetworkMap _map({
  required List<Map<String, dynamic>> points,
  required ValueChanged<Map<String, dynamic>> onPointSelected,
  List<Map<String, dynamic>> openTickets = const [],
  List<Map<String, dynamic>> compliance = const [],
  ValueChanged<Map<String, dynamic>>? onRequestSupport,
  double bottomInset = 0,
  double topInset = 0,
  double openBottomClearance = 8,
}) {
  return CaptureNetworkMap(
    points: points,
    onPointSelected: onPointSelected,
    openTickets: openTickets,
    compliance: compliance,
    onRequestSupport: onRequestSupport,
    bottomInset: bottomInset,
    topInset: topInset,
    openBottomClearance: openBottomClearance,
    checkApiHealth: () async => true,
  );
}

Map<String, dynamic> _point({
  required int id,
  required String title,
  required String project,
  bool surface = false,
  bool gap = false,
  double? lat,
  double? lon,
  double? flow,
}) {
  return {
    'id': id,
    'title': title,
    'project_name': project,
    'type_dga': surface ? 'SUPERFICIAL' : 'SUBTERRANEO',
    'lat': ?lat,
    'lon': ?lon,
    'latest_telemetry': gap
        ? {'days_not_connection': 2, if (flow != null) 'flow': flow}
        : {
            'date_time_medition': DateTime.now().toIso8601String(),
            'days_not_connection': 0,
            if (flow != null) 'flow': flow,
          },
  };
}
