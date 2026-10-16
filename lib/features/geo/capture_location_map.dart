import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../dashboard/point_link.dart';
import '../dashboard/widgets/capture_logger_plate.dart';
import 'capture_coordinates.dart';
import 'capture_map_chrome.dart';
import 'capture_relief.dart';
import 'capture_water_mark.dart';

/// Mapa de ubicaciones de los puntos de captación.
///
/// En web y móvil la cámara va inclinada, con terreno y edificios en volumen.
/// El fondo es vectorial y no pide clave. CARTO raster pinta "API KEY REQUIRED".
/// En las pruebas, y en escritorio, el plano es el lienzo oscuro de Esri.
/// Ahí el punto es el dibujo del logger, sin marco. En el relieve el logger es
/// un volumen del mapa: cuerpo, antena y luz, con la misma perspectiva.
/// Los puntos cercanos (80 px) se juntan. Un toque los abre y acerca la cámara.
/// El punto elegido lleva un charco de agua en su coordenada.
class CaptureLocationMap extends StatefulWidget {
  const CaptureLocationMap({
    required this.points,
    this.onSelect,
    this.selectedKey,
    this.locateTick = 0,
    this.tileProvider,
    super.key,
  });

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

class _CaptureLocationMapState extends State<CaptureLocationMap> {
  final MapController _map = MapController();
  var _ready = false;

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

