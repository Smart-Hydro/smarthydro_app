import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'package:flutter_map/flutter_map.dart';

import '../../../core/api/smarthydro_api.dart';
import '../../../core/brand.dart';
import '../../../shared/ui/hydro_ui.dart';
import '../../../shared/widgets/workstation_backdrop.dart';
import '../../geo/capture_coordinates.dart';
import '../../geo/capture_location_map.dart';
import 'capture_logger_plate.dart';
import '../point_link.dart';
import '../point_meta.dart';
import '../point_system.dart';

export '../../geo/capture_coordinates.dart';

/// Celdas vacías del borde. La cuadrícula llega al filo; los loggers no.
const captureEdgePad = 32.0;

/// Cuadro de la pizarra. El esquema calza en esta medida y no se arrastra.
const captureBoardStep = 16.0;

/// Todas las placas miden lo mismo. El nombre largo se corta.
const capturePlateWidth = 80.0;

/// Dos cuadros de alto. Igual para cada logger.
const capturePlateHeight = 32.0;

/// Aire entre placas, para que el enlace se lea.
const capturePlateGap = 32.0;

/// Núcleo SMARTHYDRO. Cinco cuadros, para calzar en la misma grilla.
const captureHubSize = 80.0;

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

  @override
  State<_WaterView> createState() => _WaterViewState();
}

