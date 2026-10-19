import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/brand.dart';
import '../dashboard/point_link.dart';
import '../dashboard/widgets/capture_logger_plate.dart';
import 'capture_coordinates.dart';
import 'capture_water_mark.dart';

/// Mapa de ubicaciones de los puntos de captación, como el observatorio:
/// plano oscuro de Esri, el dibujo del logger en cada punto y los cercanos
/// (80 px) juntos. Un toque abre el grupo y acerca la cámara.
/// El punto elegido lleva un charco de agua en su coordenada.
class CaptureLocationMap extends StatefulWidget {
  const CaptureLocationMap({
    required this.points,
    this.onSelect,
    this.selectedKey,
    this.locateTick = 0,
    this.tileProvider,
    this.fitPadding,
    this.publicPoints = const [],
    this.cluster = false,
    super.key,
  });

  /// Junta los puntos cercanos (80 px). Apagado por ahora: cada punto va
  /// suelto con su logger.
  final bool cluster;

  /// Aire del encuadre inicial. De borde a borde, el inicio deja libres el
  /// título, el rail y la barra de abajo.
  final EdgeInsets? fitPadding;

  /// Capa pública del observatorio: códigos DGA de todo Chile, sin datos
  /// privados. Se dibujan tenues y debajo de los puntos del usuario.
  final List<Map<String, dynamic>> publicPoints;

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>>? onSelect;

  /// `id` del punto marcado. Al cambiar, el mapa se acerca a ese punto.
  final String? selectedKey;

  /// Sube para repetir el acercamiento y el oleaje del punto ya elegido.
  final int locateTick;

  /// Teselas de prueba. En la app se piden por red.
  final TileProvider? tileProvider;

  @override
  State<CaptureLocationMap> createState() => _CaptureLocationMapState();
}