  void _focus(LatLng location) {
    if (!_ready) return;
    final zoom = _map.camera.zoom;
    if (!zoom.isFinite || zoom < 2) return;
    _map.move(location, zoom);
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
    if (located.isEmpty) {
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

    if (widget.tileProvider == null && captureReliefSupported) {
      return _ReliefMap(
        located: located,
        missing: missing,
        selectedKey: widget.selectedKey,
        locateTick: widget.locateTick,
        onSelect: widget.onSelect,
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
                    padding: const EdgeInsets.fromLTRB(36, 28, 36, 36),
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
            _WaterOnPoint(
              located: located,
              selectedKey: widget.selectedKey,
              burst: widget.locateTick,
            ),
            _CaptureMarkers(
              located: located,
              selectedKey: widget.selectedKey,
              onSelect: widget.onSelect,
            ),
            if (missing > 0)
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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

class _CaptureMarkers extends StatelessWidget {
  const _CaptureMarkers({
    required this.located,
    required this.selectedKey,
    required this.onSelect,
  });

  final List<_Located> located;
  final String? selectedKey;
  final ValueChanged<Map<String, dynamic>>? onSelect;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final separate =
        camera.zoom >= captureClusterSeparateZoom || !_cameraSized(camera);
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
            _loggerMarker(located[group.first])
          else
            _clusterMarker(context, camera, [
              for (final index in group) located[index],
            ]),
      ],
    );
  }

  Marker _loggerMarker(_Located item) {
    final key = capturePointKey(item.point);
    return Marker(
      point: item.location,
      width: captureLoggerMarkSize,
      height: captureLoggerMarkSize,
      alignment: Alignment.center,
      child: CaptureLoggerMark(
        point: item.point,
        selected: selectedKey != null && key == selectedKey,
        onTap: onSelect == null ? null : () => onSelect!(item.point),
        tapKey: ValueKey('capture-location-$key'),
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

class _ReliefMap extends StatefulWidget {
  const _ReliefMap({
    required this.located,
    required this.missing,
    required this.selectedKey,
    required this.locateTick,
    required this.onSelect,
  });

  final List<_Located> located;
  final int missing;
  final String? selectedKey;
  final int locateTick;
  final ValueChanged<Map<String, dynamic>>? onSelect;

  @override
  State<_ReliefMap> createState() => _ReliefMapState();
}

class _ReliefMapState extends State<_ReliefMap>
    with SingleTickerProviderStateMixin {
  final _camera = ValueNotifier<ml.CameraPosition?>(null);
  final _pixels = ValueNotifier<List<Offset>?>(null);
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..addListener(_pushRings);
  ml.MapLibreMapController? _controller;
  ml.CameraPosition? _queued;
  Size _size = Size.zero;
  var _ringsReady = false;
  var _installing = false;
  var _waterBusy = false;
  var _pixelBusy = false;
  var _pixelDirty = false;
  var _pixelGen = 0;
  var _reduce = false;
  var _loggersReady = false;
  var _loggerBusy = false;
  var _loggerDirty = false;
  var _loggerSig = '';
  DateTime _lastRing = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _loggerStamp = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _loggerTimer;

  /// Ids ordenados del grupo que el usuario pidió abrir.
  String? _opened;

  /// Cuántos movimientos de cámara llegaron desde el mapa.
  var _moves = 0;

  /// Vuelo en curso. Sirve para ignorar el respaldo de uno anterior.
  var _flight = 0;

  /// El punto ya elegido al abrir se acerca una sola vez.
  var _didFocusInitial = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce == _reduce) return;
    _reduce = reduce;
    _syncWave();
  }

  @override
  void dispose() {
    _flight = -1;
    _pixelGen++;
    _ringsReady = false;
    _loggersReady = false;
    _loggerTimer?.cancel();
    _wave.dispose();
    _pixels.dispose();
    _camera.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ReliefMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = widget.selectedKey != oldWidget.selectedKey;
    final again = widget.locateTick != oldWidget.locateTick;
    if (changed || again) {
      if (widget.selectedKey != null) {
        for (final item in widget.located) {
          if (capturePointKey(item.point) == widget.selectedKey) {
            _glide(item.location);
            break;
          }
        }
      }
      _syncSource();
      _syncWave();
    }
    _flushLoggers();
  }

  /// Lleva la cámara al punto sin cambiar el zoom.
  void _glide(LatLng location) {
    final current = _camera.value ?? _viewCamera();
    _play(
      ml.CameraPosition(
        target: ml.LatLng(location.latitude, location.longitude),
        zoom: current?.zoom ?? 8,
        tilt: current?.tilt ?? captureReliefPitch,
        bearing: current?.bearing ?? captureReliefBearing,
      ),
      duration: const Duration(milliseconds: 900),
    );
  }

  void _go(LatLng location, {required double zoom}) {
    final current = _camera.value;
    _play(
      ml.CameraPosition(
        target: ml.LatLng(location.latitude, location.longitude),
        zoom: current == null ? zoom : math.max(current.zoom, zoom),
        tilt: current?.tilt ?? captureReliefPitch,
        bearing: current?.bearing ?? captureReliefBearing,
      ),
    );
  }

  void _play(
    ml.CameraPosition next, {
    Duration duration = const Duration(milliseconds: 700),
  }) {
    _queued = next;
    final controller = _controller;
    if (controller == null) {
      _camera.value = next;
      return;
    }
    final flight = ++_flight;
    final stamp = _moves;
    controller.easeCamera(
      ml.CameraUpdate.newCameraPosition(next),
      duration: duration,
    );
    // Si el mapa no avisa el movimiento, el agua igual queda en el punto.
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || flight != _flight || _moves != stamp) return;
      _camera.value = next;
    });
  }

  void _turn(double delta, {bool animate = true}) {
    final current = _camera.value ?? _viewCamera();
    if (current == null) return;
    _aim(
      ml.CameraPosition(
        target: current.target,
        zoom: current.zoom,
        tilt: current.tilt,
        bearing: current.bearing + delta,
      ),
      animate: animate,
    );
  }

  void _resetAngle() {
    final current = _camera.value ?? _viewCamera();
    if (current == null) return;
    _aim(
      ml.CameraPosition(
        target: current.target,
        zoom: current.zoom,
        tilt: captureReliefPitch,
        bearing: captureReliefBearing,
      ),
    );
  }

  void _aim(ml.CameraPosition next, {bool animate = true}) {
    _camera.value = next;
    final controller = _controller;
    if (controller == null) return;
    final update = ml.CameraUpdate.newCameraPosition(next);
    if (animate) {
      controller.easeCamera(
        update,
        duration: const Duration(milliseconds: 240),
      );
      return;
    }
    controller.moveCamera(update);
  }

  void _focusInitial() {
    if (_didFocusInitial || widget.selectedKey == null) return;
    for (final item in widget.located) {
      if (capturePointKey(item.point) != widget.selectedKey) continue;
      _didFocusInitial = true;
      _glide(item.location);
      return;
    }
  }

  void _openCluster(List<int> group) {
    setState(() => _opened = _ids(group));
    _reveal([for (final index in group) widget.located[index].location]);
    _flushLoggers();
  }

  void _reveal(List<LatLng> spots) {
    if (spots.isEmpty || _size.width < 32) return;
    final framed = captureCameraFor(_size, spots);
    final current = _camera.value?.zoom ?? framed.zoom - 1;
    final zoom = captureRevealZoom(
      spots: [
        for (final spot in spots)
          (latitude: spot.latitude, longitude: spot.longitude),
      ],
      size: _size,
      currentZoom: current,
    );
    _go(_meanLatLng(spots), zoom: zoom);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _size = size;
        final coords = [for (final item in widget.located) item.location];
        final framed = captureCameraFor(size, coords);
        final initial = ml.CameraPosition(
          target: ml.LatLng(framed.center.latitude, framed.center.longitude),
          zoom: (framed.zoom - 1).clamp(2, 14).toDouble(),
          tilt: captureReliefPitch,
          bearing: captureReliefBearing,
        );
        return Stack(
          children: [
            _ReliefSurface(
              initial: initial,
              onCreated: (controller) {
                toneCaptureMapChrome();
                _controller = controller;
                final queued = _queued;
                if (queued == null) return;
                controller.animateCamera(
                  ml.CameraUpdate.newCameraPosition(queued),
                  duration: const Duration(milliseconds: 700),
                );
              },
              onStyle: () {
                _installLayers();
                _focusInitial();
              },
              onClick: _onMapClick,
              onIdle: () {
                final position = _controller?.cameraPosition;
                if (position != null) {
                  _moves++;
                  _camera.value = position;
                }
                _readPixels();
                if (!_ringsReady) _installLayers();
                _flushLoggers();
              },
              onMove: (position) {
                _moves++;
                _camera.value = position;
                _readPixels();
                _pokeLoggers();
              },
            ),
            ValueListenableBuilder<ml.CameraPosition?>(
              valueListenable: _camera,
              builder: (context, camera, _) {
                return ValueListenableBuilder<List<Offset>?>(
                  valueListenable: _pixels,
                  builder: (context, pixels, _) =>
                      Stack(children: _marks(size, camera ?? initial, pixels)),
                );
              },
            ),
            if (widget.missing > 0)
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _MissingChip(count: widget.missing),
                ),
              ),
            ValueListenableBuilder<ml.CameraPosition?>(
              valueListenable: _camera,
              builder: (context, camera, _) {
                return Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: _OrbitControl(
                      bearing: camera?.bearing ?? captureReliefBearing,
                      onTurn: _turn,
                      onReset: _resetAngle,
                    ),
                  ),
                );
              },
            ),
            const Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Text(
                  '© OpenStreetMap © OpenMapTiles',
                  style: TextStyle(color: Color(0xFF8FA3A4), fontSize: 10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _marks(
    Size size,
    ml.CameraPosition camera,
    List<Offset>? screen,
  ) {
    if (_ringsReady) return const [];
    final offsets = _offsets(size, camera, screen);
    return [?_water(size, camera, offsets)];
  }

  List<Offset> _offsets(
    Size size,
    ml.CameraPosition camera,
    List<Offset>? screen,
  ) {
    final projected = [
      for (final item in widget.located)
        captureReliefOffset(
          latitude: item.location.latitude,
          longitude: item.location.longitude,
          centerLat: camera.target.latitude,
          centerLng: camera.target.longitude,
          zoom: camera.zoom,
          pitchDeg: camera.tilt,
          bearingDeg: camera.bearing,
          size: size,
        ),
    ];
    return _preferScreen(screen, projected, size);
  }

  List<Offset> _preferScreen(
    List<Offset>? screen,
    List<Offset> projected,
    Size size,
  ) {
    if (screen == null || screen.length != projected.length) return projected;
    var inside = 0;
    for (final offset in screen) {
      if (!_onScreen(offset, size, margin: 80)) continue;
      inside++;
    }
    if (inside == 0) return projected;
    return [
      for (final offset in screen)
        offset.dx.isFinite && offset.dy.isFinite
            ? offset
            : const Offset(double.infinity, double.infinity),
    ];
  }

  bool _groupVisible(List<int> group, List<Offset> offsets, Size size) {
    for (final index in group) {
      if (_onScreen(offsets[index], size, margin: 24)) return true;
    }
    return false;
  }

  bool _onScreen(Offset offset, Size size, {required double margin}) {
    return offset.dx.isFinite &&
        offset.dy.isFinite &&
        offset.dx >= -margin &&
        offset.dy >= -margin &&
        offset.dx <= size.width + margin &&
        offset.dy <= size.height + margin;
  }

  void _syncWave() {
    if (_reduce || widget.selectedKey == null) {
      _wave
        ..stop()
        ..value = 0;
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
    _pushRings();
  }

  Map<String, dynamic> _pointsGeoJson() {
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final item in widget.located)
          {
            'type': 'Feature',
            'properties': {
              'sel': capturePointKey(item.point) == widget.selectedKey ? 1 : 0,
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [item.location.longitude, item.location.latitude],
            },
          },
      ],
    };
  }

