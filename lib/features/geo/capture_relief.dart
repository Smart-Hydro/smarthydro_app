import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Inclinación de la cámara. MapLibre llega hasta 60°.
const captureReliefPitch = 52.0;

/// Un giro leve para que el volumen de los edificios se lea.
const captureReliefBearing = -18.0;

/// Zoom para abrir un grupo: el más cercano en el que todos siguen en pantalla.
///
/// Si a [captureReliefSeparateZoom] todavía caben, usa ese, para que cada
/// logger quede en su coordenada y no en la placa del conteo.
double captureRevealZoom({
  required List<({double latitude, double longitude})> spots,
  required Size size,
  required double currentZoom,
}) {
  if (spots.isEmpty || size.width < 32 || size.height < 32) {
    return currentZoom.clamp(2.0, 16.0);
  }
  var lat = 0.0;
  var lon = 0.0;
  for (final spot in spots) {
    lat += spot.latitude;
    lon += spot.longitude;
  }
  final centerLat = lat / spots.length;
  final centerLng = lon / spots.length;

  bool frames(double zoom) {
    const margin = 28.0;
    for (final spot in spots) {
      final offset = captureReliefOffset(
        latitude: spot.latitude,
        longitude: spot.longitude,
        centerLat: centerLat,
        centerLng: centerLng,
        zoom: zoom,
        pitchDeg: captureReliefPitch,
        bearingDeg: captureReliefBearing,
        size: size,
      );
      if (!offset.dx.isFinite || !offset.dy.isFinite) return false;
      if (offset.dx < margin || offset.dx > size.width - margin) return false;
      if (offset.dy < margin + 36 || offset.dy > size.height - margin) {
        return false;
      }
    }
    return true;
  }

  var zoom = currentZoom.clamp(2.0, 16.0);
  for (var step = zoom; step <= 16.001; step += 0.5) {
    if (!frames(step)) break;
    zoom = step;
  }
  if (frames(captureReliefSeparateZoom)) {
    zoom = math.max(zoom, captureReliefSeparateZoom);
  }
  return zoom.clamp(2.0, 16.0);
}

/// Zoom de MapLibre en el que cada logger queda suelto.
///
/// MapLibre mide el mundo en 512 px en el zoom 0. El encuadre del esquema
/// usa el zoom de Leaflet (256 px). Por eso este umbral es uno menos que
/// [captureClusterSeparateZoom].
const captureReliefSeparateZoom = 15.0;

/// Escala de los píxeles que devuelve el mapa respecto del lienzo de Flutter.
///
/// El centro de la cámara cae en el centro de la vista. Si el valor viene en
/// píxeles físicos, queda unas [devicePixelRatio] veces más lejos.
double captureScreenScale({
  required Offset reportedCenter,
  required Size size,
}) {
  if (size.width < 32 || size.height < 32) return 1;
  if (!reportedCenter.dx.isFinite || !reportedCenter.dy.isFinite) return 1;
  final sx = reportedCenter.dx / (size.width / 2);
  final sy = reportedCenter.dy / (size.height / 2);
  if (sx <= 0 || sy <= 0) return 1;
  final scale = (sx + sy) / 2;
  if (scale > 1.4 && scale < 4 && (sx - sy).abs() < 0.35 * scale) {
    return scale;
  }
  return 1;
}