class _CaptureLocationMapState extends State<CaptureLocationMap>
    with SingleTickerProviderStateMixin {
  final MapController _map = MapController();
  var _ready = false;

  /// La cámara viaja al punto elegido en vez de saltar.
  late final AnimationController _fly =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 420),
      )..addListener(() {
        final from = _flyFrom;
        final to = _flyTo;
        if (from == null || to == null) return;
        final t = Curves.easeInOutCubic.transform(_fly.value);
        _map.move(
          LatLng(
            from.latitude + (to.latitude - from.latitude) * t,
            from.longitude + (to.longitude - from.longitude) * t,
          ),
          _flyZoom,
        );
      });
  LatLng? _flyFrom;
  LatLng? _flyTo;
  var _flyZoom = 0.0;

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  List<({Map<String, dynamic> point, LatLng location})> get _located => [
    for (final point in widget.points)
      if (captureLatLng(point) case final location?)
        (point: point, location: location),
  ];

  @override
  void didUpdateWidget(covariant CaptureLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final chosen =
        widget.selectedKey != null &&
        widget.selectedKey != oldWidget.selectedKey;
    final again = widget.locateTick != oldWidget.locateTick;
    if (!chosen && !again) return;
    for (final item in _located) {
      if (capturePointKey(item.point) == widget.selectedKey) {
        _focus(item.location);
        break;
      }
    }
  }

  /// Los puntos propios ya van con su logger: la capa pública no los repite.
  List<CircleMarker> _publicCircles() {
    if (widget.publicPoints.isEmpty) return const [];
    final own = {for (final point in widget.points) '${point['id']}'};
    return [
      for (final point in widget.publicPoints)
        if (!own.contains('${point['id']}'))
          if (captureLatLng(point) case final location?)
            CircleMarker(
              point: location,
              radius: 3.2,
              color: _publicColor(point).withValues(alpha: 0.55),
              borderColor: const Color(0x66081216),
              borderStrokeWidth: 1,
            ),
    ];
  }

  void _focus(LatLng location) {
    if (!_ready) return;
    final camera = _map.camera;
    final zoom = camera.zoom;
    if (!zoom.isFinite || zoom < 2) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _map.move(location, zoom);
      return;
    }
    _flyFrom = camera.center;
    _flyTo = location;
    _flyZoom = zoom;
    _fly.forward(from: 0);
  }

  void _focusSelected() {
    final key = widget.selectedKey;
    if (key == null) return;
    for (final item in _located) {
      if (capturePointKey(item.point) != key) continue;
      _focus(item.location);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final located = _located;
    final missing = widget.points.length - located.length;
    final public = _publicCircles();
    if (located.isEmpty && public.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Estos puntos no tienen coordenadas GPS.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB7C8C7), height: 1.35),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final coords = [for (final item in located) item.location];
        final camera = captureCameraFor(size, coords);
        return FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: camera.center,
            initialZoom: camera.zoom,
            initialCameraFit: coords.length < 2
                ? null
                : CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(coords),
                    padding:
                        widget.fitPadding ??
                        const EdgeInsets.fromLTRB(36, 28, 36, 36),
                    maxZoom: 13,
                  ),
            minZoom: 3,
            maxZoom: 16,
            backgroundColor: const Color(0xFF0B171B),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _ready = true;
              _focusSelected();
            },
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'cl.smarthydro.smarthydro_app',
              maxNativeZoom: 16,
              tileProvider: widget.tileProvider,
              tileDisplay: const TileDisplay.instantaneous(),
            ),
            TileLayer(
              urlTemplate:
                  'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'cl.smarthydro.smarthydro_app',
              maxNativeZoom: 16,
              tileProvider: widget.tileProvider,
              tileDisplay: const TileDisplay.instantaneous(),
            ),
            if (public.isNotEmpty) CircleLayer(circles: public),
            _WaterOnPoint(
              located: located,
              selectedKey: widget.selectedKey,
              burst: widget.locateTick,
            ),
            _CaptureMarkers(
              cluster: widget.cluster,
              located: located,
              selectedKey: widget.selectedKey,
              onSelect: widget.onSelect,
            ),
            // Encima del logger: la luz que late tapa la luz fija de la
            // antena. No recibe toques.
            _ActivePulse(located: located, cluster: widget.cluster),
            if (missing > 0)
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    math.max(12, (widget.fitPadding?.left ?? 0) - 24),
                    math.max(8, (widget.fitPadding?.top ?? 0) - 20),
                    12,
                    0,
                  ),
                  child: _MissingChip(count: missing),
                ),
              ),
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Text(
                  '© Esri © OpenStreetMap',
                  style: TextStyle(color: Color(0xFF8FA3A4), fontSize: 10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

typedef _Located = ({Map<String, dynamic> point, LatLng location});

/// Mismo criterio que el observatorio: subterráneo mide nivel, superficial
/// mide caudal.
Color _publicColor(Map<String, dynamic> point) =>
    '${point['type_dga']}'.toUpperCase() == 'SUPERFICIAL'
    ? const Color(0xFF6FB7FF)
    : const Color(0xFF7EE0D0);

/// Charco sobre la coordenada del punto elegido. No tapa el toque del logger.
class _WaterOnPoint extends StatelessWidget {
  const _WaterOnPoint({
    required this.located,
    required this.selectedKey,
    required this.burst,
  });

  final List<_Located> located;
  final String? selectedKey;
  final int burst;

  @override
  Widget build(BuildContext context) {
    if (selectedKey == null) return const SizedBox.shrink();
    for (final item in located) {
      if (capturePointKey(item.point) != selectedKey) continue;
      return MarkerLayer(
        markers: [
          Marker(
            point: item.location,
            width: _waterSize,
            height: _waterSize,
            alignment: Alignment.center,
            child: CaptureWaterMark(
              key: ValueKey('capture-water-$selectedKey'),
              burst: burst,
              ground: 0.72,
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

const _waterSize = 220.0;

/// Onda que sale de la luz de la antena de cada punto conectado, para verlos
/// de un vistazo. Si el punto quedó dentro de un grupo, late la antena del
/// grupo. Es una sola capa de canvas: no hay un widget animado por punto.
class _ActivePulse extends StatefulWidget {
  const _ActivePulse({required this.located, required this.cluster});

  final List<_Located> located;
  final bool cluster;

  /// Luz de la antena respecto del centro del dibujo del logger.
  static const _tip = Offset(
    0,
    captureLoggerAntennaTipY - captureLoggerMarkSize / 2,
  );

  /// En el grupo el logger va a la izquierda del número.
  static const _clusterTip = Offset(
    captureLoggerMarkSize / 2 - _clusterWidth / 2,
    captureLoggerAntennaTipY - captureLoggerMarkSize / 2,
  );

  @override
  State<_ActivePulse> createState() => _ActivePulseState();
}

class _ActivePulseState extends State<_ActivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat
        ..stop()
        ..value = 0.35;
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final screen = [
      for (final item in widget.located)
        camera.latLngToScreenOffset(item.location),
    ];
    final separate =
        !widget.cluster ||
        camera.zoom >= captureClusterSeparateZoom ||
        !_cameraSized(camera);
    final groups = separate
        ? [
            for (var index = 0; index < screen.length; index++) [index],
          ]
        : clusterByPixel(screen);
    final spots = <Offset>[
      for (final group in groups)
        if (group.any(
          (index) =>
              pointLinkOf(widget.located[index].point) == PointLink.connected,
        ))
          group.map((index) => screen[index]).reduce((a, b) => a + b) /
                  group.length.toDouble() +
              (group.length == 1
                  ? _ActivePulse._tip
                  : _ActivePulse._clusterTip),
    ];
    if (spots.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _PulsePainter(spots: spots, beat: _beat),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.spots, required this.beat})
    : super(repaint: beat);

  final List<Offset> spots;
  final Animation<double> beat;

  static const _color = IkoluColors.connected;

  @override
  void paint(Canvas canvas, Size size) {
    // Dos ondas desfasadas: siempre hay una visible. Nacen del tamaño de la
    // luz (~2 px) y se abren poco, para no tapar el dibujo del logger.
    for (final phase in const [0.0, 0.5]) {
      final t = (beat.value + phase) % 1;
      final radius = 2.5 + 11 * Curves.easeOutCubic.transform(t);
      final alpha = (1 - t) * 0.85;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _color.withValues(alpha: alpha);
      final glow = Paint()..color = _color.withValues(alpha: alpha * 0.22);
      for (final spot in spots) {
        canvas.drawCircle(spot, radius, glow);
        canvas.drawCircle(spot, radius, ring);
      }
    }
    // La luz misma brilla al ritmo de la onda.
    final light = 0.55 + 0.45 * math.sin(beat.value * 2 * math.pi * 2).abs();
    final core = Paint()..color = _color.withValues(alpha: light);
    for (final spot in spots) {
      canvas.drawCircle(spot, 2.4, core);
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) =>
      oldDelegate.spots != spots || oldDelegate.beat != beat;
}

class _CaptureMarkers extends StatelessWidget {
  const _CaptureMarkers({
    required this.cluster,
    required this.located,
    required this.selectedKey,
    required this.onSelect,
  });

  final bool cluster;
  final List<_Located> located;
  final String? selectedKey;
  final ValueChanged<Map<String, dynamic>>? onSelect;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final separate =
        !cluster ||
        camera.zoom >= captureClusterSeparateZoom ||
        !_cameraSized(camera);
    final groups = separate
        ? [
            for (var index = 0; index < located.length; index++) [index],
          ]
        : clusterByPixel([
            for (final item in located)
              camera.latLngToScreenOffset(item.location),
          ]);
    return MarkerLayer(
      markers: [
        for (final group in groups)
          if (group.length == 1)
            _loggerMarker(
              located[group.first],
              motion: !MediaQuery.disableAnimationsOf(context),
            )
          else
            _clusterMarker(context, camera, [
              for (final index in group) located[index],
            ]),
      ],
    );
  }

  Marker _loggerMarker(_Located item, {required bool motion}) {
    final key = capturePointKey(item.point);
    final selected = selectedKey != null && key == selectedKey;
    final mark = CaptureLoggerMark(
      point: item.point,
      selected: selected,
      onTap: onSelect == null ? null : () => onSelect!(item.point),
      tapKey: ValueKey('capture-location-$key'),
    );
    return Marker(
      point: item.location,
      width: captureLoggerMarkSize,
      height: captureLoggerMarkSize,
      alignment: Alignment.center,
      // El mismo golpe corto que el nodo de la red al elegirlo.
      child: !selected || !motion
          ? mark
          : TweenAnimationBuilder<double>(
              key: ValueKey('capture-location-snap-$key'),
              tween: Tween(begin: 0.8, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: mark,
            ),
    );
  }

  Marker _clusterMarker(
    BuildContext context,
    MapCamera camera,
    List<_Located> members,
  ) {
    final ids = [for (final item in members) capturePointKey(item.point)]
      ..sort();
    return Marker(
      point: _meanLatLng([for (final item in members) item.location]),
      width: _clusterWidth,
      height: _clusterHeight,
      alignment: Alignment.center,
      child: _ClusterBubble(
        point: members.first.point,
        count: members.length,
        tapKey: ValueKey('capture-cluster-${ids.join('-')}'),
        onTap: () => _revealCluster(MapController.of(context), camera, [
          for (final item in members) item.location,
        ]),
      ),
    );
  }
}

const _clusterWidth = 46.0;
const _clusterHeight = captureLoggerMarkSize;

bool _cameraSized(MapCamera camera) {
  final size = camera.nonRotatedSize;
  return size.width.isFinite &&
      size.height.isFinite &&
      size.width >= 32 &&
      size.height >= 32;
}

LatLng _meanLatLng(List<LatLng> spots) {
  var latitude = 0.0;
  var longitude = 0.0;
  for (final spot in spots) {
    latitude += spot.latitude;
    longitude += spot.longitude;
  }
  final count = spots.length;
  return LatLng(latitude / count, longitude / count);
}

/// Acerca el grupo hasta el zoom en que cada logger queda suelto.
void _revealCluster(
  MapController controller,
  MapCamera camera,
  List<LatLng> spots,
) {
  if (spots.isEmpty) return;
  final cap = camera.maxZoom ?? captureClusterSeparateZoom;
  var minLat = spots.first.latitude;
  var maxLat = minLat;
  var minLon = spots.first.longitude;
  var maxLon = minLon;
  for (final spot in spots) {
    minLat = math.min(minLat, spot.latitude);
    maxLat = math.max(maxLat, spot.latitude);
    minLon = math.min(minLon, spot.longitude);
    maxLon = math.max(maxLon, spot.longitude);
  }
  final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
  if (maxLat - minLat < 1e-7 && maxLon - minLon < 1e-7) {
    controller.move(center, cap);
    return;
  }
  final fitted = CameraFit.bounds(
    bounds: LatLngBounds.fromPoints(spots),
    padding: const EdgeInsets.all(72),
    maxZoom: cap,
    minZoom: math.min(cap, camera.zoom + 1),
  ).fit(camera);
  var zoom = fitted.zoom.isFinite ? fitted.zoom : cap;
  if (_leafletSpanPx(spots, zoom) < 120) zoom = cap;
  final next =
      fitted.center.latitude.isFinite && fitted.center.longitude.isFinite
      ? fitted.center
      : center;
  controller.move(next, zoom.clamp(camera.minZoom ?? 3, cap).toDouble());
}

/// Ancho en píxeles del grupo a un zoom de Leaflet (mundo de 256 px).
double _leafletSpanPx(List<LatLng> spots, double zoom) {
  var minLat = spots.first.latitude;
  var maxLat = minLat;
  var minLon = spots.first.longitude;
  var maxLon = minLon;
  for (final spot in spots) {
    minLat = math.min(minLat, spot.latitude);
    maxLat = math.max(maxLat, spot.latitude);
    minLon = math.min(minLon, spot.longitude);
    maxLon = math.max(maxLon, spot.longitude);
  }
  final world = 256 * math.pow(2, zoom);
  final midLat = (minLat + maxLat) / 2;
  final dx =
      (maxLon - minLon).abs() / 360 * world * math.cos(midLat * math.pi / 180);
  final dy = (maxLat - minLat).abs() / 360 * world;
  return math.sqrt(dx * dx + dy * dy);
}

/// Grupo sin marco: el dibujo del logger y el número.
class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({
    required this.point,
    required this.count,
    required this.onTap,
    required this.tapKey,
  });

  final Map<String, dynamic> point;
  final int count;
  final VoidCallback onTap;
  final Key tapKey;

  @override
  Widget build(BuildContext context) {
    final noun = count == 1 ? 'punto' : 'puntos';
    return Semantics(
      button: true,
      label: '$count $noun de captación',
      child: GestureDetector(
        key: tapKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            SizedBox(
              width: captureLoggerMarkSize,
              height: captureLoggerMarkSize,
              child: IgnorePointer(
                child: CaptureLoggerMark(
                  point: point,
                  selected: false,
                  onTap: null,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: Color(0xFFF4FEFF),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1,
                shadows: [Shadow(color: Color(0xFF062026), blurRadius: 3)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingChip extends StatelessWidget {
  const _MissingChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final noun = count == 1
        ? 'punto sin coordenadas'
        : 'puntos sin coordenadas';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC102328),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '$count $noun',
          style: const TextStyle(color: Color(0xFFFFC46B), fontSize: 11),
        ),
      ),
    );
  }
}
