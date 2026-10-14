import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/brand.dart';
import '../point_link.dart';

/// Mapa de agua del inicio. Los puntos se ven como marcas,
/// con un brillo corto, y se puede girar arrastrando.
class CaptureNetworkMap extends StatelessWidget {
  const CaptureNetworkMap({
    required this.points,
    required this.onPointSelected,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onPointSelected;

  @override
  Widget build(BuildContext context) {
    return _WaterView(points: points, onOpen: onPointSelected);
  }
}

class _WaterView extends StatefulWidget {
  const _WaterView({required this.points, required this.onOpen});

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  State<_WaterView> createState() => _WaterViewState();
}

class _WaterViewState extends State<_WaterView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late List<Offset> _ground = layoutWaterField(widget.points);
  double _yaw = 0.12;
  double _tilt = 0.64;

  _WaterCamera get _camera => _WaterCamera(yaw: _yaw, tilt: _tilt);

  @override
  void initState() {
    super.initState();
    _glow.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _glow.stop();
      _glow.value = 0.35;
    } else if (!_glow.isAnimating) {
      _glow.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _WaterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ground = layoutWaterField(widget.points);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _orbit(Offset delta) {
    setState(() {
      _yaw += delta.dx * 0.007;
      _tilt = (_tilt + delta.dy * 0.0032).clamp(0.34, 0.92);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final anchors = [
          for (final ground in _ground) _camera.project(ground, size),
        ];
        final chips = placeCaptureChips(anchors, size);
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onPanUpdate: (details) => _orbit(details.delta),
                child: CustomPaint(
                  painter: const _WaterPainter(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            for (var index = 0; index < widget.points.length; index++)
              Positioned(
                left: chips[index].left,
                top: chips[index].top,
                width: chips[index].width,
                child: _StatusChip(
                  point: widget.points[index],
                  onTap: () => widget.onOpen(widget.points[index]),
                ),
              ),
            AnimatedBuilder(
              animation: _glow,
              builder: (context, _) {
                final crest = 0.5 + 0.5 * math.sin(_glow.value * math.pi * 2);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var index = 0; index < widget.points.length; index++)
                      Positioned(
                        left: anchors[index].dx - 22,
                        top: anchors[index].dy - 22,
                        child: _Beacon(
                          point: widget.points[index],
                          glow: crest,
                          onTap: () => widget.onOpen(widget.points[index]),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (widget.points.isEmpty) const _EmptyNetwork(),
          ],
        );
      },
    );
  }
}

class _WaterCamera {
  const _WaterCamera({required this.yaw, required this.tilt});

  final double yaw;
  final double tilt;

  (double x, double z) _rotated(Offset ground) {
    return (
      ground.dx * math.cos(yaw) - ground.dy * math.sin(yaw),
      ground.dx * math.sin(yaw) + ground.dy * math.cos(yaw),
    );
  }

  /// Perspectiva suave: lo cercano baja y se abre, sin recortar una lámina.
  Offset project(Offset ground, Size size) {
    final (x, z) = _rotated(ground);
    final depth = ((z + 1.15) / 2.3).clamp(0.0, 1.0);
    final spread = 0.84 + depth * (0.16 + tilt * 0.22);
    final yNorm = 0.16 + depth * (0.36 + tilt * 0.26);
    return Offset(size.width * (0.50 + x * 0.44 * spread), size.height * yNorm);
  }
}

class _WaterPainter extends CustomPainter {
  const _WaterPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A3C46), Color(0xFF10262C), Color(0xFF071214)],
          stops: [0, 0.34, 1],
        ).createShader(bounds),
    );
    final sheen = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.42),
      width: size.width * 1.2,
      height: size.height * 0.7,
    );
    canvas.drawOval(
      sheen,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF2A6270).withValues(alpha: 0.22),
            const Color(0xFF2A6270).withValues(alpha: 0),
          ],
        ).createShader(sheen),
    );
  }

  @override
  bool shouldRepaint(covariant _WaterPainter oldDelegate) => false;
}