/// Web, Android e iOS. En escritorio el mapa sigue plano.
bool get captureReliefSupported {
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Estilo vectorial oscuro, sin clave. Teselas de OpenFreeMap.
///
/// El relieve sombreado da textura de lejos. Desde el zoom 14 los edificios
/// salen en volumen, en el teal de la app.
final String captureReliefStyle = jsonEncode(const {
  'version': 8,
  'name': 'SmartHydro',
  'light': {
    'anchor': 'viewport',
    'color': '#E7F4F6',
    'intensity': 0.42,
    'position': [1.15, 210, 28],
  },
  'sources': {
    'ne2': {
      'type': 'raster',
      'tileSize': 256,
      'maxzoom': 6,
      'tiles': [
        'https://tiles.openfreemap.org/natural_earth/ne2sr/{z}/{x}/{y}.png',
      ],
    },
    'openmaptiles': {
      'type': 'vector',
      'url': 'https://tiles.openfreemap.org/planet',
    },
  },
  'sprite': 'https://tiles.openfreemap.org/sprites/ofm_f384/ofm',
  'glyphs': 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#0B171B'},
    },
    {
      'id': 'terrain',
      'type': 'raster',
      'source': 'ne2',
      'maxzoom': 8,
      'paint': {
        'raster-opacity': 0.38,
        'raster-saturation': -0.55,
        'raster-contrast': 0.15,
        'raster-fade-duration': 0,
      },
    },
    {
      'id': 'water',
      'type': 'fill',
      'source': 'openmaptiles',
      'source-layer': 'water',
      'paint': {'fill-color': '#0E3C46'},
    },
    {
      'id': 'landuse-residential',
      'type': 'fill',
      'source': 'openmaptiles',
      'source-layer': 'landuse',
      'filter': [
        '==',
        ['get', 'class'],
        'residential',
      ],
      'paint': {'fill-color': '#10262C', 'fill-opacity': 0.7},
    },
    {
      'id': 'landuse-park',
      'type': 'fill',
      'source': 'openmaptiles',
      'source-layer': 'landuse',
      'filter': [
        '==',
        ['get', 'class'],
        'park',
      ],
      'paint': {'fill-color': '#14342C'},
    },
    {
      'id': 'landcover-wood',
      'type': 'fill',
      'source': 'openmaptiles',
      'source-layer': 'landcover',
      'filter': [
        '==',
        ['get', 'class'],
        'wood',
      ],
      'paint': {'fill-color': '#102820', 'fill-opacity': 0.85},
    },
    {
      'id': 'waterway',
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'waterway',
      'paint': {'line-color': '#1A6070', 'line-width': 1.2},
    },
    {
      'id': 'road-minor',
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'transportation',
      'minzoom': 12,
      'filter': [
        'match',
        ['get', 'class'],
        ['minor', 'service', 'track'],
        true,
        false,
      ],
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': '#2A454C',
        'line-width': [
          'interpolate',
          ['linear'],
          ['zoom'],
          12,
          0.4,
          16,
          3,
        ],
      },
    },
    {
      'id': 'road-major',
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'transportation',
      'minzoom': 8,
      'filter': [
        'match',
        ['get', 'class'],
        ['primary', 'secondary', 'tertiary', 'trunk'],
        true,
        false,
      ],
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': '#4E727C',
        'line-width': [
          'interpolate',
          ['linear'],
          ['zoom'],
          8,
          0.6,
          16,
          6,
        ],
      },
    },
    {
      'id': 'road-motorway',
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'transportation',
      'filter': [
        '==',
        ['get', 'class'],
        'motorway',
      ],
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': '#7FD3E0',
        'line-width': [
          'interpolate',
          ['linear'],
          ['zoom'],
          6,
          0.6,
          16,
          7,
        ],
      },
    },
    {
      'id': 'building',
      'type': 'fill',
      'source': 'openmaptiles',
      'source-layer': 'building',
      'minzoom': 13,
      'maxzoom': 14,
      'paint': {'fill-color': '#163038', 'fill-outline-color': '#2A4E58'},
    },
    {
      'id': 'building-3d',
      'type': 'fill-extrusion',
      'source': 'openmaptiles',
      'source-layer': 'building',
      'minzoom': 14,
      'paint': {
        'fill-extrusion-color': [
          'interpolate',
          ['linear'],
          [
            'coalesce',
            ['get', 'render_height'],
            8,
          ],
          0,
          '#1A333C',
          30,
          '#2A4C58',
          80,
          '#3E6A78',
        ],
        'fill-extrusion-height': [
          'coalesce',
          ['get', 'render_height'],
          8,
        ],
        'fill-extrusion-base': [
          'coalesce',
          ['get', 'render_min_height'],
          0,
        ],
        'fill-extrusion-opacity': 0.94,
        'fill-extrusion-vertical-gradient': true,
      },
    },
    {
      'id': 'road-name',
      'type': 'symbol',
      'source': 'openmaptiles',
      'source-layer': 'transportation_name',
      'minzoom': 14,
      'layout': {
        'symbol-placement': 'line',
        'text-field': [
          'coalesce',
          ['get', 'name:es'],
          ['get', 'name'],
        ],
        'text-font': ['Noto Sans Regular'],
        'text-size': 11,
      },
      'paint': {
        'text-color': '#C5D8D6',
        'text-halo-color': '#0B171B',
        'text-halo-width': 1.2,
      },
    },
    {
      'id': 'place',
      'type': 'symbol',
      'source': 'openmaptiles',
      'source-layer': 'place',
      'filter': [
        'match',
        ['get', 'class'],
        ['city', 'town', 'village'],
        true,
        false,
      ],
      'layout': {
        'text-field': [
          'coalesce',
          ['get', 'name:es'],
          ['get', 'name'],
        ],
        'text-font': ['Noto Sans Regular'],
        'text-size': [
          'interpolate',
          ['linear'],
          ['zoom'],
          4,
          10,
          10,
          14,
        ],
      },
      'paint': {
        'text-color': '#E7F4F2',
        'text-halo-color': '#0B171B',
        'text-halo-width': 1.3,
      },
    },
  ],
});

