import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Encuadre para que todos los puntos quepan, dejando aire al título.
({LatLng center, double zoom}) captureCameraFor(
  Size size,
  List<LatLng> points,
) {
  if (points.isEmpty || size.width < 32 || size.height < 32) {
    return (center: const LatLng(-33.45, -70.66), zoom: 5);
  }
  var minLat = points.first.latitude;
  var maxLat = minLat;
  var minLon = points.first.longitude;
  var maxLon = minLon;
  for (final point in points) {
    minLat = math.min(minLat, point.latitude);
    maxLat = math.max(maxLat, point.latitude);
    minLon = math.min(minLon, point.longitude);
    maxLon = math.max(maxLon, point.longitude);
  }
  final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
  if ((maxLat - minLat).abs() < 0.0008 && (maxLon - minLon).abs() < 0.0008) {
    return (center: center, zoom: 13);
  }

  final padX = math.min(56.0, size.width * 0.12);
  final padTop = math.min(128.0, size.height * 0.24);
  final padBottom = math.min(80.0, size.height * 0.14);
  final availW = math.max(48.0, size.width - padX * 2);
  final availH = math.max(48.0, size.height - padTop - padBottom);
  final dx = math.max((maxLon - minLon).abs() / 360, 1e-9);
  final dy = math.max((_mercatorY(minLat) - _mercatorY(maxLat)).abs(), 1e-9);
  final zoomX = math.log(availW / (256 * dx)) / math.ln2;
  final zoomY = math.log(availH / (256 * dy)) / math.ln2;
  // Un nivel de aire para que la red no quede pegada al borde del visor.
  final zoom = (math.min(zoomX, zoomY) - 1.1).clamp(3.0, 13.0);
  return (center: center, zoom: zoom);
}

double _mercatorY(double latitude) {
  final sine = math.sin(latitude * math.pi / 180);
  return 0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi);
}

/// Coordenada del punto. Cero o ausente no cuenta como GPS.
///
/// Igual que el observatorio (`_resolve_coords` del API): si el par no es
/// geográfico pero parece UTM (`lat` = norte, `lon` = este) se convierte
/// desde la zona 19S.
LatLng? captureLatLng(Map<String, dynamic> point) {
  final lat =
      _coordinate(point['lat']) ??
      _coordinate(point['latitude']) ??
      _nestedCoordinate(point, 'lat');
  final lon =
      _coordinate(point['lon']) ??
      _coordinate(point['lng']) ??
      _coordinate(point['longitude']) ??
      _nestedCoordinate(point, 'lon') ??
      _nestedCoordinate(point, 'lng');
  if (lat == null || lon == null || lat == 0 || lon == 0) return null;
  if (!lat.isFinite || !lon.isFinite) return null;
  if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
    return LatLng(lat, lon);
  }
  final northing = lat;
  final easting = lon;
  if (northing < 0 || northing > 10000000) return null;
  if (easting < 100000 || easting > 900000) return null;
  final converted = utmToLatLng(easting, northing);
  if (converted.latitude.abs() > 90 || converted.longitude.abs() > 180) {
    return null;
  }
  return converted;
}