  Future<void> _installLayers() async {
    final controller = _controller;
    if (controller == null || _ringsReady || _installing || !mounted) return;
    _installing = true;
    try {
      final layout = _loggerCollections();
      await controller.addGeoJsonSource('capture-points', _pointsGeoJson());
      await controller.addGeoJsonSource('capture-loggers', layout.volumes);
      await controller.addFillExtrusionLayer(
        'capture-loggers',
        'capture-logger',
        const ml.FillExtrusionLayerProperties(
          fillExtrusionColor: ['get', 'color'],
          fillExtrusionHeight: ['get', 'h'],
          fillExtrusionBase: ['get', 'b'],
          fillExtrusionOpacity: 1,
          fillExtrusionVerticalGradient: true,
        ),
        belowLayerId: 'place',
        enableInteraction: false,
      );
      for (var index = 0; index < 3; index++) {
        await controller.addCircleLayer(
          'capture-points',
          'capture-water-$index',
          _ringProperties(index, 0.35),
          belowLayerId: 'place',
          enableInteraction: false,
          filter: const [
            '==',
            ['get', 'sel'],
            1,
          ],
        );
      }
      await controller.addGeoJsonSource('capture-counts', layout.counts);
      await controller.addSymbolLayer(
        'capture-counts',
        'capture-count',
        const ml.SymbolLayerProperties(
          textField: ['get', 'n'],
          textFont: ['Noto Sans Regular'],
          textSize: 14,
          textColor: '#F4FEFF',
          textHaloColor: '#062026',
          textHaloWidth: 1.4,
          textAllowOverlap: true,
          textIgnorePlacement: true,
          textAnchor: 'bottom',
          textOffset: [0.85, -0.15],
        ),
        belowLayerId: 'place',
        enableInteraction: false,
      );
      if (!mounted) return;
      _ringsReady = true;
      _loggersReady = true;
      _loggerSig = '';
      _syncWave();
      _flushLoggers();
      if (mounted) setState(() {});
    } catch (_) {
      _ringsReady = false;
      _loggersReady = false;
    } finally {
      _installing = false;
    }
  }