class _WaterViewState extends State<_WaterView> with TickerProviderStateMixin {
  /// Tiempo continuo en segundos: la onda no “reinicia” al llegar a 1.
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);
  Ticker? _ticker;
  late final AnimationController _approach = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  late final AnimationController _seat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  int? _selected;

  /// Claves de puntos con ventana abierta (HOME web). Orden = orden de apertura.
  final List<String> _openKeys = [];

  /// Orden de pintura. La última queda delante. No cambia de escritorio.
  final List<String> _windowZ = [];
  final Map<String, Rect> _windowFrames = {};
  int _focusTick = 0;
  int _page = 0;
  int _windowDesktop = 0;
  bool _pageForward = true;
  bool _motion = true;
  bool? _apiOnline;
  bool _showLocations = false;
  final SmartHydroApi _api = SmartHydroApi();
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _openKey = GlobalKey();
  Rect? _openPlacement;

  bool _isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 980;

  String _keyOf(Map<String, dynamic> point) => '${_pointKey(point)}';

  String? _locationSelectionKey(bool wide) {
    if (wide && _openKeys.isNotEmpty) {
      final point = _pointForOpenKey(_openKeys.last);
      return point == null ? null : capturePointKey(point);
    }
    final index = _selected;
    if (index == null || index < 0 || index >= widget.points.length) {
      return null;
    }
    return capturePointKey(widget.points[index]);
  }

  Map<String, dynamic>? _pointForOpenKey(String key) {
    for (final point in widget.points) {
      if (_keyOf(point) == key) return point;
    }
    return null;
  }

  void _pruneOpenKeys() {
    _openKeys.removeWhere((key) => _pointForOpenKey(key) == null);
    _windowZ.removeWhere((key) => !_openKeys.contains(key));
    _windowFrames.removeWhere((key, _) => !_openKeys.contains(key));
  }

  void _raiseWindow(String key) {
    _windowZ.remove(key);
    _windowZ.add(key);
  }

  int? _indexForOpenKey(String key) {
    final index = widget.points.indexWhere((point) => _keyOf(point) == key);
    return index < 0 ? null : index;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _trackOpenCard();
      _seconds.value = elapsed.inMicroseconds / 1e6;
    });
    _ticker!.start();
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
    } else if (_ticker != null && !_ticker!.isActive) {
      _ticker!.start();
    }
  }

  @override
  void didUpdateWidget(covariant _WaterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pruneOpenKeys();
    if (widget.points.length != oldWidget.points.length) {
      _page = 0;
      if (_openKeys.isEmpty) {
        _selected = null;
      } else if (_selected != null && _selected! >= widget.points.length) {
        _selected = _openKeys.isEmpty ? null : _indexForOpenKey(_openKeys.last);
      }
    } else if (_selected != null && _selected! >= widget.points.length) {
      _selected = null;
    }
  }

  void _turnPage(int delta, int pages) {
    final next = (_page + delta).clamp(0, pages - 1);
    if (next == _page) return;
    setState(() {
      _pageForward = delta >= 0;
      _page = next;
      // En web las ventanas persisten entre páginas; en móvil se cierra la ficha.
      if (!_isWide(context)) {
        _selected = null;
        _openPlacement = null;
      }
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _seconds.dispose();
    _approach.dispose();
    _seat.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index < 0 || index >= widget.points.length) return;
    final key = _keyOf(widget.points[index]);
    setState(() {
      _openPlacement = null;
      _focusTick++;
      if (_isWide(context)) {
        // Solo la X cierra. Volver a tocar el punto lo trae al frente.
        if (!_openKeys.contains(key)) {
          _openKeys.add(key);
          _windowDesktop = 1 << 20;
        }
        _raiseWindow(key);
        _selected = _indexForOpenKey(key);
      } else {
        _selected = index;
        _openKeys.clear();
        _windowZ.clear();
      }
    });
    if (_selected == null && _openKeys.isEmpty) {
      _seat.value = 0;
    } else if (_motion) {
      _seat.forward(from: 0);
    } else {
      _seat.value = 1;
    }
  }

  Rect _clampWindow(Rect rect, Rect bounds) {
    const minW = 280.0;
    const minH = 220.0;
    final maxW = math.max(minW, bounds.width);
    final maxH = math.max(minH, bounds.height);
    final w = rect.width.clamp(minW, maxW).toDouble();
    final h = rect.height.clamp(minH, maxH).toDouble();
    final left = rect.left.clamp(bounds.left, bounds.right - w).toDouble();
    final top = rect.top.clamp(bounds.top, bounds.bottom - h).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  void _closeOpenKey(String key) {
    setState(() {
      _openKeys.remove(key);
      _windowZ.remove(key);
      _windowFrames.remove(key);
      if (_selected != null &&
          _selected! < widget.points.length &&
          _keyOf(widget.points[_selected!]) == key) {
        _selected = _openKeys.isEmpty ? null : _indexForOpenKey(_openKeys.last);
      }
      _openPlacement = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
      _openKeys.clear();
      _windowZ.clear();
      _windowFrames.clear();
      _openPlacement = null;
    });
  }

  /// La línea sigue a la ficha ya sentada, no al rectángulo estimado.
  void _trackOpenCard() {
    if (_selected == null) {
      _openPlacement = null;
      return;
    }
    final cardContext = _openKey.currentContext;
    final stackContext = _stackKey.currentContext;
    if (cardContext == null || stackContext == null) return;
    final card = cardContext.findRenderObject();
    final stack = stackContext.findRenderObject();
    if (card is! RenderBox || stack is! RenderBox) return;
    if (!card.attached || !stack.attached || !card.hasSize || !stack.hasSize) {
      return;
    }
    final origin = card.localToGlobal(Offset.zero, ancestor: stack);
    final next = origin & card.size;
    final prev = _openPlacement;
    if (prev != null &&
        (prev.left - next.left).abs() < 0.5 &&
        (prev.top - next.top).abs() < 0.5 &&
        (prev.width - next.width).abs() < 0.5 &&
        (prev.height - next.height).abs() < 0.5) {
      return;
    }
    final heightChanged =
        prev == null || (prev.height - next.height).abs() >= 4;
    _openPlacement = next;
    // El alto real puede pasar el estimado: hay que volver a apartar
    // las otras fichas. El ticker ya redibuja la línea sin setState.
    if (heightChanged && mounted) {
      setState(() {});
      return;
    }
    if (!(_ticker?.isActive ?? false) && mounted) {
      setState(() {});
    }
  }

  void _openSelected() {
    final index = _selected;
    if (index == null) return;
    widget.onOpen(widget.points[index]);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_selected != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _trackOpenCard();
          });
        }
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        // El encabezado ocupa la franja de arriba. La red vive debajo.
        // Con la pregunta rápida la franja es un poco más alta.
        final headerBand = widget.askBar == null ? 84.0 : 108.0;
        final contentTop = widget.topInset + headerBand;
        final contentLeft = widget.leftInset;
        // Sin lista inferior permanente: el diagrama usa casi todo el alto.
        // La ficha de un punto elegido flota encima y no reserva layout.
        final fieldBottom = math.max(
          widget.bottomInset + 8,
          widget.openBottomClearance,
        );
        var pageSize = math.max(
          1,
          captureSchemePageSize(
            size,
            top: contentTop,
            bottom: fieldBottom,
            left: contentLeft,
          ),
        );
        var pages = math.max(1, (widget.points.length / pageSize).ceil());
        final pagerBand = pages > 1 ? 40.0 : 0.0;
        if (pagerBand > 0) {
          pageSize = math.max(
            1,
            captureSchemePageSize(
              size,
              top: contentTop,
              bottom: fieldBottom + pagerBand,
              left: contentLeft,
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
          bottom: fieldBottom + pagerBand,
          left: contentLeft,
          groups: [
            for (final index in pageIndexes)
              captureProjectKey(widget.points[index]),
          ],
          labels: [
            for (final index in pageIndexes) _title(widget.points[index]),
          ],
        );
        final plates = scheme.plates;
        final hub = scheme.hub;
        final pagePoints = [
          for (final index in pageIndexes) widget.points[index],
        ];
        final wide = _isWide(context);
        final found = _selected == null ? -1 : pageIndexes.indexOf(_selected!);
        int? selectedOnPage = found < 0 ? null : found;
        if (wide && _openKeys.isNotEmpty) {
          selectedOnPage = null;
          for (final key in _openKeys.reversed) {
            final local = pageIndexes.indexWhere(
              (index) => _keyOf(widget.points[index]) == key,
            );
            if (local >= 0) {
              selectedOnPage = local;
              break;
            }
          }
        }
        final openLocals = <int>{
          if (wide)
            for (var local = 0; local < pageIndexes.length; local++)
              if (_openKeys.contains(_keyOf(pagePoints[local]))) local,
        };
        final maxFlow = captureMaxFlow(widget.points);
        final openPoints = [
          if (wide)
            for (final key in _openKeys)
              if (_pointForOpenKey(key) case final point?) point,
        ];
        final desks = wide
            ? layoutWindowDesktops(
                area: size,
                count: openPoints.length,
                desktop: _windowDesktop,
                windowWidth: 360,
                windowHeight: 460,
                bottomInset: math.max(8.0, widget.openBottomClearance - 2),
                leftInset: contentLeft,
              )
            : (
                capacity: 1,
                pages: 1,
                rects: const <Rect>[],
              );
        final windowBounds = Rect.fromLTRB(
          contentLeft,
          contentTop,
          math.max(contentLeft + 280, size.width - 8),
          math.max(contentTop + 240, size.height - 8),
        );
        final deskIndex = desks.pages <= 1
            ? 0
            : (_windowDesktop >= 100000
                  ? desks.pages - 1
                  : _windowDesktop.clamp(0, desks.pages - 1));
        final windowStart = deskIndex * desks.capacity;
        final windowPoints = openPoints
            .skip(windowStart)
            .take(desks.rects.length)
            .toList();
        final windowObstacles = <Rect>[
          if (!hub.isEmpty) hub,
          ...plates,
          if (!_showLocations && pagePoints.length > 1)
            Rect.fromLTWH(size.width - 164, contentTop + 8, 148, 96),
        ];
        final openFrames = placeOpenWindowFrames(
          count: windowPoints.length,
          bounds: windowBounds,
          obstacles: windowObstacles,
        );
        final paintPoints = [...windowPoints]..sort((a, b) {
          final az = _windowZ.indexOf(_keyOf(a));
          final bz = _windowZ.indexOf(_keyOf(b));
          return az.compareTo(bz);
        });

        return AnimatedBuilder(
          animation: _approach,
          builder: (context, _) {
            final selected = selectedOnPage;

            Widget waterLayer = Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
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
                            approach: _approach.value,
                            gridTop: contentTop,
                            boardBottom: fieldBottom,
                            pan: Offset.zero,
                          ),
                          child: const SizedBox.expand(),
                        );
                      },
                    ),
                ),
              ],
            );

            return Stack(
              key: _stackKey,
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                waterLayer,
                Positioned(
                  left: math.max(18.0, contentLeft + 12),
                  right: 18,
                  top: widget.topInset + 10,
                  child: _NetworkHeader(
                    points: widget.points,
                    askBar: widget.askBar,
                    locationMode: _showLocations,
                    onToggleLocation: widget.points.isEmpty
                        ? null
                        : () => setState(() {
                            _showLocations = !_showLocations;
                            _openPlacement = null;
                          }),
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
                      selectedKey: _locationSelectionKey(wide),
                      tileProvider: widget.locationTiles,
                      onSelect: (point) {
                        final index = widget.points.indexOf(point);
                        if (index >= 0) _select(index);
                      },
                    ),
                  ),
                if (!_showLocations)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: contentTop,
                    bottom: fieldBottom + pagerBand,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        if (!hub.isEmpty)
                          Positioned(
                            left: hub.left,
                            top: hub.top - contentTop,
                            width: hub.width,
                            height: hub.height,
                            child: IgnorePointer(
                              child: _DataSmartCore(
                                clock: _motion ? _seconds : null,
                                apiOnline: _apiOnline,
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
                                  scale: Tween<double>(
                                    begin: 0.96,
                                    end: 1,
                                  ).animate(snap),
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
                                  child: ValueListenableBuilder<double>(
                                    valueListenable: _seconds,
                                    builder: (context, seconds, _) {
                                      return CustomPaint(
                                        painter: _HubLinkPainter(
                                          plates: [
                                            for (final plate in plates)
                                              plate.shift(
                                                Offset(0, -contentTop),
                                              ),
                                          ],
                                          hub: hub.shift(
                                            Offset(0, -contentTop),
                                          ),
                                          selected: selected,
                                          seconds: seconds,
                                          motion: _motion,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              for (
                                var local = 0;
                                local < pageIndexes.length;
                                local++
                              )
                                Positioned(
                                  key: ValueKey(
                                    'capture-label-${pageIndexes[local]}',
                                  ),
                                  left: plates[local].left,
                                  top: plates[local].top - contentTop,
                                  width: plates[local].width,
                                  height: plates[local].height,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity:
                                        (wide
                                            ? openLocals.isNotEmpty &&
                                                  !openLocals.contains(local)
                                            : selected != null &&
                                                  local != selected)
                                        ? 0.38
                                        : 1,
                                    child: _Snap(
                                      token: pageIndexes[local] == _selected
                                          ? _focusTick
                                          : 'still-$local',
                                      play: pageIndexes[local] == _selected,
                                      motion: _motion,
                                      child: _LoggerNode(
                                        point: pagePoints[local],
                                        selected: wide
                                            ? openLocals.contains(local)
                                            : local == selected,
                                        clock: _motion ? _seconds : null,
                                        onTap: () =>
                                            _select(pageIndexes[local]),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_showLocations && pages > 1)
                  Positioned(
                    left: math.max(12.0, contentLeft + 12),
                    right: 12,
                    bottom: fieldBottom + 4,
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
                if (!_showLocations && pagePoints.length > 1)
                  Positioned(
                    right: 16,
                    top: contentTop + 8,
                    child: _SchemeMinimap(
                      plates: plates,
                      hub: hub,
                      selected: selected,
                      onJump: (local) => _select(pageIndexes[local]),
                    ),
                  ),
                if (wide && desks.pages > 1)
                  Positioned(
                    left: math.max(12.0, contentLeft + 12),
                    bottom: math.max(8.0, widget.openBottomClearance - 2),
                    child: _DesktopSwitch(
                      index: deskIndex,
                      pages: desks.pages,
                      onPrev: deskIndex > 0
                          ? () => setState(() => _windowDesktop = deskIndex - 1)
                          : null,
                      onNext: deskIndex < desks.pages - 1
                          ? () => setState(() => _windowDesktop = deskIndex + 1)
                          : null,
                    ),
                  ),
                // Web: ventanas completas, movibles y redimensionables.
                if (wide)
                  for (final point in paintPoints)
                    () {
                      final key = _keyOf(point);
                      final i = windowPoints.indexOf(point);
                      final fallback = i < openFrames.length
                          ? openFrames[i]
                          : Rect.fromLTWH(
                              windowBounds.right - 360,
                              windowBounds.top,
                              math.min(360, windowBounds.width),
                              math.min(460, windowBounds.height),
                            );
                      final frame = _clampWindow(
                        _windowFrames[key] ?? fallback,
                        windowBounds,
                      );
                      return Positioned(
                        left: frame.left,
                        top: frame.top,
                        width: frame.width,
                        height: frame.height,
                        child: Stack(
                          children: [
                            _PointWindow(
                              key: ValueKey(
                                'capture-point-window-${_pointKey(point)}',
                              ),
                              focus: point,
                              onEnter: () => widget.onOpen(point),
                              onClose: () => _closeOpenKey(key),
                              openTickets: widget.openTickets,
                              compliance: widget.compliance,
                              onRequestSupport: widget.onRequestSupport,
                            ),
                            Positioned(
                              left: 8,
                              top: 6,
                              right: 40,
                              height: 32,
                              child: GestureDetector(
                                key: ValueKey(
                                  'capture-window-drag-${_pointKey(point)}',
                                ),
                                behavior: HitTestBehavior.translucent,
                                onPanStart: (_) => setState(() => _raiseWindow(key)),
                                onPanUpdate: (details) {
                                  setState(() {
                                    final current = _windowFrames[key] ?? frame;
                                    _windowFrames[key] = _clampWindow(
                                      current.shift(details.delta),
                                      windowBounds,
                                    );
                                  });
                                },
                                child: const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    size: 16,
                                    color: Color(0xFF8FB0AC),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 2,
                              bottom: 2,
                              width: 28,
                              height: 28,
                              child: GestureDetector(
                                key: ValueKey(
                                  'capture-window-resize-${_pointKey(point)}',
                                ),
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (details) {
                                  setState(() {
                                    final current = _windowFrames[key] ?? frame;
                                    _windowFrames[key] = _clampWindow(
                                      Rect.fromLTWH(
                                        current.left,
                                        current.top,
                                        current.width + details.delta.dx,
                                        current.height + details.delta.dy,
                                      ),
                                      windowBounds,
                                    );
                                  });
                                },
                                child: const Icon(
                                  Icons.open_in_full_rounded,
                                  size: 14,
                                  color: Color(0xFF8FB0AC),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }()
                else if (_selected != null &&
                    _selected! >= 0 &&
                    _selected! < widget.points.length)
                  Positioned(
                    left: captureEdgePad,
                    right: captureEdgePad,
                    bottom: math.max(8.0, widget.openBottomClearance - 2),
                    height: math.min(520, size.height * 0.72),
                    child: _ViewRecords(
                      focus: widget.points[_selected!],
                      onEnter: _openSelected,
                      onClose: _clearSelection,
                      openTickets: widget.openTickets,
                      compliance: widget.compliance,
                      onRequestSupport: widget.onRequestSupport,
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
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: child,
      ),
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
    required this.approach,
    required this.gridTop,
    required this.boardBottom,
    required this.pan,
  });

  final double seconds;
  final bool motion;
  final List<Map<String, dynamic>> points;
  final List<Offset> anchors;
  final List<Rect> plates;
  final Rect hub;
  final int? selected;
  final double maxFlow;
  final double approach;
  final double gridTop;
  final double boardBottom;
  final Offset pan;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;

    // Base opaca de estación de trabajo. Sin velo sobre agua ni adornos.
    canvas.drawRect(bounds, Paint()..color = WorkstationBackdrop.base);

    // La cuadrícula cubre toda la página; no se corta sobre la ficha.
    _paintGrid(canvas, size);

    final board = _boardRect(size);
    if (selected != null && approach > 0) {
      _paintDiveWash(canvas, size, approach);
    }

    if (approach < 0.55 && board.width > 0 && board.height > 0) {
      canvas.save();
      canvas.clipRect(board);
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 1 - approach * 1.4),
      );
      _paintHub(canvas);
      _paintLoggerCells(canvas);
      canvas.restore();
      canvas.restore();
    }
  }

  /// Zona del esquema (hub + loggers). La grilla ya no depende de este rect.
  Rect _boardRect(Size size) {
    final bottom = math.max(0.0, size.height - boardBottom);
    return Rect.fromLTRB(0, 0, size.width, bottom);
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
      final color = _linkColor(points[index]);
      final hot = selected == index;
      final picked = selected != null;
      final alpha = hot
          ? 0.62 + breath * 0.28
          : picked
          ? 0.06 + breath * 0.04
          : 0.20 + breath * 0.16;
      final cell = RRect.fromRectAndRadius(plate, Radius.zero);
      canvas.drawRRect(
        cell,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = color.withValues(alpha: alpha * 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 2.2),
      );
      canvas.drawRRect(
        cell,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15
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

  void _paintDiveWash(Canvas canvas, Size size, double approach) {
    final t = Curves.easeInOutCubic.transform(approach.clamp(0.0, 1.0));
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF02080A).withValues(alpha: 0.5 * t),
    );
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
        ..strokeWidth = 2.4
        ..color = color.withValues(alpha: alpha * 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3),
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
      oldDelegate.approach != approach ||
      oldDelegate.gridTop != gridTop ||
      oldDelegate.boardBottom != boardBottom ||
      oldDelegate.pan != pan ||
      oldDelegate.points != points ||
      oldDelegate.anchors != anchors ||
      oldDelegate.plates != plates ||
      oldDelegate.hub != hub;
}

/// Enlaces de la página visible. Sale y entra con los loggers.
class _HubLinkPainter extends CustomPainter {
  _HubLinkPainter({
    required this.plates,
    required this.hub,
    required this.selected,
    required this.seconds,
    required this.motion,
  });

  final List<Rect> plates;
  final Rect hub;
  final int? selected;
  final double seconds;
  final bool motion;

  @override
  void paint(Canvas canvas, Size size) {
    if (hub.isEmpty || plates.isEmpty) return;
    final blocks = [...plates, hub];
    final links = captureHubLinks(plates, hub);
    for (var index = 0; index < links.length; index++) {
      final path = links[index];
      if (path.length < 2) continue;
      final hot = selected == index;
      final alpha = selected == null
          ? 0.62
          : hot
          ? 0.92
          : 0.22;
      final paint = Paint()
        ..color = const Color(0xFFD5E4E2).withValues(alpha: alpha)
        ..strokeWidth = hot ? 1.35 : 1.05
        ..strokeCap = StrokeCap.round;
      for (var step = 0; step < path.length - 1; step++) {
        _dashClipped(
          canvas,
          path[step],
          path[step + 1],
          blocks,
          paint,
          phase: motion ? seconds * 10 : 0,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HubLinkPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.selected != selected ||
      oldDelegate.motion != motion ||
      oldDelegate.hub != hub ||
      oldDelegate.plates != plates;
}

void _dashClipped(
  Canvas canvas,
  Offset a,
  Offset b,
  List<Rect> blocks,
  Paint paint, {
  required double phase,
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
    _dashLine(canvas, start, end, paint, phase: phase);
  }
}

void _dashLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  required double phase,
}) {
  final delta = b - a;
  final length = delta.distance;
  if (length < 1) return;
  final dir = delta / length;
  const dash = 6.0;
  const gap = 5.0;
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
double captureLoggerWidthFor(String title, {bool compliance = false}) {
  final painter = TextPainter(
    text: TextSpan(text: title, style: captureLoggerNameStyle),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  // Icono, nombre, lámpara y, si existe, la marca de cumplimiento.
  final chrome = 4.0 + 16 + 4 + 4 + (compliance ? 15 : 0) + 7 + 6;
  return math.max(56.0, chrome + painter.width);
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
bool captureHasCompliance(Map<String, dynamic> point) {
  final nested = point['dga'];
  if (nested is Map) {
    final info = DgaInfo.tryParse(Map<String, dynamic>.from(nested));
    if (info != null) return true;
  }
  return DgaInfo.tryParse(point) != null;
}

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
}) {
  if (size.isEmpty) return 1;
  var fitted = 1;
  for (var count = 1; count <= 24; count++) {
    final scheme = placeCaptureScheme(
      count,
      size,
      top: top,
      bottom: bottom,
      left: left,
    );
    final viewLeft = math.max(captureEdgePad, left);
    final viewRight = math.max(viewLeft, size.width - captureEdgePad);
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
  List<String>? groups,
  List<String>? labels,
}) {
  const hub = captureHubSize;
  if (count <= 0 || size.isEmpty) {
    return (plates: const <Rect>[], hub: Rect.zero);
  }
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

  final viewLeft = math.max(captureEdgePad, left);
  final viewRight = math.max(viewLeft + hub, size.width - captureEdgePad);
  final viewTop = math.max(captureEdgePad, top);
  final viewBottom = math.max(viewTop + hub, size.height - bottom);
  final hubRect = Rect.fromCenter(
    center: Offset((viewLeft + viewRight) / 2, (viewTop + viewBottom) / 2),
    width: hub,
    height: hub,
  );

  if (count == 1) {
    final plate = Rect.fromCenter(
      center: Offset(hubRect.center.dx, hubRect.top - capturePlateGap - capturePlateHeight / 2),
      width: capturePlateWidth,
      height: capturePlateHeight,
    );
    return (plates: [plate], hub: hubRect);
  }

  var scale = count <= 6 ? 1.0 : (1 - ((count - 6) / 40).clamp(0.0, 0.2));
  var placed = _compassPlates(order, hubRect, scale);
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
    if (scale <= 0.8) break;
    scale = math.max(0.8, scale - 0.05);
    placed = _compassPlates(order, hubRect, scale);
  }
  return (plates: placed, hub: hubRect);
}

List<Rect> _compassPlates(List<int> order, Rect hub, double scale) {
  final count = order.length;
  final pw = capturePlateWidth * scale;
  final ph = capturePlateHeight * scale;
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
}) {
  if (plate.isEmpty || hub.isEmpty) return const [];
  final dx = hub.center.dx - plate.center.dx;
  final dy = hub.center.dy - plate.center.dy;
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
  left.sort(byY);
  right.sort(byY);

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
  final attach = List<double?>.filled(plates.length, null);
  void assignY(List<int> side) {
    for (var i = 0; i < side.length; i++) {
      final t = (i + 1) / (side.length + 1);
      attach[side[i]] = hub.top + hub.height * t;
    }
  }

  assignY(left);
  assignY(right);
  return [
    for (var i = 0; i < plates.length; i++)
      if (above.contains(i) || below.contains(i))
        captureHubLink(plates[i], hub)
      else
        captureHubLink(
          plates[i],
          hub,
          attachY: attach[i],
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
  double windowWidth = 360,
  double windowHeight = 460,
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

  bool sameSlot(Rect a, Rect b) =>
      (a.left - b.left).abs() < 8 && (a.top - b.top).abs() < 8;

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
          if (hits(rect) || placed.any((other) => sameSlot(other, rect))) {
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
  final columns = math.max(
    1,
    ((usableW + gap) / (windowWidth + gap)).floor(),
  );
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
}) {
  if (count <= 0 || area.width <= 0 || area.height <= 0) {
    return (capacity: 1, pages: 1, rects: const <Rect>[]);
  }
  final usableW = math.max(windowWidth, area.width - leftInset);
  final columns = math.max(1, ((usableW + gap) / (windowWidth + gap)).floor());
  final usableH = math.max(windowHeight, area.height - bottomInset);
  final rows = math.max(1, ((usableH + gap) / (windowHeight + gap)).floor());
  final capacity = math.max(1, columns * rows);
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

class _DesktopSwitch extends StatelessWidget {
  const _DesktopSwitch({
    required this.index,
    required this.pages,
    required this.onPrev,
    required this.onNext,
  });

  final int index;
  final int pages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE60E1A1E),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Escritorio anterior',
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              visualDensity: VisualDensity.compact,
            ),
            Text(
              'Escritorio ${index + 1} / $pages',
              style: const TextStyle(
                color: Color(0xFFE8F2F1),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            IconButton(
              tooltip: 'Siguiente escritorio',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _SchemeMinimap extends StatelessWidget {
  const _SchemeMinimap({
    required this.plates,
    required this.hub,
    required this.selected,
    required this.onJump,
  });

  final List<Rect> plates;
  final Rect hub;
  final int? selected;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC0B1618),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 148,
        height: 96,
        child: GestureDetector(
          onTapDown: (details) {
            final local = details.localPosition;
            var best = -1;
            var bestD = 18.0;
            final bounds = _bounds();
            if (bounds == null) return;
            for (var i = 0; i < plates.length; i++) {
              final c = _map(plates[i].center, bounds, const Size(148, 96));
              final d = (c - local).distance;
              if (d < bestD) {
                best = i;
                bestD = d;
              }
            }
            if (best >= 0) onJump(best);
          },
          child: CustomPaint(
            painter: _MinimapPainter(
              plates: plates,
              hub: hub,
              selected: selected,
            ),
          ),
        ),
      ),
    );
  }

  Rect? _bounds() {
    if (hub.isEmpty && plates.isEmpty) return null;
    var rect = hub.isEmpty ? plates.first : hub;
    for (final plate in plates) {
      rect = rect.expandToInclude(plate);
    }
    return rect.inflate(8);
  }

  Offset _map(Offset point, Rect bounds, Size size) {
    final sx = bounds.width <= 0 ? 0.0 : (point.dx - bounds.left) / bounds.width;
    final sy = bounds.height <= 0 ? 0.0 : (point.dy - bounds.top) / bounds.height;
    return Offset(sx * size.width, sy * size.height);
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
      final sx = bounds.width <= 0 ? 0.0 : (point.dx - bounds.left) / bounds.width;
      final sy = bounds.height <= 0 ? 0.0 : (point.dy - bounds.top) / bounds.height;
      return Offset(sx * size.width, sy * size.height);
    }

    if (!hub.isEmpty) {
      final c = map(hub.center);
      canvas.drawCircle(c, 5, Paint()..color = IkoluColors.cyan);
    }
    for (var i = 0; i < plates.length; i++) {
      final c = map(plates[i].center);
      final active = i == selected;
      canvas.drawCircle(
        c,
        active ? 4.2 : 2.6,
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

/// Núcleo SMARTHYDRO. Muestra si el API responde en /health.
class _DataSmartCore extends StatelessWidget {
  const _DataSmartCore({this.clock, this.apiOnline});

  final ValueNotifier<double>? clock;
  final bool? apiOnline;

  @override
  Widget build(BuildContext context) {
    final online = apiOnline;
    final statusColor = online == null
        ? const Color(0xFF9AB0B1)
        : online
        ? const Color(0xFF66E0C2)
        : const Color(0xFFFF847A);
    final statusLabel = online == null
        ? 'API…'
        : online
        ? 'API en línea'
        : 'API fuera';

    Widget core(double glow) {
      final edge = 0.55 + 0.35 * glow;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: statusColor.withValues(alpha: edge),
            width: 1.4,
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF7FBFA).withValues(alpha: 0.22),
              const Color(0xFF14343C).withValues(alpha: 0.88),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hub_outlined, size: 16, color: statusColor),
            const SizedBox(height: 3),
            const Text(
              'SMARTHYDRO',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFFE7F4F2),
                fontSize: 7.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: statusColor.withValues(alpha: 0.92),
                fontSize: 7,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'SMARTHYDRO, $statusLabel',
      child: KeyedSubtree(
        key: const ValueKey('capture-hub'),
        child: clock == null
            ? core(0.45)
            : ValueListenableBuilder<double>(
                valueListenable: clock!,
                builder: (context, seconds, _) {
                  final glow = 0.5 + 0.5 * math.sin(seconds * 1.1);
                  return core(glow);
                },
              ),
      ),
    );
  }
}

class _BeaconPainter extends CustomPainter {
  _BeaconPainter({
    required this.color,
    required this.selected,
    required this.surface,
  });

  final Color color;
  final bool selected;
  final bool surface;

  static const _hole = Color(0xFF0B1418);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.45 : 1.15
      ..color = selected
          ? color.withValues(alpha: 0.92)
          : const Color(0xFFD5E4E2).withValues(alpha: 0.82);
    if (surface) {
      final side = math.min(size.width, size.height) * 0.62;
      final cell = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: size.center(Offset.zero),
          width: side,
          height: side,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(cell, Paint()..color = _hole);
      canvas.drawRRect(cell, stroke);
      canvas.drawLine(
        size.center(const Offset(-4, 0)),
        size.center(const Offset(4, 0)),
        stroke..strokeWidth = 1,
      );
      return;
    }
    final mouth = Offset(size.width / 2, size.height * 0.64);
    final housing = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: mouth,
        width: size.width * 0.78,
        height: size.height * 0.34,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(housing, Paint()..color = const Color(0xFF1A282E));
    canvas.drawRRect(housing, stroke);
    final tip = Offset(mouth.dx, size.height * 0.08);
    canvas.drawLine(
      Offset(mouth.dx, mouth.dy - size.height * 0.16),
      tip,
      Paint()
        ..color = const Color(0xFFD5E4E2)
        ..strokeWidth = 1.1,
    );
    canvas.drawCircle(tip, 1.7, Paint()..color = const Color(0xFFD5E4E2));
    canvas.drawCircle(
      mouth.translate(size.width * 0.18, 0),
      1.15,
      Paint()..color = const Color(0xFF9CC8C2),
    );
  }

  @override
  bool shouldRepaint(covariant _BeaconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.surface != surface;
}

class _NetworkHeader extends StatelessWidget {
  const _NetworkHeader({
    required this.points,
    required this.locationMode,
    required this.onToggleLocation,
    this.askBar,
  });

  final List<Map<String, dynamic>> points;
  final bool locationMode;
  final VoidCallback? onToggleLocation;
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
        if (onToggleLocation != null) ...[
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('capture-location-toggle'),
            tooltip: locationMode ? 'Volver al esquema' : 'Ver ubicaciones',
            onPressed: onToggleLocation,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              locationMode ? Icons.hub_outlined : Icons.location_on_outlined,
              color: const Color(0xFF9CC8C2),
              size: 20,
            ),
          ),
        ],
        const SizedBox(width: 4),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendDot(color: IkoluColors.connected, label: 'Conectado'),
            SizedBox(height: 3),
            _LegendDot(color: IkoluColors.warning, label: 'Advertencia'),
            SizedBox(height: 3),
            _LegendDot(color: IkoluColors.incident, label: 'Incidencia'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFB7C6C4), fontSize: 11),
        ),
      ],
    );
  }
}

/// Ficha compacta del punto elegido (móvil). Flota sobre el diagrama.
class _ViewRecords extends StatelessWidget {
  const _ViewRecords({
    required this.focus,
    required this.onEnter,
    required this.onClose,
    required this.openTickets,
    required this.compliance,
    required this.onRequestSupport,
  });

  final Map<String, dynamic> focus;
  final VoidCallback? onEnter;
  final VoidCallback onClose;
  final List<Map<String, dynamic>> openTickets;
  final List<Map<String, dynamic>> compliance;
  final ValueChanged<Map<String, dynamic>>? onRequestSupport;

  @override
  Widget build(BuildContext context) {
    return _FocusShell(
      key: const ValueKey('capture-view-records'),
      focus: focus,
      onEnter: onEnter,
      onClose: onClose,
      openTickets: openTickets,
      compliance: compliance,
      onRequestSupport: onRequestSupport,
    );
  }
}

/// Ventana compacta de un punto abierto (HOME web, mosaico).
class _PointWindow extends StatelessWidget {
  const _PointWindow({
    super.key,
    required this.focus,
    required this.onEnter,
    required this.onClose,
    required this.openTickets,
    required this.compliance,
    required this.onRequestSupport,
  });

  final Map<String, dynamic> focus;
  final VoidCallback? onEnter;
  final VoidCallback onClose;
  final List<Map<String, dynamic>> openTickets;
  final List<Map<String, dynamic>> compliance;
  final ValueChanged<Map<String, dynamic>>? onRequestSupport;

  @override
  Widget build(BuildContext context) {
    return _FocusShell(
      focus: focus,
      onEnter: onEnter,
      onClose: onClose,
      openTickets: openTickets,
      compliance: compliance,
      onRequestSupport: onRequestSupport,
    );
  }
}

class _FocusShell extends StatelessWidget {
  const _FocusShell({
    super.key,
    required this.focus,
    required this.onEnter,
    required this.onClose,
    required this.openTickets,
    required this.compliance,
    required this.onRequestSupport,
  });

  final Map<String, dynamic> focus;
  final VoidCallback? onEnter;
  final VoidCallback onClose;
  final List<Map<String, dynamic>> openTickets;
  final List<Map<String, dynamic>> compliance;
  final ValueChanged<Map<String, dynamic>>? onRequestSupport;

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xD6081216),
      ),
      child: HydroGlassLight(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        radius: 16,
        strength: 1.1,
        child: AnimatedSwitcher(
          duration: motion ? const Duration(milliseconds: 180) : Duration.zero,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _FocusedPoint(
            key: ValueKey('capture-board-focus-${_pointKey(focus)}'),
            point: focus,
            status: pointLinkLabel(pointLinkOf(focus)),
            onEnter: onEnter,
            onClose: onClose,
            openTickets: openTickets,
            compliance: compliance,
            onRequestSupport: onRequestSupport,
          ),
        ),
      ),
    );
  }
}

class _FocusedPoint extends StatelessWidget {
  const _FocusedPoint({
    super.key,
    required this.point,
    required this.status,
    required this.onEnter,
    required this.onClose,
    required this.openTickets,
    required this.compliance,
    required this.onRequestSupport,
  });

  final Map<String, dynamic> point;
  final String status;
  final VoidCallback? onEnter;
  final VoidCallback onClose;
  final List<Map<String, dynamic>> openTickets;
  final List<Map<String, dynamic>> compliance;
  final ValueChanged<Map<String, dynamic>>? onRequestSupport;

  @override
  Widget build(BuildContext context) {
    final reading = captureReadingLabel(point);
    final when = captureMeasuredAt(point);
    final last = reading == when ? when : '$reading · $when';
    final tickets = captureTicketsForPoint(point, openTickets);
    final complianceItem = captureComplianceFor(point, compliance);
    final color = _linkColor(point);
    final surface = captureIsSurface(point);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _FocusLoggerPlate(
                      color: color,
                      surface: surface,
                      selected: true,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _title(point),
                              style: const TextStyle(
                                color: Color(0xFFF4F8F6),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            TextSpan(
                              text: ' · $status',
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: Color(0xFFD5E4E2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ProfileLine(
                  surface ? Icons.waves_outlined : Icons.water_drop_outlined,
                  'Tipo',
                  captureKindLabel(point),
                ),
                _ProfileLine(
                  Icons.memory_outlined,
                  'Proveedor',
                  captureProviderLabel(point),
                ),
                _ProfileLine(
                  Icons.schedule_outlined,
                  'Frecuencia',
                  captureFrequencyLabel(point),
                ),
                _ProfileLine(
                  Icons.verified_outlined,
                  'Cumplimiento',
                  captureComplianceLabel(point, compliance: complianceItem),
                ),
                _ProfileLine(Icons.speed_outlined, 'Última medición', last),
                _ProfileLine(
                  Icons.update_outlined,
                  'Siguiente medición',
                  captureNextReading(point),
                ),
                _ProfileLine(
                  Icons.tune_outlined,
                  'Variables',
                  captureVariableLabel(point),
                  maxLines: 2,
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 14,
                      color: Color(0xFF9CC8C2),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Soporte',
                      style: TextStyle(
                        color: Color(0xFFB7C8C6),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                if (tickets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Sin tickets abiertos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFD5E4E2),
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  )
                else
                  for (final ticket in tickets)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        captureTicketLine(ticket),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD5E4E2),
                          fontSize: 11.5,
                          height: 1.2,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('capture-quick-ver'),
                onPressed: onEnter,
                icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE7F4F2),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                  minimumSize: const Size.fromHeight(36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                label: const Text('Entrar', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('capture-quick-support'),
                onPressed: () => onRequestSupport?.call(point),
                icon: const Icon(Icons.support_agent_outlined, size: 15),
                style: FilledButton.styleFrom(
                  foregroundColor: const Color(0xFFE7F4F2),
                  backgroundColor: const Color(0xFF1C4A46),
                  minimumSize: const Size.fromHeight(36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                label: const Text(
                  'Pedir soporte',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Mini caja de logger en el encabezado de la ficha (misma lectura que el mapa).
class _FocusLoggerPlate extends StatelessWidget {
  const _FocusLoggerPlate({
    required this.color,
    required this.surface,
    required this.selected,
  });

  final Color color;
  final bool surface;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('capture-focus-logger'),
      width: 44,
      height: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: selected ? 0.82 : 0.4),
            width: selected ? 1.5 : 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF7FBFA).withValues(alpha: 0.20),
              const Color(0xFF1A343C).withValues(alpha: 0.78),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CustomPaint(
                  painter: _BeaconPainter(
                    color: color,
                    selected: selected,
                    surface: surface,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.95),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine(this.icon, this.label, this.value, {this.maxLines = 1});

  final IconData icon;
  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: const Color(0xFF9CC8C2)),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 108,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB7C8C6),
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF4F8F6),
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

Color _linkColor(Map<String, dynamic> point) => switch (pointLinkOf(point)) {
  PointLink.connected => IkoluColors.connected,
  PointLink.gap => IkoluColors.warning,
  PointLink.incident => IkoluColors.incident,
};