/// Puntos sobre el plano de agua, separados para que las fichas no se monten.
@visibleForTesting
List<Offset> layoutWaterField(List<Map<String, dynamic>> points) {
  if (points.isEmpty) return const [];
  final coords = [for (final point in points) captureLatLng(point)];
  final raw = coords.every((coord) => coord != null)
      ? _groundFromGps([for (final coord in coords) coord!])
      : _groundFromLayout(points);
  _separateGround(raw);
  return raw;
}

List<Offset> _groundFromGps(List<LatLng> coords) {
  if (coords.length == 1) return const [Offset.zero];
  var minLat = coords.first.latitude;
  var maxLat = minLat;
  var minLon = coords.first.longitude;
  var maxLon = minLon;
  for (final coord in coords) {
    minLat = math.min(minLat, coord.latitude);
    maxLat = math.max(maxLat, coord.latitude);
    minLon = math.min(minLon, coord.longitude);
    maxLon = math.max(maxLon, coord.longitude);
  }
  final latSpan = math.max(maxLat - minLat, 0.0008);
  final lonSpan = math.max(maxLon - minLon, 0.0008);
  return [
    for (final coord in coords)
      Offset(
        ((coord.longitude - minLon) / lonSpan - 0.5) * 1.35,
        (0.5 - (coord.latitude - minLat) / latSpan) * 1.35,
      ),
  ];
}

List<Offset> _groundFromLayout(List<Map<String, dynamic>> points) {
  const board = Size(1000, 1000);
  final laid = layoutCaptureNodes(board, [
    for (final point in points) captureProjectKey(point),
  ]);
  return [
    for (final spot in laid)
      Offset(
        (spot.dx / board.width - 0.5) * 1.5,
        (spot.dy / board.height - 0.5) * 1.5,
      ),
  ];
}

void _separateGround(List<Offset> spots) {
  const minDist = 0.38;
  for (var pass = 0; pass < 28; pass++) {
    for (var i = 0; i < spots.length; i++) {
      for (var j = i + 1; j < spots.length; j++) {
        var delta = spots[j] - spots[i];
        var dist = delta.distance;
        if (dist < 0.001) {
          delta = Offset(minDist, 0.05 * (j - i));
          dist = delta.distance;
        }
        if (dist >= minDist) continue;
        final push = delta / dist * (minDist - dist) * 0.5;
        spots[i] -= push;
        spots[j] += push;
      }
    }
    for (var i = 0; i < spots.length; i++) {
      spots[i] = Offset(
        spots[i].dx.clamp(-0.86, 0.86),
        spots[i].dy.clamp(-0.86, 0.86),
      );
    }
  }
}

/// Coloca cada ficha en el hueco libre más cercano a su punto.
@visibleForTesting
List<Rect> placeCaptureChips(List<Offset> anchors, Size size) {
  const width = 148.0;
  const height = 46.0;
  const pad = 8.0;
  final maxLeft = math.max(pad, size.width - width - pad);
  final maxTop = math.max(pad, size.height - height - pad);

  List<Rect> slotsFor({required bool avoidBeacons}) {
    final slots = <Rect>[];
    for (var top = pad; top <= maxTop + 0.1; top += height + 8) {
      for (var left = pad; left <= maxLeft + 0.1; left += width + 8) {
        final rect = Rect.fromLTWH(left, top, width, height);
        if (avoidBeacons &&
            anchors.any(
              (point) => rect.overlaps(
                Rect.fromCenter(center: point, width: 64, height: 64),
              ),
            )) {
          continue;
        }
        slots.add(rect);
      }
    }
    return slots;
  }

  var slots = slotsFor(avoidBeacons: true);
  if (slots.length < anchors.length) {
    slots = slotsFor(avoidBeacons: false);
  }

  final used = List<bool>.filled(slots.length, false);
  final placed = <Rect>[];
  for (final anchor in anchors) {
    var best = -1;
    var bestDist = double.infinity;
    for (var index = 0; index < slots.length; index++) {
      if (used[index]) continue;
      final dist = (slots[index].center - anchor).distance;
      if (dist < bestDist) {
        bestDist = dist;
        best = index;
      }
    }
    if (best < 0) {
      placed.add(Rect.fromLTWH(pad, pad, width, height));
      continue;
    }
    used[best] = true;
    placed.add(slots[best]);
  }
  return placed;
}