  Future<void> _syncSource() async {
    final controller = _controller;
    if (controller == null || !_ringsReady || !mounted) return;
    try {
      await controller.setGeoJsonSource('capture-points', _pointsGeoJson());
    } catch (_) {}
  }

  void _pushRings() {
    final controller = _controller;
    if (!_ringsReady || _waterBusy || controller == null || !mounted) return;
    final now = DateTime.now();
    if (_wave.isAnimating && now.difference(_lastRing).inMilliseconds < 48) {
      return;
    }
    _lastRing = now;
    _waterBusy = true;
    final phase = _reduce || !_wave.isAnimating ? 0.35 : _wave.value;
    final pending = <Future<void>>[
      for (var index = 0; index < 3; index++)
        controller.setLayerProperties(
          'capture-water-$index',
          _ringProperties(index, phase),
        ),
    ];
    Future.wait(pending).catchError((Object _) => <void>[]).whenComplete(() {
      _waterBusy = false;
    });
  }

  ml.CircleLayerProperties _ringProperties(int index, double phase) {
    final travel = (phase + index / 3) % 1;
    final alpha = (1 - travel) * 0.34;
    return ml.CircleLayerProperties(
      circleRadius: 14 + travel * 70,
      circleColor: '#7FEFFF',
      circleOpacity: alpha,
      circleStrokeWidth: 2.5,
      circleStrokeColor: '#F4FEFF',
      circleStrokeOpacity: alpha,
      circleBlur: 0.12,
      circlePitchAlignment: 'map',
      circlePitchScale: 'map',
    );
  }