/// Proyecta un punto GPS a la pantalla con la misma cámara que MapLibre.
///
/// Con inclinación 0 el norte queda arriba. Un punto detrás de la cámara
/// sale como desplazamiento infinito.
Offset captureReliefOffset({
  required double latitude,
  required double longitude,
  required double centerLat,
  required double centerLng,
  required double zoom,
  required double pitchDeg,
  required double bearingDeg,
  required Size size,
}) {
  if (!zoom.isFinite || size.width < 1 || size.height < 1) {
    return const Offset(double.infinity, double.infinity);
  }
  final world = 512 * math.pow(2, zoom);
  final point = _mercatorPx(longitude, latitude, world);
  final center = _mercatorPx(centerLng, centerLat, world);
  final x = point.dx - center.dx;
  final y = point.dy - center.dy;

  final bearing = bearingDeg * math.pi / 180;
  final cosB = math.cos(bearing);
  final sinB = math.sin(bearing);
  final rx = x * cosB + y * sinB;
  final ry = -x * sinB + y * cosB;

  const fov = 36.86989764584402 * math.pi / 180;
  final cameraToCenter = 0.5 / math.tan(fov / 2) * size.height;
  final pitch = pitchDeg * math.pi / 180;
  final depth = cameraToCenter - ry * math.sin(pitch);
  if (depth <= 1) return const Offset(double.infinity, double.infinity);
  final scale = cameraToCenter / depth;
  return Offset(
    size.width / 2 + rx * scale,
    size.height / 2 + ry * math.cos(pitch) * scale,
  );
}

Offset _mercatorPx(double longitude, double latitude, num world) {
  final clamped = latitude.clamp(-85.05112878, 85.05112878);
  final sine = math.sin(clamped * math.pi / 180);
  final x = (longitude + 180) / 360 * world;
  final y = (0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi)) * world;
  return Offset(x.toDouble(), y.toDouble());
}

/// Metal del cuerpo. La luz de arriba va aparte.
const captureLoggerMetal = '#D5E4E2';

/// Punto de la antena cuando el logger está activo.
const captureLoggerLampOn = '#B8FFE8';

/// Punto de la antena apagado.
const captureLoggerLampOff = '#243236';

/// Metros por píxel de MapLibre. El zoom 0 cubre el mundo en 512 px.
double captureMetersPerPixel({required double latitude, required double zoom}) {
  if (!latitude.isFinite || !zoom.isFinite) return 1;
  final lat = latitude.clamp(-75.0, 75.0);
  final z = zoom.clamp(0.0, 22.0);
  const earth = 40075016.686;
  return earth * math.cos(lat * math.pi / 180) / (512 * math.pow(2, z));
}