class _Beacon extends StatelessWidget {
  const _Beacon({required this.point, required this.glow, required this.onTap});

  final Map<String, dynamic> point;
  final double glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _linkColor(point);
    return Semantics(
      button: true,
      label: _title(point),
      child: GestureDetector(
        key: ValueKey('capture-node-${_pointKey(point)}'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35 + 0.4 * glow),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.point, required this.onTap});

  final Map<String, dynamic> point;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _linkColor(point);
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 156),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE0101618),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _title(point),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFFE7F1F0),
                        ),
                      ),
                      Text(
                        pointLinkLabel(pointLinkOf(point)),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF93A8A9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyNetwork extends StatelessWidget {
  const _EmptyNetwork();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Cuando tu cuenta tenga puntos de captación, la red aparecerá aquí.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFB7C8C7), height: 1.35),
        ),
      ),
    );
  }
}

/// Encuadre para que todos los puntos quepan, dejando aire al título.
@visibleForTesting
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
@visibleForTesting
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

/// Nombre de proyecto usado para agrupar la red. Vacío si no hay.
@visibleForTesting
String captureProjectKey(Map<String, dynamic> point) {
  final name = point['project_name']?.toString().trim();
  if (name == null || name.isEmpty || name == 'null') return '';
  return name;
}

@visibleForTesting
bool captureIsSurface(Map<String, dynamic> point) {
  final dga = point['dga'];
  if (dga is Map && '${dga['type_dga']}'.toUpperCase() == 'SUPERFICIAL') {
    return true;
  }
  return '${point['type_dga']}'.toUpperCase() == 'SUPERFICIAL';
}

/// Árbol de la red: primero une cada proyecto, después une los proyectos.
@visibleForTesting
List<(int, int)> captureNetworkEdges({
  required List<String> projects,
  required List<Offset> positions,
}) {
  final groups = <String, List<int>>{};
  for (var index = 0; index < projects.length; index++) {
    groups.putIfAbsent(projects[index], () => []).add(index);
  }
  double distance(int a, int b) {
    final delta = positions[a] - positions[b];
    return delta.dx * delta.dx + delta.dy * delta.dy;
  }

  final links = <(int, int)>[];
  final reps = <int>[];
  for (final members in groups.values) {
    links.addAll(_spanningTree(members, distance));
    reps.add(_representative(members, positions));
  }
  if (reps.length > 1) links.addAll(_spanningTree(reps, distance));
  return links;
}