  Future<void> _readPixels() async {
    if (_pixelBusy) {
      _pixelDirty = true;
      return;
    }
    _pixelBusy = true;
    try {
      do {
        _pixelDirty = false;
        await _readPixelsOnce();
      } while (_pixelDirty && mounted);
    } finally {
      _pixelBusy = false;
    }
  }

  Future<void> _readPixelsOnce() async {
    final controller = _controller;
    final camera = _camera.value;
    final size = _size;
    if (controller == null || camera == null || size.width < 32 || !mounted) {
      return;
    }
    final gen = ++_pixelGen;
    final located = [
      for (final item in widget.located)
        ml.LatLng(item.location.latitude, item.location.longitude),
    ];
    if (located.isEmpty) return;
    try {
      final batch = await controller.toScreenLocationBatch([
        ml.LatLng(camera.target.latitude, camera.target.longitude),
        ...located,
      ]);
      if (!mounted || gen != _pixelGen || batch.length != located.length + 1) {
        return;
      }
      final scale = captureScreenScale(
        reportedCenter: Offset(
          batch.first.x.toDouble(),
          batch.first.y.toDouble(),
        ),
        size: size,
      );
      _pixels.value = [
        for (final point in batch.skip(1))
          Offset(point.x.toDouble() / scale, point.y.toDouble() / scale),
      ];
    } catch (_) {}
  }

  Widget? _water(Size size, ml.CameraPosition camera, List<Offset> offsets) {
    final key = widget.selectedKey;
    if (key == null) return null;
    for (var index = 0; index < widget.located.length; index++) {
      final item = widget.located[index];
      if (capturePointKey(item.point) != key) continue;
      final atTarget = _sameSpot(item.location, camera.target);
      final offset = atTarget
          ? Offset(size.width / 2, size.height / 2)
          : offsets[index];
      return _placed(
        offset,
        _waterSize,
        _waterSize,
        CaptureWaterMark(
          key: ValueKey('capture-water-$key'),
          burst: widget.locateTick,
          ground: 1,
        ),
        pitch: camera.tilt,
        bearing: camera.bearing,
      );
    }
    return null;
  }

  String _ids(List<int> group) {
    final ids = [
      for (final index in group) capturePointKey(widget.located[index].point),
    ]..sort();
    return ids.join('-');
  }

  Widget _placed(
    Offset offset,
    double width,
    double height,
    Widget child, {
    double pitch = 0,
    double bearing = 0,
  }) {
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: offset.dx - width / 2,
      top: offset.dy - height / 2,
      width: width,
      height: height,
      child: _OnGround(pitchDeg: pitch, bearingDeg: bearing, child: child),
    );
  }