/// Volumen del logger parado en el terreno, no una calcomanía.
///
/// El cuerpo, el mástil y la luz se miden para ocupar unos píxeles a este
/// zoom. Así crecen con la perspectiva del mapa y no quedan dentro de un cuadro.
List<Map<String, dynamic>> captureLoggerVolume({
  required double latitude,
  required double longitude,
  required double zoom,
  required String accent,
  required bool selected,
  required bool surface,
  required String pointKey,
  bool active = false,
  bool cluster = false,
  String members = '',
}) {
  final mpp = captureMetersPerPixel(latitude: latitude, zoom: zoom);
  final scale = (selected ? 1.12 : 1.0) * (cluster ? 1.15 : 1.0);
  double span(double pixels) => (pixels * scale * mpp).clamp(0.5, 12000.0);

  Map<String, dynamic> part({
    required String name,
    required double east,
    required double north,
    required double width,
    required double depth,
    required double base,
    required double height,
    required String color,
  }) {
    return {
      'type': 'Feature',
      'properties': <String, dynamic>{
        'key': pointKey,
        'part': name,
        'color': color,
        'h': height,
        'b': base,
        'cluster': cluster ? 1 : 0,
        'members': members,
      },
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          _groundRing(
            latitude: latitude,
            longitude: longitude,
            east: east,
            north: north,
            width: width,
            depth: depth,
          ),
        ],
      },
    };
  }

  final bodyW = span(surface ? 22 : 20);
  final bodyD = span(surface ? 16 : 12);
  final bodyH = span(surface ? 6 : 9);
  final plinthH = selected ? span(1.6) : 0.0;
  final roof = plinthH + bodyH;
  final mastH = span(surface ? 14 : 26);
  final mastTop = roof + mastH;
  final lamp = active ? captureLoggerLampOn : captureLoggerLampOff;
  return [
    if (selected)
      part(
        name: 'plinth',
        east: 0,
        north: 0,
        width: bodyW + span(3),
        depth: bodyD + span(3),
        base: 0,
        height: plinthH,
        color: accent,
      ),
    part(
      name: 'body',
      east: 0,
      north: 0,
      width: bodyW,
      depth: bodyD,
      base: plinthH,
      height: bodyH,
      color: captureLoggerMetal,
    ),
    part(
      name: 'lamp',
      east: bodyW * 0.28,
      north: -bodyD * 0.28,
      width: span(3.4),
      depth: span(3.2),
      base: roof,
      height: span(3.4),
      color: accent,
    ),
    part(
      name: 'mast',
      east: 0,
      north: 0,
      width: span(1.7),
      depth: span(1.7),
      base: roof,
      height: mastH,
      color: '#F4FEFF',
    ),
    part(
      name: 'tip',
      east: 0,
      north: 0,
      width: span(active ? 5.2 : 3.6),
      depth: span(active ? 5.2 : 3.6),
      base: mastTop,
      height: span(active ? 3.6 : 2.6),
      color: lamp,
    ),
  ];
}

/// Anillo cerrado, en sentido antihorario, centrado en metros locales.
List<List<double>> _groundRing({
  required double latitude,
  required double longitude,
  required double east,
  required double north,
  required double width,
  required double depth,
}) {
  final halfW = width / 2;
  final halfD = depth / 2;
  final cosLat = math.cos(latitude * math.pi / 180).abs().clamp(0.2, 1.0);
  const metersPerDegree = 111320.0;
  final lonPerMeter = 1 / (metersPerDegree * cosLat);
  final latPerMeter = 1 / metersPerDegree;
  List<double> at(double eastMeter, double northMeter) => [
    longitude + eastMeter * lonPerMeter,
    latitude + northMeter * latPerMeter,
  ];
  final ring = [
    at(east - halfW, north - halfD),
    at(east + halfW, north - halfD),
    at(east + halfW, north + halfD),
    at(east - halfW, north + halfD),
  ];
  ring.add(ring.first);
  return ring;
}