/// Posiciones de la vista esquemática, agrupadas por proyecto.
@visibleForTesting
List<Offset> layoutCaptureNodes(Size size, List<String> projects) {
  final offsets = List<Offset>.filled(projects.length, Offset.zero);
  if (projects.isEmpty || size.isEmpty) return offsets;

  final groups = <String, List<int>>{};
  for (var index = 0; index < projects.length; index++) {
    groups.putIfAbsent(projects[index], () => []).add(index);
  }
  final keys = groups.keys.toList(growable: false);
  // El título ocupa arriba y las etiquetas necesitan aire abajo.
  final insetX = math.min(40.0, size.width * 0.12);
  final top = math.min(118.0, size.height * 0.24);
  final insetBottom = math.min(84.0, size.height * 0.18);
  final safe = Rect.fromLTRB(
    insetX,
    top,
    math.max(insetX + 1, size.width - insetX),
    math.max(top + 1, size.height - insetBottom),
  );
  final center = safe.center;
  final clusterPad = groups.values.map(_clusterRadius).reduce(math.max);
  final room = math.min(safe.width, safe.height);
  final fit = room / 2 - clusterPad - 8;
  // La red queda en el centro, sin estirarse hasta los bordes.
  final orbit = keys.length <= 1
      ? math.min(math.max(52.0, fit), room * 0.34)
      : math.min(math.max(72.0, fit * 0.45), room * 0.28);

  if (keys.length == 1) {
    _placeRing(offsets, groups[keys.first]!, center, orbit);
  } else {
    for (var group = 0; group < keys.length; group++) {
      final angle = -math.pi / 2 + group * 2 * math.pi / keys.length;
      final hub = center + Offset(math.cos(angle), math.sin(angle)) * orbit;
      final members = groups[keys[group]]!;
      _placeRing(offsets, members, hub, _clusterRadius(members));
    }
  }

  for (var index = 0; index < offsets.length; index++) {
    offsets[index] = Offset(
      offsets[index].dx.clamp(safe.left, safe.right),
      offsets[index].dy.clamp(safe.top, safe.bottom),
    );
  }
  return offsets;
}

double _clusterRadius(List<int> members) {
  if (members.length <= 1) return 0;
  return 36 / math.sin(math.pi / members.length);
}

void _placeRing(
  List<Offset> out,
  List<int> members,
  Offset center,
  double radius,
) {
  if (members.length == 1 || radius == 0) {
    out[members.first] = center;
    return;
  }
  for (var index = 0; index < members.length; index++) {
    final angle = -math.pi / 2 + index * 2 * math.pi / members.length;
    out[members[index]] =
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }
}

int _representative(List<int> members, List<Offset> positions) {
  if (members.length == 1) return members.first;
  var cx = 0.0;
  var cy = 0.0;
  for (final index in members) {
    cx += positions[index].dx;
    cy += positions[index].dy;
  }
  final centroid = Offset(cx / members.length, cy / members.length);
  var best = members.first;
  var bestDistance = double.infinity;
  for (final index in members) {
    final distance = (positions[index] - centroid).distanceSquared;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = index;
    }
  }
  return best;
}

List<(int, int)> _spanningTree(
  List<int> nodes,
  double Function(int a, int b) distance,
) {
  if (nodes.length < 2) return const [];
  final edges = <(double, int, int)>[];
  for (var i = 0; i < nodes.length; i++) {
    for (var j = i + 1; j < nodes.length; j++) {
      edges.add((distance(nodes[i], nodes[j]), nodes[i], nodes[j]));
    }
  }
  edges.sort((a, b) => a.$1.compareTo(b.$1));

  final parent = <int, int>{for (final node in nodes) node: node};
  int find(int node) {
    var root = node;
    while (parent[root] != root) {
      root = parent[root]!;
    }
    var current = node;
    while (parent[current] != root) {
      final next = parent[current]!;
      parent[current] = root;
      current = next;
    }
    return root;
  }

  final links = <(int, int)>[];
  for (final edge in edges) {
    final left = find(edge.$2);
    final right = find(edge.$3);
    if (left == right) continue;
    parent[left] = right;
    links.add((edge.$2, edge.$3));
    if (links.length == nodes.length - 1) break;
  }
  return links;
}

int _pointKey(Map<String, dynamic> point) {
  final raw = point['id'];
  if (raw is int) return raw;
  final parsed = int.tryParse('$raw');
  if (parsed != null) return parsed;
  return identityHashCode(point);
}

String _title(Map<String, dynamic> point) {
  final title = point['title']?.toString().trim();
  if (title == null || title.isEmpty || title == 'null') return 'Punto';
  return title;
}

Color _linkColor(Map<String, dynamic> point) => switch (pointLinkOf(point)) {
  PointLink.connected => IkoluColors.connected,
  PointLink.gap => IkoluColors.warning,
  PointLink.incident => IkoluColors.incident,
};