  void _pokeLoggers() {
    if (!mounted || !_loggersReady) return;
    final elapsed = DateTime.now().difference(_loggerStamp);
    if (elapsed.inMilliseconds >= 120) {
      _loggerStamp = DateTime.now();
      _syncLoggers();
      return;
    }
    _loggerTimer ??= Timer(
      Duration(milliseconds: 120 - elapsed.inMilliseconds),
      () {
        _loggerTimer = null;
        _loggerStamp = DateTime.now();
        if (mounted) _syncLoggers();
      },
    );
  }

  void _flushLoggers() {
    _loggerTimer?.cancel();
    _loggerTimer = null;
    _loggerStamp = DateTime.now();
    _syncLoggers();
  }

  Future<void> _syncLoggers() async {
    if (_loggerBusy) {
      _loggerDirty = true;
      return;
    }
    _loggerBusy = true;
    try {
      do {
        _loggerDirty = false;
        await _syncLoggersOnce();
      } while (_loggerDirty && mounted);
    } finally {
      _loggerBusy = false;
    }
  }

  Future<void> _syncLoggersOnce() async {
    final controller = _controller;
    if (controller == null || !_loggersReady || !mounted) return;
    final signature = _loggerSignature();
    if (signature == _loggerSig) return;
    final layout = _loggerCollections();
    try {
      await controller.setGeoJsonSource('capture-loggers', layout.volumes);
      await controller.setGeoJsonSource('capture-counts', layout.counts);
      if (!mounted) return;
      _loggerSig = signature;
    } catch (_) {
      _loggerSig = '';
    }
  }

  String _loggerSignature() {
    final camera = _viewCamera();
    final zoom = camera?.zoom ?? -1;
    final names = [
      for (final spot in _spots(camera))
        '${spot.cluster ? 'c:${spot.members}' : 'p:${spot.key}'}:${_active(spot.point) ? 1 : 0}',
    ];
    return '${zoom.toStringAsFixed(2)}|${widget.selectedKey}|$_opened|${names.join(',')}';
  }

  ({Map<String, dynamic> volumes, Map<String, dynamic> counts})
  _loggerCollections() {
    final camera = _viewCamera();
    final zoom = camera?.zoom ?? 8;
    final volumes = <Map<String, dynamic>>[];
    final counts = <Map<String, dynamic>>[];
    var id = 1;
    for (final spot in _spots(camera)) {
      final parts = captureLoggerVolume(
        latitude: spot.latitude,
        longitude: spot.longitude,
        zoom: zoom,
        accent: _accent(spot.point),
        selected: !spot.cluster && spot.key == widget.selectedKey,
        surface: _surface(spot.point),
        active: _active(spot.point),
        pointKey: spot.key,
        cluster: spot.cluster,
        members: spot.members,
      );
      for (final part in parts) {
        part['id'] = id++;
        volumes.add(part);
      }
      if (!spot.cluster) continue;
      counts.add({
        'type': 'Feature',
        'properties': {
          'n': '${spot.group.length}',
          'cluster': 1,
          'members': spot.members,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [spot.longitude, spot.latitude],
        },
      });
    }
    return (
      volumes: {'type': 'FeatureCollection', 'features': volumes},
      counts: {'type': 'FeatureCollection', 'features': counts},
    );
  }

  ml.CameraPosition? _viewCamera() {
    final live = _camera.value;
    if (live != null) return live;
    final size = _size;
    if (size.width < 32 || widget.located.isEmpty) return null;
    final framed = captureCameraFor(size, [
      for (final item in widget.located) item.location,
    ]);
    return ml.CameraPosition(
      target: ml.LatLng(framed.center.latitude, framed.center.longitude),
      zoom: (framed.zoom - 1).clamp(2, 14).toDouble(),
      tilt: captureReliefPitch,
      bearing: captureReliefBearing,
    );
  }

