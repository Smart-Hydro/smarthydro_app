import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/geo/capture_coordinates.dart';
import 'package:smarthydro_app/features/geo/capture_location_map.dart';
import 'package:smarthydro_app/features/geo/capture_relief.dart';
import 'package:smarthydro_app/features/geo/capture_water_mark.dart';

void main() {
  test('el estilo trae terreno y edificios en volumen', () {
    final style = jsonDecode(captureReliefStyle) as Map<String, dynamic>;
    final layers = style['layers'] as List<dynamic>;
    final ids = [
      for (final layer in layers)
        if (layer is Map) layer['id'],
    ];
    expect(ids, contains('terrain'));
    expect(ids, contains('building-3d'));
    expect(style['sources'], containsPair('openmaptiles', isNotNull));
  });

  test('la proyección deja el centro quieto y el norte arriba', () {
    const size = Size(200, 200);
    final center = captureReliefOffset(
      latitude: -33.45,
      longitude: -70.66,
      centerLat: -33.45,
      centerLng: -70.66,
      zoom: 12,
      pitchDeg: 0,
      bearingDeg: 0,
      size: size,
    );
    expect(center.dx, closeTo(100, 0.01));
    expect(center.dy, closeTo(100, 0.01));

    final east = captureReliefOffset(
      latitude: -33.45,
      longitude: -70.65,
      centerLat: -33.45,
      centerLng: -70.66,
      zoom: 12,
      pitchDeg: 0,
      bearingDeg: 0,
      size: size,
    );
    expect(east.dx, greaterThan(center.dx));

    final north = captureReliefOffset(
      latitude: -33.44,
      longitude: -70.66,
      centerLat: -33.45,
      centerLng: -70.66,
      zoom: 12,
      pitchDeg: 0,
      bearingDeg: 0,
      size: size,
    );
    expect(north.dy, lessThan(center.dy));

    final tilted = captureReliefOffset(
      latitude: -33.44,
      longitude: -70.66,
      centerLat: -33.45,
      centerLng: -70.66,
      zoom: 12,
      pitchDeg: 55,
      bearingDeg: 0,
      size: size,
    );
    expect((tilted.dy - 100).abs(), lessThan((north.dy - 100).abs()));
  });

  test(
    'abrir un grupo cercano llega al zoom en que cada logger queda suelto',
    () {
      final zoom = captureRevealZoom(
        spots: const [
          (latitude: -36.61, longitude: -72.10),
          (latitude: -36.612, longitude: -72.103),
          (latitude: -36.608, longitude: -72.098),
        ],
        size: const Size(390, 640),
        currentZoom: 8,
      );
      expect(zoom, greaterThanOrEqualTo(captureReliefSeparateZoom));
    },
  );

  test('abrir un grupo amplio no salta al zoom de calle', () {
    final zoom = captureRevealZoom(
      spots: const [
        (latitude: -35.4, longitude: -72.4),
        (latitude: -36.6, longitude: -71.8),
        (latitude: -37.2, longitude: -72.6),
      ],
      size: const Size(390, 640),
      currentZoom: 6,
    );
    expect(zoom, greaterThanOrEqualTo(6));
    expect(zoom, lessThan(captureReliefSeparateZoom));
  });

  test('los píxeles físicos del mapa se bajan a la escala de Flutter', () {
    const size = Size(400, 640);
    expect(
      captureScreenScale(reportedCenter: const Offset(200, 320), size: size),
      1,
    );
    expect(
      captureScreenScale(reportedCenter: const Offset(600, 960), size: size),
      closeTo(3, 0.01),
    );
    expect(
      captureScreenScale(reportedCenter: const Offset(40, 900), size: size),
      1,
    );
  });

  test('el logger del relieve es un volumen parado en el terreno', () {
    final well = captureLoggerVolume(
      latitude: -36.6,
      longitude: -72.1,
      zoom: 11,
      accent: '#66E0C2',
      selected: true,
      surface: false,
      active: true,
      pointKey: '7',
    );
    final surface = captureLoggerVolume(
      latitude: -36.6,
      longitude: -72.1,
      zoom: 11,
      accent: '#FFC46B',
      selected: false,
      surface: true,
      pointKey: '8',
    );

    Map<String, dynamic> propsOf(
      List<Map<String, dynamic>> parts,
      String name,
    ) {
      return parts.firstWhere(
            (part) => part['properties']['part'] == name,
          )['properties']
          as Map<String, dynamic>;
    }

    double topOf(List<Map<String, dynamic>> parts, String name) {
      final props = propsOf(parts, name);
      return ((props['b'] as num) + (props['h'] as num)).toDouble();
    }

    final body = propsOf(well, 'body');
    final mast = propsOf(well, 'mast');
    expect(body['color'], captureLoggerMetal);
    expect(body['key'], '7');
    expect(mast['b'], closeTo(topOf(well, 'body'), 0.001));
    expect(topOf(well, 'tip'), greaterThan(topOf(well, 'body') * 2));
    expect(propsOf(well, 'tip')['color'], captureLoggerLampOn);
    expect(propsOf(surface, 'tip')['color'], captureLoggerLampOff);
    expect(well.any((part) => part['properties']['part'] == 'plinth'), isTrue);
    expect(
      surface.any((part) => part['properties']['part'] == 'plinth'),
      isFalse,
    );
    expect(topOf(surface, 'tip'), lessThan(topOf(well, 'tip')));

    final ring =
        ((well.firstWhere(
                      (part) => part['properties']['part'] == 'body',
                    )['geometry']
                    as Map)['coordinates']
                as List)[0]
            as List;
    expect(ring.first, ring.last);
    expect(ring.length, 5);
    var minLon = (ring.first as List)[0] as double;
    var maxLon = minLon;
    for (final corner in ring) {
      final lon = (corner as List)[0] as double;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }
    expect(maxLon - minLon, greaterThan(0));
    expect(maxLon - minLon, lessThan(0.05));
    expect((mast['h'] as num), greaterThan((body['h'] as num) * 2));
  });

  test('los loggers encimados se abren en arco', () {
    final spread = captureFanOffsets(const [
      Offset(40, 40),
      Offset(44, 42),
      Offset(400, 40),
    ]);
    expect((spread[0] - spread[1]).distance, greaterThanOrEqualTo(96));
    expect(spread[2], const Offset(400, 40));
  });

  testWidgets('el punto elegido muestra el agua en su lugar', (tester) async {
    const point = {
      'id': 7,
      'title': 'Pozo Norte',
      'lat': -33.45,
      'lon': -70.66,
    };
    Future<void> pumpMap({String? selectedKey, int locateTick = 0}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: CaptureLocationMap(
                tileProvider: _QuietTiles(),
                points: const [point],
                selectedKey: selectedKey,
                locateTick: locateTick,
              ),
            ),
          ),
        ),
      );
    }

    await pumpMap();
    await tester.pump();
    expect(find.byKey(const ValueKey('capture-water-7')), findsNothing);

    await pumpMap(selectedKey: '7', locateTick: 1);
    await tester.pump();
    expect(find.byKey(const ValueKey('capture-water-7')), findsOneWidget);
    expect(find.byType(CaptureWaterMark), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('el agua queda quieta si se reducen las animaciones', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 220,
            height: 220,
            child: CaptureWaterMark(key: ValueKey('capture-water-quiet')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('capture-water-quiet')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
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
