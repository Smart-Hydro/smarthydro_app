import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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
            child: CaptureNetworkMap(
              points: points,
              onPointSelected: (point) => opened = point,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Pozo Norte'), findsOneWidget);
    expect(find.text('Conectado'), findsWidgets);
    expect(find.text('Advertencia'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('capture-node-1')));
    await tester.pump();
    expect(opened?['title'], 'Pozo Norte');
    expect(tester.takeException(), isNull);
  });

  testWidgets('con GPS muestra el mapa de la red', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 640,
            child: CaptureNetworkMap(
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

    expect(find.text('Pozo Norte'), findsOneWidget);
    expect(find.text('Canal Sur'), findsOneWidget);
    expect(find.text('Conectado'), findsNWidgets(2));
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
            child: CaptureNetworkMap(
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

    final boxes = [for (final name in names) tester.getRect(find.text(name))];
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        expect(
          boxes[i].overlaps(boxes[j]),
          isFalse,
          reason: '${names[i]} $i ${boxes[i]} pisa ${names[j]} ${boxes[j]}',
        );
      }
    }
  });
}

Map<String, dynamic> _point({
  required int id,
  required String title,
  required String project,
  bool surface = false,
  bool gap = false,
  double? lat,
  double? lon,
}) {
  return {
    'id': id,
    'title': title,
    'project_name': project,
    'type_dga': surface ? 'SUPERFICIAL' : 'SUBTERRANEO',
    'lat': ?lat,
    'lon': ?lon,
    'latest_telemetry': gap
        ? {'days_not_connection': 2}
        : {
            'date_time_medition': DateTime.now().toIso8601String(),
            'days_not_connection': 0,
          },
  };
}