  List<_VolumeSpot> _spots(ml.CameraPosition? camera) {
    if (camera == null || _size.width < 32) {
      return [
        for (final item in widget.located)
          _VolumeSpot.single(item.point, item.location),
      ];
    }
    final offsets = _offsets(_size, camera, _pixels.value);
    final separate = camera.zoom >= captureReliefSeparateZoom;
    final groups = separate
        ? [
            for (var index = 0; index < widget.located.length; index++) [index],
          ]
        : clusterByPixel(offsets);
    final spots = <_VolumeSpot>[];
    for (final group in groups) {
      final opened = group.length > 1 && _opened == _ids(group);
      final collapsed =
          group.length > 1 &&
          (!opened || !_groupVisible(group, offsets, _size));
      if (collapsed) {
        final at = _meanLatLng([
          for (final index in group) widget.located[index].location,
        ]);
        spots.add(
          _VolumeSpot(
            latitude: at.latitude,
            longitude: at.longitude,
            point: _lead(group),
            cluster: true,
            members: _ids(group),
            group: group,
          ),
        );
        continue;
      }
      for (final index in group) {
        final item = widget.located[index];
        spots.add(_VolumeSpot.single(item.point, item.location));
      }
    }
    return spots;
  }

  Map<String, dynamic> _lead(List<int> group) {
    var best = widget.located[group.first].point;
    var rank = _linkRank(best);
    for (final index in group.skip(1)) {
      final point = widget.located[index].point;
      final next = _linkRank(point);
      if (next <= rank) continue;
      best = point;
      rank = next;
    }
    return best;
  }

  Future<void> _onMapClick(math.Point<double> point, ml.LatLng _) async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    List<dynamic> found;
    try {
      found = await controller.queryRenderedFeaturesInRect(
        Rect.fromCenter(
          center: Offset(point.x.toDouble(), point.y.toDouble()),
          width: 36,
          height: 48,
        ),
        const ['capture-logger', 'capture-count'],
        null,
      );
    } catch (_) {
      return;
    }
    if (!mounted || found.isEmpty) return;
    final props = _featureProps(found.first);
    if (props == null) return;
    if (_isCluster(props['cluster'])) {
      final members = props['members']?.toString() ?? '';
      final group = _groupFromMembers(members);
      if (group.length > 1) _openCluster(group);
      return;
    }
    final key = props['key']?.toString();
    if (key == null || widget.onSelect == null) return;
    for (final item in widget.located) {
      if (capturePointKey(item.point) != key) continue;
      widget.onSelect!(item.point);
      return;
    }
  }

  List<int> _groupFromMembers(String members) {
    final camera = _viewCamera();
    for (final spot in _spots(camera)) {
      if (spot.cluster && spot.members == members) return spot.group;
    }
    return const [];
  }
}

class _VolumeSpot {
  const _VolumeSpot({
    required this.latitude,
    required this.longitude,
    required this.point,
    required this.cluster,
    required this.members,
    required this.group,
  });

  factory _VolumeSpot.single(Map<String, dynamic> point, LatLng location) {
    return _VolumeSpot(
      latitude: location.latitude,
      longitude: location.longitude,
      point: point,
      cluster: false,
      members: '',
      group: const [],
    );
  }

  final double latitude;
  final double longitude;
  final Map<String, dynamic> point;
  final bool cluster;
  final String members;
  final List<int> group;

  String get key => cluster ? members : capturePointKey(point);
}

/// Acuesta el charco de respaldo. El logger del relieve no pasa por acá:
/// es un volumen del mapa.
class _OnGround extends StatelessWidget {
  const _OnGround({
    required this.pitchDeg,
    required this.bearingDeg,
    required this.child,
  });

  final double pitchDeg;
  final double bearingDeg;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pitch = pitchDeg * math.pi / 180;
    final bearing = -bearingDeg * math.pi / 180;
    if (pitch.abs() < 0.02 && bearing.abs() < 0.02) return child;
    return Transform(
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateX(pitch)
        ..rotateZ(bearing),
      child: child,
    );
  }
}

class _ReliefSurface extends StatelessWidget {
  const _ReliefSurface({
    required this.initial,
    required this.onCreated,
    required this.onStyle,
    required this.onIdle,
    required this.onMove,
    required this.onClick,
  });

