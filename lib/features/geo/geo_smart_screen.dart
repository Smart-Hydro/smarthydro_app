import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/widgets/hydro_glass.dart';
import '../dashboard/point_link.dart';

class GeoSmartScreen extends StatefulWidget {
  const GeoSmartScreen({
    required this.points,
    required this.onSelectPoint,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onSelectPoint;

  @override
  State<GeoSmartScreen> createState() => _GeoSmartScreenState();
}

class _GeoSmartScreenState extends State<GeoSmartScreen> {
  final MapController _map = MapController();
  bool _ready = false;
  int? _selectedId;

  void _focus(LatLng location, {double zoom = 13}) {
    if (!_ready) return;
    _map.move(location, zoom);
  }

  void _frame(List<_LocatedPoint> points) {
    if (!_ready || points.isEmpty) return;
    if (points.length == 1) {
      _map.move(points.first.location, 13);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          for (final point in points) point.location,
        ]),
        padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final geolocated = widget.points
        .map((point) {
          final lat = _coordinate(point['lat']);
          final lon = _coordinate(point['lon']);
          if (lat == null || lon == null || lat == 0 || lon == 0) return null;
          return _LocatedPoint(point: point, location: LatLng(lat, lon));
        })
        .whereType<_LocatedPoint>()
        .toList(growable: false);
    final center = geolocated.isEmpty
        ? const LatLng(-33.4489, -70.6693)
        : LatLng(
            geolocated
                    .map((item) => item.location.latitude)
                    .reduce((a, b) => a + b) /
                geolocated.length,
            geolocated
                    .map((item) => item.location.longitude)
                    .reduce((a, b) => a + b) /
                geolocated.length,
          );

    final missingGps = widget.points.length - geolocated.length;
    _LocatedPoint? selected;
    for (final item in geolocated) {
      if (_intId(item.point['id']) == _selectedId) {
        selected = item;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('GEO Smart'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                missingGps == 0
                    ? '${geolocated.length} en el mapa'
                    : '${geolocated.length} en el mapa · $missingGps sin GPS',
              ),
            ),
          ),
        ],
      ),
      body: geolocated.isEmpty
          ? _NoGpsPoints(
              points: widget.points,
              onSelectPoint: widget.onSelectPoint,
            )
          : Column(
              children: [
                Expanded(
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: geolocated.length == 1 ? 12 : 5.2,
                      minZoom: 3,
                      maxZoom: 18,
                      onMapReady: () {
                        _ready = true;
                        _frame(geolocated);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                        userAgentPackageName: 'cl.smarthydro.smarthydro_app',
                        maxNativeZoom: 19,
                      ),
                      MarkerLayer(
                        markers: [
                          for (final item in geolocated)
                            Marker(
                              point: item.location,
                              width: 54,
                              height: 64,
                              child: Tooltip(
                                message:
                                    item.point['title']?.toString() ?? 'Punto',
                                child: GestureDetector(
                                  onTap: () {
                                    setState(
                                      () => _selectedId = _intId(item.point['id']),
                                    );
                                    _focus(item.location);
                                  },
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF102328),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _linkColor(item.point),
                                            width: 2.5,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x44000000),
                                              blurRadius: 9,
                                              offset: Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.water_drop_rounded,
                                          color: _linkColor(item.point),
                                          size: 19,
                                        ),
                                      ),
                                      Container(
                                        width: 2,
                                        height: 9,
                                        color: const Color(0xFF66E0C2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            '© OpenStreetMap © CARTO',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (selected != null)
                  _MapInfo(
                    point: selected.point,
                    onOpen: () => widget.onSelectPoint(selected!.point),
                  ),
                SizedBox(
                  height: 86,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: geolocated.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final item = geolocated[index];
                      final id = _intId(item.point['id']);
                      return SizedBox(
                        width: 220,
                        child: _MapPointCard(
                          point: item.point,
                          selected: id != null && id == _selectedId,
                          onOpen: () => widget.onSelectPoint(item.point),
                          onFocus: () {
                            setState(() => _selectedId = id);
                            _focus(item.location);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _LocatedPoint {
  const _LocatedPoint({required this.point, required this.location});

  final Map<String, dynamic> point;
  final LatLng location;
}

class _MapPointCard extends StatelessWidget {
  const _MapPointCard({
    required this.point,
    required this.onOpen,
    this.onFocus,
    this.selected = false,
  });

  final Map<String, dynamic> point;
  final VoidCallback onOpen;
  final VoidCallback? onFocus;
  final bool selected;

  @override
  Widget build(BuildContext context) => HydroGlass(
    onTap: onFocus ?? onOpen,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    radius: 16,
    child: Row(
      children: [
        Icon(Icons.water_drop_outlined, color: _linkColor(point)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            point['title']?.toString() ?? 'Punto',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        if (onFocus != null)
          IconButton(
            tooltip: 'Ver captura',
            onPressed: onOpen,
            icon: const Icon(
              Icons.north_east_rounded,
              color: Color(0xFF91A8AA),
              size: 18,
            ),
          ),
      ],
    ),
  );
}

class _MapInfo extends StatelessWidget {
  const _MapInfo({required this.point, required this.onOpen});

  final Map<String, dynamic> point;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final telemetry = _asMap(point['latest_telemetry']);
    final dga = _asMap(point['dga']);
    final surface = '${dga['type_dga']}'.toUpperCase() == 'SUPERFICIAL';
    final flow = telemetry['flow'];
    final level = telemetry['water_table'] ?? telemetry['nivel'];
    final when = telemetry['date_time_medition'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: HydroGlass(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_drop_rounded, color: _linkColor(point), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    point['title']?.toString() ?? 'Punto',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  surface ? 'Agua superficial' : 'Pozo',
                  style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${pointLinkLabel(pointLinkOf(point))} · ${point['project_name'] ?? 'Proyecto'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFB7C8C7), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Caudal ${_reading(flow, 'L/s')} · nivel ${_reading(level, 'm')}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Última medición ${_when(when)}',
              style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onOpen,
                child: const Text('Ver captura'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int? _intId(dynamic value) => value is int ? value : int.tryParse('$value');

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  return const {};
}

String _reading(dynamic value, String unit) {
  if (value == null || '$value'.isEmpty || value == 'null') return 'sin dato';
  return '$value $unit';
}

String _when(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (parsed == null) return 'sin lectura';
  final day = parsed.day.toString().padLeft(2, '0');
  final month = parsed.month.toString().padLeft(2, '0');
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

Color _linkColor(Map<String, dynamic> point) => switch (pointLinkOf(point)) {
  PointLink.connected => const Color(0xFF66E0C2),
  PointLink.gap => const Color(0xFFFFC46B),
  PointLink.incident => const Color(0xFFFF847A),
};

class _NoGpsPoints extends StatelessWidget {
  const _NoGpsPoints({required this.points, required this.onSelectPoint});

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onSelectPoint;

  @override
  Widget build(BuildContext context) => HydroFrame(
    child: ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Icon(
        Icons.location_off_outlined,
        color: Color(0xFFFFC46B),
        size: 36,
      ),
      const SizedBox(height: 12),
      const Text(
        'Tus puntos no tienen coordenadas GPS disponibles.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      for (final point in points) ...[
        _MapPointCard(point: point, onOpen: () => onSelectPoint(point)),
        const SizedBox(height: 8),
      ],
    ],
    ),
  );
}

double? _coordinate(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
  return null;
}
