import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'package:flutter_map/flutter_map.dart';

import '../../../core/api/smarthydro_api.dart';
import '../../../core/brand.dart';
import '../../../shared/ui/hydro_ui.dart';
import '../../../shared/ui/point_tool_sheet.dart';
import '../../../shared/widgets/workstation_backdrop.dart';
import '../../geo/capture_coordinates.dart';
import '../../geo/capture_location_map.dart';
import 'capture_logger_plate.dart';
import 'point_config_card.dart';

export 'capture_logger_plate.dart'
    show captureLoggerAntennaGlow, captureLoggerNameFit, captureLoggerNameStyle;
import '../point_link.dart';
import '../point_meta.dart';
import '../point_system.dart';
import 'portfolio_network.dart' show MiniIsoWell;

export '../../geo/capture_coordinates.dart';

/// Celdas vacías del borde. La cuadrícula llega al filo; los loggers no.
const captureEdgePad = 32.0;

/// Medida que usaba el mosaico de ventanas. El resumen ya no la abre.
const captureWindowWidth = 340.0;
const captureWindowHeight = 228.0;
const captureWindowsPerDesktop = 2;

/// Resumen del punto sobre la pizarra. No crece con el texto.
const captureBriefWidth = 320.0;
const captureBriefHeight = 220.0;

/// Lado de la ficha que mira al logger del que salió.
enum CaptureBriefSide { right, left, below, above }

/// Cuadro de la pizarra. El esquema calza en esta medida y no se arrastra.
const captureBoardStep = 16.0;

/// Ancho base de la placa. Si el nombre no cabe, el lugar la ensancha.
const capturePlateWidth = 80.0;

/// Dos cuadros de alto. Igual para cada logger.
const capturePlateHeight = 32.0;

/// Aire entre placas, para que el enlace se lea.
const capturePlateGap = 32.0;

/// Núcleo SMARTHYDRO. Cinco cuadros, para calzar en la misma grilla.
const captureHubSize = 80.0;

/// Franja del botón Stats, para que las placas no queden debajo.
const captureStatsBand = 44.0;

/// Zoom del esquema. 1 es la página encuadrada; no se aleja más.
const captureSchemeZoomMin = 1.0;
const captureSchemeZoomMax = 2.75;

/// Nodo de la red. El nombre va dentro; la caja no tapa el enlace.
const captureLoggerWidth = 84.0;
const captureLoggerHeight = 26.0;

/// Como máximo tres loggers por fila. Si no caben, la pizarra se recorre.
const captureMaxColumns = 3;

/// Segunda línea del logger cuando el punto trae una variable real.
const captureVariableTagHeight = 16.0;

/// Esquema de telemetría del inicio. La pizarra se desplaza por cuadros
/// y no gira. Al tocar un punto se marca y se abre su ficha.
class CaptureNetworkMap extends StatelessWidget {
  const CaptureNetworkMap({
    required this.points,
    required this.onPointSelected,
    this.openTickets = const [],
    this.compliance = const [],
    this.onRequestSupport,
    this.bottomInset = 0,
    this.topInset = 0,
    this.leftInset = 0,
    this.openBottomClearance = 8,
    this.checkApiHealth,
    this.locationTiles,
    this.askBar,
    this.token,
    this.userId,
    this.onConfigured,
    this.seatedWell,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onPointSelected;

  /// Tickets abiertos que el inicio ya cargó. La ficha deja solo el soporte del punto.
  final List<Map<String, dynamic>> openTickets;

  /// Fichas de cumplimiento ya cargadas, por `point_id`.
  final List<Map<String, dynamic>> compliance;

  /// Abre la solicitud de soporte con este punto ya elegido.
  final ValueChanged<Map<String, dynamic>>? onRequestSupport;

  /// Margen inferior solo para puntos/tags (el agua pinta todo el rect).
  final double bottomInset;

  /// Margen superior solo para puntos/tags (el agua pinta todo el rect).
  final double topInset;

  /// Margen izquierdo para el rail desktop (el agua pinta todo el rect).
  final double leftInset;

  /// La ficha abierta no baja de esta distancia al borde inferior.
  /// En el teléfono es el tope de Resumen más 10 px.
  final double openBottomClearance;

  /// Salud del API (`GET /health`). En tests se inyecta para no abrir Dio.
  final Future<bool> Function()? checkApiHealth;

  /// Teselas del mapa de ubicaciones. En la app van por red.
  final TileProvider? locationTiles;

  /// Barra de pregunta rápida. Si viene, reemplaza el título del esquema.
  final Widget? askBar;

  /// Sesión para crear y editar el punto. Sin token la ficha no guarda.
  final String? token;

  /// Dueño que la API pide al crear. Es el usuario de la sesión.
  final int? userId;

  /// Recarga el esquema después de guardar.
  final VoidCallback? onConfigured;

  /// Pozo sobre la cuadrícula. Nulo deja la red de loggers.
  final Widget? seatedWell;

  @override
  Widget build(BuildContext context) {
    return _WaterView(
      points: points,
      onOpen: onPointSelected,
      openTickets: openTickets,
      compliance: compliance,
      onRequestSupport: onRequestSupport,
      topInset: topInset,
      bottomInset: bottomInset,
      leftInset: leftInset,
      openBottomClearance: openBottomClearance,
      checkApiHealth: checkApiHealth,
      locationTiles: locationTiles,
      askBar: askBar,
      token: token,
      userId: userId,
      onConfigured: onConfigured,
      seatedWell: seatedWell,
    );
  }
}

class _WaterView extends StatefulWidget {
  const _WaterView({
    required this.points,
    required this.onOpen,
    required this.openTickets,
    required this.compliance,
    required this.onRequestSupport,
    required this.topInset,
    required this.bottomInset,
    required this.leftInset,
    required this.openBottomClearance,
    this.checkApiHealth,
    this.locationTiles,
    this.askBar,
    this.token,
    this.userId,
    this.onConfigured,
    this.seatedWell,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final List<Map<String, dynamic>> openTickets;
  final List<Map<String, dynamic>> compliance;
  final ValueChanged<Map<String, dynamic>>? onRequestSupport;
  final double topInset;
  final double bottomInset;
  final double leftInset;
  final double openBottomClearance;
  final Future<bool> Function()? checkApiHealth;
  final TileProvider? locationTiles;
  final Widget? askBar;
  final String? token;
  final int? userId;
  final VoidCallback? onConfigured;
  final Widget? seatedWell;

  @override
  State<_WaterView> createState() => _WaterViewState();
}

class _WaterViewState extends State<_WaterView> with TickerProviderStateMixin {
  /// Tiempo continuo en segundos: la onda no “reinicia” al llegar a 1.
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);
  Ticker? _ticker;
  late final AnimationController _assemble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );

  /// La ficha sale del logger y, al terminar, el layout queda en el tamaño fijo.
  late final AnimationController _seat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  int? _selected;
  int _focusTick = 0;
  int _page = 0;
  bool _pageForward = true;
  bool _motion = true;
  bool? _apiOnline;
  bool _showLocations = false;

  /// Zoom pedido. El que se ve va detrás, para que crezca y no salte.
  double _zoomTarget = captureSchemeZoomMin;
  double _shownZoom = captureSchemeZoomMin;
  double _swell = 0;
  double _swellSign = 1;
  Offset _panTarget = Offset.zero;
  Offset _shownPan = Offset.zero;
  Size _schemeSize = Size.zero;
  Offset _zoomAnchor = Offset.zero;
  bool _boardPan = false;
  bool _hubHover = false;
  double _hubHoverShown = 0;
  bool _hubHoverLatched = false;
  bool _hubHoverTainted = false;
  Timer? _hubHoverTimer;
  bool _zoomGuard = false;
  Timer? _zoomGuardTimer;
  bool _statsOpen = false;
  bool _configOpen = false;

  /// Panel con el que abre la ficha: point, telemetry, compliance, physical, scheme.
  String _configPanel = 'point';

  /// Nulo abre la ficha para crear. Con punto, edita ese.
  Map<String, dynamic>? _configPoint;
  Duration? _lastTick;
  final SmartHydroApi _api = SmartHydroApi();
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _headerKey = GlobalKey();
  double _askBand = 0;

  bool _isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 980;

  String? _locationSelectionKey() {
    final index = _selected;
    if (index == null || index < 0 || index >= widget.points.length) {
      return null;
    }
    return capturePointKey(widget.points[index]);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _seconds.value = elapsed.inMicroseconds / 1e6;
      final previous = _lastTick;
      _lastTick = elapsed;
      if (previous != null) {
        _easeZoom((elapsed - previous).inMicroseconds / 1e6);
      }
    });
    if (widget.seatedWell == null) _ticker!.start();
    _refreshApiHealth();
  }

  Future<void> _refreshApiHealth() async {
    final check = widget.checkApiHealth ?? _api.health;
    final ok = await check();
    if (!mounted) return;
    if (_apiOnline == ok) return;
    setState(() => _apiOnline = ok);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = !MediaQuery.disableAnimationsOf(context);
    if (!_motion) {
      _ticker?.stop();
      _seconds.value = 2.4;
      _assemble.value = 1;
      _shownZoom = _zoomTarget;
      _shownPan = _clampSchemePan(_panTarget, _zoomTarget);
      _panTarget = _shownPan;
      _swell = 0;
      _hubHoverShown = _hubHover ? 1 : 0;
    } else if (widget.seatedWell != null) {
      _ticker?.stop();
    } else {
      if (_ticker != null && !_ticker!.isActive) _ticker!.start();
      if (!_assemble.isAnimating && _assemble.value == 0) {
        _assemble.forward();
      }
    }
  }