  final ml.CameraPosition initial;
  final ValueChanged<ml.MapLibreMapController> onCreated;
  final VoidCallback onStyle;
  final VoidCallback onIdle;
  final ValueChanged<ml.CameraPosition> onMove;
  final void Function(math.Point<double> point, ml.LatLng coordinates) onClick;

  @override
  Widget build(BuildContext context) {
    return ml.MapLibreMap(
      styleString: captureReliefStyle,
      initialCameraPosition: initial,
      trackCameraPosition: true,
      compassEnabled: false,
      logoEnabled: false,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      minMaxZoomPreference: const ml.MinMaxZoomPreference(2, 17),
      foregroundLoadColor: const Color(0xFF0B171B),
      attributionButtonPosition: ml.AttributionButtonPosition.bottomRight,
      onMapCreated: onCreated,
      onStyleLoadedCallback: onStyle,
      onCameraIdle: onIdle,
      onCameraMove: onMove,
      onMapClick: onClick,
    );
  }
}

bool _sameSpot(LatLng location, ml.LatLng target) {
  return (location.latitude - target.latitude).abs() < 1e-6 &&
      (location.longitude - target.longitude).abs() < 1e-6;
}

bool _active(Map<String, dynamic> point) =>
    pointLinkOf(point) == PointLink.connected;

String _accent(Map<String, dynamic> point) => switch (pointLinkOf(point)) {
  PointLink.connected => '#66E0C2',
  PointLink.gap => '#FFC46B',
  PointLink.incident => '#FF847A',
};

int _linkRank(Map<String, dynamic> point) => switch (pointLinkOf(point)) {
  PointLink.connected => 0,
  PointLink.gap => 1,
  PointLink.incident => 2,
};

bool _surface(Map<String, dynamic> point) {
  final dga = point['dga'];
  if (dga is Map && '${dga['type_dga']}'.toUpperCase() == 'SUPERFICIAL') {
    return true;
  }
  return '${point['type_dga']}'.toUpperCase() == 'SUPERFICIAL';
}

bool _isCluster(Object? value) => value == 1 || value == 1.0 || value == '1';

Map<String, dynamic>? _featureProps(Object? feature) {
  if (feature is! Map) return null;
  final props = feature['properties'];
  if (props is Map<String, dynamic>) return props;
  if (props is Map) {
    return props.map((key, value) => MapEntry('$key', value));
  }
  return null;
}

/// Gira el mapa 3D. El centro vuelve a la inclinación de inicio.
class _OrbitControl extends StatelessWidget {
  const _OrbitControl({
    required this.bearing,
    required this.onTurn,
    required this.onReset,
  });

  final double bearing;
  final void Function(double delta, {bool animate}) onTurn;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF102328),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2A4E58)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _turnButton(
              icon: Icons.rotate_left,
              label: 'Girar a la izquierda',
              onTap: () => onTurn(-22),
            ),
            Semantics(
              button: true,
              label: 'Girar el mapa. Toca para volver a la vista.',
              child: GestureDetector(
                onHorizontalDragUpdate: (details) =>
                    onTurn(details.delta.dx * 0.45, animate: false),
                onTap: onReset,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Transform.rotate(
                    angle: -bearing * math.pi / 180,
                    child: const CustomPaint(painter: _NeedlePainter()),
                  ),
                ),
              ),
            ),
            _turnButton(
              icon: Icons.rotate_right,
              label: 'Girar a la derecha',
              onTap: () => onTurn(22),
            ),
          ],
        ),
      ),
    );
  }

  Widget _turnButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: const Color(0xFFD7E6E3)),
        ),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  const _NeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final needle = Path()
      ..moveTo(center.dx, center.dy - 11)
      ..lineTo(center.dx - 4.2, center.dy + 7)
      ..lineTo(center.dx + 4.2, center.dy + 7)
      ..close();
    canvas.drawPath(needle, Paint()..color = const Color(0xFF7DFFE0));
    canvas.drawCircle(center, 2.2, Paint()..color = const Color(0xFFF4FEFF));
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter oldDelegate) => false;
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
