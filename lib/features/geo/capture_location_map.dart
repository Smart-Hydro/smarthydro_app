import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
    this.onSelectedSpot,
    this.network = false,
    this.mesh = false,
    this.readoutOf,
    this.readoutArea,
    this.keepClearOf,
    this.readoutBlocks = const [],
    this.loggers = true,
    this.markExtent = captureLoggerMarkSize,
    super.key,
  });

  /// Lo que flota encima del mapa, como el panel de capas. Las tarjetas no
  /// se meten ahí.
  final List<Rect> readoutBlocks;

  /// Apagada, no se dibuja ningún enlace entre equipos.
  final bool network;

  /// Red de cobertura: cada punto se une con todos. Si no, solo con los
  /// vecinos más cercanos.
  final bool mesh;

  /// Tarjeta que flota junto a cada punto. Nula o sin variables, no hay.
  final CaptureReadoutCard? Function(Map<String, dynamic> point)? readoutOf;

  /// Dónde pueden ir las tarjetas, en coordenadas del mapa. Nulo, todo él.
  final Rect? readoutArea;

  /// Lo que ocupa la ficha del punto elegido, según dónde quedó el punto.
  /// Las tarjetas no se meten ahí.
  final Rect? Function(Offset spot)? keepClearOf;

  /// Dónde queda en pantalla el punto marcado, con cada movimiento de la
  /// cámara. Nulo sin punto marcado o sin coordenadas.
  final ValueChanged<Offset?>? onSelectedSpot;

  /// Dibujo del logger. Apagado, cada punto es un punto parpadeante.
  final bool loggers;

  /// Lado de la marca, en px. Solo chico o grande, a medida real.
  final double markExtent;

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
    if (widget.selectedKey != oldWidget.selectedKey ||
        widget.points != oldWidget.points) {
      _reportSpot();
    }
    final chosen =
        widget.selectedKey != null &&
        widget.selectedKey != oldWidget.selectedKey;
    final again = widget.locateTick != oldWidget.locateTick;
    if (!chosen && !again) return;
    for (final item in _located) {
      if (capturePointKey(item.point) == widget.selectedKey) {
        _focus(item.location, always: again);
        break;
      }
    }
  }

  void _reportSpot([MapCamera? camera]) {
    final report = widget.onSelectedSpot;
    if (report == null) return;
    // Quien escucha reconstruye: durante el build se avisa al terminar el
    // frame, con la cámara de ese momento.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportSpot();
      });
      return;
    }
    final key = widget.selectedKey;
    Offset? spot;
    if (key != null && _ready) {
      final view = camera ?? _map.camera;
      for (final item in _located) {
        if (capturePointKey(item.point) != key) continue;
        spot = view.latLngToScreenOffset(item.location);
        break;
      }
    }
    report(spot);
  }

  List<LatLng>? _edgeSource;
  var _edgeMesh = false;
  List<(int, int)> _edges = const [];

  /// La red solo se recalcula si cambian las coordenadas o el tipo de red.
  List<(int, int)> _edgesFor(List<_Located> located) {
    final coords = [for (final item in located) item.location];
    final same =
        _edgeSource != null &&
        _edgeMesh == widget.mesh &&
        _edgeSource!.length == coords.length &&
        Iterable<int>.generate(
          coords.length,
        ).every((i) => _edgeSource![i] == coords[i]);
    if (!same) {
      _edgeSource = coords;
      _edgeMesh = widget.mesh;
      _edges = widget.mesh
          ? captureMeshEdges(coords.length)
          : captureGeoEdges(coords);
    }
    return _edges;
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

  /// Lleva la cámara al punto. Si ya se ve con aire, no la mueve: la ficha lo
  /// sigue donde esté y el mapa no salta al elegir. [always] centra igual.
  void _focus(LatLng location, {bool always = false}) {
    if (!_ready) return;
    final camera = _map.camera;
    final zoom = camera.zoom;
    if (!zoom.isFinite || zoom < 2) return;
    if (!always) {
      final pad =
          widget.fitPadding ?? const EdgeInsets.fromLTRB(36, 28, 36, 36);
      // El encuadre inicial deja los puntos extremos justo en el margen: con
      // algo de holgura cuentan como visibles, sin llegar a los bordes.
      final room = pad
          .deflateRect(Offset.zero & camera.nonRotatedSize)
          .inflate(24);
      final spot = camera.latLngToScreenOffset(location);
      if (!room.isEmpty && room.contains(spot)) return;
    }
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
            // Sin inercia: al soltar un arrastre rápido flutter_map corre
            // la cámara una pantalla entera, aunque el gesto fuera corto.
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.all &
                  ~InteractiveFlag.rotate &
                  ~InteractiveFlag.flingAnimation,
            ),
            onMapReady: () {
              _ready = true;
              _focusSelected();
              _reportSpot();
            },
            onMapEvent: (event) {
              // Si el usuario toma el mapa, el viaje al punto se detiene y
              // no le disputa la cámara.
              if (_fly.isAnimating &&
                  event.source != MapEventSource.mapController &&
                  event.source != MapEventSource.nonRotatedSizeChange) {
                _fly.stop();
              }
              _reportSpot(event.camera);
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
            if (widget.network && located.length > 1)
              _NetworkEdges(
                located: located,
                edges: _edgesFor(located),
                selectedKey: widget.selectedKey,
                solid: widget.mesh,
              ),
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
              loggers: widget.loggers,
              markExtent: widget.markExtent,
            ),
            // Encima del logger: la luz que late tapa la luz fija de la
            // antena. No recibe toques. Sin el dibujo, late el centro.
            _ActivePulse(
              located: located,
              cluster: widget.cluster,
              loggers: widget.loggers,
              markExtent: widget.markExtent,
            ),
            if (widget.readoutOf case final readoutOf? when !widget.cluster)
              _Readouts(
                located: located,
                selectedKey: widget.selectedKey,
                readoutOf: readoutOf,
                area: widget.readoutArea,
                keepClearOf: widget.keepClearOf,
                blocks: widget.readoutBlocks,
                onSelect: widget.onSelect,
                markExtent: widget.markExtent,
              ),
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

/// Red entre equipos, como el observatorio: trazos punteados que fluyen.
/// Aparece desde zoom 4; los enlaces del punto elegido brillan y corren más
/// rápido.
class _NetworkEdges extends StatefulWidget {
  const _NetworkEdges({
    required this.located,
    required this.edges,
    required this.selectedKey,
    this.solid = false,
  });

  final List<_Located> located;
  final List<(int, int)> edges;
  final String? selectedKey;

  /// Trazo continuo y tenue para los enlaces quietos. Con la red de
  /// cobertura son muchos: punteados taparían el mapa y pesarían.
  final bool solid;

  static const minZoom = 4.0;

  /// Bajo este zoom la red va más tenue, para no tapar el mapa.
  static const fineZoom = 8.0;

  @override
  State<_NetworkEdges> createState() => _NetworkEdgesState();
}

class _NetworkEdgesState extends State<_NetworkEdges>
    with SingleTickerProviderStateMixin {
  static const _frame = 1 / 30;

  late final Ticker _ticker = createTicker((elapsed) {
    final next = elapsed.inMicroseconds / 1e6;
    if (next - _seconds.value < _frame) return;
    _seconds.value = next;
  });
  final _seconds = ValueNotifier<double>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (camera.zoom < _NetworkEdges.minZoom) return const SizedBox.shrink();
    var selected = -1;
    final screen = <Offset>[];
    for (var i = 0; i < widget.located.length; i++) {
      final item = widget.located[i];
      screen.add(camera.latLngToScreenOffset(item.location));
      if (capturePointKey(item.point) == widget.selectedKey) selected = i;
    }
    final plain = <(Offset, Offset)>[];
    final hot = <(Offset, Offset)>[];
    for (final (a, b) in widget.edges) {
      final segment = (screen[a], screen[b]);
      (a == selected || b == selected ? hot : plain).add(segment);
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _EdgePainter(
              plain: plain,
              hot: hot,
              fine: camera.zoom >= _NetworkEdges.fineZoom,
              solid: widget.solid,
              clock: _seconds,
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.plain,
    required this.hot,
    required this.fine,
    required this.clock,
    this.solid = false,
  }) : super(repaint: clock);

  final List<(Offset, Offset)> plain;
  final List<(Offset, Offset)> hot;
  final bool fine;
  final bool solid;
  final ValueListenable<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final view = (Offset.zero & size).inflate(8);
    final seconds = clock.value;
    if (solid) {
      _ridges(canvas, view, plain, fine: fine, hot: false);
      _ridges(canvas, view, hot, fine: true, hot: true);
      return;
    }
    // Mismas velocidades que el CSS del observatorio: 16 px en 4 s, y en
    // 2,2 s para los enlaces del punto elegido.
    _dashes(
      canvas,
      view,
      plain,
      dash: 1.5,
      gap: 5,
      shift: seconds * 16 / 4,
      paint: Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = fine ? 1.2 : 1
        // Algo más visible que el observatorio: aquí la red es el foco.
        ..color = fine ? const Color(0x8C78B4DC) : const Color(0x6678AFD2),
    );
    _dashes(
      canvas,
      view,
      hot,
      dash: 1,
      gap: 3,
      shift: seconds * 16 / 2.2,
      paint: Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.8
        ..color = const Color(0xC7B4D7EB),
    );
  }

  /// Malla de cobertura: grabado fino, sombra pegada y un filo apenas más
  /// claro. El arco es bajo para no leerse como cable.
  void _ridges(
    Canvas canvas,
    Rect view,
    List<(Offset, Offset)> segments, {
    required bool fine,
    required bool hot,
  }) {
    if (segments.isEmpty) return;
    final room = view.inflate(16);
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = hot ? 2.0 : (fine ? 1.7 : 1.4)
      ..color = const Color(0x2A041018)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1);
    final body = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = hot ? 1.35 : (fine ? 1.15 : 0.95)
      ..color = hot
          ? const Color(0xA3B4D7EB)
          : (fine ? const Color(0x6B78B4DC) : const Color(0x5278AFD2));
    final filo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = hot ? 0.7 : 0.55
      ..color = hot ? const Color(0x66D7EAF4) : const Color(0x3DC5E4F4);
    const ground = Offset(0.7, 1.0);
    const crest = Offset(-0.35, -0.45);
    for (final (from, to) in segments) {
      if (_clip(from, to, room) == null) continue;
      final apex = captureMeshApex(from, to);
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(apex.dx, apex.dy, to.dx, to.dy);
      canvas.drawPath(path.shift(ground), shadow);
      canvas.drawPath(path, body);
      canvas.drawPath(path.shift(crest), filo);
    }
  }

  void _dashes(
    Canvas canvas,
    Rect view,
    List<(Offset, Offset)> segments, {
    required double dash,
    required double gap,
    required double shift,
    required Paint paint,
  }) {
    if (segments.isEmpty) return;
    final period = dash + gap;
    final phase = shift % period;
    final out = <double>[];
    for (final (from, to) in segments) {
      final clipped = _clip(from, to, view);
      if (clipped == null) continue;
      final (a, b) = clipped;
      final along = b - a;
      final length = along.distance;
      if (length < 0.5) continue;
      final unit = along / length;
      // El patrón queda anclado al inicio real del enlace, no al recorte.
      final start = (a - from).distance;
      var s = phase - period - (start % period);
      while (s < length) {
        final head = math.max(0.0, s);
        final tail = math.min(length, s + dash);
        if (tail > head) {
          final p = a + unit * head;
          final q = a + unit * tail;
          out
            ..add(p.dx)
            ..add(p.dy)
            ..add(q.dx)
            ..add(q.dy);
        }
        s += period;
      }
    }
    if (out.isEmpty) return;
    canvas.drawRawPoints(PointMode.lines, Float32List.fromList(out), paint);
  }

  /// Recorta el tramo a lo visible (Liang-Barsky). Nulo si queda fuera.
  static (Offset, Offset)? _clip(Offset a, Offset b, Rect r) {
    var t0 = 0.0;
    var t1 = 1.0;
    final d = b - a;
    bool edge(double p, double q) {
      if (p == 0) return q >= 0;
      final t = q / p;
      if (p < 0) {
        if (t > t1) return false;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return false;
        if (t < t1) t1 = t;
      }
      return true;
    }

    if (!edge(-d.dx, a.dx - r.left) ||
        !edge(d.dx, r.right - a.dx) ||
        !edge(-d.dy, a.dy - r.top) ||
        !edge(d.dy, r.bottom - a.dy)) {
      return null;
    }
    return (a + d * t0, a + d * t1);
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) =>
      oldDelegate.plain != plain ||
      oldDelegate.hot != hot ||
      oldDelegate.fine != fine ||
      oldDelegate.solid != solid ||
      oldDelegate.clock != clock;
}

