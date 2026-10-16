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
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
  return LatLng(lat, lon);
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