  @override
  void didUpdateWidget(covariant _WaterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points.length != oldWidget.points.length) {
      _page = 0;
      if (_motion) {
        _assemble.forward(from: 0);
      } else {
        _assemble.value = 1;
      }
    }
    if (_selected != null &&
        (_selected! < 0 || _selected! >= widget.points.length)) {
      _selected = null;
    }
    if ((widget.seatedWell != null) == (oldWidget.seatedWell != null)) return;
    if (widget.seatedWell != null || !_motion) {
      _ticker?.stop();
    } else if (_ticker != null && !_ticker!.isActive) {
      _ticker!.start();
    }
  }

  void _turnPage(int delta, int pages) {
    final next = (_page + delta).clamp(0, pages - 1);
    if (next == _page) return;
    setState(() {
      _pageForward = delta >= 0;
      _page = next;
      _selected = null;
    });
    if (_motion) {
      _assemble.forward(from: 0);
    } else {
      _assemble.value = 1;
    }
  }

  @override
  void dispose() {
    _hubHoverTimer?.cancel();
    _zoomGuardTimer?.cancel();
    _ticker?.dispose();
    _seconds.dispose();
    _assemble.dispose();
    _seat.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index < 0 || index >= widget.points.length) return;
    setState(() {
      _focusTick++;
      _selected = index;
    });
    if (_motion) {
      _seat.forward(from: 0);
    } else {
      _seat.value = 1;
    }
  }

  void _openConfig(Map<String, dynamic>? point, {String panel = 'point'}) {
    setState(() {
      _configPoint = point;
      _configPanel = panel;
      _configOpen = true;
      _statsOpen = false;
    });
  }

  void _closeConfig() {
    setState(() => _configOpen = false);
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
    });
  }

  void _onHubHover(bool inside) {
    _hubHoverTimer?.cancel();
    _hubHoverTimer = null;
    if (!inside) {
      _hubHoverTainted = false;
      if (!_statsOpen) _hubHoverLatched = false;
    }
    setState(() {
      _hubHover = inside;
      if (!_motion) _hubHoverShown = inside ? 1 : 0;
    });
    if (!inside || _statsOpen || _hubHoverLatched || _showLocations) return;
    // El zoom crece desde el cubo y lo mete bajo el cursor. Eso no es un hover.
    if (_hubHoverTainted || _zoomGuard) {
      _hubHoverTainted = true;
      return;
    }
    _hubHoverTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted ||
          !_hubHover ||
          _statsOpen ||
          _hubHoverTainted ||
          _zoomGuard) {
        return;
      }
      _hubHoverLatched = true;
      _openHubStats();
    });
  }

  /// Un zoom en curso no debe abrir el estado de la red.
  void _holdHubForZoom() {
    _hubHoverTimer?.cancel();
    _hubHoverTimer = null;
    _zoomGuard = true;
    if (_hubHover) _hubHoverTainted = true;
    _zoomGuardTimer?.cancel();
    _zoomGuardTimer = Timer(const Duration(milliseconds: 800), () {
      _zoomGuard = false;
      _zoomGuardTimer = null;
    });
  }

  void _openHubStats() {
    if (_statsOpen || !mounted) return;
    _hubHoverTimer?.cancel();
    setState(() => _statsOpen = true);
  }

  void _closeHubStats() {
    if (!_statsOpen) return;
    setState(() => _statsOpen = false);
  }

  void _setZoomTarget(double next) {
    _holdHubForZoom();
    final clamped = next
        .clamp(captureSchemeZoomMin, captureSchemeZoomMax)
        .toDouble();
    final growing = clamped > _shownZoom + 0.02;
    final shrinking = clamped < _shownZoom - 0.02;
    setState(() {
      _zoomTarget = clamped;
      _panTarget = _clampSchemePan(_panTarget, clamped);
      if (!_motion) {
        _shownZoom = clamped;
        _shownPan = _panTarget;
        _swell = 0;
      } else if (growing || shrinking) {
        _swell = 1;
        _swellSign = shrinking ? -1 : 1;
      }
    });
  }

  /// Llega al zoom pedido. El agua acompaña el acercar y el alejar.
  void _easeZoom(double dt) {
    if (!_motion || dt <= 0) return;
    final step = 1 - math.exp(-dt * 9);
    final zoom = _shownZoom + (_zoomTarget - _shownZoom) * step;
    final nextZoom = (zoom - _zoomTarget).abs() < 0.001 ? _zoomTarget : zoom;
    final nextSwell = _swell <= 0.02 ? 0.0 : _swell * math.exp(-dt * 2.6);
    final allowed = _clampSchemePan(_panTarget, nextZoom);
    final pan = Offset.lerp(_shownPan, allowed, step)!;
    final nextPan = (pan - allowed).distance < 0.4 ? allowed : pan;
    final hoverTarget = _hubHover ? 1.0 : 0.0;
    final hover = _hubHoverShown + (hoverTarget - _hubHoverShown) * step;
    final nextHover = (hover - hoverTarget).abs() < 0.01 ? hoverTarget : hover;
    if (nextZoom == _shownZoom &&
        nextSwell == _swell &&
        nextPan == _shownPan &&
        nextHover == _hubHoverShown) {
      return;
    }
    setState(() {
      _shownZoom = nextZoom;
      _swell = nextSwell;
      _panTarget = allowed;
      _shownPan = nextPan;
      _hubHoverShown = nextHover;
    });
  }

  /// Con zoom, el arrastre recorre la red sin dejar el tablero fuera de vista.
  Offset _clampSchemePan(Offset pan, double zoom) {
    final size = _schemeSize;
    final anchor = _zoomAnchor;
    if (zoom <= captureSchemeZoomMin + 0.001 ||
        size.width < 1 ||
        size.height < 1) {
      return Offset.zero;
    }
    final extra = zoom - 1;
    final minX = -(size.width - anchor.dx) * extra;
    final maxX = anchor.dx * extra;
    final minY = -(size.height - anchor.dy) * extra;
    final maxY = anchor.dy * extra;
    return Offset(
      pan.dx.clamp(math.min(minX, maxX), math.max(minX, maxX)).toDouble(),
      pan.dy.clamp(math.min(minY, maxY), math.max(minY, maxY)).toDouble(),
    );
  }

  void _panBy(Offset delta) {
    final next = _clampSchemePan(_shownPan + delta, _shownZoom);
    if (next == _shownPan) return;
    setState(() {
      _shownPan = next;
      _panTarget = next;
    });
  }

  bool _panStartsOnBoard(Offset local, List<Rect> plates, Rect hub) {
    if (_shownZoom <= captureSchemeZoomMin + 0.04) return false;
    final anchor = _zoomAnchor;
    final content = anchor + (local - _shownPan - anchor) / _shownZoom;
    if (!hub.isEmpty && hub.inflate(4).contains(content)) return false;
    for (final plate in plates) {
      if (plate.inflate(4).contains(content)) return false;
    }
    return true;
  }

  void _syncHeader() {
    if (widget.askBar == null) return;
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final next = box.size.height + 18;
    if ((next - _askBand).abs() < 0.5) return;
    setState(() => _askBand = next);
  }

  Widget _briefFor(
    Map<String, dynamic> point, {
    CaptureBriefSide? side,
    double aim = 0.5,
  }) {
    return _BoardBrief(
      point: point,
      openTickets: widget.openTickets,
      compliance: widget.compliance,
      clock: _motion ? _seconds : null,
      token: widget.token,
      api: _api,
      side: side,
      aim: aim,
      onEnter: _openSelected,
      onConfigurePanel: (panel) => _openConfig(point, panel: panel),
      onClose: _clearSelection,
    );
  }

  void _openSelected() {
    final index = _selected;
    if (index == null) return;
    widget.onOpen(widget.points[index]);
  }

  Widget _schemeField({
    required double contentTop,
    required double bottom,
    required List<Rect> plates,
    required Rect hub,
    required List<Map<String, dynamic>> pagePoints,
    required List<int> pageIndexes,
    required int? selected,
    required Set<int> openLocals,
    required bool wide,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      top: contentTop,
      bottom: bottom,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (!hub.isEmpty)
            Positioned(
              left: hub.left,
              top: hub.top - contentTop,
              width: hub.width,
              height: hub.height,
              child: MouseRegion(
                onEnter: (_) => _onHubHover(true),
                onExit: (_) => _onHubHover(false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openHubStats,
                  child: _DataSmartCore(
                    clock: _motion ? _seconds : null,
                    apiOnline: _apiOnline,
                    hover: _hubHoverShown,
                  ),
                ),
              ),
            ),
          AnimatedSwitcher(
            duration: _motion
                ? const Duration(milliseconds: 160)
                : Duration.zero,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) {
              return Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              );
            },
            transitionBuilder: (child, animation) {
              final dir = _pageForward ? 1.0 : -1.0;
              final snap = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              );
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(dir * 0.045, 0),
                    end: Offset.zero,
                  ).animate(snap),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1).animate(snap),
                    child: child,
                  ),
                ),
              );
            },
            child: Stack(
              key: ValueKey('capture-page-$_page'),
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _seconds,
                        builder: (context, seconds, _) {
                          return CustomPaint(
                            painter: _HubLinkPainter(
                              plates: [
                                for (final plate in plates)
                                  plate.shift(Offset(0, -contentTop)),
                              ],
                              hub: hub.shift(Offset(0, -contentTop)),
                              links: [
                                for (final point in pagePoints)
                                  pointLinkOf(point),
                              ],
                              selected: selected,
                              seconds: seconds,
                              motion: _motion,
                              appear: _motion ? _assemble.value : 1,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                for (var local = 0; local < pageIndexes.length; local++)
                  Positioned(
                    key: ValueKey('capture-label-${pageIndexes[local]}'),
                    left: plates[local].left,
                    top: plates[local].top - contentTop,
                    width: plates[local].width,
                    height: plates[local].height,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: () {
                        final marked = wide
                            ? (openLocals.isNotEmpty
                                  ? openLocals.contains(local)
                                  : local == selected)
                            : local == selected;
                        final hasFocus = wide
                            ? openLocals.isNotEmpty || selected != null
                            : selected != null;
                        final dim = hasFocus && !marked ? 0.38 : 1.0;
                        return dim *
                            _schemePlateReveal(
                              plates[local],
                              hub,
                              _motion ? _assemble.value : 1,
                              _motion,
                              order: local,
                            );
                      }(),
                      child: _Snap(
                        token: pageIndexes[local] == _selected
                            ? _focusTick
                            : 'still-$local',
                        play: pageIndexes[local] == _selected,
                        motion: _motion,
                        child: _LoggerNode(
                          point: pagePoints[local],
                          selected: wide
                              ? (openLocals.isNotEmpty
                                    ? openLocals.contains(local)
                                    : local == selected)
                              : local == selected,
                          clock: _motion ? _seconds : null,
                          onTap: () => _select(pageIndexes[local]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Cuadrícula quieta, la pregunta arriba y el pozo en el hueco.
  /// No arma loggers, cables ni el zoom: eso es lo que pesa.
  Widget _seatedNetwork({
    required double contentTop,
    required double contentLeft,
    required double bottom,
    required Widget well,
  }) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: _GridSettle(
            motion: _motion,
            child: const WorkstationBackdrop(),
          ),
        ),
        Positioned(
          left: contentLeft,
          right: 0,
          top: 0,
          bottom: 0,
          child: WellPaletteHost(
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: 0,
                  right: 8,
                  top: contentTop,
                  bottom: bottom,
                  child: _SeatedWell(motion: _motion, child: well),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: widget.topInset + 10,
                  child: KeyedSubtree(
                    key: _headerKey,
                    child: _NetworkHeader(
                      points: widget.points,
                      askBar: widget.askBar,
                      locationMode: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncHeader();
        });
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        // El encabezado ocupa la franja de arriba. La red empieza debajo.
        // Si la respuesta del agente crece, la franja crece con ella.
        final headerBand = widget.askBar == null
            ? 84.0
            : math.max(108.0, _askBand);
        final contentTop = widget.topInset + headerBand;
        final contentLeft = widget.leftInset;
        // Sin lista inferior permanente: el diagrama usa casi todo el alto.
        // La ficha de un punto elegido flota encima y no reserva layout.
        final fieldBottom = math.max(
          widget.bottomInset + 8,
          widget.openBottomClearance,
        );
        final seated = widget.seatedWell;
        if (seated != null) {
          return _seatedNetwork(
            contentTop: contentTop,
            contentLeft: contentLeft,
            bottom: fieldBottom,
            well: seated,
          );
        }
        // El minimapa es un dibujo en la esquina. No corre la red.
        const schemeRight = 0.0;
        final titles = [for (final point in widget.points) _title(point)];
        var pageSize = math.max(
          1,
          captureSchemePageSize(
            size,
            top: contentTop,
            bottom: fieldBottom + captureStatsBand,
            left: contentLeft,
            right: schemeRight,
          ),
        );
        var pages = math.max(1, (widget.points.length / pageSize).ceil());
        final pagerBand = pages > 1 ? 40.0 : 0.0;
        final schemeBottomPad = pagerBand + captureStatsBand;
        if (pagerBand > 0) {
          pageSize = math.max(
            1,
            captureSchemePageSize(
              size,
              top: contentTop,
              bottom: fieldBottom + schemeBottomPad,
              left: contentLeft,
              right: schemeRight,
            ),
          );
          pages = math.max(1, (widget.points.length / pageSize).ceil());
        }
        if (_page >= pages) _page = pages - 1;
        if (_page < 0) _page = 0;
        final pageStart = _page * pageSize;
        final pageEnd = math.min(widget.points.length, pageStart + pageSize);
        final pageIndexes = [
          for (var index = pageStart; index < pageEnd; index++) index,
        ];
        final scheme = placeCaptureScheme(
          pageIndexes.length,
          size,
          top: contentTop,
          bottom: fieldBottom + schemeBottomPad,
          left: contentLeft,
          right: schemeRight,
          groups: [
            for (final index in pageIndexes)
              captureProjectKey(widget.points[index]),
          ],
          labels: [for (final index in pageIndexes) titles[index]],
        );
        final plates = scheme.plates;
        final hub = scheme.hub;
        final stage = captureSchemeStage(
          size,
          top: contentTop,
          bottom: fieldBottom + schemeBottomPad,
          left: contentLeft,
          right: schemeRight,
        );
        final pagePoints = [
          for (final index in pageIndexes) widget.points[index],
        ];
        final wide = _isWide(context);
        final found = _selected == null ? -1 : pageIndexes.indexOf(_selected!);
        final int? selectedOnPage = found < 0 ? null : found;
        const openLocals = <int>{};
        final maxFlow = captureMaxFlow(widget.points);
        final focus =
            _selected != null &&
                _selected! >= 0 &&
                _selected! < widget.points.length
            ? widget.points[_selected!]
            : null;

        return AnimatedBuilder(
          animation: _assemble,
          builder: (context, _) {
            final selected = selectedOnPage;

            // Cada capa que late con el reloj lleva su RepaintBoundary: sin
            // ellos, en escritorio cada frame repinta el shell entero.
            Widget waterLayer = Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _seconds,
                      builder: (context, seconds, _) {
                        return CustomPaint(
                          painter: _LivingWaterPainter(
                            seconds: seconds,
                            motion: _motion,
                            points: pagePoints,
                            anchors: [for (final plate in plates) plate.center],
                            plates: plates,
                            hub: hub,
                            selected: selected,
                            maxFlow: maxFlow,
                            pan: Offset.zero,
                          ),
                          child: const SizedBox.expand(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );

            final viewingScheme = !_showLocations;
            final zoomFrozen = !viewingScheme;
            final zoomAnchor = hub.isEmpty
                ? Offset(size.width / 2, size.height / 2)
                : hub.center;
            _schemeSize = size;
            _zoomAnchor = zoomAnchor;
            final briefFrame = captureBriefFrame(
              onPage: selected,
              plates: plates,
              hub: hub,
              bounds: stage,
              anchor: zoomAnchor,
              pan: zoomFrozen ? Offset.zero : _shownPan,
              zoom: zoomFrozen ? captureSchemeZoomMin : _shownZoom,
            );
            return Stack(
              key: _stackKey,
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                _SchemeZoom(
                  zoom: _zoomTarget,
                  shown: zoomFrozen ? captureSchemeZoomMin : _shownZoom,
                  pan: zoomFrozen ? Offset.zero : _shownPan,
                  anchor: zoomAnchor,
                  enabled: viewingScheme,
                  onChanged: _setZoomTarget,
                  onPanStart: (local) {
                    _boardPan = _panStartsOnBoard(local, plates, hub);
                  },
                  onPanUpdate: (delta) {
                    if (_boardPan) _panBy(delta);
                  },
                  child: waterLayer,
                ),
                if (viewingScheme)
                  _SchemeZoom(
                    zoom: _zoomTarget,
                    shown: zoomFrozen ? captureSchemeZoomMin : _shownZoom,
                    pan: zoomFrozen ? Offset.zero : _shownPan,
                    anchor: zoomAnchor,
                    enabled: viewingScheme,
                    interactive: false,
                    onChanged: _setZoomTarget,
                    onPanStart: (_) {},
                    onPanUpdate: (_) {},
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: ValueListenableBuilder<double>(
                                valueListenable: _seconds,
                                builder: (context, seconds, _) {
                                  return CustomPaint(
                                    painter: _LivingWaterPainter(
                                      seconds: seconds,
                                      motion: _motion,
                                      points: pagePoints,
                                      anchors: [
                                        for (final plate in plates)
                                          plate.center,
                                      ],
                                      plates: plates,
                                      hub: hub,
                                      selected: selected,
                                      maxFlow: maxFlow,
                                      pan: Offset.zero,
                                      lines: true,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        _schemeField(
                          contentTop: contentTop,
                          bottom: fieldBottom + schemeBottomPad,
                          plates: plates,
                          hub: hub,
                          pagePoints: pagePoints,
                          pageIndexes: pageIndexes,
                          selected: selectedOnPage,
                          openLocals: openLocals,
                          wide: wide,
                        ),
                      ],
                    ),
                  ),
                if (viewingScheme && _swell > 0.02 && !hub.isEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GrowSwellPainter(
                          center: hub.center + _shownPan,
                          amount: _swell,
                          direction: _swellSign,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: stage.left,
                  right: size.width - stage.right,
                  top: widget.topInset + 10,
                  child: KeyedSubtree(
                    key: _headerKey,
                    child: _NetworkHeader(
                      points: widget.points,
                      askBar: widget.askBar,
                      locationMode: _showLocations,
                    ),
                  ),
                ),
                if (_showLocations)
                  Positioned(
                    left: contentLeft,
                    right: 0,
                    top: contentTop,
                    bottom: fieldBottom,
                    child: CaptureLocationMap(
                      points: widget.points,
                      selectedKey: _locationSelectionKey(),
                      tileProvider: widget.locationTiles,
                      onSelect: (point) {
                        final index = widget.points.indexOf(point);
                        if (index >= 0) _select(index);
                      },
                    ),
                  ),
                if (viewingScheme && pages > 1)
                  Positioned(
                    left: stage.left,
                    right: size.width - stage.right,
                    bottom: fieldBottom + captureStatsBand,
                    height: 32,
                    child: Row(
                      children: [
                        if (_page > 0)
                          _PageStep(
                            key: const ValueKey('capture-page-prev'),
                            label: 'Anterior',
                            icon: Icons.chevron_left_rounded,
                            iconFirst: true,
                            onTap: () => _turnPage(-1, pages),
                          )
                        else
                          const SizedBox(width: 96),
                        Expanded(
                          child: Text(
                            '${_page + 1} / $pages',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFB7C8C6),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_page < pages - 1)
                          _PageStep(
                            key: const ValueKey('capture-page-next'),
                            label: 'Siguiente',
                            icon: Icons.chevron_right_rounded,
                            onTap: () => _turnPage(1, pages),
                          )
                        else
                          const SizedBox(width: 96),
                      ],
                    ),
                  ),
                if (widget.points.isEmpty) const _EmptyNetwork(),
                if (viewingScheme && pagePoints.length > 1)
                  Positioned(
                    right: 16,
                    top: contentTop + 8,
                    child: _SchemeMinimap(
                      plates: [
                        for (final plate in plates)
                          plate.shift(Offset(0, -contentTop)),
                      ],
                      hub: hub.shift(Offset(0, -contentTop)),
                      selected: selected,
                    ),
                  ),
                if (focus != null && viewingScheme && wide)
                  Positioned(
                    key: const ValueKey('capture-board-brief'),
                    left: briefFrame.rect.left,
                    top: briefFrame.rect.top,
                    width: captureBriefWidth,
                    height: captureBriefHeight,
                    child: _BriefPop(
                      reveal: _seat,
                      motion: _motion,
                      side: briefFrame.side,
                      aim: briefFrame.aim,
                      child: _briefFor(
                        focus,
                        side: briefFrame.side,
                        aim: briefFrame.aim,
                      ),
                    ),
                  ),
                if (focus != null && !wide)
                  Positioned(
                    left: captureEdgePad,
                    right: captureEdgePad,
                    bottom:
                        math.max(8.0, widget.openBottomClearance - 2) +
                        captureStatsBand,
                    height: math.min(300, size.height * 0.5),
                    child: KeyedSubtree(
                      key: const ValueKey('capture-view-records'),
                      child: _BriefPop(
                        reveal: _seat,
                        motion: _motion,
                        side: CaptureBriefSide.above,
                        aim: 0.5,
                        child: _briefFor(focus),
                      ),
                    ),
                  ),
                if (viewingScheme || widget.points.isNotEmpty)
                  Positioned(
                    left: stage.left,
                    right: size.width - stage.right,
                    bottom: fieldBottom + 6,
                    height: 34,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (viewingScheme) ...[
                          // El mismo ancho que el botón Nuevo, para que el zoom
                          // siga centrado en el cubo.
                          const SizedBox(width: 42),
                          _ZoomStep(
                            key: const ValueKey('capture-zoom-out'),
                            icon: Icons.remove_rounded,
                            tooltip: 'Alejar',
                            enabled: _zoomTarget > captureSchemeZoomMin + 0.001,
                            onTap: () => _setZoomTarget(_zoomTarget - 0.25),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (widget.points.isNotEmpty)
                          _SchemeMode(
                            map: _showLocations,
                            onPressed: () => setState(() {
                              _showLocations = !_showLocations;
                            }),
                          ),
                        if (viewingScheme) ...[
                          const SizedBox(width: 8),
                          _ZoomStep(
                            key: const ValueKey('capture-zoom-in'),
                            icon: Icons.add_rounded,
                            tooltip: 'Acercar',
                            enabled: _zoomTarget < captureSchemeZoomMax - 0.001,
                            onTap: () => _setZoomTarget(_zoomTarget + 0.25),
                          ),
                          const SizedBox(width: 8),
                          _ZoomStep(
                            key: const ValueKey('capture-new-point'),
                            icon: Icons.add_location_alt_outlined,
                            tooltip: 'Nuevo punto',
                            enabled: true,
                            onTap: () => _openConfig(null),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_statsOpen)
                  Positioned.fromRect(
                    rect: stage,
                    child: _SchemeStatsLayer(
                      points: widget.points,
                      apiOnline: _apiOnline,
                      onClose: _closeHubStats,
                    ),
                  ),
                if (_configOpen)
                  Positioned.fromRect(
                    rect: stage,
                    child: _PointConfigLayer(
                      point: _configPoint,
                      panel: _configPanel,
                      token: widget.token,
                      userId: widget.userId,
                      api: _api,
                      knownPoints: widget.points,
                      onClose: _closeConfig,
                      onSaved: widget.onConfigured,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Golpe corto al elegir un punto. No cambia el tamaño de layout.
class _Snap extends StatelessWidget {
  const _Snap({
    required this.token,
    required this.play,
    required this.motion,
    required this.child,
  });

  final Object token;
  final bool play;
  final bool motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(token),
      tween: Tween(begin: play && motion ? 0.92 : 1, end: 1),
      duration: motion ? const Duration(milliseconds: 170) : Duration.zero,
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

/// Plano fijo. El arrastre mueve la pizarra; el esquema no gira.
@visibleForTesting
Offset projectCaptureBoard(Offset ground, Size size) {
  return Offset(
    size.width * (0.50 + ground.dx * 0.42),
    size.height * (0.50 + ground.dy * 0.36),
  );
}

/// Redondea el desplazamiento al cuadro de la pizarra.
@visibleForTesting
Offset snapBoardPan(Offset pan) {
  double axis(double value) =>
      (value / captureBoardStep).roundToDouble() * captureBoardStep;
  return Offset(axis(pan.dx), axis(pan.dy));
}

/// Mantiene el dibujo dentro del panel, con margen.
@visibleForTesting
Offset clampBoardPan({
  required Offset pan,
  required Rect content,
  required Rect view,
}) {
  if (content.isEmpty || view.isEmpty) return Offset.zero;
  double axis(double value, double c0, double c1, double v0, double v1) {
    if (c1 - c0 <= v1 - v0) {
      return value.clamp(v0 - c0, v1 - c1);
    }
    return value.clamp(v1 - c1, v0 - c0);
  }

  return Offset(
    axis(pan.dx, content.left, content.right, view.left, view.right),
    axis(pan.dy, content.top, content.bottom, view.top, view.bottom),
  );
}

class _LivingWaterPainter extends CustomPainter {
  _LivingWaterPainter({
    required this.seconds,
    required this.motion,
    required this.points,
    required this.anchors,
    required this.plates,
    required this.hub,
    required this.selected,
    required this.maxFlow,
    required this.pan,
    this.lines = false,
  });

  final double seconds;
  final bool motion;
  final bool lines;
  final List<Map<String, dynamic>> points;
  final List<Offset> anchors;
  final List<Rect> plates;
  final Rect hub;
  final int? selected;
  final double maxFlow;
  final Offset pan;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;

    if (!lines) {
      canvas.drawRect(bounds, Paint()..color = WorkstationBackdrop.base);
      _paintRelief(canvas);
      return;
    }
    _paintGrid(canvas, size);
    _paintHub(canvas);
    _paintLoggerCells(canvas);
  }

  /// Sube un poco donde está la red y baja en el vacío. Sin blur ni capa extra.
  void _paintRelief(Canvas canvas) {
    final breath = motion ? 0.86 + 0.14 * math.sin(seconds * 0.35) : 1.0;
    void lift(Offset center, double radius, double alpha) {
      if (radius < 4) return;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFF1A4550).withValues(alpha: alpha * breath),
              const Color(0xFF102E36).withValues(alpha: alpha * 0.35 * breath),
              const Color(0xFF081216).withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    if (!hub.isEmpty) lift(hub.center, hub.longestSide * 1.35, 0.95);
    for (final plate in plates) {
      if (plate.width < 1 || plate.height < 1) continue;
      lift(plate.center, math.max(plate.width, plate.height) * 0.9, 0.55);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final line = Paint()
      ..color = workstationGridLine
      ..strokeWidth = 1;
    const step = captureBoardStep;
    final ox = ((pan.dx % step) + step) % step;
    final oy = ((pan.dy % step) + step) % step;
    for (var x = ox; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = oy; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// Las líneas del cuadro que ocupa el logger laten suave, justo en su celda.
  /// El desenfoque exterior solo roza la celda de al lado.
  void _paintLoggerCells(Canvas canvas) {
    final breath = motion ? 0.5 + 0.5 * math.sin(seconds * 1.7) : 0.45;
    for (var index = 0; index < plates.length; index++) {
      final plate = plates[index];
      if (plate.width < 1 || plate.height < 1) continue;
      final link = pointLinkOf(points[index]);
      final gap = link == PointLink.gap;
      final color = captureSchemeLinkColor(link);
      final hot = selected == index;
      final picked = selected != null;
      final alpha = gap
          ? 0.34
          : hot
          ? 0.72
          : picked
          ? 0.16
          : link == PointLink.incident
          ? 0.7
          : 0.22 + breath * 0.18;
      final cell = RRect.fromRectAndRadius(plate, Radius.zero);
      canvas.drawRRect(
        cell,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hot ? 1.6 : 1.15
          ..color = color.withValues(alpha: alpha),
      );
      // Sin rayitas internas: el logger se lee solo.
      if (hot) _paintSelectionCorners(canvas, plate, color);
    }
  }

  /// Esquinas firmes alrededor de la celda elegida. No laten: marcan.
  void _paintSelectionCorners(Canvas canvas, Rect plate, Color color) {
    final frame = plate.inflate(3);
    const arm = 8.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.square
      ..color = color.withValues(alpha: 0.95);
    void corner(Offset origin, Offset alongX, Offset alongY) {
      canvas.drawLine(origin, origin + alongX, paint);
      canvas.drawLine(origin, origin + alongY, paint);
    }

    corner(frame.topLeft, const Offset(arm, 0), const Offset(0, arm));
    corner(frame.topRight, const Offset(-arm, 0), const Offset(0, arm));
    corner(frame.bottomLeft, const Offset(arm, 0), const Offset(0, -arm));
    corner(frame.bottomRight, const Offset(-arm, 0), const Offset(0, -arm));
  }

  void _paintHub(Canvas canvas) {
    if (hub.isEmpty) return;
    final breath = motion ? 0.5 + 0.5 * math.sin(seconds * 1.1) : 0.45;
    const color = Color(0xFF7EE0D0);
    final alpha = 0.42 + breath * 0.28;
    final cell = RRect.fromRectAndRadius(hub, const Radius.circular(8));
    canvas.drawRRect(
      cell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: alpha * 0.55),
    );
    canvas.drawRRect(
      cell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _LivingWaterPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.motion != motion ||
      oldDelegate.selected != selected ||
      oldDelegate.maxFlow != maxFlow ||
      oldDelegate.pan != pan ||
      oldDelegate.points != points ||
      oldDelegate.anchors != anchors ||
      oldDelegate.plates != plates ||
      oldDelegate.hub != hub ||
      oldDelegate.lines != lines;
}

/// Enlaces de la página visible. Sale y entra con los loggers.
class _HubLinkPainter extends CustomPainter {
  _HubLinkPainter({
    required this.plates,
    required this.hub,
    required this.links,
    required this.selected,
    required this.seconds,
    required this.motion,
    required this.appear,
  });

  final List<Rect> plates;
  final Rect hub;
  final List<PointLink> links;
  final int? selected;
  final double seconds;
  final bool motion;
  final double appear;

  @override
  void paint(Canvas canvas, Size size) {
    if (hub.isEmpty || plates.isEmpty) return;
    final blocks = [...plates, hub];
    final paths = captureHubLinks(plates, hub);
    for (var index = 0; index < paths.length; index++) {
      final full = paths[index];
      if (full.length < 2) continue;
      final reveal = _schemeReveal(
        plates[index],
        hub,
        appear,
        motion,
        order: index,
      );
      final path = _pathTowardHub(full, reveal);
      if (path.length < 2) continue;
      final link = index < links.length ? links[index] : PointLink.connected;
      final hot = selected == index;
      final quiet = selected != null && !hot;
      final live = captureLinkFlows(link);
      if (!live) {
        final off = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = hot ? 1.55 : 1.2
          ..color = captureSchemeLinkColor(link).withValues(
            alpha: link == PointLink.gap
                ? (quiet ? 0.28 : 0.4)
                : (quiet ? 0.42 : 0.7),
          );
        for (var step = 0; step < path.length - 1; step++) {
          _dashClipped(
            canvas,
            path[step],
            path[step + 1],
            blocks,
            off,
            phase: 0,
            dash: 0,
          );
        }
        continue;
      }
      final energyAlpha = quiet ? 0.22 : 0.82;
      const waterColor = Color(0xFF7EE0D0);
      final tube = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = hot ? 2.8 : 2.3
        ..color = const Color(
          0xFFE7F6F3,
        ).withValues(alpha: (hot ? 0.20 : 0.13) * (quiet ? 0.45 : 1));
      final water = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = hot ? 1.2 : 0.95
        ..color = waterColor.withValues(alpha: energyAlpha);
      for (var step = 0; step < path.length - 1; step++) {
        _dashClipped(
          canvas,
          path[step],
          path[step + 1],
          blocks,
          tube,
          phase: 0,
          dash: 0,
        );
      }
      for (final piece in captureHubwardDashes(
        path,
        travel: motion ? seconds * 32 : 6,
      )) {
        _dashClipped(
          canvas,
          piece.$1,
          piece.$2,
          blocks,
          water,
          phase: 0,
          dash: 0,
        );
      }
      if (motion && reveal < 0.985) {
        canvas.drawCircle(
          path.last,
          1.7,
          Paint()..color = waterColor.withValues(alpha: energyAlpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HubLinkPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.selected != selected ||
      oldDelegate.motion != motion ||
      oldDelegate.appear != appear ||
      oldDelegate.hub != hub ||
      oldDelegate.plates != plates ||
      oldDelegate.links != links;
}

/// Recorta el cable para que crezca desde el logger hacia el cubo.
List<Offset> _pathTowardHub(List<Offset> path, double reveal) {
  if (reveal >= 1) return path;
  if (reveal <= 0 || path.length < 2) return const [];
  var total = 0.0;
  final lengths = <double>[];
  for (var i = 0; i < path.length - 1; i++) {
    final len = (path[i + 1] - path[i]).distance;
    lengths.add(len);
    total += len;
  }
  if (total < 1) return path;
  var remain = total * reveal;
  final out = <Offset>[path.first];
  for (var i = 0; i < lengths.length; i++) {
    final b = path[i + 1];
    final len = lengths[i];
    if (remain >= len) {
      out.add(b);
      remain -= len;
      continue;
    }
    if (len > 0) {
      out.add(Offset.lerp(path[i], b, remain / len)!);
    }
    break;
  }
  return out.length < 2 ? const [] : out;
}

double _schemeReveal(
  Rect plate,
  Rect hub,
  double t,
  bool motion, {
  int order = 0,
}) {
  if (!motion || t >= 1 || hub.isEmpty) return 1;
  final reach = math.max(
    (plate.center.dx - hub.center.dx).abs(),
    (plate.center.dy - hub.center.dy).abs(),
  );
  final ring = (reach / (captureHubSize + capturePlateGap)).floor();
  final start = (ring * 0.15 + (order % 4) * 0.035).clamp(0.0, 0.58);
  return Curves.easeOutCubic.transform(((t - start) / 0.32).clamp(0.0, 1.0));
}

/// La placa entra rápido. El hilo sigue saliendo del cubo después.
double _schemePlateReveal(
  Rect plate,
  Rect hub,
  double t,
  bool motion, {
  int order = 0,
}) {
  if (!motion || t >= 1 || hub.isEmpty) return 1;
  final reach = math.max(
    (plate.center.dx - hub.center.dx).abs(),
    (plate.center.dy - hub.center.dy).abs(),
  );
  final ring = (reach / (captureHubSize + capturePlateGap)).floor();
  final start = (ring * 0.04 + (order % 4) * 0.015).clamp(0.0, 0.12);
  return Curves.easeOut.transform(((t - start) / 0.16).clamp(0.0, 1.0));
}

/// Trazos de agua que van del logger (el primer punto) hacia el cubo.
@visibleForTesting
List<(Offset, Offset)> captureHubwardDashes(
  List<Offset> path, {
  required double travel,
  double dash = 3.5,
  double gap = 9,
}) {
  if (path.length < 2 || dash <= 0) return const [];
  final from = <Offset>[];
  final to = <Offset>[];
  final start = <double>[];
  final length = <double>[];
  var total = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    final len = (path[i + 1] - path[i]).distance;
    if (len < 0.01) continue;
    from.add(path[i]);
    to.add(path[i + 1]);
    start.add(total);
    length.add(len);
    total += len;
  }
  if (total < 1) return const [];
  final period = dash + gap;
  var cursor = travel % period;
  if (cursor < 0) cursor += period;
  final out = <(Offset, Offset)>[];
  while (cursor < total) {
    final end = math.min(cursor + dash, total);
    for (var i = 0; i < from.length; i++) {
      final segEnd = start[i] + length[i];
      final lo = math.max(cursor, start[i]);
      final hi = math.min(end, segEnd);
      if (hi - lo < 0.4) continue;
      final t0 = (lo - start[i]) / length[i];
      final t1 = (hi - start[i]) / length[i];
      out.add((
        Offset.lerp(from[i], to[i], t0)!,
        Offset.lerp(from[i], to[i], t1)!,
      ));
    }
    cursor += period;
  }
  return out;
}

void _dashClipped(
  Canvas canvas,
  Offset a,
  Offset b,
  List<Rect> blocks,
  Paint paint, {
  required double phase,
  double dash = 6,
  double gap = 5,
}) {
  final horizontal = (a.dy - b.dy).abs() <= (a.dx - b.dx).abs();
  final fixed = horizontal ? a.dy : a.dx;
  var spans = <(double, double)>[
    (
      horizontal ? math.min(a.dx, b.dx) : math.min(a.dy, b.dy),
      horizontal ? math.max(a.dx, b.dx) : math.max(a.dy, b.dy),
    ),
  ];
  for (final block in blocks) {
    final next = <(double, double)>[];
    for (final span in spans) {
      next.addAll(_cutSpan(span, block, horizontal: horizontal, fixed: fixed));
    }
    spans = next;
  }
  for (final span in spans) {
    if (span.$2 - span.$1 < 1) continue;
    final start = horizontal ? Offset(span.$1, fixed) : Offset(fixed, span.$1);
    final end = horizontal ? Offset(span.$2, fixed) : Offset(fixed, span.$2);
    _dashLine(canvas, start, end, paint, phase: phase, dash: dash, gap: gap);
  }
}

void _dashLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  required double phase,
  double dash = 6,
  double gap = 5,
}) {
  final delta = b - a;
  final length = delta.distance;
  if (length < 1) return;
  if (dash <= 0) {
    canvas.drawLine(a, b, paint);
    return;
  }
  final dir = delta / length;
  final period = dash + gap;
  var cursor = -(phase % period);
  while (cursor < length) {
    final start = math.max(cursor, 0.0);
    final end = math.min(cursor + dash, length);
    if (end > start) {
      canvas.drawLine(a + dir * start, a + dir * end, paint);
    }
    cursor += period;
  }
}

/// Puntos sobre el plano de agua, separados para que las fichas no se monten.
@visibleForTesting
List<Offset> layoutWaterField(List<Map<String, dynamic>> points) {
  if (points.isEmpty) return const [];
  final coords = [for (final point in points) captureLatLng(point)];
  final raw = coords.every((coord) => coord != null)
      ? _groundFromGps([for (final coord in coords) coord!])
      : _groundFromLayout(points);
  final spread = _spreadGround(raw);
  _separateGround(spread);
  return spread;
}

/// Estira la forma de la red para que ocupe la pizarra, sin cambiar quién
/// está junto a quién.
List<Offset> _spreadGround(List<Offset> spots) {
  if (spots.length < 2) return spots;
  var maxAbs = 0.0;
  for (final spot in spots) {
    maxAbs = math.max(maxAbs, math.max(spot.dx.abs(), spot.dy.abs()));
  }
  const target = 0.70;
  if (maxAbs < 0.08 || maxAbs >= target) return spots;
  final gain = target / maxAbs;
  return [for (final spot in spots) spot * gain];
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
  // Un poco más de aire para que los ripples no se monten.
  const minDist = 0.44;
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

/// Ancho del logger según el nombre. Crece para no cortarlo.
@visibleForTesting
double captureLoggerWidthFor(String title) {
  final painter = TextPainter(
    text: TextSpan(text: title, style: captureLoggerNameStyle),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  // Antena, aire y lámpara. El nombre va debajo y usa casi todo el ancho.
  const chrome = 8.0;
  return math.max(64.0, chrome + width);
}

/// Rectángulo de la vista de la red. El núcleo, el zoom y el estado
/// se alinean a este cuadro, no al centro de la ventana.
@visibleForTesting
Rect captureSchemeStage(
  Size size, {
  double top = 8,
  double bottom = 8,
  double left = 0,
  double right = 0,
}) {
  const hub = captureHubSize;
  final viewLeft = math.max(captureEdgePad, left);
  final viewRight = math.max(
    viewLeft + hub,
    size.width - captureEdgePad - right,
  );
  final viewTop = math.max(captureEdgePad, top);
  final viewBottom = math.max(viewTop + hub, size.height - bottom);
  return Rect.fromLTRB(viewLeft, viewTop, viewRight, viewBottom);
}

/// Hueco útil del esquema, entre el margen y el núcleo.
@visibleForTesting
({double width, double height}) captureSchemeViewSpan(
  Size size, {
  double top = 8,
  double bottom = 8,
  double left = 0,
  double right = 0,
}) {
  final stage = captureSchemeStage(
    size,
    top: top,
    bottom: bottom,
    left: left,
    right: right,
  );
  return (width: stage.width, height: stage.height);
}

/// La placa del logger no crece con el nombre. El texto se acomoda adentro.
@visibleForTesting
({double width, double height})? captureLoggerBoxFor(
  List<String>? labels, {
  required int count,
  required double viewWidth,
  required double viewHeight,
}) {
  if (count <= 0 || viewWidth < 1 || viewHeight < 1) return null;
  // El nombre se dibuja dentro de la placa fija. [labels] no la agranda.
  return (width: capturePlateWidth, height: capturePlateHeight);
}

/// Corre el bloque para sentarlo al medio, en cuadros enteros.
/// Si no cabe, el valor es negativo y sobra lo mismo a cada lado.
@visibleForTesting
double captureCenterShift({
  required double slack,
  double step = captureBoardStep,
}) {
  if (step <= 0) return 0;
  final raw = (slack / 2 / step).round() * step;
  if (slack < 0) return raw;
  final maxShift = (slack / step).floor() * step;
  if (maxShift <= 0) return 0;
  return raw.clamp(0.0, maxShift);
}

/// Siguiente línea de la pizarra. La cuadrícula nace en el borde de la pantalla.
double _snapUpToStep(double value, double step) {
  if (step <= 0) return value;
  final rem = ((value % step) + step) % step;
  if (rem < 0.1) return value;
  return value + (step - rem);
}

/// Sube la medida al siguiente cuadro. El borde queda sobre la línea.
@visibleForTesting
double captureGridSpan(double width, {int minSteps = 2}) {
  final steps = (width / captureBoardStep).ceil();
  return math.max(minSteps, steps) * captureBoardStep;
}

/// El punto trae ficha DGA activa. Si no, no se dibuja el ícono.
@visibleForTesting
bool captureHasCompliance(Map<String, dynamic> point) =>
    complianceAgencyOf(point) != null;

/// Nivel real de `compliance_warning`, si el punto lo trae.
@visibleForTesting
String? captureComplianceLevel(Map<String, dynamic> point) {
  final raw = point['compliance_warning'];
  if (raw is! Map) return null;
  final level = raw['level']?.toString();
  if (level == null || level.isEmpty || level == 'null') return null;
  return level;
}

/// Codo en la cuadrícula: horizontal y después vertical.
@visibleForTesting
List<Offset> captureGridLink(Offset a, Offset b) {
  if ((a.dx - b.dx).abs() < 1 || (a.dy - b.dy).abs() < 1) return [a, b];
  return [a, Offset(b.dx, a.dy), b];
}

/// Vecinos inmediatos de la grilla: al lado y debajo, sin saltar un nodo.
@visibleForTesting
List<(int, int)> captureGridNeighbors(List<Rect> plates) {
  bool sameRow(Rect a, Rect b) => (a.top - b.top).abs() < 4;
  bool sameCol(Rect a, Rect b) => (a.left - b.left).abs() < 4;
  final links = <(int, int)>[];
  for (var i = 0; i < plates.length; i++) {
    for (var j = i + 1; j < plates.length; j++) {
      final a = plates[i];
      final b = plates[j];
      if (sameRow(a, b)) {
        final left = a.left <= b.left ? i : j;
        final right = left == i ? j : i;
        var blocked = false;
        for (var k = 0; k < plates.length; k++) {
          if (k == i || k == j) continue;
          final mid = plates[k];
          if (!sameRow(mid, a)) continue;
          if (mid.left > plates[left].left + 1 &&
              mid.left < plates[right].left - 1) {
            blocked = true;
            break;
          }
        }
        if (!blocked && plates[right].left + 1 >= plates[left].right) {
          links.add((i, j));
        }
      } else if (sameCol(a, b)) {
        final upper = a.top <= b.top ? i : j;
        final lower = upper == i ? j : i;
        var blocked = false;
        for (var k = 0; k < plates.length; k++) {
          if (k == i || k == j) continue;
          final mid = plates[k];
          if (!sameCol(mid, a)) continue;
          if (mid.top > plates[upper].top + 1 &&
              mid.top < plates[lower].top - 1) {
            blocked = true;
            break;
          }
        }
        if (!blocked && plates[lower].top + 1 >= plates[upper].bottom) {
          links.add((i, j));
        }
      }
    }
  }
  return links;
}

/// Quita el tramo de una línea que cruza un logger, con un pelo de aire.
List<(double, double)> _cutSpan(
  (double, double) span,
  Rect block, {
  required bool horizontal,
  required double fixed,
}) {
  const air = 3.0;
  final cross0 = horizontal ? block.top : block.left;
  final cross1 = horizontal ? block.bottom : block.right;
  if (fixed < cross0 - 0.5 || fixed > cross1 + 0.5) return [span];
  final cut0 = (horizontal ? block.left : block.top) - air;
  final cut1 = (horizontal ? block.right : block.bottom) + air;
  final start = span.$1;
  final end = span.$2;
  if (end <= cut0 || start >= cut1) return [span];
  final parts = <(double, double)>[];
  if (start < cut0) parts.add((start, math.min(end, cut0)));
  if (end > cut1) parts.add((math.max(start, cut1), end));
  return parts;
}

/// La mayor cantidad de columnas que entra. Si una sola no cabe, igual se usa
/// y el bloque sigue centrado, aunque cruce el margen.
int _columnsThatFit({
  required List<int> order,
  required List<double> nodeW,
  required double available,
  required int maxColumns,
}) {
  const step = captureBoardStep;
  const gap = capturePlateGap;
  double blockWidth(int cols) {
    final colW = List<double>.filled(cols, step * 2);
    for (var slot = 0; slot < order.length; slot++) {
      final col = slot % cols;
      colW[col] = math.max(colW[col], nodeW[order[slot]]);
    }
    var width = colW.first;
    for (var col = 1; col < cols; col++) {
      width += gap + colW[col];
    }
    return width;
  }

  var best = 1;
  for (var cols = 1; cols <= maxColumns; cols++) {
    if (blockWidth(cols) <= available + step) best = cols;
  }
  return best;
}

/// Loggers en columnas de la cuadrícula, máximo tres por fila.
/// El bloque queda al medio en los dos ejes, también cuando no cabe.
/// El borde izquierdo y el superior caen sobre una línea que nace en cero.
@visibleForTesting
List<Rect> placeNodeLabels(
  List<Offset> anchors,
  Size size, {
  double top = 8,
  double bottom = 8,
  List<double>? widths,
  List<double>? heights,
  List<String>? groups,
  List<String>? labels,
  int maxColumns = captureMaxColumns,
}) {
  const pad = captureEdgePad;
  const step = captureBoardStep;
  if (anchors.isEmpty || size.isEmpty) return const [];
  final nodeW = List<double>.generate(anchors.length, (index) {
    final raw = (widths != null && index < widths.length)
        ? widths[index]
        : captureLoggerWidth;
    return captureGridSpan(raw);
  });
  final nodeH = List<double>.generate(anchors.length, (index) {
    final raw = (heights != null && index < heights.length)
        ? heights[index]
        : captureLoggerHeight;
    return captureGridSpan(raw, minSteps: 1);
  });
  final minTop = math.max(pad, top);
  final y0 = _snapUpToStep(minTop, step);

  final order = List<int>.generate(anchors.length, (index) => index);
  if (groups != null && groups.length == anchors.length) {
    order.sort((a, b) {
      final byGroup = groups[a].compareTo(groups[b]);
      if (byGroup != 0) return byGroup;
      if (labels != null && labels.length == anchors.length) {
        final byLabel = labels[a].compareTo(labels[b]);
        if (byLabel != 0) return byLabel;
      }
      return a.compareTo(b);
    });
  }

  final available = math.max(step * 2, size.width - 2 * pad);
  final cols = _columnsThatFit(
    order: order,
    nodeW: nodeW,
    available: available,
    maxColumns: math.max(1, math.min(maxColumns, anchors.length)),
  );
  final colWidth = List<double>.filled(cols, step * 2);
  for (var slot = 0; slot < order.length; slot++) {
    final col = slot % cols;
    colWidth[col] = math.max(colWidth[col], nodeW[order[slot]]);
  }
  const gap = capturePlateGap;
  final relLeft = List<double>.filled(cols, 0);
  for (var col = 1; col < cols; col++) {
    relLeft[col] = relLeft[col - 1] + colWidth[col - 1] + gap;
  }

  final maxH = nodeH.reduce(math.max);
  final pitch = maxH + gap;
  final rows = (order.length + cols - 1) ~/ cols;
  final blockW = relLeft.last + colWidth.last;
  final blockH = rows == 0 ? 0.0 : (rows - 1) * pitch + maxH;
  final viewRight = math.max(pad, size.width - pad);
  final viewBottom = math.max(y0, size.height - bottom);
  final originX =
      pad + captureCenterShift(slack: (viewRight - pad) - blockW, step: step);
  final originY =
      y0 + captureCenterShift(slack: (viewBottom - y0) - blockH, step: step);
  final result = List<Rect?>.filled(anchors.length, null);
  for (var slot = 0; slot < order.length; slot++) {
    final index = order[slot];
    final col = slot % cols;
    final row = slot ~/ cols;
    result[index] = Rect.fromLTWH(
      originX + relLeft[col],
      originY + row * pitch,
      nodeW[index],
      nodeH[index],
    );
  }
  return [for (final rect in result) rect ?? Rect.zero];
}

/// Cuántos loggers caben en la vista sin salir de la pizarra.
@visibleForTesting
int captureSchemePageSize(
  Size size, {
  double top = 8,
  double bottom = 8,
  double left = 0,
  double right = 0,
  List<String>? labels,
}) {
  if (size.isEmpty) return 1;
  var fitted = 1;
  final span = captureSchemeViewSpan(
    size,
    top: top,
    bottom: bottom,
    left: left,
    right: right,
  );
  for (var count = 1; count <= 24; count++) {
    final box = (labels == null || labels.isEmpty)
        ? null
        : captureLoggerBoxFor(
            labels,
            count: count,
            viewWidth: span.width,
            viewHeight: span.height,
          );
    if (labels != null && labels.isNotEmpty && box == null) break;
    final scheme = placeCaptureScheme(
      count,
      size,
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      plateWidth: box?.width,
      plateHeight: box?.height,
    );
    final viewLeft = math.max(captureEdgePad, left);
    final viewRight = math.max(viewLeft, size.width - captureEdgePad - right);
    final viewTop = math.max(captureEdgePad, top);
    final viewBottom = math.max(viewTop, size.height - bottom);
    if (_platesInside(
      scheme.plates,
      viewLeft,
      viewRight,
      viewTop,
      viewBottom,
      scheme.hub,
    )) {
      fitted = count;
    } else {
      break;
    }
  }
  return fitted;
}

/// Columnas de loggers a cada lado del núcleo. En el teléfono cabe una.
@visibleForTesting
int captureSchemeSideColumns(double width, {double left = 0}) {
  const pad = captureEdgePad;
  const step = captureBoardStep;
  const plateW = capturePlateWidth;
  const gap = capturePlateGap;
  const hub = captureHubSize;
  final viewLeft = math.max(pad, left);
  final available = math.max(step * 2, width - viewLeft - pad);
  var side = 1;
  for (var cols = 1; cols <= 3; cols++) {
    final flank = cols * plateW + (cols - 1) * gap;
    final block = flank + gap + hub + gap + flank;
    if (block <= available + step) side = cols;
  }
  return side;
}

int _schemeRows(double height, {required double top, required double bottom}) {
  const pad = captureEdgePad;
  const step = captureBoardStep;
  const plateH = capturePlateHeight;
  const gap = capturePlateGap;
  const hub = captureHubSize;
  final y0 = _snapUpToStep(math.max(pad, top), step);
  final viewBottom = math.max(y0, height - bottom);
  final room = viewBottom - y0;
  var rows = 1;
  for (var count = 1; count <= 16; count++) {
    final blockH = count * plateH + (count - 1) * gap;
    if (math.max(blockH, hub) <= room + 0.5) rows = count;
  }
  return rows;
}

/// Loggers alrededor del núcleo: crece a izquierda, derecha, arriba y abajo.
/// Si son muchos, las placas se achican para seguir viéndose como una red.
@visibleForTesting
({List<Rect> plates, Rect hub}) placeCaptureScheme(
  int count,
  Size size, {
  double top = 8,
  double bottom = 8,
  double left = 0,
  double right = 0,
  List<String>? groups,
  List<String>? labels,
  double? plateWidth,
  double? plateHeight,
}) {
  const hub = captureHubSize;
  if (count <= 0 || size.isEmpty) {
    return (plates: const <Rect>[], hub: Rect.zero);
  }
  final stage = captureSchemeStage(
    size,
    top: top,
    bottom: bottom,
    left: left,
    right: right,
  );
  final order = List<int>.generate(count, (index) => index);
  if (groups != null && groups.length == count) {
    order.sort((a, b) {
      final byGroup = groups[a].compareTo(groups[b]);
      if (byGroup != 0) return byGroup;
      if (labels != null && labels.length == count) {
        final byLabel = labels[a].compareTo(labels[b]);
        if (byLabel != 0) return byLabel;
      }
      return a.compareTo(b);
    });
  }

  final viewLeft = stage.left;
  final viewRight = stage.right;
  final viewTop = stage.top;
  final viewBottom = stage.bottom;
  final hubRect = Rect.fromCenter(
    center: stage.center,
    width: hub,
    height: hub,
  );

  final named = plateWidth != null || plateHeight != null;
  final pw0 = plateWidth ?? capturePlateWidth;
  final ph0 = plateHeight ?? capturePlateHeight;
  if (count == 1) {
    final plate = Rect.fromCenter(
      center: Offset(
        hubRect.center.dx,
        hubRect.top - capturePlateGap - ph0 / 2,
      ),
      width: pw0,
      height: ph0,
    );
    return (plates: [plate], hub: hubRect);
  }

  var scale = !named && count > 6
      ? (1 - ((count - 6) / 40).clamp(0.0, 0.2))
      : 1.0;
  final minScale = named ? 0.85 : 0.8;
  var placed = _compassPlates(
    order,
    hubRect,
    scale,
    plateWidth: pw0,
    plateHeight: ph0,
  );
  for (var step = 0; step < 8; step++) {
    if (_platesInside(
      placed,
      viewLeft,
      viewRight,
      viewTop,
      viewBottom,
      hubRect,
    )) {
      break;
    }
    if (scale <= minScale) break;
    scale = math.max(minScale, scale - 0.05);
    placed = _compassPlates(
      order,
      hubRect,
      scale,
      plateWidth: pw0,
      plateHeight: ph0,
    );
  }
  return (plates: placed, hub: hubRect);
}

List<Rect> _compassPlates(
  List<int> order,
  Rect hub,
  double scale, {
  double? plateWidth,
  double? plateHeight,
}) {
  final count = order.length;
  final pw = (plateWidth ?? capturePlateWidth) * scale;
  final ph = (plateHeight ?? capturePlateHeight) * scale;
  final gap = math.max(6.0, capturePlateGap * scale);
  final strideX = pw + gap;
  final strideY = ph + gap;
  final baseX = hub.width / 2 + gap + pw / 2;
  final baseY = hub.height / 2 + gap + ph / 2;
  final cells = _compassCells(count);
  final slots = List<Rect?>.filled(count, null);
  for (var i = 0; i < count; i++) {
    final cell = cells[i];
    final dx = cell.dx == 0
        ? 0.0
        : cell.dx.sign * (baseX + (cell.dx.abs() - 1) * strideX);
    final dy = cell.dy == 0
        ? 0.0
        : cell.dy.sign * (baseY + (cell.dy.abs() - 1) * strideY);
    slots[order[i]] = Rect.fromCenter(
      center: hub.center + Offset(dx, dy),
      width: pw,
      height: ph,
    );
  }
  return [for (final rect in slots) rect ?? Rect.zero];
}

/// Anillos de Chebyshev: primero los cuatro cardinales, luego el resto.
List<Offset> _compassCells(int count) {
  final cells = <Offset>[];
  var ring = 1;
  while (cells.length < count) {
    final ringCells = <Offset>[];
    for (var y = -ring; y <= ring; y++) {
      for (var x = -ring; x <= ring; x++) {
        if (math.max(x.abs(), y.abs()) != ring) continue;
        ringCells.add(Offset(x.toDouble(), y.toDouble()));
      }
    }
    ringCells.sort((a, b) {
      int rank(Offset c) {
        if (c.dy == 0 && c.dx > 0) return 0;
        if (c.dy == 0 && c.dx < 0) return 1;
        if (c.dx == 0 && c.dy < 0) return 2;
        if (c.dx == 0 && c.dy > 0) return 3;
        return 20 + ((math.atan2(c.dy, c.dx) + math.pi) * 8).round();
      }

      return rank(a).compareTo(rank(b));
    });
    cells.addAll(ringCells);
    ring++;
  }
  return cells.take(count).toList();
}

bool _platesInside(
  List<Rect> plates,
  double left,
  double right,
  double top,
  double bottom,
  Rect hub,
) {
  for (final plate in plates) {
    if (plate.left < left - 0.5) return false;
    if (plate.right > right + 0.5) return false;
    if (plate.top < top - 0.5) return false;
    if (plate.bottom > bottom + 0.5) return false;
    if (plate.overlaps(hub)) return false;
  }
  return true;
}

/// Camino ortogonal desde el logger hasta un punto de entrada en el hub.
/// [attachY] fija la altura de entrada; [busX] el canal vertical del lado.
@visibleForTesting
List<Offset> captureHubLink(
  Rect plate,
  Rect hub, {
  double? attachY,
  double? busX,
  double? attachX,
  double? busY,
}) {
  if (plate.isEmpty || hub.isEmpty) return const [];
  final dx = hub.center.dx - plate.center.dx;
  final dy = hub.center.dy - plate.center.dy;
  if (attachX != null) {
    return _verticalHubLink(plate, hub, attachX: attachX, busY: busY);
  }
  // Con bus/entrada asignados no usar atajos: cruzarían el canal vertical.
  final routed = attachY != null || busX != null;
  if (!routed) {
    final overlapX = plate.right > hub.left && plate.left < hub.right;
    final overlapY = plate.bottom > hub.top && plate.top < hub.bottom;
    if (overlapX && !overlapY) {
      final x = plate.center.dx;
      return dy >= 0
          ? [Offset(x, plate.bottom), Offset(x, hub.top)]
          : [Offset(x, plate.top), Offset(x, hub.bottom)];
    }
    if (overlapY && !overlapX) {
      final y = plate.center.dy;
      return dx >= 0
          ? [Offset(plate.right, y), Offset(hub.left, y)]
          : [Offset(plate.left, y), Offset(hub.right, y)];
    }
  }
  final toRight = dx >= 0;
  final start = toRight
      ? Offset(plate.right, plate.center.dy)
      : Offset(plate.left, plate.center.dy);
  final endX = toRight ? hub.left : hub.right;
  final y = (attachY ?? hub.center.dy)
      .clamp(hub.top + 4, hub.bottom - 4)
      .toDouble();
  final end = Offset(endX, y);
  if ((start.dy - y).abs() < 1) return [start, end];
  final channel =
      busX ??
      (toRight ? hub.left - captureBoardStep : hub.right + captureBoardStep);
  if ((channel - start.dx).abs() < 1) {
    return [start, Offset(start.dx, y), end];
  }
  return [start, Offset(channel, start.dy), Offset(channel, y), end];
}

/// Llegada por arriba o abajo. El bus puede ir junto; el puerto no se repite.
List<Offset> _verticalHubLink(
  Rect plate,
  Rect hub, {
  required double attachX,
  double? busY,
}) {
  final above = plate.center.dy <= hub.center.dy;
  final start = above
      ? Offset(plate.center.dx, plate.bottom)
      : Offset(plate.center.dx, plate.top);
  final x = attachX.clamp(hub.left + 4, hub.right - 4).toDouble();
  final end = Offset(x, above ? hub.top : hub.bottom);
  if ((start.dx - x).abs() < 1) return [start, end];
  final channel = busY ?? (above ? hub.top - 8 : hub.bottom + 8);
  if ((channel - start.dy).abs() < 1) {
    return [start, Offset(x, start.dy), end];
  }
  return [start, Offset(start.dx, channel), Offset(x, channel), end];
}

/// Enlaces de todos los loggers al hub sin cruzarse: un bus fijo por lado
/// y entradas distintas a lo largo del borde del núcleo.
@visibleForTesting
List<List<Offset>> captureHubLinks(List<Rect> plates, Rect hub) {
  if (hub.isEmpty || plates.isEmpty) return const [];
  final left = <int>[];
  final right = <int>[];
  final above = <int>[];
  final below = <int>[];
  for (var i = 0; i < plates.length; i++) {
    final plate = plates[i];
    if (plate.isEmpty) continue;
    final dx = (plate.center.dx - hub.center.dx).abs();
    if (plate.bottom <= hub.top && dx < hub.width * 0.85) {
      above.add(i);
    } else if (plate.top >= hub.bottom && dx < hub.width * 0.85) {
      below.add(i);
    } else if (plate.center.dx <= hub.center.dx) {
      left.add(i);
    } else {
      right.add(i);
    }
  }
  int byY(int a, int b) => plates[a].center.dy.compareTo(plates[b].center.dy);
  int byX(int a, int b) => plates[a].center.dx.compareTo(plates[b].center.dx);
  left.sort(byY);
  right.sort(byY);
  above.sort(byX);
  below.sort(byX);

  double sideBus(List<int> side, {required bool toRight}) {
    if (side.isEmpty) {
      return toRight
          ? hub.left - captureBoardStep
          : hub.right + captureBoardStep;
    }
    if (toRight) {
      var edge = hub.left - captureBoardStep;
      for (final i in side) {
        edge = math.max(edge, plates[i].right + 4);
      }
      return math.min(edge, hub.left - 4);
    }
    var edge = hub.right + captureBoardStep;
    for (final i in side) {
      edge = math.min(edge, plates[i].left - 4);
    }
    return math.max(edge, hub.right + 4);
  }

  final leftBus = sideBus(left, toRight: true);
  final rightBus = sideBus(right, toRight: false);
  final attachY = List<double?>.filled(plates.length, null);
  final attachX = List<double?>.filled(plates.length, null);
  void assignEdge(
    List<int> side,
    List<double?> into,
    double start,
    double span,
  ) {
    for (var i = 0; i < side.length; i++) {
      final t = (i + 1) / (side.length + 1);
      into[side[i]] = start + span * t;
    }
  }

  assignEdge(left, attachY, hub.top, hub.height);
  assignEdge(right, attachY, hub.top, hub.height);
  assignEdge(above, attachX, hub.left, hub.width);
  assignEdge(below, attachX, hub.left, hub.width);

  double rowBus(List<int> side, {required bool aboveHub}) {
    if (side.isEmpty) return aboveHub ? hub.top - 8 : hub.bottom + 8;
    if (aboveHub) {
      var edge = hub.top - 8;
      for (final i in side) {
        edge = math.max(edge, plates[i].bottom + 4);
      }
      return math.min(edge, hub.top - 4);
    }
    var edge = hub.bottom + 8;
    for (final i in side) {
      edge = math.min(edge, plates[i].top - 4);
    }
    return math.max(edge, hub.bottom + 4);
  }

  final topBus = rowBus(above, aboveHub: true);
  final bottomBus = rowBus(below, aboveHub: false);
  return [
    for (var i = 0; i < plates.length; i++)
      if (above.contains(i))
        captureHubLink(plates[i], hub, attachX: attachX[i], busY: topBus)
      else if (below.contains(i))
        captureHubLink(plates[i], hub, attachX: attachX[i], busY: bottomBus)
      else
        captureHubLink(
          plates[i],
          hub,
          attachY: attachY[i],
          busX: plates[i].center.dx <= hub.center.dx ? leftBus : rightBus,
        ),
  ];
}

/// Coloca fichas arriba/abajo, alejadas de los puntos (arquitectura de nodos).
@visibleForTesting
List<Rect> placeCaptureChips(List<Offset> anchors, Size size) {
  const gap = 10.0;
  const pad = 12.0;
  final width = size.width < 420 ? 136.0 : 168.0;
  const height = 48.0;
  // Holgura para que la ficha no tape el beacon ni su ripple cercano.
  const clearR = 56.0;

  bool overlapsBeacon(Rect rect) {
    final hit = rect.inflate(8);
    return anchors.any(
      (a) => hit.overlaps(Rect.fromCircle(center: a, radius: clearR)),
    );
  }

  bool overlapsAny(Rect rect, List<Rect> placed) =>
      placed.any((other) => other.inflate(4).overlaps(rect));

  List<Rect> bandSlots({required bool top}) {
    final slots = <Rect>[];
    final maxLeft = math.max(pad, size.width - width - pad);
    // Hasta 3 filas por banda para muchos puntos, sin entrar al núcleo.
    final rows = size.height < 560 ? 2 : 3;
    for (var row = 0; row < rows; row++) {
      final y = top
          ? pad + row * (height + gap)
          : math.max(pad, size.height - height - pad) - row * (height + gap);
      if (y < pad || y + height > size.height - pad) continue;
      // Evita filas que caigan en la franja central de puntos.
      final ny = (y + height / 2) / size.height;
      if (ny > 0.32 && ny < 0.68) continue;
      final stagger = row.isOdd ? (width + gap) * 0.5 : 0.0;
      for (
        var left = pad + stagger;
        left <= maxLeft + 0.1;
        left += width + gap
      ) {
        slots.add(Rect.fromLTWH(left, y, width, height));
      }
    }
    return slots;
  }

  final slots = [...bandSlots(top: true), ...bandSlots(top: false)];
  final used = List<bool>.filled(slots.length, false);
  final assigned = List<Rect?>.filled(anchors.length, null);

  final order = List<int>.generate(anchors.length, (i) => i)
    ..sort((a, b) {
      // Primero los más centrados: necesitan tag en el borde con más cuidado.
      final ca =
          (anchors[a] - Offset(size.width / 2, size.height / 2)).distance;
      final cb =
          (anchors[b] - Offset(size.width / 2, size.height / 2)).distance;
      return cb.compareTo(ca);
    });

  for (final index in order) {
    final anchor = anchors[index];
    final preferTop = anchor.dy >= size.height * 0.5;
    var best = -1;
    var bestScore = double.infinity;
    for (var s = 0; s < slots.length; s++) {
      if (used[s]) continue;
      final slot = slots[s];
      if (overlapsBeacon(slot)) continue;
      final onTop = slot.top < size.height * 0.35;
      final bandBias = (preferTop == onTop) ? 0.0 : 90.0;
      final dist = (slot.center - anchor).distance;
      final score = dist + bandBias;
      if (score < bestScore) {
        bestScore = score;
        best = s;
      }
    }
    if (best >= 0) {
      used[best] = true;
      assigned[index] = slots[best];
    }
  }

  final placed = <Rect>[];
  for (var index = 0; index < anchors.length; index++) {
    if (assigned[index] != null) {
      placed.add(assigned[index]!);
      continue;
    }
    // Reservas libres aunque toquen menos; luego se empujan.
    final preferTop = anchors[index].dy >= size.height * 0.5;
    final y = preferTop ? pad : math.max(pad, size.height - height - pad);
    var left = pad;
    var rect = Rect.fromLTWH(left, y, width, height);
    var guard = 0;
    while ((overlapsAny(rect, placed) || overlapsBeacon(rect)) && guard < 40) {
      left += width + gap;
      if (left > size.width - width - pad) {
        left = pad;
        final altY = preferTop
            ? pad + height + gap
            : math.max(pad, y - height - gap);
        rect = Rect.fromLTWH(left, altY, width, height);
      } else {
        rect = Rect.fromLTWH(left, y, width, height);
      }
      guard++;
    }
    placed.add(rect);
  }

  // Empuje sutil: fichas lejos de beacons y entre sí.
  final separated = _separateChipsFromBeacons(placed, anchors, size);
  return _dedupeChipSlots(separated, size, width, height);
}

List<Rect> _dedupeChipSlots(
  List<Rect> chips,
  Size size,
  double width,
  double height,
) {
  const pad = 10.0;
  const gap = 8.0;
  final result = [for (final c in chips) c];
  for (var i = 0; i < result.length; i++) {
    for (var j = 0; j < i; j++) {
      if (!result[i].inflate(2).overlaps(result[j])) continue;
      // Busca hueco libre en bandas.
      var placed = false;
      for (final topBand in [true, false]) {
        final rows = 4;
        for (var row = 0; row < rows && !placed; row++) {
          final y = topBand
              ? pad + row * (height + gap)
              : math.max(pad, size.height - height - pad) -
                    row * (height + gap);
          if (y < pad || y + height > size.height - pad) continue;
          final ny = (y + height / 2) / size.height;
          if (ny > 0.34 && ny < 0.66) continue;
          for (
            var left = pad;
            left <= size.width - width - pad + 0.1;
            left += width + gap
          ) {
            final candidate = Rect.fromLTWH(left, y, width, height);
            final hits = result.asMap().entries.any(
              (e) => e.key != i && e.value.inflate(2).overlaps(candidate),
            );
            if (hits) continue;
            result[i] = candidate;
            placed = true;
            break;
          }
        }
      }
    }
  }
  return result;
}

List<Rect> _separateChipsFromBeacons(
  List<Rect> chips,
  List<Offset> anchors,
  Size size,
) {
  const pad = 10.0;
  const clearR = 52.0;
  final result = [for (final c in chips) c];
  for (var round = 0; round < 10; round++) {
    for (var i = 0; i < result.length; i++) {
      var rect = result[i];
      for (final anchor in anchors) {
        final zone = Rect.fromCircle(center: anchor, radius: clearR);
        if (!rect.overlaps(zone)) continue;
        final delta = rect.center - anchor;
        final dir = delta.distance < 0.001
            ? const Offset(0, -1)
            : delta / delta.distance;
        final vertical = Offset(dir.dx * 0.2, dir.dy >= 0 ? 1.0 : -1.0);
        final norm = vertical.distance < 0.001
            ? const Offset(0, -1)
            : vertical / vertical.distance;
        rect = rect.shift(norm * 14);
      }
      for (var j = 0; j < result.length; j++) {
        if (i == j) continue;
        if (!rect.inflate(4).overlaps(result[j])) continue;
        final delta = rect.center - result[j].center;
        final dir = delta.distance < 0.001
            ? Offset(i.isEven ? 1.0 : -1.0, 0)
            : delta / delta.distance;
        rect = rect.shift(Offset(dir.dx * 12, dir.dy * 8));
      }
      final left = rect.left.clamp(
        pad,
        math.max(pad, size.width - pad - rect.width),
      );
      var top = rect.top.clamp(
        pad,
        math.max(pad, size.height - pad - rect.height),
      );
      // Si quedó en el núcleo, mándala a la banda más cercana.
      final ny = (top + rect.height / 2) / size.height;
      if (ny > 0.34 && ny < 0.66) {
        top = ny < 0.5
            ? pad.toDouble()
            : math.max(pad, size.height - pad - rect.height).toDouble();
      }
      result[i] = Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        rect.width,
        rect.height,
      );
    }
  }
  return result;
}

/// Al abrir una ficha, crece y empuja las demás para que no se pisen.
@visibleForTesting
List<Rect> repelCaptureChips({
  required List<Rect> chips,
  required int? selected,
  required Size size,
  required double expandedWidth,
  required double expandedHeight,
  double bottomClearance = 8,
}) {
  if (chips.isEmpty) return const [];
  final result = [for (final chip in chips) chip];
  if (selected == null || selected < 0 || selected >= chips.length) {
    return result;
  }

  const pad = 8.0;
  final bottomLimit = size.height - bottomClearance;
  final focusW = expandedWidth
      .clamp(80.0, math.max(80.0, size.width - pad * 2))
      .toDouble();
  final focusH = expandedHeight
      .clamp(50.0, math.max(50.0, size.height - pad * 2))
      .toDouble();
  var focusLeft = chips[selected].left;
  if (focusLeft + focusW > size.width - pad) {
    focusLeft = size.width - pad - focusW;
  }
  focusLeft = focusLeft
      .clamp(pad, math.max(pad, size.width - pad - focusW))
      .toDouble();
  final focusTop = seatCaptureChipTop(
    preferredTop: chips[selected].top,
    height: focusH,
    maxBottom: bottomLimit,
    minTop: pad,
  );
  final focus = Rect.fromLTWH(focusLeft, focusTop, focusW, focusH);
  result[selected] = focus;

  Offset clampOrigin(Rect rect) {
    return Offset(
      rect.left.clamp(pad, math.max(pad, size.width - pad - rect.width)),
      rect.top.clamp(pad, math.max(pad, bottomLimit - rect.height)),
    );
  }

  for (var round = 0; round < 14; round++) {
    for (var i = 0; i < result.length; i++) {
      if (i == selected) continue;
      var rect = result[i];
      final blockers = <Rect>[
        focus.inflate(12),
        for (var j = 0; j < result.length; j++)
          if (j != i && j != selected) result[j].inflate(5),
      ];
      for (final blocker in blockers) {
        if (!rect.overlaps(blocker)) continue;
        var delta = rect.center - blocker.center;
        if (delta.distance < 0.001) {
          delta = Offset(
            i.isEven ? 1.0 : -1.0,
            rect.center.dy < focus.center.dy ? -1.0 : 1.0,
          );
        }
        // Empuja más en vertical para mantener bandas arriba/abajo.
        final push = Offset(
          (delta.dx / delta.distance) * 10,
          (delta.dy / delta.distance) * 16,
        );
        rect = rect.shift(push);
        final origin = clampOrigin(rect);
        rect = Rect.fromLTWH(origin.dx, origin.dy, rect.width, rect.height);
      }
      result[i] = rect;
    }
  }
  return result;
}

/// Top de una ficha abierta. Si no cabe sobre [maxBottom], sube hasta
/// dejar el borde inferior en ese límite.
@visibleForTesting
double seatCaptureChipTop({
  required double preferredTop,
  required double height,
  required double maxBottom,
  required double minTop,
}) {
  var top = preferredTop;
  if (top + height > maxBottom) top = maxBottom - height;
  if (top < minTop) top = minTop;
  if (top + height > maxBottom) top = maxBottom - height;
  return top;
}

/// Hueco del chip Resumen y tope de la ficha abierta (10 px por encima).
({double handleBottom, double cardClearance}) captureResumenInsets({
  required double bottomInset,
  required double handleHeight,
  double gap = 10,
}) {
  final handleBottom = math.max(88.0, bottomInset - 4);
  return (
    handleBottom: handleBottom,
    cardClearance: handleBottom + handleHeight + gap,
  );
}

/// Cada ventana entra completa en [bounds]. Si hay aire, no tapa loggers ni el minimapa.
/// Las siguientes bajan un poco para que se vea la barra de la anterior.
@visibleForTesting
List<Rect> placeOpenWindowFrames({
  required int count,
  required Rect bounds,
  List<Rect> obstacles = const [],
  double windowWidth = captureWindowWidth,
  double windowHeight = captureWindowHeight,
  double cascade = 36,
}) {
  if (count <= 0 || bounds.width <= 0 || bounds.height <= 0) {
    return const [];
  }
  final h = math.min(windowHeight, bounds.height);
  final widest = math.min(windowWidth, bounds.width);
  final widths = <double>[
    for (final candidate in [widest, 330.0, 300.0, 280.0])
      if (candidate <= widest + 0.1 && candidate >= 280) candidate,
  ];
  if (widths.isEmpty) widths.add(widest);
  final slack = bounds.height - h >= 48 ? 20.0 : 0.0;

  bool hits(Rect rect) {
    for (final obstacle in obstacles) {
      if (rect.overlaps(obstacle.inflate(4))) return true;
    }
    return false;
  }

  Rect fit(double left, double top, double width) {
    final maxLeft = math.max(bounds.left, bounds.right - width);
    final l = left.clamp(bounds.left, maxLeft).toDouble();
    final t = top
        .clamp(bounds.top, math.max(bounds.top, bounds.bottom - h))
        .toDouble();
    return Rect.fromLTWH(l, t, width, h);
  }

  final placed = <Rect>[];
  for (var i = 0; i < count; i++) {
    Rect? chosen;
    for (final width in widths) {
      if (chosen != null) break;
      final maxLeft = math.max(bounds.left, bounds.right - width);
      final maxTop = math.max(bounds.top, bounds.bottom - h - slack);
      for (var col = 0; col < 16 && chosen == null; col++) {
        final left = maxLeft - col * 48;
        for (var row = 0; row < 24 && chosen == null; row++) {
          final top = bounds.top + row * 32 + i * cascade;
          if (slack > 0 && top > maxTop + 0.5) continue;
          final rect = fit(left, top, width);
          if (rect.bottom > bounds.bottom - slack + 0.5) continue;
          if (hits(rect) ||
              placed.any((other) => other.overlaps(rect.inflate(-6)))) {
            continue;
          }
          chosen = rect;
        }
      }
    }
    final fallbackW = widths.first;
    placed.add(
      chosen ??
          fit(
            bounds.right - fallbackW,
            bounds.top + 12 + i * cascade,
            fallbackW,
          ),
    );
  }
  return placed;
}

/// Mosaico inferior de ventanas compactas (HOME web). Filas de abajo hacia arriba.
@visibleForTesting
List<Rect> layoutPointWindows({
  required Size area,
  required int count,
  double windowWidth = 340,
  double windowHeight = 228,
  double gap = 12,
  double bottomInset = 8,
  double leftInset = 0,
}) {
  if (count <= 0 ||
      area.width <= 0 ||
      area.height <= 0 ||
      windowWidth <= 0 ||
      windowHeight <= 0) {
    return const [];
  }
  final usableW = math.max(0.0, area.width - leftInset);
  final columns = math.max(1, ((usableW + gap) / (windowWidth + gap)).floor());
  final rects = <Rect>[];
  for (var i = 0; i < count; i++) {
    final col = i % columns;
    final row = i ~/ columns;
    final left = leftInset + col * (windowWidth + gap);
    final bottom = area.height - bottomInset - row * (windowHeight + gap);
    final top = bottom - windowHeight;
    rects.add(Rect.fromLTWH(left, top, windowWidth, windowHeight));
  }
  return rects;
}

/// Ventanas que caben en un escritorio. El resto pasa al siguiente.
@visibleForTesting
({int capacity, int pages, List<Rect> rects}) layoutWindowDesktops({
  required Size area,
  required int count,
  int desktop = 0,
  double windowWidth = 340,
  double windowHeight = 228,
  double gap = 12,
  double bottomInset = 8,
  double leftInset = 0,
  int? limit,
}) {
  if (count <= 0 || area.width <= 0 || area.height <= 0) {
    return (capacity: 1, pages: 1, rects: const <Rect>[]);
  }
  final usableW = math.max(windowWidth, area.width - leftInset);
  final columns = math.max(1, ((usableW + gap) / (windowWidth + gap)).floor());
  final usableH = math.max(windowHeight, area.height - bottomInset);
  final rows = math.max(1, ((usableH + gap) / (windowHeight + gap)).floor());
  final fitted = math.max(1, columns * rows);
  final capacity = limit == null
      ? fitted
      : math.max(1, math.min(limit, fitted));
  final pages = math.max(1, (count / capacity).ceil());
  final page = desktop.clamp(0, pages - 1);
  final start = page * capacity;
  final shown = math.max(0, math.min(capacity, count - start));
  final laid = layoutPointWindows(
    area: area,
    count: shown,
    windowWidth: windowWidth,
    windowHeight: windowHeight,
    gap: gap,
    bottomInset: bottomInset,
    leftInset: leftInset,
  );
  return (capacity: capacity, pages: pages, rects: laid);
}

class _SchemeMinimap extends StatefulWidget {
  const _SchemeMinimap({
    required this.plates,
    required this.hub,
    required this.selected,
  });

  final List<Rect> plates;
  final Rect hub;
  final int? selected;

  @override
  State<_SchemeMinimap> createState() => _SchemeMinimapState();
}

class _SchemeMinimapState extends State<_SchemeMinimap> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final width = _open ? 132.0 : 36.0;
    final height = _open ? 88.0 : 36.0;
    return MouseRegion(
      onEnter: (_) {
        if (!_open) setState(() => _open = true);
      },
      onExit: (_) {
        if (_open) setState(() => _open = false);
      },
      child: AnimatedContainer(
        key: const ValueKey('capture-minimap'),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        alignment: Alignment.topRight,
        decoration: BoxDecoration(
          color: _open ? const Color(0xC0081216) : const Color(0x00081216),
          borderRadius: BorderRadius.circular(_open ? 10 : 8),
        ),
        child: CustomPaint(
          painter: _MinimapPainter(
            plates: widget.plates,
            hub: widget.hub,
            selected: widget.selected,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  const _MinimapPainter({
    required this.plates,
    required this.hub,
    required this.selected,
  });

  final List<Rect> plates;
  final Rect hub;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (plates.isEmpty && hub.isEmpty) return;
    var bounds = hub.isEmpty ? plates.first : hub;
    for (final plate in plates) {
      bounds = bounds.expandToInclude(plate);
    }
    bounds = bounds.inflate(8);
    Offset map(Offset point) {
      final sx = bounds.width <= 0
          ? 0.0
          : (point.dx - bounds.left) / bounds.width;
      final sy = bounds.height <= 0
          ? 0.0
          : (point.dy - bounds.top) / bounds.height;
      return Offset(sx * size.width, sy * size.height);
    }

    final compact = size.shortestSide < 50;
    if (!hub.isEmpty) {
      final c = map(hub.center);
      final s = compact ? 2.2 : 3.4;
      final cube = Path()
        ..moveTo(c.dx, c.dy - s)
        ..lineTo(c.dx + s, c.dy)
        ..lineTo(c.dx, c.dy + s * 0.7)
        ..lineTo(c.dx - s, c.dy)
        ..close();
      canvas.drawPath(cube, Paint()..color = IkoluColors.cyan);
    }
    final dot = compact ? 1.15 : 2.1;
    for (var i = 0; i < plates.length; i++) {
      final c = map(plates[i].center);
      final active = i == selected;
      canvas.drawCircle(
        c,
        active ? dot + 0.8 : dot,
        Paint()
          ..color = active ? const Color(0xFFFFC46B) : const Color(0xFF9AD7D0),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) => true;
}

class _LoggerNode extends StatelessWidget {
  const _LoggerNode({
    required this.point,
    required this.selected,
    required this.onTap,
    this.clock,
  });

  final Map<String, dynamic> point;
  final bool selected;
  final VoidCallback onTap;
  final ValueNotifier<double>? clock;

  @override
  Widget build(BuildContext context) {
    return CaptureLoggerPlate(
      point: point,
      selected: selected,
      onTap: onTap,
      clock: clock,
      tapKey: ValueKey('capture-node-${_pointKey(point)}'),
    );
  }
}

class _PageStep extends StatelessWidget {
  const _PageStep({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconFirst = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool iconFirst;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 18);
    final text = Text(label, style: const TextStyle(fontSize: 12));
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFE7F4F2),
        backgroundColor: const Color(0xFF14343C).withValues(alpha: 0.72),
        minimumSize: const Size(96, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconFirst) iconWidget,
          if (iconFirst) const SizedBox(width: 2),
          text,
          if (!iconFirst) const SizedBox(width: 2),
          if (!iconFirst) iconWidget,
        ],
      ),
    );
  }
}

/// Núcleo SMARTHYDRO. Si el servicio responde, el cubo se hincha con energía.
/// Si no, parpadea apagado. No escribe el estado en texto.
class _DataSmartCore extends StatelessWidget {
  const _DataSmartCore({this.clock, this.apiOnline, this.hover = 0});

  final ValueNotifier<double>? clock;
  final bool? apiOnline;
  final double hover;

  @override
  Widget build(BuildContext context) {
    final online = apiOnline;
    final alive = online == true;
    final accent = alive ? const Color(0xFF7EE0D0) : const Color(0xFF9AB0B1);
    final status = alive
        ? 'con energía'
        : online == false
        ? 'apagado'
        : 'en espera';

    Widget core(double seconds) {
      final energy = captureHubEnergy(
        online: online,
        seconds: seconds,
        motion: clock != null,
      );
      return Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _HubCubePainter(
                seconds: seconds,
                accent: accent,
                hover: hover,
                swell: energy.swell,
                power: energy.power,
                jets: energy.jets,
                alive: alive,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const Text(
            'SMARTHYDRO',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFE7F4F2),
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
        ],
      );
    }

    return Semantics(
      container: true,
      button: true,
      label: 'SMARTHYDRO, $status. Ver disponibilidad y rendimiento',
      child: KeyedSubtree(
        key: const ValueKey('capture-hub'),
        child: clock == null
            ? core(1.2)
            : ValueListenableBuilder<double>(
                valueListenable: clock!,
                builder: (context, seconds, _) => core(seconds),
              ),
      ),
    );
  }
}

/// Respiración del cubo. Activo se hincha poco; apagado baja la luz y parpadea.
/// [jets] es la fuerza de las líneas que salen al crecer y al achicar.
@visibleForTesting
({double swell, double power, double jets}) captureHubEnergy({
  required bool? online,
  required double seconds,
  required bool motion,
}) {
  if (online == true) {
    if (!motion) return (swell: 1, power: 1, jets: 0);
    final angle = seconds * 1.7;
    return (
      swell: 0.5 + 0.5 * math.sin(angle),
      power: 1,
      jets: math.cos(angle).abs(),
    );
  }
  if (online == false) {
    if (!motion) return (swell: 0, power: 0.22, jets: 0);
    final blink = 0.5 + 0.5 * math.sin(seconds * math.pi * 2 / 1.35);
    return (swell: 0, power: 0.08 + 0.55 * blink, jets: 0);
  }
  return (swell: 0, power: 0.4, jets: 0);
}

/// Cubo isométrico de aristas iguales, centrado en [size] y dentro de él.
///
/// Las tres aristas miden lo mismo y salen a 30°. Así el rombo de arriba
/// es simétrico y el dibujo cabe en la card del núcleo.
@visibleForTesting
({Offset center, double edge}) captureHubCubeFrame(Size size) {
  final margin = math.max(3.0, size.shortestSide * 0.06);
  final roomW = math.max(0.0, size.width - margin * 2);
  final roomH = math.max(0.0, size.height - margin * 2);
  final edge = math.min(roomW / math.sqrt(3), roomH / 2);
  return (center: size.center(Offset.zero), edge: edge);
}

/// Cubo de vidrio. Cabe en la card de 80, con aristas iguales.
class _HubCubePainter extends CustomPainter {
  _HubCubePainter({
    required this.seconds,
    required this.accent,
    required this.swell,
    required this.power,
    required this.jets,
    required this.alive,
    this.hover = 0,
  });

  final double seconds;
  final Color accent;
  final double swell;
  final double power;
  final double jets;
  final bool alive;
  final double hover;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final frame = captureHubCubeFrame(size);
    final c = frame.center;
    final lift = hover.clamp(0.0, 1.0);
    final breath = swell.clamp(0.0, 1.0);
    final gain = power.clamp(0.0, 1.0);
    final scale = alive
        ? (0.88 + 0.07 * breath + 0.02 * lift)
        : (0.74 + 0.02 * lift);
    final e = frame.edge * scale;
    if (e < 1) return;
    final dx = e * math.sqrt(3) / 2;
    final dy = e / 2;
    final vx = Offset(dx, -dy);
    final vy = Offset(-dx, -dy);
    final vz = const Offset(0, 1) * e;
    final top = [c + vx + vy, c + vx, c, c + vy];
    final left = [c + vy, c, c + vz, c + vy + vz];
    final right = [c, c + vx, c + vx + vz, c + vz];

    Path face(List<Offset> pts) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final point in pts.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      return path;
    }

    Rect shade(List<Offset> pts) {
      var minX = pts.first.dx;
      var maxX = minX;
      var minY = pts.first.dy;
      var maxY = minY;
      for (final point in pts.skip(1)) {
        minX = math.min(minX, point.dx);
        maxX = math.max(maxX, point.dx);
        minY = math.min(minY, point.dy);
        maxY = math.max(maxY, point.dy);
      }
      return Rect.fromLTRB(
        minX,
        minY,
        math.max(maxX, minX + 1),
        math.max(maxY, minY + 1),
      );
    }

    Paint glass(List<Color> colors, List<Offset> pts) => Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          for (final color in colors) color.withValues(alpha: color.a * gain),
        ],
      ).createShader(shade(pts));

    canvas.drawPath(
      face(left),
      glass([
        const Color(0xFFB7F6FF).withValues(alpha: 0.16),
        const Color(0xFF1C4E58).withValues(alpha: 0.22),
        const Color(0xFF081216).withValues(alpha: 0.05),
      ], left),
    );
    canvas.drawPath(
      face(right),
      glass([
        const Color(0xFF7ED4E8).withValues(alpha: 0.10),
        const Color(0xFF10213A).withValues(alpha: 0.20),
        const Color(0xFF081216).withValues(alpha: 0.04),
      ], right),
    );
    canvas.drawPath(
      face(top),
      glass([
        Colors.white.withValues(alpha: 0.28),
        const Color(0xFF9AE7F2).withValues(alpha: 0.16),
        const Color(0xFF7EE0D0).withValues(alpha: 0.05),
      ], top),
    );

    canvas.save();
    canvas.clipPath(face(top));
    final vein = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.white.withValues(alpha: 0.16 * gain);
    for (final t in const [0.28, 0.5, 0.72]) {
      canvas.drawLine(
        Offset.lerp(top[3], top[2], t)!,
        Offset.lerp(top[0], top[1], t)!,
        vein,
      );
    }
    canvas.restore();

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15 + 0.45 * lift
      ..strokeJoin = StrokeJoin.round
      ..color = Color.lerp(
        Colors.white,
        accent,
        alive ? 0.62 : 0.12,
      )!.withValues(alpha: (0.55 + 0.28 * lift) * gain);
    canvas.drawPath(face(top), rim);
    canvas.drawPath(
      face(left),
      rim..color = accent.withValues(alpha: (0.22 + 0.16 * lift) * gain),
    );
    canvas.drawPath(
      face(right),
      rim..color = accent.withValues(alpha: (0.16 + 0.14 * lift) * gain),
    );
    if (alive && gain > 0.2) {
      List<Offset> inset(List<Offset> pts) {
        final mid = pts.fold<Offset>(Offset.zero, (sum, point) => sum + point);
        final center = mid / pts.length.toDouble();
        return [for (final point in pts) Offset.lerp(point, center, 0.2)!];
      }

      final intake = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 0.85
        ..color = accent.withValues(alpha: (0.16 + 0.22 * breath) * gain);
      canvas.drawPath(face(inset(top)), intake);
      canvas.drawPath(
        face(inset(left)),
        intake..color = accent.withValues(alpha: 0.1 * gain),
      );
      canvas.drawPath(
        face(inset(right)),
        intake..color = accent.withValues(alpha: 0.08 * gain),
      );
    }

    void glow(Offset at, double radius, double alpha) {
      final charge = alive ? (0.78 + 0.22 * breath) : 1.0;
      final bright = alpha * (1 + 0.45 * lift) * gain * charge;
      if (bright < 0.03 || radius < 0.5) return;
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accent.withValues(alpha: bright),
              const Color(0xFFE7FBFF).withValues(alpha: bright * 0.28),
              accent.withValues(alpha: 0),
            ],
            stops: const [0, 0.42, 1],
          ).createShader(Rect.fromCircle(center: at, radius: radius)),
      );
    }

    double wave(double speed, double phase) =>
        0.5 + 0.5 * math.sin(seconds * speed + phase);

    glow(
      Offset.lerp(top[3], top[0], wave(0.62, 0))!,
      8.5 * (0.72 + 0.28 * wave(1.15, 0.4)),
      0.34 + 0.22 * wave(0.9, 1.2),
    );
    glow(
      Offset.lerp(top[0], top[1], wave(0.48, 2.1))!,
      6.2 * (0.7 + 0.3 * wave(0.8, 2.4)),
      0.22 + 0.16 * wave(1.05, 0.2),
    );
    glow(
      Offset.lerp(left[1], left[2], wave(0.41, 4.0))!,
      5.4 * (0.75 + 0.25 * wave(0.7, 3.3)),
      0.16 + 0.12 * wave(0.55, 1.7),
    );
    glow(
      top[0],
      4.2 * (0.8 + 0.2 * wave(0.5, 0.6)),
      0.18 + 0.1 * wave(0.45, 2.8),
    );
    final jet = jets.clamp(0.0, 1.0);
    if (alive && jet > 0.08) {
      final thread = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.16 + 0.42 * jet * gain);
      for (final vertex in [top[0], top[1], top[3]]) {
        final into = c - vertex;
        final length = into.distance;
        if (length < 1) continue;
        final dir = into / length;
        canvas.drawLine(vertex, vertex + dir * (1.1 + 2.6 * jet), thread);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HubCubePainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.accent != accent ||
      oldDelegate.hover != hover ||
      oldDelegate.swell != swell ||
      oldDelegate.power != power ||
      oldDelegate.jets != jets ||
      oldDelegate.alive != alive;
}

/// Crece desde [anchor]. Con zoom, un arrastre en vacío mueve la red.
class _SchemeZoom extends StatefulWidget {
  const _SchemeZoom({
    required this.zoom,
    required this.shown,
    required this.pan,
    required this.anchor,
    required this.enabled,
    this.interactive = true,
    required this.onChanged,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.child,
  });

  /// Zoom pedido. Los gestos se acumulan sobre este valor.
  final double zoom;

  /// Zoom que se está viendo. Va llegando a [zoom].
  final double shown;

  /// Desplazamiento en pantalla, para recorrer lo que el zoom deja fuera.
  final Offset pan;

  /// Punto que se queda quieto al acercar, en coordenadas de este hijo.
  final Offset anchor;

  final bool enabled;

  /// El piso recibe rueda y arrastre. La red de encima solo pinta.
  final bool interactive;
  final ValueChanged<double> onChanged;
  final ValueChanged<Offset> onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final Widget child;

  @override
  State<_SchemeZoom> createState() => _SchemeZoomState();
}

class _SchemeZoomState extends State<_SchemeZoom> {
  var _baseZoom = captureSchemeZoomMin;
  var _panning = false;

  void _commit(double next) {
    widget.onChanged(
      next.clamp(captureSchemeZoomMin, captureSchemeZoomMax).toDouble(),
    );
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final dy = event.scrollDelta.dy;
      if (dy == 0 || !dy.isFinite) return;
      _commit(widget.zoom * math.exp(-dy * 0.0016));
      return;
    }
    if (event is PointerScaleEvent) {
      if (!event.scale.isFinite || event.scale <= 0) return;
      _commit(widget.zoom * event.scale);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.shown;
    final pan = widget.pan;
    final anchor = widget.anchor;
    final moved =
        pan.distance > 0.4 || (shown - captureSchemeZoomMin).abs() >= 0.001;
    final child = moved
        ? Transform(
            alignment: Alignment.topLeft,
            transform: Matrix4.identity()
              ..translateByDouble(pan.dx, pan.dy, 0, 1)
              ..translateByDouble(anchor.dx, anchor.dy, 0, 1)
              ..scaleByDouble(shown, shown, 1, 1)
              ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1),
            child: widget.child,
          )
        : widget.child;
    if (!widget.enabled) return child;
    // La red de encima tapa el piso. La rueda sobre un logger o el cubo
    // igual acerca, y no abre el estado de la red. El arrastre sigue abajo.
    if (!widget.interactive) {
      return Listener(onPointerSignal: _onSignal, child: child);
    }
    return Listener(
      onPointerSignal: _onSignal,
      child: GestureDetector(
        onScaleStart: (details) {
          _baseZoom = widget.zoom;
          widget.onPanStart(details.localFocalPoint);
          _panning = true;
        },
        onScaleUpdate: (details) {
          if (details.pointerCount >= 2) {
            _panning = false;
            _commit(_baseZoom * details.scale);
            return;
          }
          if (!_panning) return;
          widget.onPanUpdate(details.focalPointDelta);
        },
        onScaleEnd: (_) => _panning = false,
        child: child,
      ),
    );
  }
}

/// Anillo de agua corto al acercar y al alejar. Sin desenfoque.
class _GrowSwellPainter extends CustomPainter {
  _GrowSwellPainter({
    required this.center,
    required this.amount,
    required this.direction,
  });

  final Offset center;
  final double amount;

  /// 1 abre el anillo. -1 lo cierra.
  final double direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (amount < 0.02 || size.isEmpty) return;
    final travel = direction < 0
        ? amount.clamp(0.0, 1.0)
        : (1 - amount).clamp(0.0, 1.0);
    final reach = math.min(size.width, size.height);
    final radius = 30 + travel * reach * 0.38;
    final alpha = amount * 0.20;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF7EE7F0).withValues(alpha: alpha);
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(
      center,
      radius * 0.64,
      ring
        ..strokeWidth = 1.05
        ..color = const Color(0xFFD7F7FF).withValues(alpha: alpha * 0.5),
    );
    canvas.drawCircle(
      center,
      radius * 0.36,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF7EE7F0).withValues(alpha: alpha * 0.4),
            const Color(0xFF7EE7F0).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 0.36)),
    );
  }

  @override
  bool shouldRepaint(covariant _GrowSwellPainter oldDelegate) =>
      oldDelegate.amount != amount ||
      oldDelegate.center != center ||
      oldDelegate.direction != direction;
}

class _ZoomStep extends StatelessWidget {
  const _ZoomStep({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xD6081216),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 18,
              color: const Color(
                0xFFE7F4F2,
              ).withValues(alpha: enabled ? 0.92 : 0.28),
            ),
          ),
        ),
      ),
    );
  }
}

/// Estado de la red, centrado en la sección del esquema.
class _SchemeStatsLayer extends StatelessWidget {
  const _SchemeStatsLayer({
    required this.points,
    required this.apiOnline,
    required this.onClose,
  });

  final List<Map<String, dynamic>> points;
  final bool? apiOnline;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Color(0xB3081216)),
          ),
        ),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: motion
                ? const Duration(milliseconds: 180)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, t, child) {
              return Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _SchemeStats(
                points: points,
                apiOnline: apiOnline,
                onClose: onClose,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SchemeStats extends StatelessWidget {
  const _SchemeStats({
    required this.points,
    required this.apiOnline,
    required this.onClose,
  });

  final List<Map<String, dynamic>> points;
  final bool? apiOnline;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final mix = captureLinkCounts(points);
    return Material(
      key: const ValueKey('capture-hub-card'),
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xE6081216),
          ),
          child: HydroGlassLight(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
            radius: 18,
            strength: 1.12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Estado de la red',
                        style: TextStyle(
                          color: Color(0xFFF4FBFA),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('capture-hub-card-close'),
                      tooltip: 'Cerrar',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: const Color(0xFFB7C6C4),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  captureServicePulse(points),
                  style: const TextStyle(
                    color: Color(0xFFC5D5D4),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _CountStat(
                      label: 'Conectado',
                      value: mix.connected,
                      color: IkoluColors.connected,
                    ),
                    const SizedBox(width: 8),
                    _CountStat(
                      label: 'Advertencia',
                      value: mix.warning,
                      color: IkoluColors.warning,
                    ),
                    const SizedBox(width: 8),
                    _CountStat(
                      label: 'Incidencia',
                      value: mix.incident,
                      color: IkoluColors.incident,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _MetricBlock(
                  title: 'Disponibilidad',
                  body: captureAvailabilityLine(points, apiOnline: apiOnline),
                ),
                const SizedBox(height: 10),
                _MetricBlock(
                  title: 'Rendimiento',
                  body: capturePerformanceLine(points),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountStat extends StatelessWidget {
  const _CountStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFB7C6C4), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF9CC8C2),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          body,
          style: const TextStyle(
            color: Color(0xFFF4FBFA),
            fontSize: 13.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _NetworkHeader extends StatelessWidget {
  const _NetworkHeader({
    required this.points,
    required this.locationMode,
    this.askBar,
  });

  final List<Map<String, dynamic>> points;
  final bool locationMode;
  final Widget? askBar;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: askBar != null
              ? askBar!
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      locationMode ? 'Ubicaciones' : 'Esquema de telemetría',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF4F8F6),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      captureNetworkSubtitle(points),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8FA3A4),
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      captureServicePulse(points),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFC5D5D4),
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Red o Mapa, junto al zoom. Un toque cambia de modo.
class _SchemeMode extends StatelessWidget {
  const _SchemeMode({required this.map, required this.onPressed});

  final bool map;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: map ? 'Ver la red' : 'Ver el mapa',
      child: Material(
        key: const ValueKey('capture-location-toggle'),
        color: const Color(0xD6081216),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onPressed,
          child: SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _chip('Red', active: !map),
                  _chip('Mapa', active: map),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, {required bool active}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? const Color(0xFF14343C) : const Color(0x00000000),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFFE7F4F2) : const Color(0xFF8FA3A4),
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pasa un rect del esquema (coordenadas del tablero) a la pantalla.
/// `pantalla = ancla + pan + (contenido - ancla) * zoom`.
@visibleForTesting
Rect captureSchemeScreenRect({
  required Rect content,
  required Offset anchor,
  required Offset pan,
  required double zoom,
}) {
  final scale = zoom.isFinite && zoom > 0 ? zoom : 1.0;
  return Rect.fromLTRB(
    anchor.dx + pan.dx + (content.left - anchor.dx) * scale,
    anchor.dy + pan.dy + (content.top - anchor.dy) * scale,
    anchor.dx + pan.dx + (content.right - anchor.dx) * scale,
    anchor.dy + pan.dy + (content.bottom - anchor.dy) * scale,
  );
}

/// Dónde se abre la ficha. El borde que mira al logger no se suelta de él.
/// Entre los lados libres gana el que menos se desliza, para que la muesca
/// quede frente al centro de ese logger. [aim] es ese punto del borde
/// (0 arriba o izquierda, 1 abajo o derecha).
@visibleForTesting
({Rect rect, CaptureBriefSide side, double aim}) captureBriefSlot({
  required Rect plate,
  required Rect bounds,
  List<Rect> obstacles = const [],
  double width = captureBriefWidth,
  double height = captureBriefHeight,
  double gap = 10,
}) {
  double roomOf(CaptureBriefSide side) {
    switch (side) {
      case CaptureBriefSide.right:
        return bounds.right - plate.right - gap;
      case CaptureBriefSide.left:
        return plate.left - bounds.left - gap;
      case CaptureBriefSide.below:
        return bounds.bottom - plate.bottom - gap;
      case CaptureBriefSide.above:
        return plate.top - bounds.top - gap;
    }
  }

  bool horizontal(CaptureBriefSide side) =>
      side == CaptureBriefSide.right || side == CaptureBriefSide.left;

  ({Rect rect, double aim}) place(CaptureBriefSide side) {
    final maxLeft = math.max(bounds.left, bounds.right - width);
    final maxTop = math.max(bounds.top, bounds.bottom - height);
    final Rect rect;
    switch (side) {
      case CaptureBriefSide.right:
        final top = (plate.center.dy - height / 2)
            .clamp(bounds.top, maxTop)
            .toDouble();
        rect = Rect.fromLTWH(plate.right + gap, top, width, height);
      case CaptureBriefSide.left:
        final top = (plate.center.dy - height / 2)
            .clamp(bounds.top, maxTop)
            .toDouble();
        rect = Rect.fromLTWH(plate.left - gap - width, top, width, height);
      case CaptureBriefSide.below:
        final left = (plate.center.dx - width / 2)
            .clamp(bounds.left, maxLeft)
            .toDouble();
        rect = Rect.fromLTWH(left, plate.bottom + gap, width, height);
      case CaptureBriefSide.above:
        final left = (plate.center.dx - width / 2)
            .clamp(bounds.left, maxLeft)
            .toDouble();
        rect = Rect.fromLTWH(left, plate.top - gap - height, width, height);
    }
    final raw = horizontal(side)
        ? (plate.center.dy - rect.top) / height
        : (plate.center.dx - rect.left) / width;
    return (rect: rect, aim: raw.clamp(0.12, 0.88).toDouble());
  }

  bool fits(CaptureBriefSide side, Rect rect) {
    final need = horizontal(side) ? width : height;
    if (roomOf(side) + 0.5 < need) return false;
    if (rect.left < bounds.left - 0.5 || rect.top < bounds.top - 0.5) {
      return false;
    }
    if (rect.right > bounds.right + 0.5 || rect.bottom > bounds.bottom + 0.5) {
      return false;
    }
    if (rect.overlaps(plate)) return false;
    return true;
  }

  bool blocked(Rect rect) {
    for (final block in obstacles) {
      if (rect.overlaps(block)) return true;
    }
    return false;
  }

  // Cuánto hubo que correr la ficha a lo largo del logger para no salir.
  double slideOf(CaptureBriefSide side, Rect rect) {
    switch (side) {
      case CaptureBriefSide.right:
      case CaptureBriefSide.left:
        return (rect.top - (plate.center.dy - height / 2)).abs();
      case CaptureBriefSide.below:
      case CaptureBriefSide.above:
        return (rect.left - (plate.center.dx - width / 2)).abs();
    }
  }

  ({Rect rect, CaptureBriefSide side, double aim})? clear;
  var clearSlide = double.infinity;
  ({Rect rect, CaptureBriefSide side, double aim})? fitted;
  var fittedSlide = double.infinity;
  for (final side in CaptureBriefSide.values) {
    final placed = place(side);
    if (!fits(side, placed.rect)) continue;
    final slide = slideOf(side, placed.rect);
    final candidate = (rect: placed.rect, side: side, aim: placed.aim);
    if (slide < fittedSlide - 0.5) {
      fitted = candidate;
      fittedSlide = slide;
    }
    if (!blocked(placed.rect) && slide < clearSlide - 0.5) {
      clear = candidate;
      clearSlide = slide;
    }
  }
  final chosen = clear ?? fitted;
  if (chosen != null) return chosen;

  var best = CaptureBriefSide.right;
  var bestRoom = roomOf(best);
  for (final side in CaptureBriefSide.values.skip(1)) {
    final space = roomOf(side);
    if (space > bestRoom) {
      best = side;
      bestRoom = space;
    }
  }
  final placed = place(best);
  return (rect: placed.rect, side: best, aim: placed.aim);
}

Rect _clampBriefRect(Rect rect, Rect bounds, double width, double height) {
  final maxLeft = math.max(bounds.left, bounds.right - width);
  final maxTop = math.max(bounds.top, bounds.bottom - height);
  return Rect.fromLTWH(
    rect.left.clamp(bounds.left, maxLeft).toDouble(),
    rect.top.clamp(bounds.top, maxTop).toDouble(),
    width,
    height,
  );
}

/// La ficha del punto visible. Si no está en la página, queda abajo a la izquierda.
@visibleForTesting
({Rect rect, CaptureBriefSide? side, double aim}) captureBriefFrame({
  required int? onPage,
  required List<Rect> plates,
  required Rect hub,
  required Rect bounds,
  required Offset anchor,
  required Offset pan,
  required double zoom,
}) {
  final missing =
      onPage == null ||
      onPage < 0 ||
      onPage >= plates.length ||
      plates[onPage].isEmpty;
  if (missing) {
    return (
      rect: _clampBriefRect(
        Rect.fromLTWH(
          bounds.left + 12,
          bounds.bottom - captureBriefHeight - 8,
          captureBriefWidth,
          captureBriefHeight,
        ),
        bounds,
        captureBriefWidth,
        captureBriefHeight,
      ),
      side: null,
      aim: 0.5,
    );
  }
  Rect map(Rect content) => captureSchemeScreenRect(
    content: content,
    anchor: anchor,
    pan: pan,
    zoom: zoom,
  );
  final obstacles = <Rect>[
    if (!hub.isEmpty) map(hub).inflate(8),
    for (var index = 0; index < plates.length; index++)
      if (index != onPage && !plates[index].isEmpty)
        map(plates[index]).inflate(4),
  ];
  final slot = captureBriefSlot(
    plate: map(plates[onPage]),
    bounds: bounds,
    obstacles: obstacles,
  );
  return (rect: slot.rect, side: slot.side, aim: slot.aim);
}

/// Sale del logger. Al terminar, el layout queda en el tamaño fijo.
class _BriefPop extends StatelessWidget {
  const _BriefPop({
    required this.reveal,
    required this.motion,
    required this.side,
    required this.aim,
    required this.child,
  });

  final Animation<double> reveal;
  final bool motion;
  final CaptureBriefSide? side;
  final double aim;
  final Widget child;

  Alignment get _origin {
    final along = (aim.clamp(0.0, 1.0) * 2 - 1).toDouble();
    switch (side) {
      case CaptureBriefSide.right:
        return Alignment(-1, along);
      case CaptureBriefSide.left:
        return Alignment(1, along);
      case CaptureBriefSide.below:
        return Alignment(along, -1);
      case CaptureBriefSide.above:
        return Alignment(along, 1);
      case null:
        return Alignment.center;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reveal,
      builder: (context, child) {
        if (!motion || reveal.value >= 1) return child!;
        final t = Curves.easeOutCubic.transform(reveal.value.clamp(0.0, 1.0));
        final slide = (1 - t) * 18;
        final offset = switch (side) {
          CaptureBriefSide.right => Offset(-slide, 0),
          CaptureBriefSide.left => Offset(slide, 0),
          CaptureBriefSide.below => Offset(0, -slide),
          CaptureBriefSide.above => Offset(0, slide),
          null => Offset(0, slide * 0.6),
        };
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: offset,
            child: Transform.scale(
              alignment: _origin,
              scale: 0.9 + 0.1 * t,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

Color _briefEdge(Map<String, dynamic> point) {
  switch (pointLinkOf(point)) {
    case PointLink.connected:
      return const Color(0xFF7EE0D0);
    case PointLink.gap:
      return const Color(0xFFFFC46B);
    case PointLink.incident:
      return const Color(0xFFFF847A);
  }
}

class _BriefNotchPainter extends CustomPainter {
  const _BriefNotchPainter({
    required this.side,
    required this.color,
    required this.aim,
  });

  final CaptureBriefSide side;
  final Color color;

  /// 0 es un extremo del borde y 1 el otro. Apunta al centro del logger.
  final double aim;

  @override
  void paint(Canvas canvas, Size size) {
    const depth = 8.0;
    const half = 7.0;
    final along = aim.clamp(0.0, 1.0);
    final path = Path();
    switch (side) {
      case CaptureBriefSide.right:
        final y = size.height * along;
        path
          ..moveTo(0, y - half)
          ..lineTo(-depth, y)
          ..lineTo(0, y + half);
      case CaptureBriefSide.left:
        final y = size.height * along;
        path
          ..moveTo(size.width, y - half)
          ..lineTo(size.width + depth, y)
          ..lineTo(size.width, y + half);
      case CaptureBriefSide.below:
        final x = size.width * along;
        path
          ..moveTo(x - half, 0)
          ..lineTo(x, -depth)
          ..lineTo(x + half, 0);
      case CaptureBriefSide.above:
        final x = size.width * along;
        path
          ..moveTo(x - half, size.height)
          ..lineTo(x, size.height + depth)
          ..lineTo(x + half, size.height);
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BriefNotchPainter oldDelegate) =>
      oldDelegate.side != side ||
      oldDelegate.color != color ||
      oldDelegate.aim != aim;
}

/// Resumen fijo del punto, encima de la grilla.
///
/// El trazo sigue las variables del punto: total en m³, si no caudal,
/// si no nivel. Sin ninguna de esas, no hay gráfico.
class _BoardBrief extends StatefulWidget {
  const _BoardBrief({
    required this.point,
    required this.openTickets,
    required this.onEnter,
    required this.onConfigurePanel,
    required this.onClose,
    this.compliance = const [],
    this.clock,
    this.token,
    this.api,
    this.side,
    this.aim = 0.5,
  });

  final Map<String, dynamic> point;
  final List<Map<String, dynamic>> openTickets;
  final List<Map<String, dynamic>> compliance;
  final ValueNotifier<double>? clock;
  final VoidCallback onEnter;
  final ValueChanged<String> onConfigurePanel;
  final VoidCallback onClose;
  final String? token;
  final SmartHydroApi? api;
  final CaptureBriefSide? side;
  final double aim;

  @override
  State<_BoardBrief> createState() => _BoardBriefState();
}

class _BoardBriefState extends State<_BoardBrief> {
  List<CaptureBriefRow> _rows = const [];
  int _loadToken = 0;
  bool _hot = false;

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  @override
  void didUpdateWidget(covariant _BoardBrief oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pointId(oldWidget.point) != _pointId(widget.point)) _loadSeries();
  }

  Future<void> _loadSeries() async {
    final token = widget.token;
    final api = widget.api;
    final id = _pointId(widget.point);
    final generation = ++_loadToken;
    if (token == null || token.isEmpty || api == null || id == null) {
      if (_rows.isNotEmpty && mounted) setState(() => _rows = const []);
      return;
    }
    try {
      final end = DateTime.now();
      final start = DateTime(
        end.year,
        end.month,
        end.day,
      ).subtract(const Duration(days: 1));
      final rows = await api.pointRecords(
        token,
        id,
        start: start,
        end: end,
        limit: 96,
      );
      if (!mounted || generation != _loadToken) return;
      setState(() => _rows = captureBriefRows(rows));
    } catch (_) {
      if (!mounted || generation != _loadToken) return;
      setState(() => _rows = const []);
    }
  }

  List<({String label, String value})> _facts(Map<String, dynamic> point) {
    final channels = captureBriefChannels(point);
    final facts = <({String label, String value})>[];
    if (channels.flow) {
      final flow = captureFlowOf(point);
      if (flow != null) {
        facts.add((label: 'Caudal', value: '${flow.toStringAsFixed(2)} L/s'));
      }
    }
    final telemetry = point['latest_telemetry'];
    if (telemetry is! Map) return facts;
    if (channels.level) {
      final level = telemetry['water_table'] ?? telemetry['nivel'];
      final levelText = _plain(level);
      if (levelText != null) {
        facts.add((label: 'Nivel', value: '$levelText m'));
      }
    }
    if (channels.total) {
      final total = telemetry['total'] ?? telemetry['total_raw'];
      final totalText = _plain(total);
      if (totalText != null) {
        facts.add((label: 'Acumulado', value: '${_grouped(totalText)} m³'));
      }
    }
    return facts;
  }

  String? _complianceLine(Map<String, dynamic> point) {
    final row = captureComplianceFor(point, widget.compliance);
    if (row == null && !captureHasCompliance(point)) return null;
    final label = captureComplianceLabel(point, compliance: row);
    return switch (label) {
      'Dentro del límite' || 'Cerca del límite' || 'Excede el caudal' => label,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    final link = pointLinkOf(point);
    final tickets = captureTicketsForPoint(point, widget.openTickets);
    final provider = captureProviderLabel(point);
    final frequency = captureFrequencyLabel(point);
    final when = captureMeasuredAt(point);
    final facts = _facts(point);
    final compliance = _complianceLine(point);
    final code = captureWorkCode(point);
    final day = captureBriefDay(point, _rows);
    final clocks = captureBriefClocks(_rows);
    final edge = _briefEdge(point);
    final side = widget.side;
    final statusColor = switch (link) {
      PointLink.connected => IkoluColors.connected,
      PointLink.gap => IkoluColors.warning,
      PointLink.incident => IkoluColors.incident,
    };
    final showModel = provider != 'Sin modelo';
    final showFrequency = frequency != 'Sin frecuencia';
    final showMeasured = when != 'Sin lectura';
    final rim = _hot ? edge : edge.withValues(alpha: 0.78);
    return MouseRegion(
      onEnter: (_) {
        if (!_hot) setState(() => _hot = true);
      },
      onExit: (_) {
        if (_hot) setState(() => _hot = false);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xF21A3036), Color(0xF20A1418)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: rim),
              boxShadow: [
                BoxShadow(
                  color: edge.withValues(alpha: _hot ? 0.34 : 0.18),
                  blurRadius: _hot ? 22 : 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(painter: _BoardGridPainter()),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 0,
                    height: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: edge.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 6, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              key: const ValueKey('capture-focus-logger'),
                              width: 26,
                              height: 32,
                              child: _loggerMark(
                                statusColor,
                                captureIsSurface(point),
                                link,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          flex: 3,
                                          child: Text(
                                            _title(point),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFF4F8F6),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              height: 1.1,
                                            ),
                                          ),
                                        ),
                                        if (code != null) ...[
                                          const SizedBox(width: 6),
                                          Flexible(
                                            flex: 2,
                                            child: Text(
                                              code,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF7EE0D0),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                height: 1.1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    _statusLine(
                                      link: link,
                                      color: statusColor,
                                      kind: captureKindLabel(point),
                                      compliance: compliance,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('capture-brief-close'),
                              onPressed: widget.onClose,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Color(0xFFD5E4E2),
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showModel ||
                                    showFrequency ||
                                    showMeasured ||
                                    clocks.logger != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 2,
                                      children: [
                                        if (showModel)
                                          Text(provider, style: _metaStyle),
                                        if (showFrequency)
                                          Text(frequency, style: _metaStyle),
                                        if (showMeasured)
                                          Text(
                                            'Medición $when',
                                            style: _metaStyle,
                                          ),
                                        if (clocks.logger != null)
                                          Text(
                                            'Logger ${clocks.logger}',
                                            style: _metaStyle,
                                          ),
                                      ],
                                    ),
                                  ),
                                if (facts.isEmpty && !showMeasured)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Sin lectura',
                                      style: TextStyle(
                                        color: Color(0xFF9AB0B1),
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                else if (facts.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        for (
                                          var index = 0;
                                          index < facts.length;
                                          index++
                                        ) ...[
                                          if (index > 0)
                                            const SizedBox(width: 8),
                                          Expanded(child: _fact(facts[index])),
                                        ],
                                      ],
                                    ),
                                  ),
                                if (tickets.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      captureTicketLine(tickets.first),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFFFC46B),
                                        fontSize: 11,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                _todayBand(day, statusColor),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _enterButton(
                          surface: captureIsSurface(point),
                          link: link,
                        ),
                        const SizedBox(height: 6),
                        _configButtons(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (side != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BriefNotchPainter(
                    side: side,
                    color: edge,
                    aim: widget.aim,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusLine({
    required PointLink link,
    required Color color,
    required String kind,
    required String? compliance,
  }) {
    final parts = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _linkLamp(link, color),
          const SizedBox(width: 4),
          Text(
            pointLinkLabel(link),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
      Text(
        kind,
        style: const TextStyle(
          color: Color(0xFF9AB0B1),
          fontSize: 11,
          height: 1.1,
        ),
      ),
      if (compliance != null)
        Text(
          compliance,
          style: TextStyle(
            color: _complianceColor(compliance),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            const Text(
              '·',
              style: TextStyle(color: Color(0xFF4E6A68), fontSize: 11),
            ),
          parts[i],
        ],
      ],
    );
  }

  Widget _todayBand(CaptureBriefDay day, Color color) {
    final title = captureBriefTodayLabel(day);
    final extras = captureBriefAverageLine(day);
    final showLine = day.line.length >= 2;
    if (title == null && !showLine && extras == null) {
      return const SizedBox.shrink();
    }
    final motion = widget.clock != null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: 40,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8FA3A4),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  if (day.focus != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey('${day.metric}-${day.focus}'),
                        tween: Tween(
                          begin: motion ? 0 : day.focus!,
                          end: day.focus!,
                        ),
                        duration: Duration(milliseconds: motion ? 520 : 0),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) {
                          return Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: captureBriefNumber(value),
                                  style: const TextStyle(
                                    color: Color(0xFFF4FBFA),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                TextSpan(
                                  text: ' ${day.focusUnit}',
                                  style: const TextStyle(
                                    color: Color(0xFF8FA3A4),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  Expanded(
                    child: showLine
                        ? TweenAnimationBuilder<double>(
                            key: ValueKey(day.metric),
                            tween: Tween(begin: motion ? 0.0 : 1.0, end: 1.0),
                            duration: Duration(milliseconds: motion ? 420 : 0),
                            curve: Curves.easeOutCubic,
                            builder: (context, reveal, _) => CustomPaint(
                              painter: _BriefFlowPainter(
                                day.line,
                                color,
                                reveal,
                              ),
                            ),
                          )
                        : const SizedBox.expand(),
                  ),
                ],
              ),
            ),
            if (extras != null)
              Text(
                extras,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6F8888),
                  fontSize: 10,
                  height: 1.1,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _enterButton({required bool surface, required PointLink link}) {
    return SizedBox(
      height: 30,
      width: double.infinity,
      child: FilledButton(
        key: const ValueKey('capture-quick-ver'),
        onPressed: widget.onEnter,
        style: FilledButton.styleFrom(
          foregroundColor: const Color(0xFFE7F4F2),
          backgroundColor: const Color(0xFF1C4A46),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          visualDensity: VisualDensity.compact,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MiniIsoWell(link: link, isSurface: surface, size: 16),
            const SizedBox(width: 8),
            const Text(
              'Ver',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.view_in_ar_rounded, size: 15),
          ],
        ),
      ),
    );
  }

  Widget _configButtons() {
    final agency = complianceAgencyOf(
      widget.point,
      compliance: captureComplianceFor(widget.point, widget.compliance),
    );
    // Sin cumplimiento no hay chip: se configura desde la ficha del punto.
    final sections = [
      for (final section in _configSections)
        if (section.panel != 'compliance' || agency != null) section,
    ];
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            if (index > 0) const SizedBox(width: 3),
            Expanded(
              child: _SectionChip(
                key: ValueKey(sections[index].token),
                icon: sections[index].icon,
                label: sections[index].panel == 'compliance'
                    ? agency!
                    : sections[index].label,
                onTap: () => widget.onConfigurePanel(sections[index].panel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linkLamp(PointLink link, Color color) {
    Widget dot(double glow) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.4 + 0.6 * glow.clamp(0.0, 1.0)),
          shape: BoxShape.circle,
        ),
      );
    }

    final clock = widget.clock;
    if (link != PointLink.connected || clock == null) return dot(1);
    return ValueListenableBuilder<double>(
      valueListenable: clock,
      builder: (context, seconds, _) =>
          dot(captureLoggerAntennaGlow(seconds, motion: true, link: link)),
    );
  }

  Widget _loggerMark(Color color, bool surface, PointLink link) {
    Widget glyph(double seconds, bool motion) {
      return CaptureLoggerGlyph(
        color: color,
        surface: surface,
        link: link,
        selected: true,
        antenna: captureLoggerAntennaGlow(seconds, motion: motion, link: link),
      );
    }

    final clock = widget.clock;
    if (clock == null) return glyph(0, false);
    return ValueListenableBuilder<double>(
      valueListenable: clock,
      builder: (context, seconds, _) => glyph(seconds, true),
    );
  }

  Widget _fact(({String label, String value}) fact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fact.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFF4FBFA),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          fact.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF8FA3A4),
            fontSize: 10,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

const _metaStyle = TextStyle(
  color: Color(0xFFD5E4E2),
  fontSize: 11,
  height: 1.2,
);

String? _plain(dynamic raw) {
  final text = raw?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  return text;
}

/// Agrupa miles de un entero. Un decimal se deja como llega.
String _grouped(String raw) {
  final number = num.tryParse(raw.replaceAll(',', '.'));
  if (number == null || number != number.roundToDouble()) return raw;
  final digits = number.round().abs().toString();
  final sign = number < 0 ? '-' : '';
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return '$sign$buffer';
}

Color _complianceColor(String label) {
  return switch (label) {
    'Excede el caudal' => IkoluColors.incident,
    'Cerca del límite' => IkoluColors.warning,
    _ => IkoluColors.connected,
  };
}

class _BoardGridPainter extends CustomPainter {
  const _BoardGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x1F47C7B8)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += captureBoardStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += captureBoardStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardGridPainter oldDelegate) => false;
}

/// Trazo fino de la serie elegida. Sin dos puntos, no pinta nada.
class _BriefFlowPainter extends CustomPainter {
  const _BriefFlowPainter(this.values, this.color, this.reveal);

  final List<double> values;
  final Color color;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width < 8 || size.height < 8 || reveal <= 0) {
      return;
    }
    var low = values.first;
    var high = values.first;
    for (final value in values) {
      if (value < low) low = value;
      if (value > high) high = value;
    }
    final span = (high - low).abs() < 0.001 ? 1.0 : high - low;
    const inset = 2.0;
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y =
          size.height -
          inset -
          ((values[index] - low) / span) * (size.height - inset * 2);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, 0, size.width * reveal.clamp(0.0, 1.0), size.height),
    );
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.07));
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BriefFlowPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.reveal != reveal;
}

/// Qué mide el punto. Total gana sobre caudal, y caudal sobre nivel.
enum CaptureBriefMetric { total, flow, level }

/// Canales que el punto tiene configurados. Sin lista de variables, se
/// deduce de la telemetría que sí llegó.
@visibleForTesting
class CaptureBriefChannels {
  const CaptureBriefChannels({
    required this.flow,
    required this.level,
    required this.total,
  });

  final bool flow;
  final bool level;
  final bool total;

  CaptureBriefMetric? get metric {
    if (total) return CaptureBriefMetric.total;
    if (flow) return CaptureBriefMetric.flow;
    if (level) return CaptureBriefMetric.level;
    return null;
  }
}

@visibleForTesting
CaptureBriefChannels captureBriefChannels(Map<String, dynamic> point) {
  final raw = point['variables'];
  if (raw is List && raw.isNotEmpty) {
    var flow = false;
    var level = false;
    var total = false;
    for (final item in raw) {
      if (item is! Map) continue;
      final variable = PointVariable.fromJson(Map<String, dynamic>.from(item));
      if (variable.type.startsWith('TOTALIZADO')) {
        total = true;
      } else if (variable.isFlow) {
        flow = true;
      } else if (variable.isLevel) {
        level = true;
      }
    }
    return CaptureBriefChannels(flow: flow, level: level, total: total);
  }
  final telemetry = point['latest_telemetry'];
  if (telemetry is! Map) {
    return const CaptureBriefChannels(flow: false, level: false, total: false);
  }
  return CaptureBriefChannels(
    flow: telemetry['flow'] != null,
    level: telemetry['water_table'] != null || telemetry['nivel'] != null,
    total: telemetry['total'] != null || telemetry['total_raw'] != null,
  );
}

/// Una fila de `pointRecords`, solo con los campos que la ficha usa.
@visibleForTesting
class CaptureBriefRow {
  const CaptureBriefRow({
    required this.at,
    this.loggerAt,
    this.created,
    this.flow,
    this.total,
    this.totalDiff,
    this.todayDiff,
    this.level,
  });

  final DateTime at;
  final DateTime? loggerAt;
  final DateTime? created;
  final double? flow;
  final double? total;
  final double? totalDiff;
  final double? todayDiff;
  final double? level;
}

@visibleForTesting
List<CaptureBriefRow> captureBriefRows(List<Map<String, dynamic>> records) {
  final rows = <CaptureBriefRow>[];
  for (final row in records) {
    final at = DateTime.tryParse(
      '${row['date_time'] ?? row['date_time_medition']}',
    )?.toLocal();
    if (at == null) continue;
    rows.add(
      CaptureBriefRow(
        at: at,
        loggerAt: DateTime.tryParse(
          '${row['date_time_last_logger']}',
        )?.toLocal(),
        created: DateTime.tryParse('${row['created']}')?.toLocal(),
        flow: _briefNum(row['flow']),
        total: _briefNum(row['total'] ?? row['total_raw']),
        totalDiff: _briefNum(row['total_diff']),
        todayDiff: _briefNum(row['total_today_diff']),
        level: _briefNum(row['nivel'] ?? row['water_table']),
      ),
    );
  }
  rows.sort((a, b) => a.at.compareTo(b.at));
  return rows;
}

/// Promedios de hoy y el trazo de la serie prioritaria.
@visibleForTesting
class CaptureBriefDay {
  const CaptureBriefDay({
    this.metric,
    this.line = const [],
    this.flowAvg,
    this.levelAvg,
    this.volume,
    this.arc = 0,
  });

  final CaptureBriefMetric? metric;
  final List<double> line;
  final double? flowAvg;
  final double? levelAvg;

  /// Consumo de hoy en m³: suma de `total_diff`, o el último `total_today_diff`.
  final double? volume;
  final double arc;

  double? get focus => switch (metric) {
    CaptureBriefMetric.total => volume,
    CaptureBriefMetric.flow => flowAvg,
    CaptureBriefMetric.level => levelAvg,
    null => null,
  };

  String get focusUnit => switch (metric) {
    CaptureBriefMetric.total => 'm³',
    CaptureBriefMetric.flow => 'L/s',
    CaptureBriefMetric.level => 'm',
    null => '',
  };
}

@visibleForTesting
CaptureBriefDay captureBriefDay(
  Map<String, dynamic> point,
  List<CaptureBriefRow> rows, {
  DateTime? now,
}) {
  final channels = captureBriefChannels(point);
  final metric = channels.metric;
  final clock = now ?? DateTime.now();
  final today = rows.where((row) => _sameDay(row.at, clock)).toList();
  double? mean(Iterable<double?> source) {
    final values = source.whereType<double>().toList();
    if (values.isEmpty) return null;
    var sum = 0.0;
    for (final value in values) {
      sum += value;
    }
    return sum / values.length;
  }

  final flowAvg = channels.flow ? mean(today.map((row) => row.flow)) : null;
  final levelAvg = channels.level ? mean(today.map((row) => row.level)) : null;
  double? volume;
  if (channels.total) {
    final diffs = today
        .map((row) => row.totalDiff)
        .whereType<double>()
        .toList();
    if (diffs.isNotEmpty) {
      volume = diffs.fold<double>(0, (sum, value) => sum + value);
    } else {
      for (final row in today.reversed) {
        if (row.todayDiff != null) {
          volume = row.todayDiff;
          break;
        }
      }
    }
  }

  List<double> seriesOf(List<CaptureBriefRow> source) {
    switch (metric) {
      case CaptureBriefMetric.total:
        final diffs = source
            .map((row) => row.totalDiff)
            .whereType<double>()
            .toList();
        if (diffs.length >= 2) return diffs;
        return source.map((row) => row.total).whereType<double>().toList();
      case CaptureBriefMetric.flow:
        return source.map((row) => row.flow).whereType<double>().toList();
      case CaptureBriefMetric.level:
        return source.map((row) => row.level).whereType<double>().toList();
      case null:
        return const [];
    }
  }

  final todayLine = seriesOf(today);
  final line = todayLine.length >= 2 ? todayLine : seriesOf(rows);
  final focus = switch (metric) {
    CaptureBriefMetric.total => volume,
    CaptureBriefMetric.flow => flowAvg,
    CaptureBriefMetric.level => levelAvg,
    null => null,
  };
  var arc = 0.0;
  final granted = metric == CaptureBriefMetric.flow
      ? _authorizedFlow(point)
      : null;
  if (granted != null && flowAvg != null) {
    arc = (flowAvg / granted).clamp(0.0, 1.0);
  } else if (line.isNotEmpty) {
    var peak = 0.0;
    for (final value in line) {
      final magnitude = value.abs();
      if (magnitude > peak) peak = magnitude;
    }
    final needle = metric == CaptureBriefMetric.total
        ? line.fold<double>(0, (sum, value) => sum + value) / line.length
        : focus;
    if (peak > 0 && needle != null) {
      arc = (needle.abs() / peak).clamp(0.0, 1.0);
    }
  }
  return CaptureBriefDay(
    metric: metric,
    line: line,
    flowAvg: flowAvg,
    levelAvg: levelAvg,
    volume: volume,
    arc: arc,
  );
}

/// Título del número de hoy. Solo el canal que el punto tiene activo.
@visibleForTesting
String? captureBriefTodayLabel(CaptureBriefDay day) {
  if (day.focus == null) return null;
  return switch (day.metric) {
    CaptureBriefMetric.total => 'Consumo de hoy',
    CaptureBriefMetric.flow => 'Caudal medio de hoy',
    CaptureBriefMetric.level => 'Nivel medio de hoy',
    null => null,
  };
}

/// Otros canales activos, sin repetir el número principal.
@visibleForTesting
String? captureBriefAverageLine(CaptureBriefDay day) {
  final extras = <String>[];
  if (day.metric != CaptureBriefMetric.flow && day.flowAvg != null) {
    extras.add('Caudal ${captureBriefNumber(day.flowAvg!)} L/s');
  }
  if (day.metric != CaptureBriefMetric.level && day.levelAvg != null) {
    extras.add('Nivel ${captureBriefNumber(day.levelAvg!)} m');
  }
  if (day.metric != CaptureBriefMetric.total && day.volume != null) {
    extras.add('Consumo ${captureBriefNumber(day.volume!)} m³');
  }
  if (extras.isEmpty) return null;
  return extras.join(' · ');
}

@visibleForTesting
String captureBriefNumber(double value) {
  final magnitude = value.abs();
  if (magnitude >= 100) return _grouped(value.round().toString());
  if (magnitude >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}

/// Hora del logger y hora en que llegó el registro.
///
/// `created` es cuando el servidor guardó el envío. Si no viene, no se
/// inventa. `date_time_last_logger` es el reloj del equipo.
@visibleForTesting
class CaptureBriefClocks {
  const CaptureBriefClocks({this.logger, this.arrived});

  final String? logger;
  final String? arrived;
}

@visibleForTesting
CaptureBriefClocks captureBriefClocks(List<CaptureBriefRow> rows) {
  if (rows.isEmpty) return const CaptureBriefClocks();
  final last = rows.last;
  final logger = last.loggerAt == null ? null : _briefStamp(last.loggerAt!);
  final arrived = last.created == null ? null : _briefStamp(last.created!);
  if (logger == null) return CaptureBriefClocks(logger: arrived);
  if (arrived == null || arrived == logger) {
    return CaptureBriefClocks(logger: logger);
  }
  return CaptureBriefClocks(logger: logger, arrived: arrived);
}

/// Código de obra, si el punto lo trae.
@visibleForTesting
String? captureWorkCode(Map<String, dynamic> point) {
  final direct = _plain(point['code_dga']);
  if (direct != null) return direct;
  final dga = point['dga'];
  if (dga is Map) return _plain(dga['code_dga'] ?? dga['code']);
  return null;
}

double? _briefNum(dynamic raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse('$raw'.trim().replaceAll(',', '.'));
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _briefStamp(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

double? _authorizedFlow(Map<String, dynamic> point) {
  final direct = _briefNum(
    point['authorized_flow'] ?? point['flow_granted_dga'],
  );
  if (direct != null && direct > 0) return direct;
  final dga = point['dga'];
  if (dga is Map) {
    final nested = _briefNum(dga['flow_granted_dga'] ?? dga['authorized_flow']);
    if (nested != null && nested > 0) return nested;
  }
  return null;
}

/// Caudales reales de `pointRecords`. Sin número, no hay trazo.
@visibleForTesting
List<double> captureFlowSeries(List<Map<String, dynamic>> records) {
  final flows = <double>[];
  for (final row in records) {
    final raw = row['flow'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse('$raw'.trim().replaceAll(',', '.'));
    if (value != null) flows.add(value);
  }
  return flows;
}

/// Última medición con lo que el punto trae: caudal, nivel, acumulado y hora.
@visibleForTesting
String captureBriefReading(Map<String, dynamic> point) {
  final telemetry = point['latest_telemetry'];
  if (telemetry is! Map) return 'Sin lectura';
  final parts = <String>[];
  final flow = captureFlowOf(point);
  if (flow != null) parts.add('${flow.toStringAsFixed(2)} L/s');
  final level = telemetry['water_table'] ?? telemetry['nivel'];
  final levelText = level?.toString().trim();
  if (levelText != null && levelText.isNotEmpty && levelText != 'null') {
    parts.add('Nivel $levelText');
  }
  final total = telemetry['total'] ?? telemetry['total_raw'];
  final totalText = total?.toString().trim();
  if (totalText != null && totalText.isNotEmpty && totalText != 'null') {
    parts.add('Acumulado $totalText');
  }
  final when = captureMeasuredAt(point);
  if (when != 'Sin lectura') parts.add(when);
  if (parts.isEmpty) return 'Sin lectura';
  return parts.join(' · ');
}

const _configSections =
    <({String panel, String label, IconData icon, String token})>[
      (
        panel: 'point',
        label: 'Punto',
        icon: Icons.place_outlined,
        token: 'capture-config-section-point',
      ),
      (
        panel: 'telemetry',
        label: 'Telemetría',
        icon: Icons.sensors_outlined,
        token: 'capture-config-section-telemetry',
      ),
      (
        panel: 'compliance',
        label: 'DGA',
        icon: Icons.verified_outlined,
        token: 'capture-config-section-compliance',
      ),
      (
        panel: 'physical',
        label: 'Física',
        icon: Icons.straighten,
        token: 'capture-config-section-physical',
      ),
      (
        panel: 'scheme',
        label: 'Esquema',
        icon: Icons.account_tree_outlined,
        token: 'capture-config-section-scheme',
      ),
    ];

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC142428),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 28,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3D6A64)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: const Color(0xFF7EE0D0)),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE7F4F2),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Misma llegada que el zoom de la red: 1 - e^(-kt), sin capa extra.
class _SchemeSettle extends Curve {
  const _SchemeSettle();

  @override
  double transformInternal(double t) {
    const k = 7.0;
    return (1 - math.exp(-k * t)) / (1 - math.exp(-k));
  }
}

/// La cuadrícula se asienta, como al soltar el zoom.
class _GridSettle extends StatelessWidget {
  const _GridSettle({required this.motion, required this.child});

  final bool motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: motion ? 1.08 : 1, end: 1),
      duration: Duration(milliseconds: motion ? 520 : 0),
      curve: const _SchemeSettle(),
      child: child,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
    );
  }
}

/// El pozo entra desde el fondo, con el mismo peso que acercar la red.
class _SeatedWell extends StatelessWidget {
  const _SeatedWell({required this.motion, required this.child});

  final bool motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: motion ? 0.82 : 1, end: 1),
      duration: Duration(milliseconds: motion ? 520 : 0),
      curve: const _SchemeSettle(),
      child: child,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
    );
  }
}

/// Ficha de configuración, centrada en la sección de la red.
class _PointConfigLayer extends StatelessWidget {
  const _PointConfigLayer({
    required this.onClose,
    required this.api,
    required this.knownPoints,
    this.point,
    this.panel = 'point',
    this.token,
    this.userId,
    this.onSaved,
  });

  final Map<String, dynamic>? point;
  final String panel;
  final String? token;
  final int? userId;
  final SmartHydroApi api;
  final List<Map<String, dynamic>> knownPoints;
  final VoidCallback onClose;
  final VoidCallback? onSaved;

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          600.0,
          math.max(280.0, constraints.maxWidth - 24),
        );
        final height = math.min(constraints.maxHeight - 16, 680.0);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: const ColoredBox(color: Color(0xB3081216)),
              ),
            ),
            Center(
              child: SizedBox(
                width: width,
                height: height,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: motion ? 0.4 : 1, end: 1),
                  duration: Duration(milliseconds: motion ? 200 : 0),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) {
                    return Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.97 + 0.03 * t,
                        child: child,
                      ),
                    );
                  },
                  child: PointConfigCard(
                    key: ValueKey('capture-config-${point?['id'] ?? 'new'}'),
                    point: point,
                    initialPanel: panel,
                    token: token,
                    userId: userId,
                    api: api,
                    knownPoints: knownPoints,
                    onClose: onClose,
                    onSaved: onSaved,
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
  return 78 / math.sin(math.pi / members.length);
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

/// Estado vivo del servicio a partir de los puntos cargados.
@visibleForTesting
String captureServicePulse(List<Map<String, dynamic>> points, {DateTime? now}) {
  if (points.isEmpty) return 'Smart Hydro · sin puntos asignados';
  final mix = captureLinkCounts(points);
  final clock = now ?? DateTime.now();
  final latest = _newestReading(points);
  final reading = latest == null
      ? 'sin lectura'
      : 'última lectura ${_readingAge(latest, clock)}';
  String count(int value, String one, String many) =>
      value == 1 ? '1 $one' : '$value $many';
  return 'Smart Hydro · ${count(mix.connected, 'en línea', 'en línea')} · ${count(mix.warning, 'atención', 'en atención')} · ${count(mix.incident, 'incidencia', 'incidencias')} · $reading';
}

/// Disponibilidad del servicio: si el API responde y qué parte de la red está en línea.
@visibleForTesting
String captureAvailabilityLine(
  List<Map<String, dynamic>> points, {
  bool? apiOnline,
}) {
  final api = switch (apiOnline) {
    true => 'API en línea',
    false => 'API sin respuesta',
    null => 'API en consulta',
  };
  if (points.isEmpty) return '$api · sin puntos asignados';
  final mix = captureLinkCounts(points);
  final pct = (100 * mix.connected / points.length).round();
  final noun = points.length == 1 ? 'punto' : 'puntos';
  return '$api · ${mix.connected} de ${points.length} $noun · $pct%';
}

/// Rendimiento a partir de los puntos que responden y de la lectura más nueva.
@visibleForTesting
String capturePerformanceLine(
  List<Map<String, dynamic>> points, {
  DateTime? now,
}) {
  if (points.isEmpty) return 'Sin lecturas para medir';
  final mix = captureLinkCounts(points);
  final clock = now ?? DateTime.now();
  final latest = _newestReading(points);
  final reading = latest == null
      ? 'sin lectura reciente'
      : 'última lectura ${_readingAge(latest, clock)}';
  final responding = mix.connected == 1
      ? '1 respondiendo'
      : '${mix.connected} respondiendo';
  return '$responding · $reading';
}

DateTime? _newestReading(List<Map<String, dynamic>> points) {
  DateTime? best;
  for (final point in points) {
    final telemetry = point['latest_telemetry'];
    if (telemetry is! Map) continue;
    final parsed = DateTime.tryParse(
      '${telemetry['date_time_medition']}',
    )?.toLocal();
    if (parsed == null) continue;
    if (best == null || parsed.isAfter(best)) best = parsed;
  }
  return best;
}

String _readingAge(DateTime time, DateTime now) {
  final delta = now.difference(time);
  if (delta.isNegative || delta.inSeconds < 60) return 'ahora';
  if (delta.inMinutes < 60) {
    final minutes = delta.inMinutes;
    return minutes <= 1 ? 'hace 1 min' : 'hace $minutes min';
  }
  if (delta.inHours < 24) {
    final hours = delta.inHours;
    return hours <= 1 ? 'hace 1 h' : 'hace $hours h';
  }
  if (delta.inDays == 1) return 'ayer';
  return 'hace ${delta.inDays} días';
}

/// Línea bajo el título: cuántos puntos hay y si la vista usa GPS.
@visibleForTesting
String captureNetworkSubtitle(List<Map<String, dynamic>> points) {
  if (points.isEmpty) return 'Cuando haya puntos, aparecen aquí';
  final count = points.length;
  final online = points
      .where((point) => pointLinkOf(point) == PointLink.connected)
      .length;
  final noun = count == 1 ? 'punto' : 'puntos';
  final where = points.any((point) => captureLatLng(point) != null)
      ? 'en su lugar'
      : 'sin coordenadas';
  return '$count $noun · $online conectados · $where';
}

/// Conteos de enlace para el peek del resumen (móvil).
@visibleForTesting
({int connected, int warning, int incident}) captureLinkCounts(
  List<Map<String, dynamic>> points,
) {
  var connected = 0;
  var warning = 0;
  var incident = 0;
  for (final point in points) {
    switch (pointLinkOf(point)) {
      case PointLink.connected:
        connected++;
      case PointLink.gap:
        warning++;
      case PointLink.incident:
        incident++;
    }
  }
  return (connected: connected, warning: warning, incident: incident);
}

/// Mezcla de la vista: conectados, advertencias e incidencias que se ven.
@visibleForTesting
String captureViewSummary(List<Map<String, dynamic>> points) {
  if (points.isEmpty) return 'Nada en esta vista';
  final mix = captureLinkCounts(points);
  final connected = mix.connected;
  final warning = mix.warning;
  final incident = mix.incident;
  String piece(int count, String one, String many) {
    if (count == 0) return '';
    return count == 1 ? '1 $one' : '$count $many';
  }

  return [
    piece(connected, 'conectado', 'conectados'),
    piece(warning, 'advertencia', 'advertencias'),
    piece(incident, 'incidencia', 'incidencias'),
  ].where((part) => part.isNotEmpty).join(' · ');
}

/// Fecha de la última lectura, o un aviso si no hay.
@visibleForTesting
String captureMeasuredAt(Map<String, dynamic> point) {
  final telemetry = point['latest_telemetry'];
  if (telemetry is! Map) return 'Sin lectura';
  final parsed = DateTime.tryParse(
    '${telemetry['date_time_medition']}',
  )?.toLocal();
  if (parsed == null) return 'Sin lectura';
  final day = parsed.day.toString().padLeft(2, '0');
  final month = parsed.month.toString().padLeft(2, '0');
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

int? _frequencyMinutes(Map<String, dynamic> point) {
  final raw = point['frecuency'] ?? point['frequency'];
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw');
}

/// Pozo o captación superficial, según `type_dga`.
@visibleForTesting
String captureKindLabel(Map<String, dynamic> point) =>
    captureIsSurface(point) ? 'Superficial' : 'Pozo';

/// Proveedor del logger. Si el punto no lo trae, no se inventa.
@visibleForTesting
String captureProviderLabel(Map<String, dynamic> point) =>
    loggerModelOf(point) ?? 'Sin modelo';

/// Cumplimiento real: el nivel de la ficha, o solo si el punto es DGA.
@visibleForTesting
String captureComplianceLabel(
  Map<String, dynamic> point, {
  Map<String, dynamic>? compliance,
}) {
  final level = compliance != null
      ? captureComplianceLevel(compliance)
      : captureComplianceLevel(point);
  final hasDga = captureHasCompliance(point) || compliance != null;
  if (!hasDga) return 'Sin cumplimiento';
  return switch (level) {
    'critical' => 'Excede el caudal',
    'warning' => 'Cerca del límite',
    'safe' => 'Dentro del límite',
    _ => compliance != null ? 'Sin caudal autorizado' : 'Con cumplimiento',
  };
}

/// Ficha de cumplimiento del punto, si el inicio ya la cargó.
@visibleForTesting
Map<String, dynamic>? captureComplianceFor(
  Map<String, dynamic> point,
  List<Map<String, dynamic>> compliance,
) {
  final id = _pointId(point);
  if (id == null) return null;
  for (final item in compliance) {
    final raw = item['point_id'];
    final itemId = raw is int ? raw : int.tryParse('$raw');
    if (itemId == id) return item;
  }
  return null;
}

/// Ticket de soporte del cliente. Un evento de sistema no entra en la ficha.
///
/// El origen `CLIENTE` es el de una solicitud de soporte. Si el origen no
/// viene, no se inventa: se conserva, salvo que el ítem sea un evento
/// (`event_type`, o severidad sin estado de ticket).
@visibleForTesting
bool captureIsSupportTicket(Map<String, dynamic> item) {
  if (_fieldText(item['event_type']) != null) return false;
  final origin = _fieldText(item['origin']);
  if (origin != null) return origin.toUpperCase() == 'CLIENTE';
  if (_fieldText(item['severity']) != null &&
      _fieldText(item['status']) == null) {
    return false;
  }
  return true;
}

/// Tickets de soporte abiertos de este punto. Eventos y otros orígenes no.
@visibleForTesting
List<Map<String, dynamic>> captureTicketsForPoint(
  Map<String, dynamic> point,
  List<Map<String, dynamic>> tickets,
) {
  final id = _pointId(point);
  if (id == null) return const [];
  return [
    for (final ticket in tickets)
      if (captureIsSupportTicket(ticket) && systemItemMatchesPoint(ticket, id))
        ticket,
  ];
}

String? _fieldText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  return text;
}

/// Una línea de ticket: título y estado, solo con lo que viene.
@visibleForTesting
String captureTicketLine(Map<String, dynamic> ticket) {
  final rawTitle = ticket['title']?.toString().trim();
  final title = rawTitle == null || rawTitle.isEmpty || rawTitle == 'null'
      ? 'Solicitud'
      : rawTitle;
  final rawStatus = ticket['status']?.toString().trim();
  if (rawStatus == null || rawStatus.isEmpty || rawStatus == 'null') {
    return title;
  }
  return '$title · ${captureTicketStatusLabel(rawStatus)}';
}

/// Estado de ticket que la API ya usa. Un código desconocido se deja tal cual.
@visibleForTesting
String captureTicketStatusLabel(dynamic status) {
  final code = '$status'.trim().toUpperCase();
  return switch (code) {
    'ABIERTO' => 'abierto',
    'EN_ANALISIS' => 'en análisis',
    'EN_ORDEN_TRABAJO' => 'en orden de trabajo',
    'ESPERA_CLIENTE' => 'espera cliente',
    'ESPERA_PROVEEDOR' => 'espera proveedor',
    _ => '$status'.trim(),
  };
}

int? _pointId(Map<String, dynamic> point) {
  final raw = point['id'];
  final id = raw is int ? raw : int.tryParse('$raw');
  if (id == null || id <= 0) return null;
  return id;
}

/// Frecuencia del logger, o un aviso si el punto no la trae.
@visibleForTesting
String captureFrequencyLabel(Map<String, dynamic> point) {
  final minutes = _frequencyMinutes(point);
  if (minutes == null || minutes <= 0) return 'Sin frecuencia';
  return '$minutes min';
}

/// Siguiente medición: última lectura más la frecuencia del logger.
@visibleForTesting
String captureNextReading(Map<String, dynamic> point) {
  final minutes = _frequencyMinutes(point);
  final telemetry = point['latest_telemetry'];
  if (minutes == null || minutes <= 0 || telemetry is! Map) {
    return 'Sin programar';
  }
  final last = DateTime.tryParse('${telemetry['date_time_medition']}');
  if (last == null) return 'Sin programar';
  final next = last.toLocal().add(Duration(minutes: minutes));
  final day = next.day.toString().padLeft(2, '0');
  final month = next.month.toString().padLeft(2, '0');
  final hour = next.hour.toString().padLeft(2, '0');
  final minute = next.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

/// Tipos cortos de variable que el punto trae de verdad. Vacío si no hay.
@visibleForTesting
List<String> captureVariableTags(Map<String, dynamic> point) {
  final raw = point['variables'];
  if (raw is List && raw.isNotEmpty) {
    final names = <String>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final variable = PointVariable.fromJson(Map<String, dynamic>.from(item));
      final name = variable.simpleType.trim();
      if (name.isEmpty || name == 'sin mapear' || names.contains(name)) {
        continue;
      }
      names.add(name);
      if (names.length == 2) break;
    }
    if (names.isNotEmpty) return names;
  }
  final telemetry = point['latest_telemetry'];
  if (telemetry is! Map) return const [];
  return [
    if (telemetry['flow'] != null) 'Caudal',
    if (telemetry['water_table'] != null || telemetry['nivel'] != null) 'Nivel',
    if (telemetry['total'] != null || telemetry['total_raw'] != null)
      'Acumulado',
  ].take(2).toList(growable: false);
}

/// Variables del esquema del logger. Si no vienen, usa la telemetría real.
@visibleForTesting
String captureVariableLabel(Map<String, dynamic> point) {
  final raw = point['variables'];
  if (raw is List && raw.isNotEmpty) {
    final names = <String>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final variable = PointVariable.fromJson(Map<String, dynamic>.from(item));
      final name = variable.schemaName.trim();
      if (name.isEmpty) continue;
      names.add('${variable.simpleType} · $name');
    }
    if (names.isNotEmpty) return names.join(', ');
  }
  final telemetry = point['latest_telemetry'];
  if (telemetry is! Map) return 'Sin variables';
  final found = <String>[
    if (telemetry['flow'] != null) 'Caudal',
    if (telemetry['water_table'] != null || telemetry['nivel'] != null) 'Nivel',
    if (telemetry['total'] != null || telemetry['total_raw'] != null)
      'Acumulado',
  ];
  if (found.isEmpty) return 'Sin variables';
  return found.join(' · ');
}

/// Medición corta junto al nombre: caudal, o la hora si no hay caudal.
@visibleForTesting
String captureReadingLabel(Map<String, dynamic> point) {
  final flow = captureFlowOf(point);
  if (flow != null) return '${flow.toStringAsFixed(2)} L/s';
  return captureMeasuredAt(point);
}

/// Texto de ubicación para la ficha: coords o aviso sin GPS.
@visibleForTesting
String captureLocationLabel(Map<String, dynamic> point) {
  final gps = captureLatLng(point);
  if (gps == null) return 'Sin ubicación GPS';
  return '${gps.latitude.toStringAsFixed(5)}, ${gps.longitude.toStringAsFixed(5)}';
}

/// Intensidad visual del ripple: caudal normalizado + boost si está activo.
@visibleForTesting
double captureRippleStrength({
  required Map<String, dynamic> point,
  required bool selected,
  double? maxFlow,
}) {
  final flow = captureFlowOf(point) ?? 0;
  final ceiling = (maxFlow == null || maxFlow <= 0) ? 1.0 : maxFlow;
  final normalized = (flow / ceiling).clamp(0.0, 1.0);
  var strength = 0.18 + normalized * 0.42;
  if (selected) strength = (strength + 0.32).clamp(0.0, 1.0);
  return strength;
}

@visibleForTesting
double? captureFlowOf(Map<String, dynamic> point) {
  final telemetry = point['latest_telemetry'];
  if (telemetry is! Map) return null;
  final raw = telemetry['flow'];
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    return double.tryParse(raw.trim().replaceAll(',', '.'));
  }
  return null;
}

@visibleForTesting
double captureMaxFlow(List<Map<String, dynamic>> points) {
  var max = 0.0;
  for (final point in points) {
    final flow = captureFlowOf(point);
    if (flow != null && flow > max) max = flow;
  }
  return max;
}

/// Línea recta desde el borde del chip hasta el beacon (arquitectura de nodos).
@visibleForTesting
Path captureLeaderPath(Rect chip, Offset beacon) {
  final attach = captureChipAttach(chip, beacon);
  return Path()
    ..moveTo(attach.dx, attach.dy)
    ..lineTo(beacon.dx, beacon.dy);
}

@visibleForTesting
Offset captureChipAttach(Rect chip, Offset beacon) {
  final center = chip.center;
  final delta = beacon - center;
  if (delta.distance < 0.001) return center;
  final nx = delta.dx / delta.distance;
  final ny = delta.dy / delta.distance;
  final halfW = chip.width / 2;
  final halfH = chip.height / 2;
  final tx = nx.abs() < 1e-9 ? double.infinity : halfW / nx.abs();
  final ty = ny.abs() < 1e-9 ? double.infinity : halfH / ny.abs();
  final t = math.min(tx, ty);
  return Offset(center.dx + nx * t, center.dy + ny * t);
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

@visibleForTesting
Color captureSchemeLinkColor(PointLink link) => switch (link) {
  PointLink.connected => IkoluColors.connected,
  PointLink.gap => const Color(0xFFFF847A),
  PointLink.incident => IkoluColors.incident,
};

/// Solo el enlace conectado lleva energía. El resto es una línea quieta.
@visibleForTesting
bool captureLinkFlows(PointLink link) => link == PointLink.connected;
