import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/brand.dart';
import '../../shared/ui/hydro_ui.dart';
import '../../shared/widgets/hydro_glass.dart';
import '../dashboard/point_link.dart';
import 'capture_coordinates.dart';
import 'capture_location_map.dart';

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
  int? _selectedId;
  var _pulse = 0;

  @override
  void initState() {
    super.initState();
    _selectedId = _firstLocatedId(widget.points);
  }

  @override
  void didUpdateWidget(covariant GeoSmartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final located = _geolocated(widget.points);
    final still = located.any((point) => _intId(point['id']) == _selectedId);
    if (still) return;
    _selectedId = located.isEmpty ? null : _intId(located.first['id']);
  }

  void _choose(int? id) {
    if (id == null) return;
    setState(() {
      _selectedId = id;
      _pulse++;
    });
  }

  void _step(int delta) {
    final located = _geolocated(widget.points);
    if (located.length < 2) return;
    var index = located.indexWhere(
      (point) => _intId(point['id']) == _selectedId,
    );
    if (index < 0) index = 0;
    final next = (index + delta) % located.length;
    final safe = next < 0 ? next + located.length : next;
    _choose(_intId(located[safe]['id']));
  }

  @override
  Widget build(BuildContext context) {
    final geolocated = _geolocated(widget.points);
    final missingGps = widget.points.length - geolocated.length;
    Map<String, dynamic>? chosen;
    for (final point in geolocated) {
      if (_intId(point['id']) == _selectedId) {
        chosen = point;
        break;
      }
    }

    final countLine = missingGps == 0
        ? '${geolocated.length} en el mapa'
        : '${geolocated.length} en el mapa · $missingGps sin GPS';
    return HydroPage(
      title: 'Ubicaciones',
      maxWidth: 1280,
      subtitle: Text(countLine, style: HydroText.subtitle),
      body: geolocated.isEmpty
          ? _NoGpsPoints(
              points: widget.points,
              onSelectPoint: widget.onSelectPoint,
            )
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CaptureLocationMap(
                          points: widget.points,
                          selectedKey: _selectedId?.toString(),
                          locateTick: _pulse,
                          onSelect: (point) => _choose(_intId(point['id'])),
                        ),
                      ),
                      if (geolocated.length > 1) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _StepButton(
                              icon: Icons.chevron_left,
                              label: 'Punto anterior',
                              onTap: () => _step(-1),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _StepButton(
                              icon: Icons.chevron_right,
                              label: 'Siguiente punto',
                              onTap: () => _step(1),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (chosen case final point?)
                  _PointSheet(
                    point: point,
                    onOpen: () => widget.onSelectPoint(point),
                    onSee: () => setState(() => _pulse++),
                  ),
              ],
            ),
    );
  }
}

class _PointSheet extends StatelessWidget {
  const _PointSheet({required this.point, required this.onOpen, this.onSee});

  final Map<String, dynamic> point;
  final VoidCallback onOpen;

  /// Muestra el agua en la coordenada. Si falta, el botón abre el punto.
  final VoidCallback? onSee;

  @override
  Widget build(BuildContext context) {
    final telemetry = _asMap(point['latest_telemetry']);
    final dga = _asMap(point['dga']);
    final type = '${point['type_dga'] ?? dga['type_dga']}'.toUpperCase();
    final surface = type == 'SUPERFICIAL';
    final flow = telemetry['flow'];
    final level = telemetry['water_table'] ?? telemetry['nivel'];
    final when = telemetry['date_time_medition'];
    final project = point['project_name']?.toString();
    final where = project == null || project.isEmpty || project == 'null'
        ? null
        : project;
    final title = point['title']?.toString().trim();
    final name = title == null || title.isEmpty || title == 'null'
        ? 'Punto'
        : title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: HydroGlass(
        frosted: true,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        radius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    foregroundColor: IkoluColors.cyan,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(onSee == null ? 'Ver el punto' : 'Entrar'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                pointLinkLabel(pointLinkOf(point)),
                surface ? 'Superficial' : 'Pozo',
                ?where,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _linkColor(point),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_reading(flow, 'L/s')} · ${_reading(level, 'm')} · ${_when(when)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB7C8C7),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            if (onSee != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: TextButton(
                  key: const ValueKey('ubicacion-ver-punto'),
                  onPressed: onSee,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF062026),
                    backgroundColor: IkoluColors.cyan,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Ver el punto',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

int? _intId(dynamic value) => value is int ? value : int.tryParse('$value');

List<Map<String, dynamic>> _geolocated(List<Map<String, dynamic>> points) => [
  for (final point in points)
    if (captureLatLng(point) != null) point,
];

int? _firstLocatedId(List<Map<String, dynamic>> points) {
  final located = _geolocated(points);
  if (located.isEmpty) return null;
  return _intId(located.first['id']);
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: const Color(0xFF102328),
          shape: const CircleBorder(side: BorderSide(color: Color(0xFF2A4E58))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 22, color: const Color(0xFFD7E6E3)),
            ),
          ),
        ),
      ),
    );
  }
}

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
          _PointSheet(point: point, onOpen: () => onSelectPoint(point)),
          const SizedBox(height: 8),
        ],
      ],
    ),
  );
}