/// Onda que sale de la luz de la antena de cada punto conectado, para verlos
/// de un vistazo. Si el punto quedó dentro de un grupo, late la antena del
/// grupo. Es una sola capa de canvas: no hay un widget animado por punto.
class _ActivePulse extends StatefulWidget {
  const _ActivePulse({
    required this.located,
    required this.cluster,
    this.loggers = true,
    this.markExtent = captureLoggerMarkSize,
  });

  final List<_Located> located;
  final bool cluster;
  final bool loggers;
  final double markExtent;

  /// Luz de la antena respecto del centro del dibujo del logger.
  static Offset _tip(double markExtent) => Offset(
    0,
    captureLoggerAntennaTipY - markExtent / 2,
  );

  /// En el grupo el logger va a la izquierda del número.
  static Offset _clusterTip(double markExtent) => Offset(
    markExtent / 2 - _clusterWidth / 2,
    captureLoggerAntennaTipY - markExtent / 2,
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
              (widget.loggers
                  ? (group.length == 1
                        ? _ActivePulse._tip(widget.markExtent)
                        : _ActivePulse._clusterTip(widget.markExtent))
                  : Offset.zero),
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

/// Una variable en la tarjeta del mapa, con su nombre para no confundir
/// unidades: el consumo del día y el acumulado van ambos en m³.
@immutable
class CaptureReadout {
  const CaptureReadout({
    required this.label,
    required this.short,
    required this.value,
    required this.unit,
  });

  /// Nombre bajo el número, en la tarjeta completa.
  final String label;

  /// Nombre delante del número, en la tarjeta de una línea.
  final String short;
  final String value;
  final String unit;

  @override
  bool operator ==(Object other) =>
      other is CaptureReadout &&
      other.label == label &&
      other.short == short &&
      other.value == value &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(label, short, value, unit);

  @override
  String toString() => '$label $value $unit';
}

@immutable
class CaptureReadoutCard {
  const CaptureReadoutCard({required this.items, this.title, this.code});

  /// Nombre del punto. Nulo si la tarjeta va solo con el código de obra.
  final String? title;

  /// Código de obra (CO). Nulo si no se pide o el punto no lo tiene.
  final String? code;
  final List<CaptureReadout> items;
}

/// De qué lado del punto queda la tarjeta. La muesca mira al punto.
enum _Side { above, below, right, left }

/// Tarjetas junto a cada punto: la ficha que se abre, comprimida. El punto
/// elegido no la lleva, porque ahí está la ficha. Ninguna se pisa con otra,
/// con un logger ni con la ficha abierta: prueba los cuatro lados en
/// completa, luego en una línea, y si nada cabe espera a que el zoom le
/// haga aire.
class _Readouts extends StatelessWidget {
  const _Readouts({
    required this.located,
    required this.selectedKey,
    required this.readoutOf,
    required this.area,
    required this.keepClearOf,
    required this.blocks,
    required this.onSelect,
    this.markExtent = captureLoggerMarkSize,
  });

  final List<_Located> located;
  final String? selectedKey;
  final CaptureReadoutCard? Function(Map<String, dynamic> point) readoutOf;
  final Rect? area;
  final Rect? Function(Offset spot)? keepClearOf;
  final List<Rect> blocks;
  final ValueChanged<Map<String, dynamic>>? onSelect;
  final double markExtent;

  /// Aire entre el logger y la punta de la muesca.
  static const _gap = 3.0;

  /// Aire mínimo entre dos tarjetas.
  static const _margin = 4.0;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (!_cameraSized(camera)) return const SizedBox.shrink();
    final view = Offset.zero & camera.nonRotatedSize;
    final bounds = area == null ? view : view.intersect(area!);
    if (bounds.width <= 0 || bounds.height <= 0) {
      return const SizedBox.shrink();
    }
    final base = DefaultTextStyle.of(context).style;
    final screen = [
      for (final item in located) camera.latLngToScreenOffset(item.location),
    ];
    final marks = [
      for (final spot in screen)
        Rect.fromCenter(
          center: spot,
          width: markExtent,
          height: markExtent,
        ),
    ];
    final cards = <Rect>[...blocks];
    for (var index = 0; index < located.length; index++) {
      if (capturePointKey(located[index].point) != selectedKey) continue;
      final clear = keepClearOf?.call(screen[index]);
      if (clear != null) cards.add(clear.inflate(_margin));
    }

    bool free(Rect footprint, int owner) {
      if (footprint.left < bounds.left ||
          footprint.top < bounds.top ||
          footprint.right > bounds.right ||
          footprint.bottom > bounds.bottom) {
        return false;
      }
      for (var other = 0; other < marks.length; other++) {
        if (other != owner && marks[other].overlaps(footprint)) return false;
      }
      for (final card in cards) {
        if (card.overlaps(footprint)) return false;
      }
      return true;
    }

    final children = <Widget>[];
    for (var index = 0; index < located.length; index++) {
      final item = located[index];
      final key = capturePointKey(item.point);
      if (key == selectedKey) continue;
      final card = readoutOf(item.point);
      if (card == null) continue;
      if (card.items.isEmpty && card.title == null && card.code == null) {
        continue;
      }
      final spot = screen[index];
      ({Rect rect, _Side side, _CardLayout layout})? slot;
      final compactModes = card.items.isEmpty
          ? const [false]
          : const [false, true];
      for (final compact in compactModes) {
        final layout = _CardLayout.of(card, base, compact: compact);
        for (final side in _Side.values) {
          final rect = _cardRect(spot, layout.size, side, markExtent);
          if (!free(_footprint(rect, spot, side), index)) continue;
          slot = (rect: rect, side: side, layout: layout);
          break;
        }
        if (slot != null) break;
      }
      if (slot == null) continue;
      cards.add(_footprint(slot.rect, spot, slot.side).inflate(_margin));
      children.add(
        Positioned.fromRect(
          rect: slot.rect,
          child: _MiniCard(
            key: ValueKey('capture-readout-$key'),
            card: card,
            layout: slot.layout,
            side: slot.side,
            edge: _cardEdge(item.point),
            status: captureLinkColor(item.point),
            onTap: onSelect == null ? null : () => onSelect!(item.point),
          ),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return SizedBox.expand(
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  static Rect _cardRect(Offset spot, Size size, _Side side, double markExtent) {
    final reach = markExtent / 2 + _gap + _notchDepth;
    return switch (side) {
      _Side.above => Rect.fromLTWH(
        spot.dx - size.width / 2,
        spot.dy - reach - size.height,
        size.width,
        size.height,
      ),
      _Side.below => Rect.fromLTWH(
        spot.dx - size.width / 2,
        spot.dy + reach,
        size.width,
        size.height,
      ),
      _Side.right => Rect.fromLTWH(
        spot.dx + reach,
        spot.dy - size.height / 2,
        size.width,
        size.height,
      ),
      _Side.left => Rect.fromLTWH(
        spot.dx - reach - size.width,
        spot.dy - size.height / 2,
        size.width,
        size.height,
      ),
    };
  }

  /// La tarjeta con su muesca.
  static Rect _footprint(Rect card, Offset spot, _Side side) {
    return switch (side) {
      _Side.above => card.expandToInclude(
        Rect.fromLTRB(
          spot.dx - _notchHalf,
          card.bottom,
          spot.dx + _notchHalf,
          card.bottom + _notchDepth,
        ),
      ),
      _Side.below => card.expandToInclude(
        Rect.fromLTRB(
          spot.dx - _notchHalf,
          card.top - _notchDepth,
          spot.dx + _notchHalf,
          card.top,
        ),
      ),
      _Side.right => card.expandToInclude(
        Rect.fromLTRB(
          card.left - _notchDepth,
          spot.dy - _notchHalf,
          card.left,
          spot.dy + _notchHalf,
        ),
      ),
      _Side.left => card.expandToInclude(
        Rect.fromLTRB(
          card.right,
          spot.dy - _notchHalf,
          card.right + _notchDepth,
          spot.dy + _notchHalf,
        ),
      ),
    };
  }
}

const _notchDepth = 6.0;
const _notchHalf = 5.0;

/// El mismo borde que la ficha abierta.
Color _cardEdge(Map<String, dynamic> point) => switch (pointLinkOf(point)) {
  PointLink.connected => const Color(0xFF7EE0D0),
  PointLink.gap => const Color(0xFFFFC46B),
  PointLink.incident => const Color(0xFFFF847A),
};

const _cardTitleStyle = TextStyle(
  color: Color(0xFFF4FEFF),
  fontSize: 10.5,
  fontWeight: FontWeight.w700,
  height: 1,
);

/// El mismo tono del código en la ficha abierta.
const _cardCodeStyle = TextStyle(
  color: Color(0xFF7EE0D0),
  fontSize: 10,
  fontWeight: FontWeight.w700,
  height: 1,
);
const _cardValueStyle = TextStyle(
  color: Color(0xFFF4FEFF),
  fontSize: 12,
  fontWeight: FontWeight.w700,
  height: 1,
  fontFeatures: [FontFeature.tabularFigures()],
);
const _cardUnitStyle = TextStyle(
  color: Color(0xFF9FB4B3),
  fontSize: 9,
  fontWeight: FontWeight.w600,
  height: 1,
);
const _cardLabelStyle = TextStyle(
  color: Color(0xFF8FA3A4),
  fontSize: 8.5,
  fontWeight: FontWeight.w500,
  height: 1,
);

final _cardWidths = <String, double>{};

double _textWidth(String text, TextStyle style, TextStyle base) {
  final key = '${base.fontFamily}|${style.fontSize}|${style.fontWeight}|$text';
  final known = _cardWidths[key];
  if (known != null) return known;
  if (_cardWidths.length > 800) _cardWidths.clear();
  final painter = TextPainter(
    text: TextSpan(text: text, style: base.merge(style)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble() + 1;
  painter.dispose();
  return _cardWidths[key] = width;
}

/// Medidas de la tarjeta, calculadas antes de ubicarla.
class _CardLayout {
  const _CardLayout({
    required this.size,
    required this.compact,
    required this.columns,
  });

  final Size size;
  final bool compact;

  /// Ancho de cada variable, en el orden de la tarjeta.
  final List<double> columns;

  static const padX = 8.0;
  static const padY = 6.0;
  static const columnGap = 10.0;
  static const dot = 6.0;
  static const dotGap = 5.0;

  /// Tope del nombre: más largo, se corta con puntos suspensivos.
  static const titleMax = 150.0;

  /// Nombre y código en dos líneas, para que «Ambos» no ensanche la tarjeta.
  static const stackedGap = 2.0;
  static const codeLine = 10.0;

  /// Borde y un píxel de aire, para que el redondeo no desborde la fila.
  static const _slack = 3.0;
  static const heading = 12.0;
  static const compactHeight = 22.0;

  static _CardLayout of(
    CaptureReadoutCard card,
    TextStyle base, {
    required bool compact,
  }) {
    if (compact) {
      final columns = [
        for (final item in card.items)
          _textWidth(item.short, _cardLabelStyle, base) +
              4 +
              _textWidth(item.value, _cardValueStyle, base) +
              4 +
              _textWidth(item.unit, _cardUnitStyle, base),
      ];
      final content =
          dot +
          dotGap +
          columns.fold<double>(0, (sum, width) => sum + width) +
          columnGap * (columns.length - 1);
      return _CardLayout(
        size: Size(content + padX * 2 + _slack, compactHeight),
        compact: true,
        columns: columns,
      );
    }
    final columns = [
      for (final item in card.items)
        math.max(
          _textWidth(item.value, _cardValueStyle, base) +
              4 +
              _textWidth(item.unit, _cardUnitStyle, base),
          _textWidth(item.label, _cardLabelStyle, base),
        ),
    ];
    final metrics = columns.isEmpty
        ? 0.0
        : columns.fold<double>(0, (sum, width) => sum + width) +
              columnGap * (columns.length - 1);
    final name = card.title;
    final code = card.code;
    final stacked = name != null && code != null;
    final nameW = name == null
        ? 0.0
        : math.min(titleMax, _textWidth(name, _cardTitleStyle, base));
    final codeW = code == null ? 0.0 : _textWidth(code, _cardCodeStyle, base);
    final title = dot + dotGap + math.max(nameW, codeW);
    final content = math.max(metrics, title);
    final headingH = heading + (stacked ? stackedGap + codeLine : 0);
    final metricsH = card.items.isEmpty ? 0.0 : 4 + 14 + 1 + 10;
    return _CardLayout(
      size: Size(
        content + padX * 2 + _slack,
        _slack + padY * 2 + headingH + metricsH,
      ),
      compact: false,
      columns: columns,
    );
  }
}

class _MiniCard extends StatefulWidget {
  const _MiniCard({
    required this.card,
    required this.layout,
    required this.side,
    required this.edge,
    required this.status,
    required this.onTap,
    super.key,
  });

  final CaptureReadoutCard card;
  final _CardLayout layout;
  final _Side side;
  final Color edge;
  final Color status;
  final VoidCallback? onTap;

  @override
  State<_MiniCard> createState() => _MiniCardState();
}

class _MiniCardState extends State<_MiniCard> {
  var _hot = false;

  @override
  Widget build(BuildContext context) {
    final edge = widget.edge;
    final layout = widget.layout;
    final dot = DecoratedBox(
      decoration: BoxDecoration(color: widget.status, shape: BoxShape.circle),
      child: const SizedBox(width: _CardLayout.dot, height: _CardLayout.dot),
    );
    final Widget body;
    if (layout.compact) {
      body = Row(
        children: [
          dot,
          const SizedBox(width: _CardLayout.dotGap),
          for (var index = 0; index < widget.card.items.length; index++) ...[
            if (index > 0) const SizedBox(width: _CardLayout.columnGap),
            SizedBox(
              width: layout.columns[index],
              child: _line(widget.card.items[index], short: true),
            ),
          ],
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: dot,
              ),
              const SizedBox(width: _CardLayout.dotGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.card.title case final name?)
                      SizedBox(
                        height: _CardLayout.heading,
                        child: Text(
                          name,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textScaler: TextScaler.noScaling,
                          style: _cardTitleStyle,
                        ),
                      ),
                    if (widget.card.title != null && widget.card.code != null)
                      const SizedBox(height: _CardLayout.stackedGap),
                    if (widget.card.code case final code?)
                      SizedBox(
                        height: widget.card.title == null
                            ? _CardLayout.heading
                            : _CardLayout.codeLine,
                        child: Text(
                          code,
                          maxLines: 1,
                          softWrap: false,
                          textScaler: TextScaler.noScaling,
                          style: _cardCodeStyle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.card.items.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                for (
                  var index = 0;
                  index < widget.card.items.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(width: _CardLayout.columnGap),
                  SizedBox(
                    width: layout.columns[index],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 14,
                          child: _line(widget.card.items[index], short: false),
                        ),
                        const SizedBox(height: 1),
                        SizedBox(
                          height: 10,
                          child: Text(
                            widget.card.items[index].label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            textScaler: TextScaler.noScaling,
                            style: _cardLabelStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    }
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) {
        if (!_hot) setState(() => _hot = true);
      },
      onExit: (_) {
        if (_hot) setState(() => _hot = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          foregroundPainter: _MiniNotchPainter(
            side: widget.side,
            color: _hot ? edge : edge.withValues(alpha: 0.7),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xEB1A3036), Color(0xEB0A1418)],
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: _hot ? edge : edge.withValues(alpha: 0.55),
              ),
              boxShadow: [
                BoxShadow(
                  color: edge.withValues(alpha: _hot ? 0.28 : 0.12),
                  blurRadius: _hot ? 14 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _CardLayout.padX,
                vertical: layout.compact ? 0 : _CardLayout.padY,
              ),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(CaptureReadout item, {required bool short}) {
    return Text.rich(
      TextSpan(
        children: [
          if (short) TextSpan(text: '${item.short} ', style: _cardLabelStyle),
          TextSpan(text: item.value, style: _cardValueStyle),
          TextSpan(text: ' ${item.unit}', style: _cardUnitStyle),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      textScaler: TextScaler.noScaling,
    );
  }
}

/// Muesca hacia el punto, centrada en el borde que lo mira.
class _MiniNotchPainter extends CustomPainter {
  const _MiniNotchPainter({required this.side, required this.color});

  final _Side side;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (side) {
      case _Side.above:
        final x = size.width / 2;
        path
          ..moveTo(x - _notchHalf, size.height)
          ..lineTo(x, size.height + _notchDepth)
          ..lineTo(x + _notchHalf, size.height);
      case _Side.below:
        final x = size.width / 2;
        path
          ..moveTo(x - _notchHalf, 0)
          ..lineTo(x, -_notchDepth)
          ..lineTo(x + _notchHalf, 0);
      case _Side.right:
        final y = size.height / 2;
        path
          ..moveTo(0, y - _notchHalf)
          ..lineTo(-_notchDepth, y)
          ..lineTo(0, y + _notchHalf);
      case _Side.left:
        final y = size.height / 2;
        path
          ..moveTo(size.width, y - _notchHalf)
          ..lineTo(size.width + _notchDepth, y)
          ..lineTo(size.width, y + _notchHalf);
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MiniNotchPainter oldDelegate) =>
      oldDelegate.side != side || oldDelegate.color != color;
}

class _CaptureMarkers extends StatelessWidget {
  const _CaptureMarkers({
    required this.cluster,
    required this.located,
    required this.selectedKey,
    required this.onSelect,
    this.loggers = true,
    this.markExtent = captureLoggerMarkSize,
  });

  final bool cluster;
  final List<_Located> located;
  final String? selectedKey;
  final ValueChanged<Map<String, dynamic>>? onSelect;
  final bool loggers;
  final double markExtent;

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
    final mark = loggers
        ? CaptureLoggerMark(
            point: item.point,
            selected: selected,
            onTap: onSelect == null ? null : () => onSelect!(item.point),
            tapKey: ValueKey('capture-location-$key'),
          )
        : CaptureDotMark(
            point: item.point,
            selected: selected,
            onTap: onSelect == null ? null : () => onSelect!(item.point),
            tapKey: ValueKey('capture-location-$key'),
          );
    return Marker(
      point: item.location,
      width: markExtent,
      height: markExtent,
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