/// UTM WGS84 a lat/lon decimal. Por defecto zona 19S (Chile central).
/// Serie estándar del USGS, la misma fórmula que usa el API.
LatLng utmToLatLng(
  double easting,
  double northing, {
  int zone = 19,
  bool southern = true,
}) {
  const a = 6378137.0;
  const f = 1 / 298.257223563;
  const e2 = f * (2 - f);
  const k0 = 0.9996;
  const ep2 = e2 / (1 - e2);
  final e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2));
  final x = easting - 500000.0;
  final y = northing - (southern ? 10000000.0 : 0.0);
  final lon0 = (zone * 6 - 183) * math.pi / 180;
  final m = y / k0;
  final mu = m / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256));
  final phi1 =
      mu +
      (3 * e1 / 2 - 27 * math.pow(e1, 3) / 32) * math.sin(2 * mu) +
      (21 * e1 * e1 / 16 - 55 * math.pow(e1, 4) / 32) * math.sin(4 * mu) +
      (151 * math.pow(e1, 3) / 96) * math.sin(6 * mu);
  final sin1 = math.sin(phi1);
  final cos1 = math.cos(phi1);
  final tan1 = math.tan(phi1);
  final n1 = a / math.sqrt(1 - e2 * sin1 * sin1);
  final t1 = tan1 * tan1;
  final c1 = ep2 * cos1 * cos1;
  final r1 = a * (1 - e2) / math.pow(1 - e2 * sin1 * sin1, 1.5);
  final d = x / (n1 * k0);
  final lat =
      phi1 -
      (n1 * tan1 / r1) *
          (d * d / 2 -
              (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * ep2) *
                  math.pow(d, 4) /
                  24 +
              (61 +
                      90 * t1 +
                      298 * c1 +
                      45 * t1 * t1 -
                      252 * ep2 -
                      3 * c1 * c1) *
                  math.pow(d, 6) /
                  720);
  final lon =
      lon0 +
      (d -
              (1 + 2 * t1 + c1) * math.pow(d, 3) / 6 +
              (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * ep2 + 24 * t1 * t1) *
                  math.pow(d, 5) /
                  120) /
          cos1;
  return LatLng(lat * 180 / math.pi, lon * 180 / math.pi);
}

/// Clave estable para marcar el punto elegido en el mapa.
String capturePointKey(Map<String, dynamic> point) {
  final raw = point['id'];
  if (raw == null || '$raw'.isEmpty || '$raw' == 'null') {
    return 'h${identityHashCode(point)}';
  }
  return '$raw';
}

double? _nestedCoordinate(Map<String, dynamic> point, String key) {
  for (final nest in ['location', 'dga', 'geo']) {
    final value = point[nest];
    if (value is Map) {
      final parsed = _coordinate(value[key]);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double? _coordinate(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
  return null;
}

/// Radio de agrupación, el mismo de leaflet.markercluster en Ikolu.
const captureClusterRadius = 80.0;

/// Desde este zoom cada punto se dibuja solo, aunque sigan cerca.
const captureClusterSeparateZoom = 16.0;

/// Junta índices cuya posición en pantalla cae dentro de [radius] del centro
/// del grupo. El orden de entrada fija el resultado.
List<List<int>> clusterByPixel(
  List<Offset> positions, {
  double radius = captureClusterRadius,
}) {
  if (positions.isEmpty) return const [];
  if (!radius.isFinite || radius <= 0) {
    return [
      for (var index = 0; index < positions.length; index++) [index],
    ];
  }
  final used = List<bool>.filled(positions.length, false);
  final groups = <List<int>>[];
  for (var index = 0; index < positions.length; index++) {
    if (used[index]) continue;
    final group = <int>[index];
    used[index] = true;
    var sum = positions[index];
    var grew = true;
    while (grew) {
      grew = false;
      final center = sum / group.length.toDouble();
      for (var other = 0; other < positions.length; other++) {
        if (used[other]) continue;
        if ((positions[other] - center).distance <= radius) {
          used[other] = true;
          group.add(other);
          sum += positions[other];
          grew = true;
        }
      }
    }
    groups.add(group);
  }
  return groups;
}

/// Separa en pantalla los puntos que quedaron encima unos de otros.
///
/// Los que ya están a más de [gap] no se mueven. El resto sale en arco
/// alrededor de su centro para que cada logger se pueda tocar.
List<Offset> captureFanOffsets(List<Offset> raw, {double gap = 96}) {
  if (raw.length < 2 || !gap.isFinite || gap <= 0) return raw;
  final groups = clusterByPixel(raw, radius: gap);
  final out = List<Offset>.of(raw);
  for (final group in groups) {
    if (group.length < 2) continue;
    var cx = 0.0;
    var cy = 0.0;
    var count = 0;
    for (final index in group) {
      final offset = raw[index];
      if (!offset.dx.isFinite || !offset.dy.isFinite) continue;
      cx += offset.dx;
      cy += offset.dy;
      count++;
    }
    if (count < 2) continue;
    final center = Offset(cx / count, cy / count);
    final radius = gap / (2 * math.sin(math.pi / count));
    var slot = 0;
    for (final index in group) {
      final angle = -math.pi / 2 + slot * 2 * math.pi / count;
      slot++;
      out[index] =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    }
  }
  return out;
}
