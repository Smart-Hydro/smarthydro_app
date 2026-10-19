import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smarthydro_app/features/dashboard/point_link.dart';
import 'package:smarthydro_app/features/dashboard/widgets/capture_network_map.dart';
import 'package:smarthydro_app/features/geo/capture_location_map.dart';

void main() {
  test('agrupa puntos que caen dentro de 80 px', () {
    final close = clusterByPixel(const [
      Offset(0, 0),
      Offset(40, 10),
      Offset(300, 40),
    ]);
    expect(close, hasLength(2));
    expect(close.first, [0, 1]);
    expect(close.last, [2]);

    expect(clusterByPixel(const [Offset(0, 0), Offset(10, 0)], radius: 0), [
      [0],
      [1],
    ]);
    expect(clusterByPixel(const []), isEmpty);
  });

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

  test('UTM 19S se convierte como en el observatorio', () {
    // Plaza de Armas de Santiago guardada como norte/este.
    final plaza = captureLatLng({'lat': '6298836', 'lon': '346454'})!;
    expect(plaza.latitude, closeTo(-33.4378, 0.003));
    expect(plaza.longitude, closeTo(-70.6504, 0.003));
    expect(captureLatLng({'lat': 6298836, 'lon': 50}), isNull);
  });

  test('layoutPointWindows con 0 no emite rects', () {
    expect(layoutPointWindows(area: const Size(1200, 800), count: 0), isEmpty);
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
    final rects = layoutPointWindows(area: const Size(1200, 800), count: 3);
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
    expect(wide, greaterThan(narrow));
    final fit = captureLoggerNameFit('Pozo Norte largo', 96);
    expect(fit.ellipsis, isFalse);
    expect(fit.fontSize, greaterThanOrEqualTo(9));
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

  test('la red crece a los cuatro lados del núcleo', () {
    final scheme = placeCaptureScheme(
      4,
      const Size(900, 700),
      top: 80,
      bottom: 40,
    );
    final hub = scheme.hub;
    expect(
      scheme.plates.any((p) => p.center.dx < hub.left),
      isTrue,
      reason: 'falta un logger a la izquierda',
    );
    expect(
      scheme.plates.any((p) => p.center.dx > hub.right),
      isTrue,
      reason: 'falta un logger a la derecha',
    );
    expect(
      scheme.plates.any((p) => p.center.dy < hub.top),
      isTrue,
      reason: 'falta un logger arriba',
    );
    expect(
      scheme.plates.any((p) => p.center.dy > hub.bottom),
      isTrue,
      reason: 'falta un logger abajo',
    );
  });

  test('con muchos loggers la red se achica para seguir cabiendo', () {
    final few = placeCaptureScheme(
      4,
      const Size(900, 700),
      top: 40,
      bottom: 40,
    );
    final many = placeCaptureScheme(
      16,
      const Size(900, 700),
      top: 40,
      bottom: 40,
    );
    expect(many.plates.first.width, lessThan(few.plates.first.width));
    for (final plate in many.plates) {
      expect(plate.overlaps(many.hub), isFalse);
    }
  });

  test('las ventanas abren completas y no tapan loggers ni el minimapa', () {
    const size = Size(1200, 800);
    const contentTop = 84.0;
    final scheme = placeCaptureScheme(3, size, top: contentTop, bottom: 8);
    final bounds = Rect.fromLTRB(
      0,
      contentTop,
      size.width - 8,
      size.height - 8,
    );
    final minimap = Rect.fromLTWH(size.width - 16 - 36, contentTop + 8, 36, 36);
    final frames = placeOpenWindowFrames(
      count: 2,
      bounds: bounds,
      obstacles: [scheme.hub, ...scheme.plates, minimap],
    );
    expect(frames, hasLength(2));
    for (final frame in frames) {
      expect(frame.width, greaterThan(300));
      expect(frame.height, inInclusiveRange(200, 250));
      expect(frame.left, greaterThanOrEqualTo(bounds.left));
      expect(frame.top, greaterThanOrEqualTo(bounds.top));
      expect(frame.right, lessThanOrEqualTo(bounds.right + 0.1));
      expect(frame.bottom, lessThanOrEqualTo(bounds.bottom - 12));
      expect(frame.overlaps(scheme.hub), isFalse);
      expect(frame.overlaps(minimap), isFalse);
      for (final plate in scheme.plates) {
        expect(frame.overlaps(plate), isFalse);
      }
    }
    expect((frames[1].top - frames[0].top).abs(), greaterThan(20));
  });

  test('con el rail la ventana se angosta y sigue fuera de los loggers', () {
    const size = Size(1100, 760);
    const left = 128.0;
    const contentTop = 84.0;
    final scheme = placeCaptureScheme(
      3,
      size,
      top: contentTop,
      bottom: 8,
      left: left,
    );
    final bounds = Rect.fromLTRB(
      left,
      contentTop,
      size.width - 8,
      size.height - 8,
    );
    final frames = placeOpenWindowFrames(
      count: 1,
      bounds: bounds,
      obstacles: [scheme.hub, ...scheme.plates],
    );
    expect(frames, hasLength(1));
    final frame = frames.single;
    expect(frame.left, greaterThanOrEqualTo(bounds.left));
    expect(frame.right, lessThanOrEqualTo(bounds.right + 0.1));
    expect(frame.bottom, lessThanOrEqualTo(bounds.bottom - 12));
    expect(frame.height, inInclusiveRange(200, 250));
    expect(frame.overlaps(scheme.hub), isFalse);
    for (final plate in scheme.plates) {
      expect(frame.overlaps(plate), isFalse, reason: 'tapa $plate');
    }
  });

  test('el segundo escritorio recibe las ventanas que no caben', () {
    final first = layoutWindowDesktops(
      area: const Size(800, 500),
      count: 6,
      desktop: 0,
      windowWidth: 340,
      windowHeight: 228,
    );
    final second = layoutWindowDesktops(
      area: const Size(800, 500),
      count: 6,
      desktop: 1,
      windowWidth: 340,
      windowHeight: 228,
    );
    expect(first.pages, greaterThan(1));
    expect(first.rects.length, first.capacity);
    expect(second.rects.length, 6 - first.capacity);
    expect(first.rects.every((r) => r.top >= 0), isTrue);
    expect(second.rects.every((r) => r.top >= 0), isTrue);
  });

  test('el inset izquierdo deja el rail sin pisar placas ni hub', () {
    const left = 128.0;
    final scheme = placeCaptureScheme(
      6,
      const Size(1200, 800),
      top: 100,
      bottom: 40,
      left: left,
    );
    expect(scheme.hub.left, greaterThanOrEqualTo(left));
    for (final plate in scheme.plates) {
      expect(plate.left, greaterThanOrEqualTo(left - 0.5));
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
    expect(wide, greaterThan(160));
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

  test('la ficha prioriza total, caudal y nivel', () {
    expect(captureWorkCode({'code_dga': 'OB-1'}), 'OB-1');
    expect(
      captureWorkCode({
        'dga': {'code_dga': 'X1'},
      }),
      'X1',
    );
    expect(captureWorkCode({'title': 'Pozo'}), isNull);
    expect(
      captureBriefChannels({
        'variables': [
          {'type_variable': 'CAUDAL'},
          {'type_variable': 'TOTALIZADO_MODBUS'},
          {'type_variable': 'NIVEL'},
        ],
      }).metric,
      CaptureBriefMetric.total,
    );
    expect(
      captureBriefChannels({
        'variables': [
          {'type_variable': 'NIVEL'},
          {'type_variable': 'CAUDAL'},
        ],
      }).metric,
      CaptureBriefMetric.flow,
    );
    expect(
      captureBriefChannels({
        'variables': [
          {'type_variable': 'NIVEL'},
        ],
      }).metric,
      CaptureBriefMetric.level,
    );
    expect(
      captureBriefChannels({
        'variables': [
          {'type_variable': 'TEMPERATURA'},
        ],
      }).metric,
      isNull,
    );
    expect(
      captureBriefChannels({
        'latest_telemetry': {'flow': 1, 'total': 9},
      }).metric,
      CaptureBriefMetric.total,
    );

    final rows = captureBriefRows([
      {
        'date_time': '2026-10-18T10:00:00',
        'flow': 1,
        'nivel': 4,
        'total_diff': 2,
        'created': '2026-10-18T10:01:00',
        'date_time_last_logger': '2026-10-18T09:59:00',
      },
      {
        'date_time': '2026-10-18T11:00:00',
        'flow': 3,
        'nivel': 6,
        'total_diff': 4,
        'created': '2026-10-18T11:01:30',
        'date_time_last_logger': '2026-10-18T10:59:00',
      },
    ]);
    final now = DateTime(2026, 10, 18, 12);
    final day = captureBriefDay(
      {
        'variables': [
          {'type_variable': 'TOTALIZADO'},
          {'type_variable': 'CAUDAL'},
          {'type_variable': 'NIVEL'},
        ],
      },
      rows,
      now: now,
    );
    expect(day.metric, CaptureBriefMetric.total);
    expect(day.line, [2, 4]);
    expect(day.volume, 6);
    expect(day.flowAvg, 2);
    expect(day.levelAvg, 5);
    expect(captureBriefTodayLabel(day), 'Consumo de hoy');
    expect(captureBriefAverageLine(day), 'Caudal 2.00 L/s · Nivel 5.00 m');
    final clocks = captureBriefClocks(rows);
    expect(clocks.logger, '18/10 10:59');
    expect(clocks.arrived, '18/10 11:01');

    final levelOnly = captureBriefDay(
      {
        'variables': [
          {'type_variable': 'NIVEL'},
        ],
      },
      rows,
      now: now,
    );
    expect(levelOnly.metric, CaptureBriefMetric.level);
    expect(levelOnly.line, [4, 6]);
    expect(levelOnly.flowAvg, isNull);
    expect(levelOnly.volume, isNull);
    expect(captureBriefTodayLabel(levelOnly), 'Nivel medio de hoy');
    expect(captureBriefAverageLine(levelOnly), isNull);

    final none = captureBriefDay(
      {
        'variables': [
          {'type_variable': 'TEMPERATURA'},
        ],
      },
      rows,
      now: now,
    );
    expect(none.line, isEmpty);
    expect(none.focus, isNull);
    expect(captureBriefAverageLine(none), isNull);

    final connected = captureBriefClocks(
      captureBriefRows([
        {'date_time': '2026-10-18T11:00:00', 'created': '2026-10-18T11:02:00'},
      ]),
    );
    expect(connected.logger, '18/10 11:02');
    expect(connected.arrived, isNull);
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

  test('los enlaces de arriba y abajo llegan a puertos distintos', () {
    final scheme = placeCaptureScheme(
      12,
      const Size(980, 720),
      top: 40,
      bottom: 40,
    );
    final links = captureHubLinks(scheme.plates, scheme.hub);
    expect(links, hasLength(12));
    final ends = [for (final link in links) link.last];
    for (var i = 0; i < ends.length; i++) {
      for (var j = i + 1; j < ends.length; j++) {
        expect(
          (ends[i] - ends[j]).distance,
          greaterThan(1.5),
          reason: 'puerto $i y $j coinciden',
        );
      }
    }
    for (final link in links) {
      for (var i = 0; i < link.length - 1; i++) {
        final sameAxis =
            link[i].dx == link[i + 1].dx || link[i].dy == link[i + 1].dy;
        expect(sameAxis, isTrue);
      }
    }
    expect(_orthogonalPolylinesCross(links), isFalse);
  });

  test('el cubo del núcleo es isométrico y cabe en la card', () {
    const size = Size(72, 48);
    final frame = captureHubCubeFrame(size);
    expect(frame.center, size.center(Offset.zero));
    final dx = frame.edge * math.sqrt(3) / 2;
    final right = Offset(dx, -frame.edge / 2);
    final left = Offset(-dx, -frame.edge / 2);
    final down = Offset(0, frame.edge);
    expect(right.distance, closeTo(frame.edge, 0.01));
    expect(left.distance, closeTo(frame.edge, 0.01));
    expect(down.distance, closeTo(frame.edge, 0.01));
    expect(dx * 2, lessThanOrEqualTo(size.width));
    expect(frame.edge * 2, lessThanOrEqualTo(size.height));
    final top = frame.center + right + left;
    final bottom = frame.center + down;
    expect(top.dx, closeTo(frame.center.dx, 0.01));
    expect(bottom.dx, closeTo(frame.center.dx, 0.01));
    expect((frame.center - top).dy, closeTo(frame.edge, 0.01));
    expect((bottom - frame.center).dy, closeTo(frame.edge, 0.01));
  });

  test('solo la antena conectada late', () {
    final gap = captureLoggerAntennaGlow(0.2, motion: true);
    expect(captureLoggerAntennaGlow(1.1, motion: true), gap);
    expect(captureLoggerAntennaGlow(0.4, motion: false), gap);
    expect(gap, greaterThan(0.4));
    final live = captureLoggerAntennaGlow(
      0,
      motion: true,
      link: PointLink.connected,
    );
    final lit = captureLoggerAntennaGlow(
      0.375,
      motion: true,
      link: PointLink.connected,
    );
    expect((live - lit).abs(), greaterThan(0.2));
    expect(
      captureLoggerAntennaGlow(0.2, motion: false, link: PointLink.connected),
      captureLoggerAntennaGlow(1.1, motion: false, link: PointLink.connected),
    );
    expect(
      captureLoggerAntennaGlow(0.2, motion: true, link: PointLink.incident),
      captureLoggerAntennaGlow(1.1, motion: true, link: PointLink.incident),
    );
  });

  test('las placas del logger no crecen con el nombre', () {
    const name = 'Estación de bombeo Santa Macarena Norte';
    final box = captureLoggerBoxFor(
      [name, 'Pozo 2', 'Canal Sur', 'Norte'],
      count: 8,
      viewWidth: 290,
      viewHeight: 480,
    );
    expect(box, isNotNull);
    expect(box!.width, capturePlateWidth);
    expect(box.height, capturePlateHeight);
    final scheme = placeCaptureScheme(
      4,
      const Size(900, 700),
      top: 80,
      bottom: 40,
      labels: [name, 'Pozo 2', 'Canal Sur', 'Norte'],
    );
    expect(scheme.plates, hasLength(4));
    for (final plate in scheme.plates) {
      expect(plate.overlaps(scheme.hub), isFalse);
      expect(plate.width, lessThanOrEqualTo(capturePlateWidth + 0.1));
      expect(plate.height, lessThanOrEqualTo(capturePlateHeight + 0.1));
    }
    final fit = captureLoggerNameFit('Norte', 48, maxHeight: 28, maxLines: 2);
    expect(fit.ellipsis, isFalse);
    expect(fit.maxLines, lessThanOrEqualTo(2));
  });

  test('el cubo activo se hincha y el apagado parpadea', () {
    final calm = captureHubEnergy(online: true, seconds: 0, motion: false);
    expect(calm.swell, 1);
    expect(calm.power, 1);
    final low = captureHubEnergy(online: true, seconds: 0, motion: true);
    final high = captureHubEnergy(online: true, seconds: 0.9, motion: true);
    expect(low.power, 1);
    expect(high.power, 1);
    expect((low.swell - high.swell).abs(), greaterThan(0.2));
    final offA = captureHubEnergy(online: false, seconds: 0.3375, motion: true);
    final offB = captureHubEnergy(online: false, seconds: 1.0125, motion: true);
    expect(offA.swell, 0);
    expect(offB.swell, 0);
    expect((offA.power - offB.power).abs(), greaterThan(0.15));
    final still = captureHubEnergy(online: false, seconds: 0.2, motion: false);
    expect(
      captureHubEnergy(online: false, seconds: 1.4, motion: false).power,
      still.power,
    );
    expect(calm.jets, 0);
    expect(offA.jets, 0);
    final leaving = captureHubEnergy(online: true, seconds: 0, motion: true);
    final grown = captureHubEnergy(
      online: true,
      seconds: math.pi / 2 / 1.7,
      motion: true,
    );
    final returning = captureHubEnergy(
      online: true,
      seconds: math.pi / 1.7,
      motion: true,
    );
    expect(leaving.jets, greaterThan(0.85));
    expect(returning.jets, greaterThan(0.85));
    expect(grown.jets, lessThan(0.08));
  });

  test('el agua del enlace va del logger hacia el cubo', () {
    final near = captureHubwardDashes(const [
      Offset(0, 0),
      Offset(100, 0),
    ], travel: 2);
    final far = captureHubwardDashes(const [
      Offset(0, 0),
      Offset(100, 0),
    ], travel: 8);
    expect(near, isNotEmpty);
    expect(far, isNotEmpty);
    expect(near.first.$1.dx, lessThan(15));
    expect(far.first.$1.dx, greaterThan(near.first.$1.dx));
    expect(far.first.$2.dx, greaterThan(far.first.$1.dx));
    final bent = captureHubwardDashes(const [
      Offset(0, 40),
      Offset(40, 40),
      Offset(40, 0),
    ], travel: 2);
    expect(bent.first.$1.dy, closeTo(40, 0.2));
    expect(bent.first.$1.dx, lessThan(8));
  });

  test('un punto en gap no usa el color de conectado', () {
    expect(captureLinkFlows(PointLink.connected), isTrue);
    expect(captureLinkFlows(PointLink.gap), isFalse);
    expect(captureLinkFlows(PointLink.incident), isFalse);
    expect(captureSchemeLinkColor(PointLink.gap), const Color(0xFFFF847A));
    expect(
      captureSchemeLinkColor(PointLink.gap),
      isNot(captureSchemeLinkColor(PointLink.connected)),
    );
    expect(
      captureSchemeLinkColor(PointLink.incident),
      isNot(captureSchemeLinkColor(PointLink.connected)),
    );
  });

  testWidgets('un solo punto no muestra el minimapa', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 640,
            child: _map(
              points: [_point(id: 1, title: 'Solo', project: 'Fundo')],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('capture-minimap')), findsNothing);
    expect(find.byKey(const ValueKey('capture-hub')), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  test('la ficha sale al lado del punto y no tapa el resto', () {
    final stage = Rect.fromLTWH(32, 84, 1136, 664);
    final hub = Rect.fromCenter(
      center: const Offset(600, 416),
      width: 80,
      height: 80,
    );
    final north = Rect.fromCenter(
      center: const Offset(600, 328),
      width: 80,
      height: 32,
    );
    final east = Rect.fromCenter(
      center: const Offset(712, 416),
      width: 80,
      height: 32,
    );
    final west = Rect.fromCenter(
      center: const Offset(488, 416),
      width: 80,
      height: 32,
    );
    final fromNorth = captureBriefSlot(
      plate: north,
      bounds: stage,
      obstacles: [hub.inflate(8), east.inflate(4), west.inflate(4)],
    );
    expect(fromNorth.side, CaptureBriefSide.right);
    expect(fromNorth.rect.overlaps(north), isFalse);
    expect(fromNorth.rect.overlaps(west), isFalse);
    expect(fromNorth.rect.width, captureBriefWidth);
    expect(fromNorth.rect.height, captureBriefHeight);

    final fromEast = captureBriefSlot(
      plate: east,
      bounds: stage,
      obstacles: [hub.inflate(8), north.inflate(4), west.inflate(4)],
    );
    expect(fromEast.side, CaptureBriefSide.right);
    expect(fromEast.rect.left, greaterThan(east.right));
    expect(fromEast.rect.overlaps(north), isFalse);
    expect(fromEast.rect.overlaps(hub), isFalse);

    final screen = captureSchemeScreenRect(
      content: const Rect.fromLTWH(100, 100, 80, 32),
      anchor: const Offset(200, 200),
      pan: const Offset(10, 0),
      zoom: 2,
    );
    expect(screen.left, 10);
    expect(screen.top, 0);
    expect(screen.right, 170);
    expect(screen.bottom, 64);
  });

  test('la ficha de un punto lejano sigue pegada y apunta a ese logger', () {
    final stage = Rect.fromLTWH(32, 84, 1136, 664);
    final hub = Rect.fromCenter(
      center: const Offset(600, 416),
      width: 80,
      height: 80,
    );
    final south = Rect.fromCenter(
      center: const Offset(600, 710),
      width: 80,
      height: 32,
    );
    final corner = Rect.fromCenter(
      center: const Offset(1100, 120),
      width: 80,
      height: 32,
    );
    final scheme = placeCaptureScheme(
      24,
      const Size(1200, 800),
      top: 84,
      bottom: 52,
    );

    void expectAimed(
      ({Rect rect, CaptureBriefSide side, double aim}) slot,
      Rect plate,
    ) {
      const gap = 10.0;
      expect(slot.rect.width, closeTo(captureBriefWidth, 0.01));
      expect(slot.rect.height, closeTo(captureBriefHeight, 0.01));
      expect(slot.rect.overlaps(plate), isFalse);
      expect(slot.rect.left, greaterThanOrEqualTo(stage.left - 0.5));
      expect(slot.rect.top, greaterThanOrEqualTo(stage.top - 0.5));
      expect(slot.rect.right, lessThanOrEqualTo(stage.right + 0.5));
      expect(slot.rect.bottom, lessThanOrEqualTo(stage.bottom + 0.5));
      late final double along;
      late final double target;
      late final double start;
      late final double span;
      switch (slot.side) {
        case CaptureBriefSide.right:
          expect(slot.rect.left, closeTo(plate.right + gap, 0.6));
          along = slot.rect.top + slot.aim * slot.rect.height;
          target = plate.center.dy;
          start = slot.rect.top;
          span = slot.rect.height;
        case CaptureBriefSide.left:
          expect(slot.rect.right, closeTo(plate.left - gap, 0.6));
          along = slot.rect.top + slot.aim * slot.rect.height;
          target = plate.center.dy;
          start = slot.rect.top;
          span = slot.rect.height;
        case CaptureBriefSide.below:
          expect(slot.rect.top, closeTo(plate.bottom + gap, 0.6));
          along = slot.rect.left + slot.aim * slot.rect.width;
          target = plate.center.dx;
          start = slot.rect.left;
          span = slot.rect.width;
        case CaptureBriefSide.above:
          expect(slot.rect.bottom, closeTo(plate.top - gap, 0.6));
          along = slot.rect.left + slot.aim * slot.rect.width;
          target = plate.center.dx;
          start = slot.rect.left;
          span = slot.rect.width;
      }
      final guarded = target.clamp(start + span * 0.12, start + span * 0.88);
      expect(along, closeTo(guarded, 0.6));
    }

    final fromSouth = captureBriefSlot(
      plate: south,
      bounds: stage,
      obstacles: [hub.inflate(8)],
    );
    expectAimed(fromSouth, south);
    expect(fromSouth.rect.overlaps(hub), isFalse);

    final fromCorner = captureBriefSlot(
      plate: corner,
      bounds: stage,
      obstacles: [hub.inflate(8)],
    );
    expect(fromCorner.side, CaptureBriefSide.left);
    expectAimed(fromCorner, corner);
    expect(fromCorner.rect.bottom, lessThan(400));

    for (var index = 0; index < scheme.plates.length; index++) {
      final plate = scheme.plates[index];
      final slot = captureBriefSlot(
        plate: plate,
        bounds: stage,
        obstacles: [
          scheme.hub.inflate(8),
          for (var other = 0; other < scheme.plates.length; other++)
            if (other != index) scheme.plates[other].inflate(4),
        ],
      );
      expectAimed(slot, plate);
    }
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
    expect(find.text('Conectado'), findsNothing);
    expect(find.text('Advertencia'), findsNothing);
    expect(find.text('Incidencia'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('capture-node-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(opened, isNull);
    expect(find.text('En esta vista'), findsNothing);
    expect(find.text('1 punto'), findsNothing);
    expect(find.text('Ver'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('capture-focus-logger')), findsOneWidget);
    expect(find.text('Nettra'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('Dentro del límite'), findsOneWidget);
    expect(find.textContaining('1.20 L/s'), findsOneWidget);
    expect(find.text('Caudal · ai1'), findsNothing);
    expect(find.text('Soporte'), findsNothing);
    expect(find.text('Sensor mudo · abierto'), findsOneWidget);
    expect(find.textContaining('Alerta interna'), findsNothing);
    expect(find.textContaining('Caída de enlace'), findsNothing);
    expect(find.textContaining('Otro fundo'), findsNothing);
    expect(find.text('Siguiente medición'), findsNothing);
    expect(find.text('Pedir soporte'), findsNothing);
    expect(find.textContaining('· Conectado'), findsNothing);
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('OB-1'), findsOneWidget);
    expect(find.byIcon(Icons.view_in_ar_rounded), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
    expect(find.text('Configurar'), findsNothing);
    expect(
      find.byKey(const ValueKey('capture-config-section-point')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('capture-quick-ver')));
    await tester.pump();
    expect(support, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en movil sigue una sola ficha ancha del panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 640,
            child: _map(
              points: [
                _point(id: 1, title: 'Pozo Norte', project: 'Fundo'),
                _point(id: 2, title: 'Canal Sur', project: 'Fundo'),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-node-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));

    expect(find.byKey(const ValueKey('capture-view-records')), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-point-window-1')), findsNothing);
    final panel = tester.getRect(
      find.byKey(const ValueKey('capture-view-records')),
    );
    expect(panel.height, greaterThanOrEqualTo(220));
    expect(tester.takeException(), isNull);
  });

  testWidgets('la ficha del punto es alta y trae la caja del logger', (
    tester,
  ) async {
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
            child: _map(points: [point], onPointSelected: (_) {}),
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
    expect(panel.height, inInclusiveRange(200, 320));
    expect(find.text('Pozo Norte'), findsWidgets);
    expect(find.textContaining('· Conectado'), findsNothing);
    expect(find.byKey(const ValueKey('capture-focus-logger')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en web abre un solo resumen de tamaño fijo', (tester) async {
    _useDesktopSurface(tester);
    await tester.pumpWidget(
      _wideApp(
        child: _map(
          points: [
            _point(id: 1, title: 'Pozo Norte', project: 'Fundo'),
            _point(id: 2, title: 'Canal Sur', project: 'Fundo'),
            _point(id: 3, title: 'Pozo Este', project: 'Fundo'),
          ],
          onPointSelected: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-node-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));
    await tester.tap(find.byKey(const ValueKey('capture-brief-close')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-node-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    expect(find.byKey(const ValueKey('capture-board-brief')), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-view-records')), findsNothing);
    expect(find.byKey(const ValueKey('capture-point-window-1')), findsNothing);
    expect(find.byKey(const ValueKey('capture-point-window-2')), findsNothing);
    expect(find.text('Escritorio 1 / 2'), findsNothing);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
    final brief = tester.getRect(
      find.byKey(const ValueKey('capture-board-brief')),
    );
    expect(brief.width, captureBriefWidth);
    expect(brief.height, captureBriefHeight);
    expect(brief.top, greaterThanOrEqualTo(0));
    expect(brief.bottom, lessThanOrEqualTo(800));
    final node = tester.getRect(find.byKey(const ValueKey('capture-node-2')));
    expect(brief.overlaps(node), isFalse);
    expect((brief.center - node.center).distance, lessThan(360));
    final card = find.descendant(
      of: find.byKey(const ValueKey('capture-board-brief')),
      matching: find.text('Canal Sur'),
    );
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('capture-board-brief')),
        matching: find.text('Pozo Norte'),
      ),
      findsNothing,
    );
    expect(find.textContaining('· Conectado'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la ficha densa de escritorio cabe sin desbordar', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    await tester.pumpWidget(
      _wideApp(
        child: _map(
          points: [
            {
              'id': 6,
              'title': 'P6',
              'project_name': 'Fundo',
              'type_dga': 'SUBTERRANEO',
              'provider': 'nettra',
              'frecuency': 15,
              'send_dga': true,
              'code_dga': 'OB-1603-392',
              'variables': [
                {'type_variable': 'CAUDAL'},
                {'type_variable': 'NIVEL'},
                {'type_variable': 'TOTALIZADO'},
              ],
              'latest_telemetry': {
                'date_time_medition': '2026-10-18T15:00:00Z',
                'days_not_connection': 0,
                'flow': 46.5,
                'water_table': 53.0,
                'total': 276,
              },
            },
            _point(id: 2, title: 'Canal Sur', project: 'Fundo'),
          ],
          openTickets: const [
            {
              'id': 1,
              'title': 'Sensor mudo',
              'status': 'ABIERTO',
              'origin': 'CLIENTE',
              'point_id': 6,
            },
          ],
          compliance: const [
            {
              'point_id': 6,
              'compliance_warning': {'level': 'safe'},
            },
          ],
          onPointSelected: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-node-6')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    final brief = find.byKey(const ValueKey('capture-board-brief'));
    expect(brief, findsOneWidget);
    expect(tester.getSize(brief).height, captureBriefHeight);
    expect(
      find.descendant(of: brief, matching: find.text('Punto')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: brief, matching: find.text('Telemetría')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: brief, matching: find.text('DGA')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: brief, matching: find.text('Física')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: brief, matching: find.text('Esquema')),
      findsOneWidget,
    );
    expect(find.text('Ver'), findsOneWidget);
    expect(find.text('Consumo de hoy'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el pozo sentado deja la pregunta y oculta la red', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    await tester.pumpWidget(
      _wideApp(
        child: _map(
          points: [_point(id: 1, title: 'Pozo Norte', project: 'Fundo')],
          onPointSelected: (_) {},
          askBar: const Text('Pregunta rápida'),
          seatedWell: const Text('Pozo sentado'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));

    expect(find.text('Pregunta rápida'), findsOneWidget);
    expect(find.text('Pozo sentado'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-node-1')), findsNothing);
    expect(find.byKey(const ValueKey('capture-config-open')), findsNothing);
    expect(find.text('Esquema de telemetría'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin cumplimiento no hay chip y DGA se elige en la ficha', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    await tester.pumpWidget(
      _wideApp(
        child: _map(
          points: [_point(id: 1, title: 'Pozo Norte', project: 'Fundo')],
          onPointSelected: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-node-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(find.byKey(const ValueKey('capture-config-card')), findsNothing);
    expect(
      find.byKey(const ValueKey('capture-config-section-point')),
      findsOneWidget,
    );
    expect(find.text('SMA'), findsNothing);
    expect(
      find.byKey(const ValueKey('capture-config-section-compliance')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('capture-board-brief')),
        matching: find.text('DGA'),
      ),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('capture-config-section-point')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('capture-config-card')), findsOneWidget);
    expect(find.text('Configurar punto'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-config-code')), findsNothing);
    expect(find.text('Código de obra'), findsNothing);

    await tester.tap(find.text('Cumplimiento'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-config-dga')));
    await tester.pump();
    expect(find.byKey(const ValueKey('capture-config-code')), findsOneWidget);
    expect(find.text('Inicio de envío'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('capture-config-close')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-new-point')));
    await tester.pump();
    expect(find.text('Nuevo punto'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-config-code')), findsNothing);
    final configCard = find.byKey(const ValueKey('capture-config-card'));
    expect(
      find.descendant(of: configCard, matching: find.text('Punto')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: configCard, matching: find.text('Telemetría')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: configCard, matching: find.text('Esquema')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: configCard, matching: find.text('Esquema')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('capture-config-scheme')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('capture-config-add-variable')),
      findsOneWidget,
    );
    expect(find.text('Tipo de variable'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('capture-config-save')),
    );
    await tester.tap(find.byKey(const ValueKey('capture-config-save')));
    await tester.pump();
    expect(find.text('La sesión no puede guardar este punto.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('Ver'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ver ubicaciones abre el mapa Leaflet de los puntos', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 640,
            child: _map(
              locationTiles: _QuietTiles(),
              points: [
                _point(
                  id: 7,
                  title: 'Pozo Norte',
                  project: 'Fundo',
                  lat: -33.45,
                  lon: -70.66,
                ),
                _point(id: 9, title: 'Sin GPS', project: 'Fundo'),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Esquema de telemetría'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-node-7')), findsOneWidget);
    expect(find.byType(CaptureLocationMap), findsNothing);

    await tester.tap(find.byKey(const ValueKey('capture-location-toggle')));
    await tester.pump();

    expect(find.text('Ubicaciones'), findsOneWidget);
    expect(find.byType(CaptureLocationMap), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('© Esri © OpenStreetMap'), findsOneWidget);
    expect(find.text('1 punto sin coordenadas'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-node-7')), findsNothing);
    expect(find.byKey(const ValueKey('capture-location-7')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('capture-location-7')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(find.text('Ver'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('capture-location-toggle')));
    await tester.pump();
    expect(find.text('Esquema de telemetría'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-node-7')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el inicio abre en el mapa, sin esquema ni botón para volver', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 640,
            child: _map(
              mapOnly: true,
              locationTiles: _QuietTiles(),
              points: [
                _point(
                  id: 7,
                  title: 'Pozo Norte',
                  project: 'Fundo',
                  lat: -33.45,
                  lon: -70.66,
                ),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CaptureLocationMap), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-node-7')), findsNothing);
    expect(find.byKey(const ValueKey('capture-location-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('capture-new-point')), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-zoom-in')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('capture-location-7')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(find.text('Ver'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en escritorio el mapa del inicio también abre la ficha', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    await tester.pumpWidget(
      _wideApp(
        child: _map(
          mapOnly: true,
          locationTiles: _QuietTiles(),
          points: [
            _point(
              id: 7,
              title: 'Pozo Norte',
              project: 'Fundo',
              lat: -33.45,
              lon: -70.66,
            ),
          ],
          onPointSelected: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-location-7')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('capture-board-brief')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la capa pública se dibuja sin repetir los puntos propios', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 640,
            child: CaptureLocationMap(
              tileProvider: _QuietTiles(),
              points: [
                _point(
                  id: 7,
                  title: 'Pozo Norte',
                  project: 'Fundo',
                  lat: -33.45,
                  lon: -70.66,
                ),
              ],
              publicPoints: const [
                {'id': 7, 'lat': -33.45, 'lon': -70.66, 'code': 'OB-1'},
                {
                  'id': 50,
                  'lat': -33.5,
                  'lon': -70.7,
                  'code': 'OB-2',
                  'type_dga': 'SUPERFICIAL',
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.widget<CircleLayer>(find.byType(CircleLayer));
    expect(layer.circles, hasLength(1));
    expect(find.byKey(const ValueKey('capture-location-7')), findsOneWidget);
  });

  testWidgets('puntos cercanos se agrupan y al tocar se separan', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 640,
            child: _map(
              locationTiles: _QuietTiles(),
              points: [
                _point(
                  id: 7,
                  title: 'Pozo Norte',
                  project: 'Fundo',
                  lat: -33.450,
                  lon: -70.660,
                ),
                _point(
                  id: 8,
                  title: 'Pozo Vecino',
                  project: 'Fundo',
                  lat: -33.451,
                  lon: -70.661,
                ),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-location-toggle')));
    await tester.pump();
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-location-7')), findsNothing);
    expect(find.byKey(const ValueKey('capture-location-8')), findsNothing);

    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.pump();

    expect(find.text('2'), findsNothing);
    expect(find.byKey(const ValueKey('capture-location-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-location-8')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('puntos lejos siguen como logger', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 640,
            child: _map(
              locationTiles: _QuietTiles(),
              points: [
                _point(
                  id: 7,
                  title: 'Pozo Norte',
                  project: 'Fundo',
                  lat: -33.45,
                  lon: -70.66,
                ),
                _point(
                  id: 8,
                  title: 'Canal Sur',
                  project: 'Fundo',
                  lat: -41.47,
                  lon: -72.94,
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
    await tester.tap(find.byKey(const ValueKey('capture-location-toggle')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('capture-location-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-location-8')), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('capture-cluster-');
      }),
      findsNothing,
    );
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

    expect(find.byKey(const ValueKey('capture-minimap')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('capture-minimap'))),
      const Size(36, 36),
    );
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
    expect(find.text('Ver'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el mouse sobre el cubo abre las stats sin tapar el esquema', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 760,
            child: _map(
              askBar: const Text('Pregunta rápida'),
              points: [
                _point(id: 1, title: 'Pozo Norte', project: 'Fundo'),
                _point(id: 2, title: 'Canal Sur', project: 'Fundo', gap: true),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Pregunta rápida'), findsOneWidget);
    expect(find.text('Conectado'), findsNothing);
    expect(find.byKey(const ValueKey('capture-stats')), findsNothing);
    expect(find.byKey(const ValueKey('capture-hub')), findsOneWidget);

    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer();
    await hover.moveTo(
      tester.getCenter(find.byKey(const ValueKey('capture-hub'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byKey(const ValueKey('capture-hub-card')), findsOneWidget);
    expect(find.text('Pregunta rápida'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-hub')), findsOneWidget);
    expect(find.text('Estado de la red'), findsOneWidget);
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Advertencia'), findsOneWidget);
    expect(find.text('Incidencia'), findsOneWidget);
    expect(find.text('Disponibilidad'), findsOneWidget);
    expect(find.text('Rendimiento'), findsOneWidget);

    await hover.moveTo(const Offset(8, 8));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-hub-card-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('capture-hub-card')), findsNothing);
    expect(find.text('Pregunta rápida'), findsOneWidget);
    expect(find.text('Conectado'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el zoom no abre el estado de la red', (tester) async {
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
                _point(id: 1, title: 'Pozo Norte', project: 'Fundo'),
                _point(id: 2, title: 'Canal Sur', project: 'Fundo', gap: true),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final hub = find.byKey(const ValueKey('capture-hub'));
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer();
    await hover.moveTo(tester.getCenter(hub));
    await tester.pump();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(hub),
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('capture-hub-card')), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('capture-hub-card')), findsNothing);

    final edge = tester.getRect(hub);
    final beside = edge.center + Offset(edge.width / 2 + 8, 0);
    expect(edge.contains(beside), isFalse);
    await hover.moveTo(beside);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-zoom-in')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('capture-hub-card')), findsNothing);

    await hover.moveTo(const Offset(8, 8));
    await tester.pump();
    await hover.moveTo(tester.getCenter(hub));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byKey(const ValueKey('capture-hub-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el cubo abre disponibilidad y rendimiento', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 700,
            child: _map(
              points: [
                _point(id: 1, title: 'Pozo Norte', project: 'Fundo'),
                _point(id: 2, title: 'Canal Sur', project: 'Fundo'),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('capture-hub-card')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('capture-hub')));
    await tester.pump();
    expect(find.byKey(const ValueKey('capture-hub-card')), findsOneWidget);
    expect(find.text('Disponibilidad'), findsOneWidget);
    expect(find.text('Rendimiento'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('capture-hub-card')),
        matching: find.textContaining('API en línea'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el estado de la red se centra en la sección', (tester) async {
    _useDesktopSurface(tester);
    await tester.pumpWidget(
      _wideApp(
        child: Row(
          children: [
            Expanded(
              child: _map(
                leftInset: 128,
                points: [
                  _point(id: 1, title: 'Pozo Norte', project: 'Fundo'),
                  _point(id: 2, title: 'Canal Sur', project: 'Fundo'),
                ],
                onPointSelected: (_) {},
              ),
            ),
            const SizedBox(width: 380),
          ],
        ),
      ),
    );
    await tester.pump();

    final hub = tester.getCenter(find.byKey(const ValueKey('capture-hub')));
    final zoomOut = tester.getCenter(
      find.byKey(const ValueKey('capture-zoom-out')),
    );
    final zoomIn = tester.getCenter(
      find.byKey(const ValueKey('capture-zoom-in')),
    );
    expect((zoomOut.dx + zoomIn.dx) / 2, closeTo(hub.dx, 8));
    expect((hub.dx - 600).abs(), greaterThan(40));

    await tester.tap(find.byKey(const ValueKey('capture-hub')));
    await tester.pump();
    final card = tester.getCenter(
      find.byKey(const ValueKey('capture-hub-card')),
    );
    expect(card.dx, closeTo(hub.dx, 12));
    expect(card.dy, closeTo(hub.dy, 16));
    expect((card.dx - 600).abs(), greaterThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('acercar no mueve un logger al arrastrarlo', (tester) async {
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
                _point(id: 1, title: 'Pozo Norte', project: 'Fundo'),
                _point(id: 2, title: 'Canal Sur', project: 'Fundo'),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final node = find.byKey(const ValueKey('capture-node-1'));
    final hub = find.byKey(const ValueKey('capture-hub'));
    final before = tester.getTopLeft(node);
    final hubBefore = tester.getRect(hub).center;
    await tester.tap(find.byKey(const ValueKey('capture-zoom-in')));
    await tester.pump(const Duration(milliseconds: 90));
    final midIn = tester.getTopLeft(node);
    expect((midIn - before).distance, greaterThan(0.5));
    await tester.pump(const Duration(milliseconds: 700));
    final zoomed = tester.getTopLeft(node);
    expect((zoomed - midIn).distance, greaterThan(0.5));
    expect((tester.getRect(hub).center - hubBefore).distance, lessThan(1.5));
    await tester.drag(node, const Offset(28, 16));
    await tester.pump();
    expect((tester.getTopLeft(node) - zoomed).distance, lessThan(0.5));
    await tester.tap(find.byKey(const ValueKey('capture-zoom-out')));
    await tester.pump(const Duration(milliseconds: 90));
    final midOut = tester.getTopLeft(node);
    expect((zoomed - midOut).distance, greaterThan(0.5));
    expect((midOut - before).distance, greaterThan(0.5));
    await tester.pump(const Duration(milliseconds: 700));
    expect((tester.getTopLeft(node) - before).distance, lessThan(1.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('con zoom el vacío mueve la red y un logger no', (tester) async {
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
                _point(id: 1, title: 'Pozo Norte', project: 'Fundo'),
                _point(id: 2, title: 'Canal Sur', project: 'Fundo'),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture-zoom-in')));
    await tester.pump(const Duration(milliseconds: 700));

    final node = find.byKey(const ValueKey('capture-node-1'));
    final occupied = [
      tester.getRect(node),
      tester.getRect(find.byKey(const ValueKey('capture-node-2'))),
      tester.getRect(find.byKey(const ValueKey('capture-hub'))),
      tester.getRect(find.byKey(const ValueKey('capture-zoom-in'))),
      tester.getRect(find.byKey(const ValueKey('capture-zoom-out'))),
    ];
    final map = tester.getRect(find.byType(CaptureNetworkMap));
    Offset? empty;
    for (var y = map.top + 150.0; y < map.bottom - 90; y += 28) {
      for (var x = map.left + 18.0; x < map.right - 18; x += 28) {
        final point = Offset(x, y);
        if (occupied.every((rect) => !rect.inflate(16).contains(point))) {
          empty = point;
          break;
        }
      }
      if (empty != null) break;
    }
    expect(empty, isNotNull);
    final before = tester.getTopLeft(node);
    await tester.dragFrom(empty!, const Offset(36, 10));
    await tester.pump();
    expect((tester.getTopLeft(node) - before).distance, greaterThan(4));
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
    expect(find.text('Ver'), findsOneWidget);
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
    expect(find.text('Ver'), findsOneWidget);
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

  testWidgets('el nombre largo se lee y no hay tick de cumplimiento', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const name = 'Estación de bombeo Santa Macarena Norte';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 720,
            child: _map(
              points: [
                {
                  ..._point(id: 1, title: name, project: 'Fundo'),
                  'send_dga': true,
                  'code_dga': 'X1',
                },
                _point(id: 2, title: 'Canal Sur', project: 'Fundo', gap: true),
              ],
              onPointSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.verified_outlined), findsNothing);
    expect(find.text('API en línea'), findsNothing);
    expect(find.text('SMARTHYDRO'), findsOneWidget);
    final title = find.text(name);
    expect(title, findsWidgets);
    final text = tester.widget<Text>(title.first);
    expect(text.maxLines, lessThanOrEqualTo(2));
    final card = tester.getSize(find.byKey(const ValueKey('capture-label-0')));
    expect(card.width, lessThanOrEqualTo(capturePlateWidth + 1));
    expect(card.height, lessThanOrEqualTo(capturePlateHeight + 1));
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

/// El MediaQuery ancho no alcanza: el layout real sigue el tamaño de la vista.
void _useDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// App ancha (≥980) para el mosaico de ventanas web.
Widget _wideApp({required Widget child}) {
  return MaterialApp(
    builder: (context, nested) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(size: const Size(1200, 800)),
        child: nested!,
      );
    },
    home: Scaffold(body: SizedBox(width: 1200, height: 800, child: child)),
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
  double leftInset = 0,
  double openBottomClearance = 8,
  TileProvider? locationTiles,
  Widget? askBar,
  Widget? seatedWell,
  bool mapOnly = false,
}) {
  return CaptureNetworkMap(
    mapOnly: mapOnly,
    points: points,
    onPointSelected: onPointSelected,
    openTickets: openTickets,
    compliance: compliance,
    onRequestSupport: onRequestSupport,
    bottomInset: bottomInset,
    topInset: topInset,
    leftInset: leftInset,
    openBottomClearance: openBottomClearance,
    checkApiHealth: () async => true,
    locationTiles: locationTiles,
    askBar: askBar,
    seatedWell: seatedWell,
  );
}

final Uint8List _quietPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
);

class _QuietTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(_quietPng);
  }
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
