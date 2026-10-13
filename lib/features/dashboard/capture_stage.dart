import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/brand.dart';
import 'point_link.dart';
import 'point_meta.dart';

/// Tipo de captación. Expone la figura mínima para que otras presentaciones
/// puedan reutilizarla.
enum CaptureKind { well, surface }

CaptureKind captureKindOf(Map<String, dynamic> data) {
  final dga = data['dga'];
  final type = dga is Map
      ? (dga['type_dga'] as String? ?? '').toUpperCase()
      : '';
  return type == 'SUPERFICIAL' ? CaptureKind.surface : CaptureKind.well;
}

/// Ficha estática de la captación (`/point/{id}/config/`). Cada medida es
/// opcional: muchos puntos solo tienen algunas configuradas.
class CaptureProfile {
  const CaptureProfile({
    this.depth,
    this.pumpDepth,
    this.sensorDepth,
    this.ductInches,
    this.flowmeterInches,
    this.maxFlow,
  });

  factory CaptureProfile.fromConfig(Map<String, dynamic> config) =>
      CaptureProfile(
        depth: _positive(config['d1']),
        pumpDepth: _positive(config['d2']),
        sensorDepth: _positive(config['d3']),
        ductInches: _positive(config['d4']),
        flowmeterInches: _positive(config['d5']),
        maxFlow: _positive(config['max_flow_ls']),
      );

  /// d1 · profundidad del pozo (m).
  final double? depth;

  /// d2 · posicionamiento de la bomba (m).
  final double? pumpDepth;

  /// d3 · posicionamiento del sensor de nivel (m).
  final double? sensorDepth;

  /// d4 · diámetro del ducto de salida de la bomba (pulgadas).
  final double? ductInches;

  /// d5 · diámetro del flujómetro (pulgadas).
  final double? flowmeterInches;

  /// Caudal máximo de procesamiento (L/s); escala el chorro.
  final double? maxFlow;

  static double? _positive(dynamic value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
    return parsed;
  }
}

/// d4 y d5 llegan siempre en pulgadas. Se muestran en esa unidad.
String formatInches(double v) {
  final text = v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);
  return '$text"';
}

/// Partes de la escena que el usuario puede señalar para que se expliquen.
enum ScenePart {
  level,
  sensor,
  pump,
  depth,
  casing,
  aquifer,
  soil,
  rock,
  logger,
  flowmeter,
  water,
  intake,

  /// Poste y acometida que alimentan el tablero.
  power,

  /// La escena completa: qué representa y de dónde salen sus datos.
  overview,
}

/// Vista singular del punto: una lámina isométrica interactiva.
///
/// Volumen con el mismo formato que la lectura «Total» del panel.
String formatCubicMeters(double v) => '${formatCl(v, 1)} m³';

/// Caudal del flujómetro en formato chileno: `1.234,56 L/s`.
String formatLitersPerSecond(double v) => '${formatCl(v, 2)} L/s';

/// Número con separador de miles chileno: punto para miles y coma decimal
/// (`1.000.000,5`).
String formatCl(double v, int decimals) {
  final fixed = v.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  final sign = v < 0 && double.parse(fixed) != 0 ? '-' : '';
  final decimalsPart = parts.length > 1 ? ',${parts[1]}' : '';
  return '$sign$grouped$decimalsPart';
}

/// 0..1 del caudal respecto de [max] (50 L/s si no hay referencia).
double flowNormOf(double q, double? max) {
  final ref = math.max(max ?? 50, 0.01);
  return (q / ref).clamp(0.0, 1.0).toDouble();
}

/// Un bloque de terreno en corte que gira 360° al arrastrar y acompaña al
/// puntero. Solo se dibuja lo que el punto tiene: el pozo usa su ficha real
/// (profundidad, bomba, sensor, ductos) y las variables con dato; lo que no
/// existe no aparece. Al tocar un equipo o una lectura se muestran sus datos.
class CaptureStage extends StatefulWidget {
  const CaptureStage({
    required this.levelMeters,
    required this.levelFill,
    required this.flowLitersPerSecond,
    required this.isSurface,
    required this.link,
    this.profile = const CaptureProfile(),
    this.levelMin,
    this.levelMax,
    this.playing = false,
    this.flowMax,
    this.totalCubicMeters,
    this.loggerInfo,
    this.topInset = 56,
    super.key,
  });

  final double? levelMeters;
  final double? levelFill;
  final double? levelMin;
  final double? levelMax;
  final double? flowLitersPerSecond;
  final bool isSurface;
  final PointLink link;
  final CaptureProfile profile;

  /// Verdadero mientras el replay corre: el agua y el chorro cobran más vida.
  final bool playing;

  /// Caudal máximo del periodo mostrado; escala el flujómetro y el chorro.
  final double? flowMax;

  /// Volumen totalizado del flujómetro (m³).
  final double? totalCubicMeters;

  /// Ficha del tablero/logger (token, modelo, variables, DGA si aplica).
  final LoggerInfo? loggerInfo;

  /// Espacio reservado arriba para controles superpuestos.
  final double topInset;

  @override
  State<CaptureStage> createState() => _CaptureStageState();
}

class _CaptureStageState extends State<CaptureStage>
    with TickerProviderStateMixin {
  static const _baseYaw = 0.66;
  static const _basePitch = 0.46;
  static const _minZoom = 0.6;
  static const _maxZoom = 2.6;

  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..addListener(_ease);

  late final AnimationController _playPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  final _SceneHits _hits = _SceneHits();
  Size _viewSize = Size.zero;
  bool _touched = false;
  double _dragYaw = 0;
  double _dragPitch = 0;
  double _yaw = _baseYaw;
  double _pitch = _basePitch;
  ScenePart? _hoverPart;
  ScenePart? _pinnedPart;
  bool _tagsOn = true;
  double _tagsShown = 1;

  /// Valores mostrados: siguen a los del replay con suavidad para que el
  /// agua suba y baje de forma continua entre registros.
  double? _level;
  double? _napa;
  double? _shownFlow;
  double _levelMotion = 0;

  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastTick = Duration.zero;
  double _travel = 0;
  double _drift = 0;

  double _zoomTarget = 1;
  double _zoom = 1;
  Offset _panTarget = Offset.zero;
  Offset _pan = Offset.zero;
  double _scaleBase = 1;
  int _pointers = 0;

  double get _targetYaw => _baseYaw + _dragYaw;
  double get _targetPitch => (_basePitch + _dragPitch).clamp(0.20, 0.92);

  void _ease() {
    final now = _clock.elapsed;
    final dt = ((now - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = now;

    _yaw += (_targetYaw - _yaw) * 0.14;
    _pitch += (_targetPitch - _pitch) * 0.14;
    _zoom += (_zoomTarget - _zoom) * 0.11;
    _pan += (_panTarget - _pan) * 0.11;
    _tagsShown += ((_tagsOn ? 1.0 : 0.0) - _tagsShown) * 0.2;

    final q = (_shownFlow ?? 0).clamp(0.0, double.infinity).toDouble();
    final moving = q > 0.01 && widget.link != PointLink.gap;
    final norm = flowNormOf(q, widget.flowMax ?? widget.profile.maxFlow);
    _travel += dt * (moving ? 0.12 + norm * 0.9 : 0);
    _drift += dt * (0.08 + (widget.playing ? 0.06 : 0) + _levelMotion * 0.6);

    final level = widget.levelMeters;
    if (level == null || _napa == null) {
      _napa = level;
    } else {
      _napa = _napa! + (level - _napa!) * 0.025;
    }
    if (level == null || _level == null) {
      _level = level;
    } else {
      final delta = level - _level!;
      _level = _level! + delta * 0.06;
      final span = (widget.levelMax ?? 0) - (widget.levelMin ?? 0);
      final scale = span > 0.01 ? span : 1.0;
      _levelMotion = (_levelMotion * 0.92 + (delta.abs() / scale) * 0.6).clamp(
        0.0,
        1.0,
      );
    }
    final flow = widget.flowLitersPerSecond;
    if (flow == null || _shownFlow == null) {
      _shownFlow = flow;
    } else {
      _shownFlow = _shownFlow! + (flow - _shownFlow!) * 0.06;
    }
  }

  void _snapIfStatic() {
    if (_flow.isAnimating) return;
    setState(() {
      _yaw = _targetYaw;
      _pitch = _targetPitch;
      _zoom = _zoomTarget;
      _pan = _panTarget;
      _tagsShown = _tagsOn ? 1 : 0;
      _level = widget.levelMeters;
      _napa = widget.levelMeters;
      _shownFlow = widget.flowLitersPerSecond;
    });
  }

  @override
  void initState() {
    super.initState();
    _level = widget.levelMeters;
    _napa = widget.levelMeters;
    _shownFlow = widget.flowLitersPerSecond;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _intro.value = 1;
    } else if (_intro.isDismissed) {
      _intro.forward();
    }
    if (reduce) {
      _flow.stop();
      _flow.value = 0;
      _playPulse.stop();
      _playPulse.value = 0;
    } else if (!_flow.isAnimating) {
      _flow.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CaptureStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_flow.isAnimating) {
      _level = widget.levelMeters;
      _napa = widget.levelMeters;
      _shownFlow = widget.flowLitersPerSecond;
    }
    if (widget.playing && !oldWidget.playing) {
      _playPulse.repeat(reverse: true);
    } else if (!widget.playing && oldWidget.playing) {
      _playPulse.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    _playPulse.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _onHover(PointerHoverEvent event) {
    // Pasar el mouse solo cambia el cursor: la escena gira al arrastrar.
    final part = _dataPartAt(event.localPosition);
    if (part != _hoverPart) setState(() => _hoverPart = part);
  }

  void _onTapUp(TapUpDetails details) {
    final part = _dataPartAt(details.localPosition);
    setState(() {
      final wasLogger = _loggerOpen;
      final next = part == _pinnedPart ? null : part;
      _pinnedPart = next;
      if (_loggerOpen) {
        _focusLogger();
      } else if (wasLogger) {
        _frameScene();
      }
    });
  }

  bool get _loggerOpen =>
      _pinnedPart == ScenePart.logger || _pinnedPart == ScenePart.power;

  /// Vuelve el encuadre al soltar el tablero, sin perder el giro.
  void _frameScene() {
    _zoomTarget = 1;
    _panTarget = Offset.zero;
    _snapIfStatic();
  }

  /// Solo equipos y lecturas reales; no capas decorativas del corte.
  static const _dataParts = {
    ScenePart.level,
    ScenePart.sensor,
    ScenePart.pump,
    ScenePart.depth,
    ScenePart.logger,
    ScenePart.flowmeter,
    ScenePart.intake,
    ScenePart.power,
  };

  ScenePart? _dataPartAt(Offset point) {
    final part = _hits.at(point);
    if (part == null || !_dataParts.contains(part)) return null;
    return part;
  }

  /// Acerca la cámara al tablero para leer su ficha con comodidad.
  void _focusLogger() {
    final rect = _hits.boundsOf(ScenePart.logger);
    final size = _viewSize;
    if (size.isEmpty) {
      _setZoom(2.05);
      return;
    }
    _setZoom(2.05);
    final target =
        rect?.center ?? Offset(size.width * 0.28, size.height * 0.38);
    final center = Offset(size.width * 0.5, size.height * 0.42);
    _panTarget = (center - target) * 0.85;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _scaleBase = _zoomTarget;
    _pointers = details.pointerCount;
  }

  /// Un dedo (o el mouse) gira; dos dedos acercan y desplazan la vista.
  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount != _pointers) {
      _pointers = details.pointerCount;
      _scaleBase = _zoomTarget / details.scale;
    }
    if (details.pointerCount >= 2) {
      _setZoom(_scaleBase * details.scale);
      _panTarget += details.focalPointDelta;
    } else {
      final delta = details.focalPointDelta;
      _dragYaw -= delta.dx * 0.009;
      _dragPitch = (_dragPitch + delta.dy * 0.004).clamp(-0.28, 0.46);
    }
    if (!_touched) setState(() => _touched = true);
    _snapIfStatic();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _setZoom(_zoomTarget * math.exp(-event.scrollDelta.dy * 0.0015));
    if (!_touched) setState(() => _touched = true);
    _snapIfStatic();
  }

  void _setZoom(double value) {
    _zoomTarget = value.clamp(_minZoom, _maxZoom).toDouble();
    if (_zoomTarget <= 1) _panTarget *= _zoomTarget;
  }

  void _zoomBy(double factor) {
    setState(() => _setZoom(_zoomTarget * factor));
    _snapIfStatic();
  }

  /// Vuelve a la pose base por el camino más corto, sin dar vueltas extra.
  void _reset() {
    const tau = math.pi * 2;
    final turns = (_dragYaw / tau).roundToDouble();
    _yaw -= turns * tau;
    _dragYaw = 0;
    _dragPitch = 0;
    _zoomTarget = 1;
    _panTarget = Offset.zero;
    _snapIfStatic();
  }

  String _semantics() {
    final p = widget.profile;
    final parts = <String>[
      widget.isSurface ? 'Captación superficial' : 'Pozo subterráneo',
      if (widget.levelMeters != null)
        'nivel ${widget.levelMeters!.toStringAsFixed(2)} metros',
      if (widget.flowLitersPerSecond != null)
        'caudal ${widget.flowLitersPerSecond!.toStringAsFixed(2)} litros por segundo',
      if (p.depth != null) 'profundidad ${p.depth!.toStringAsFixed(1)} metros',
      if (p.pumpDepth != null)
        'bomba a ${p.pumpDepth!.toStringAsFixed(1)} metros',
      if (p.sensorDepth != null)
        'sensor a ${p.sensorDepth!.toStringAsFixed(1)} metros',
      pointLinkLabel(widget.link),
    ];
    return parts.join(', ');
  }

  String _m(double v) => '${v.toStringAsFixed(v >= 100 ? 0 : 1)} m';

  String _inches(double v) => formatInches(v);

  _SceneInfo _explain(ScenePart part) {
    final p = widget.profile;
    final level = widget.levelMeters;
    final flow = widget.flowLitersPerSecond;
    switch (part) {
      case ScenePart.level:
        return widget.isSurface
            ? _SceneInfo(
                title: 'Altura de agua',
                value: level == null ? null : '${level.toStringAsFixed(2)} m',
                body:
                    'Altura de la lámina de agua en el cauce medida por el '
                    'sensor. Sube con crecidas y baja en estiaje.',
                color: _Palette.level,
              )
            : _SceneInfo(
                title: 'Nivel freático',
                value: level == null ? null : '${level.toStringAsFixed(2)} m',
                body:
                    'Profundidad desde la superficie hasta el agua del '
                    'acuífero. Más metros significa que el agua está más '
                    'abajo.',
                color: _Palette.level,
              );
      case ScenePart.sensor:
        return _SceneInfo(
          title: 'Sensor de nivel',
          value: p.sensorDepth == null
              ? null
              : 'instalado a ${_m(p.sensorDepth!)}',
          body: widget.isSurface
              ? 'Mide desde arriba la distancia a la lámina de agua y la '
                    'convierte en altura.'
              : 'Sonda sumergida que mide la presión del agua sobre ella para '
                    'calcular el nivel. Debe quedar siempre bajo el agua.',
          color: _Palette.sensor,
        );
      case ScenePart.pump:
        final submergence = (p.pumpDepth != null && level != null)
            ? p.pumpDepth! - level
            : null;
        return _SceneInfo(
          title: 'Bomba',
          value: p.pumpDepth == null
              ? null
              : [
                  'a ${_m(p.pumpDepth!)}',
                  if (p.ductInches != null) 'ducto ${_inches(p.ductInches!)}',
                  if (submergence != null)
                    submergence >= 0
                        ? '${_m(submergence)} bajo el agua'
                        : 'sobre el nivel',
                ].join(' · '),
          body:
              'Extrae el agua del pozo y la impulsa a la superficie. Debe '
              'quedar bajo el nivel freático; si el agua baja de la bomba, '
              'trabaja en seco.',
          color: _Palette.pump,
        );
      case ScenePart.depth:
        return _SceneInfo(
          title: 'Fondo del pozo',
          value: p.depth == null ? null : _m(p.depth!),
          body: 'Profundidad total perforada, medida desde la superficie.',
          color: _Palette.fog,
        );
      case ScenePart.casing:
        return _SceneInfo(
          title: 'Entubación',
          value: null,
          body:
              'Tubo que sostiene las paredes del pozo. El tramo ranurado '
              '(criba) deja entrar el agua del acuífero.',
          color: _Palette.steel,
        );
      case ScenePart.aquifer:
        return _SceneInfo(
          title: 'Acuífero · zona saturada',
          value: null,
          body:
              'Terreno bajo el nivel freático cuyos poros están llenos de '
              'agua. Desde aquí el pozo se recarga.',
          color: _Palette.aquifer,
        );
      case ScenePart.soil:
        return _SceneInfo(
          title: 'Zona no saturada',
          value: null,
          body:
              'Terreno sobre el nivel freático: sus poros tienen aire y el '
              'agua solo lo atraviesa al infiltrarse.',
          color: _Palette.soilText,
        );
      case ScenePart.rock:
        return _SceneInfo(
          title: 'Bajo el fondo',
          value: null,
          body: 'Terreno bajo la perforación, fuera del alcance del pozo.',
          color: _Palette.faint,
        );
      case ScenePart.logger:
        final info = widget.loggerInfo;
        final sections =
            <({String title, List<({String label, String value})> fields})>[
              if (info != null && info.schemeFields.isNotEmpty)
                (title: 'Variables del esquema', fields: info.schemeFields),
              if (info?.dga != null && info!.dga!.fields.isNotEmpty)
                (title: 'Cumplimiento DGA', fields: info.dga!.fields),
            ];
        return _SceneInfo(
          title: 'Tablero eléctrico con datalogger',
          value: pointLinkLabel(widget.link),
          body:
              'Gabinete que instalamos en terreno: recibe la energía y aloja '
              'el datalogger. Las variables del esquema indican qué mide el '
              'equipo (str_variable) y a qué corresponde en SmartHydro.',
          color: _Palette.linkColor(widget.link),
          fields: info?.fields ?? const [],
          sections: sections,
        );
      case ScenePart.flowmeter:
        final total = widget.totalCubicMeters;
        return _SceneInfo(
          title: 'Flujómetro',
          value: () {
            final bits = <String>[
              if (flow != null) formatLitersPerSecond(flow),
              if (p.flowmeterInches != null) _inches(p.flowmeterInches!),
              if (total != null) 'total ${formatCubicMeters(total)}',
            ];
            return bits.isEmpty ? null : bits.join(' · ');
          }(),
          body:
              'Mide el caudal que sale por la impulsión y acumula el volumen '
              'total extraído (m³).',
          color: _Palette.flow,
        );
      case ScenePart.water:
        return _SceneInfo(
          title: 'Cauce',
          value: null,
          body:
              'Curso de agua superficial. Las líneas sobre la lámina muestran '
              'la corriente; más rápidas, más caudal.',
          color: _Palette.surfaceWater,
        );
      case ScenePart.power:
        return _SceneInfo(
          title: 'Alimentación eléctrica',
          value: null,
          body:
              'Energía que llega al tablero desde el empalme para mantener '
              'encendidos el datalogger y los sensores.',
          color: _Palette.sensor,
        );
      case ScenePart.overview:
        return _SceneInfo(
          title: 'Representación de tu instalación',
          value: null,
          body:
              'Modelo armado con la ficha técnica de este punto: solo aparece '
              'lo que está configurado y con datos. No es una foto; el agua, '
              'el nivel y el caudal cambian con cada medición y con el '
              'replay para que veas cómo se comporta tu captación.',
          color: _Palette.fog,
        );
      case ScenePart.intake:
        return _SceneInfo(
          title: 'Toma',
          value: flow == null ? null : formatLitersPerSecond(flow),
          body: 'Punto donde se capta el agua del cauce hacia la impulsión.',
          color: _Palette.flow,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    // La ficha solo aparece al hacer click; el hover solo cambia el cursor.
    final focus = _pinnedPart;
    return Semantics(
      container: true,
      label: _semantics(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          _viewSize = size;
          return MouseRegion(
            cursor: _hoverPart == null
                ? SystemMouseCursors.grab
                : SystemMouseCursors.click,
            onExit: (_) => setState(() => _hoverPart = null),
            onHover: _onHover,
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onTapUp: _onTapUp,
                onDoubleTap: _reset,
                child: ExcludeSemantics(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _flow,
                          _playPulse,
                          _intro,
                        ]),
                        builder: (context, _) {
                          final alive = widget.playing
                              ? 0.55 + _playPulse.value * 0.45
                              : _playPulse.value * 0.45;
                          return ColoredBox(
                            color: const Color(0xFF0A181D),
                            child: CustomPaint(
                              painter: _CaptureStagePainter(
                                phase: _flow.value,
                                yaw: _yaw,
                                pitch: _pitch,
                                layoutYaw: _baseYaw,
                                layoutPitch: _basePitch,
                                topInset: widget.topInset,
                                levelMeters: _level,
                                napaMeters: _napa,
                                levelMotion: _levelMotion,
                                levelMin: widget.levelMin,
                                levelMax: widget.levelMax,
                                textScaler: textScaler,
                                flow: _shownFlow,
                                isSurface: widget.isSurface,
                                link: widget.link,
                                profile: widget.profile,
                                alive: alive,
                                focus: focus,
                                hits: _hits,
                                travel: _travel,
                                drift: _drift,
                                flowMax: widget.flowMax,
                                totalCubicMeters: widget.totalCubicMeters,
                                zoom: _zoom,
                                pan: _pan,
                                intro: _intro.value,
                                tagsShown: _tagsShown,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          );
                        },
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: focus == null
                                ? IgnorePointer(
                                    key: const ValueKey('hint'),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedOpacity(
                                          opacity: _tagsOn ? 0.9 : 0,
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          child: const Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 14,
                                            runSpacing: 4,
                                            children: [
                                              _LegendRow(
                                                live: true,
                                                label: 'Telemetría en vivo',
                                              ),
                                              _LegendRow(
                                                live: false,
                                                label: 'Dato de la ficha',
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        AnimatedOpacity(
                                          opacity: _touched ? 0.35 : 0.75,
                                          duration: const Duration(
                                            milliseconds: 500,
                                          ),
                                          child: const _HintRow(),
                                        ),
                                      ],
                                    ),
                                  )
                                : _InfoCard(
                                    key: ValueKey(focus),
                                    info: _explain(focus),
                                    pinned: _pinnedPart == focus,
                                    onClose: () => setState(() {
                                      final wasLogger = _loggerOpen;
                                      _pinnedPart = null;
                                      if (wasLogger) _frameScene();
                                    }),
                                  ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _ViewControls(
                          onZoomIn: () => _zoomBy(1.25),
                          onZoomOut: () => _zoomBy(0.8),
                          onAbout: () => setState(
                            () =>
                                _pinnedPart = _pinnedPart == ScenePart.overview
                                ? null
                                : ScenePart.overview,
                          ),
                          onReset: () => setState(_reset),
                          tagsOn: _tagsOn,
                          onToggleTags: () {
                            setState(() => _tagsOn = !_tagsOn);
                            _snapIfStatic();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Controles de vista en el estilo de los chips del panel, sin borde de
/// color: información, rótulos, acercar, alejar y centrar.
class _ViewControls extends StatelessWidget {
  const _ViewControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onAbout,
    required this.onReset,
    required this.tagsOn,
    required this.onToggleTags,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onAbout;
  final VoidCallback onReset;
  final bool tagsOn;
  final VoidCallback onToggleTags;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback onTap) =>
        IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          icon: Icon(icon, color: _Palette.fog.withValues(alpha: 0.85)),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _Palette.card.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.info_outline_rounded, 'Qué estoy viendo', onAbout),
          button(
            tagsOn ? Icons.label_off_outlined : Icons.label_outline_rounded,
            tagsOn ? 'Ocultar rótulos' : 'Mostrar rótulos',
            onToggleTags,
          ),
          button(Icons.add_rounded, 'Acercar', onZoomIn),
          button(Icons.remove_rounded, 'Alejar', onZoomOut),
          button(Icons.center_focus_strong_rounded, 'Centrar vista', onReset),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.live, required this.label});

  final bool live;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: live ? _Palette.fog : null,
          border: live
              ? null
              : Border.all(color: _Palette.faint.withValues(alpha: 0.8)),
          boxShadow: live
              ? [
                  BoxShadow(
                    color: _Palette.fog.withValues(alpha: 0.5),
                    blurRadius: 5,
                  ),
                ]
              : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          color: _Palette.fog.withValues(alpha: 0.8),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _SceneInfo {
  const _SceneInfo({
    required this.title,
    this.value,
    required this.body,
    required this.color,
    this.fields = const [],
    this.sections = const [],
  });

  final String title;
  final String? value;
  final String body;
  final Color color;
  final List<({String label, String value})> fields;
  final List<({String title, List<({String label, String value})> fields})>
  sections;
}

class _HintRow extends StatelessWidget {
  const _HintRow();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.threed_rotation_rounded, size: 14, color: _Palette.faint),
      SizedBox(width: 6),
      Flexible(
        child: Text(
          'Representación de tu instalación · arrastra o pellizca · '
          'toca un equipo o una lectura para ver sus datos',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _Palette.faint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.info,
    required this.pinned,
    required this.onClose,
    super.key,
  });

  final _SceneInfo info;
  final bool pinned;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _Palette.card.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 22),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: info.title,
                            style: TextStyle(
                              color: info.color,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          if (info.value != null)
                            TextSpan(
                              text: '  ${info.value}',
                              style: const TextStyle(
                                color: _Palette.fog,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      info.body,
                      style: TextStyle(
                        color: _Palette.fog.withValues(alpha: 0.78),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    if (info.fields.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...info.fields.map(_fieldRow),
                    ],
                    for (final section in info.sections) ...[
                      const SizedBox(height: 10),
                      Text(
                        section.title,
                        style: TextStyle(
                          color: info.color.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...section.fields.map(_fieldRow),
                    ],
                  ],
                ),
              ),
              if (pinned)
                IconButton(
                  tooltip: 'Cerrar',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: _Palette.faint),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldRow(({String label, String value}) field) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            field.label,
            style: TextStyle(
              color: _Palette.faint.withValues(alpha: 0.95),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Text(
            field.value,
            style: const TextStyle(
              color: _Palette.fog,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
      ],
    ),
  );
}

abstract final class _Palette {
  static const card = Color(0xFF0F2227);
  static const fog = Color(0xFFE8F2F1);
  static const faint = Color(0xFF9AB0B1);
  static const steel = Color(0xFFB4C7C8);
  static const coral = Color(0xFFFF847A);

  /// Mismos acentos que las lecturas del panel: nivel violeta, caudal cian.
  static const level = Color(0xFFC3B1F0);
  static const flow = IkoluColors.cyan;
  static const sensor = Color(0xFFFFD27A);
  static const pump = steel;

  static const wellWater = IkoluColors.cyan;
  static const surfaceWater = Color(0xFF69B9FF);
  static const aquifer = Color(0xFF4A9BEA);
  static const soilText = Color(0xFFD2C29A);

  static Color linkColor(PointLink link) => switch (link) {
    PointLink.connected => const Color(0xFF66E0C2),
    PointLink.gap => const Color(0xFFFFC46B),
    PointLink.incident => coral,
  };
}

/// Regiones señalables registradas por el pintor en cada cuadro.
class _SceneHits {
  final List<(ScenePart, Path)> _regions = [];

  void clear() => _regions.clear();

  void add(ScenePart part, Path path) => _regions.add((part, path));

  void rect(ScenePart part, Rect rect) => add(part, Path()..addRect(rect));

  ScenePart? at(Offset point) {
    for (final (part, path) in _regions.reversed) {
      if (path.contains(point)) return part;
    }
    return null;
  }

  Rect? boundsOf(ScenePart part) {
    for (final (p, path) in _regions.reversed) {
      if (p == part) return path.getBounds();
    }
    return null;
  }
}

/// Proyección axonométrica con giro (yaw) e inclinación (pitch). `y` es la
/// altura en píxeles (negativa bajo el terreno).
class _Iso {
  _Iso(this.origin, double yaw, double pitch, {this.scale = 1})
    : cy = math.cos(yaw),
      sy = math.sin(yaw),
      ps = math.sin(pitch),
      pc = math.cos(pitch);

  final Offset origin;

  /// Zoom de la vista: escala el bloque y todos los equipos por igual.
  final double scale;
  final double cy;
  final double sy;
  final double ps;
  final double pc;

  /// Signo de las caras laterales que miran al observador.
  double get sx => sy >= 0 ? 1 : -1;
  double get sz => cy >= 0 ? 1 : -1;

  Offset p(double x, double y, double z) {
    final xr = (x * cy - z * sy) * scale;
    final zr = (x * sy + z * cy) * scale;
    return Offset(origin.dx + xr, origin.dy - y * scale * pc + zr * ps);
  }

  /// Óvalo de un círculo horizontal: la proyección no depende del giro.
  Rect ring(double y, double radius, {double x = 0, double z = 0}) =>
      Rect.fromCenter(
        center: p(x, y, z),
        width: radius * 2 * scale,
        height: radius * 2 * ps * scale,
      );

  /// Cara lateral en x = ±h visible, entre las alturas [y0] y [y1].
  List<Offset> xFace(double h, double y0, double y1) => [
    p(sx * h, y0, -h * sx),
    p(sx * h, y0, h * sx),
    p(sx * h, y1, h * sx),
    p(sx * h, y1, -h * sx),
  ];

  /// Cara lateral en z = ±h visible, entre las alturas [y0] y [y1].
  List<Offset> zFace(double h, double y0, double y1) => [
    p(-h * sz, y0, sz * h),
    p(h * sz, y0, sz * h),
    p(h * sz, y1, sz * h),
    p(-h * sz, y1, sz * h),
  ];
}

/// Encuadra el bloque en el área libre con una proporción fija.
///
/// [depthFactor] es la profundidad del corte respecto del semiancho del
/// terreno. El conjunto crece o se reduce parejo: si la vista es alta no se
/// estira en una torre, y si es baja no se sale del marco.
({double half, double depth, Offset origin, Size footprint})
captureSceneLayout({
  required Size size,
  required double yaw,
  required double pitch,
  required double topInset,
  required double depthFactor,
  required double headroom,
  double zoom = 1,
  Offset pan = Offset.zero,
  double widthLimit = 0.56,
  double bottomInset = 76,
  double fill = 0.92,
}) {
  final availH = math.max(160.0, size.height - topInset - bottomInset);
  final maxDiamond = math.max(120.0, size.width * widthLimit);

  Rect measure(double half, double depth) {
    final probe = _Iso(Offset.zero, yaw, pitch);
    final corners = [
      for (final x in [-half, half])
        for (final z in [-half, half])
          for (final y in [headroom, -depth]) probe.p(x, y, z),
    ];
    var left = double.infinity, top = double.infinity;
    var right = -double.infinity, bottom = -double.infinity;
    for (final p in corners) {
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  final spread = math.sin(yaw).abs() + math.cos(yaw).abs();
  var half = maxDiamond / (2 * spread);
  var depth = math.max(64.0, half * depthFactor);
  var bounds = measure(half, depth);
  for (var i = 0; i < 4; i++) {
    final fitW = maxDiamond / math.max(bounds.width, 1);
    final fitH = (availH * fill) / math.max(bounds.height, 1);
    final fit = math.min(fitW, fitH);
    if ((fit - 1).abs() < 0.025) break;
    half = (half * fit).clamp(24.0, 420.0);
    depth = math.max(64.0, half * depthFactor);
    bounds = measure(half, depth);
  }
  final target = Offset(size.width / 2, topInset + availH / 2);
  return (
    half: half,
    depth: depth,
    origin: target - bounds.center * zoom + pan,
    footprint: bounds.size,
  );
}

/// Rótulo de una parte: leyenda corta en mayúsculas + valor destacado.
class _Tag {
  _Tag(
    this.part,
    this.caption,
    this.value,
    this.anchor,
    this.color, {
    this.detail,
    this.lift = 0,
    this.live = false,
    this.nudge = 0,
    this.left,
  });

  /// Desplaza el rótulo hacia arriba (positivo) o abajo para sacarlo de la
  /// figura cuando hay espacio libre.
  final double lift;

  /// Valor de telemetría que cambia con cada medición; si es falso, el
  /// rótulo muestra un dato fijo de la ficha técnica.
  final bool live;

  /// Corre la tarjeta hacia afuera de la figura (px).
  final double nudge;

  /// Fija el lado de la tarjeta; si es nulo se decide por el ancla.
  final bool? left;
  final ScenePart part;
  final String caption;
  final String value;
  final String? detail;
  final Offset anchor;
  final Color color;
}

class _CaptureStagePainter extends CustomPainter {
  _CaptureStagePainter({
    required this.phase,
    required this.yaw,
    required this.pitch,
    required this.layoutYaw,
    required this.layoutPitch,
    required this.topInset,
    required this.levelMeters,
    this.napaMeters,
    required this.levelMotion,
    required this.levelMin,
    required this.levelMax,
    required this.textScaler,
    required this.flow,
    required this.isSurface,
    required this.link,
    required this.profile,
    required this.alive,
    required this.focus,
    required this.hits,
    required this.travel,
    required this.drift,
    this.flowMax,
    this.totalCubicMeters,
    this.zoom = 1,
    this.pan = Offset.zero,
    this.intro = 1,
    this.tagsShown = 1,
  });

  /// Progreso 0..1 de la entrada inicial de la escena.
  final double intro;

  /// Visibilidad 0..1 de los rótulos (el usuario puede ocultarlos).
  final double tagsShown;

  final double phase;

  /// Avance acumulado del agua en tuberías y estanque (crece con el caudal).
  /// Al integrarse en el tiempo nunca salta al cambiar la velocidad.
  final double travel;

  /// Avance acumulado de la lámina y el acuífero (crece con la agitación).
  final double drift;
  final double? flowMax;
  final double? totalCubicMeters;
  final double zoom;
  final Offset pan;
  final double yaw;
  final double pitch;
  final double layoutYaw;
  final double layoutPitch;
  final double topInset;
  final double? levelMeters;

  /// Nivel que sigue la napa: el del pozo, pero con más retardo.
  final double? napaMeters;
  final double levelMotion;
  final double? levelMin;
  final double? levelMax;
  final TextScaler textScaler;
  final double? flow;
  final bool isSurface;
  final PointLink link;
  final CaptureProfile profile;
  final double alive;
  final ScenePart? focus;
  final _SceneHits hits;

  static const _tau = math.pi * 2;

  Size _size = Size.zero;

  double get _q => (flow ?? 0).clamp(0.0, double.infinity).toDouble();

  bool get _flowing => _q > 0.01 && link != PointLink.gap;

  /// 0..1 respecto del máximo del periodo (o del configurado) para que las
  /// variaciones del replay se noten aunque el caudal sea bajo.
  double get _flowNorm => flowNormOf(_q, flowMax ?? profile.maxFlow);

  /// Vida del agua: base + replay + movimiento real del nivel.
  double get _agitation => (0.25 + alive * 0.5 + levelMotion).clamp(0.0, 1.4);

  /// Color del agua: más cian y vivo con más caudal; más apagado si hay poco.
  Color get _waterTone {
    final n = _flowing ? _flowNorm : 0.0;
    return Color.lerp(
      const Color(0xFF3A5866),
      isSurface ? _Palette.surfaceWater : _Palette.wellWater,
      (0.28 + n * 0.72).clamp(0.0, 1.0),
    )!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    hits.clear();
    final backdrop = Offset.zero & size;
    // Fondo oscuro siempre: si algo falla al dibujar, no queda blanco.
    canvas.drawRect(backdrop, Paint()..color = const Color(0xFF0A181D));
    final saved = canvas.getSaveCount();
    try {
      _paintScene(canvas, size, backdrop);
    } catch (error, stack) {
      canvas.restoreToCount(saved);
      assert(() {
        // ignore: avoid_print
        print('CaptureStage paint error: $error\n$stack');
        return true;
      }());
    }
  }

  void _paintScene(Canvas canvas, Size size, Rect backdrop) {
    canvas.drawRect(
      backdrop,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.1,
          colors: [Color(0xFF10282E), Color(0xFF0A181D), Color(0xFF060F12)],
          stops: [0, 0.6, 1],
        ).createShader(backdrop),
    );
    // Entrada: el bloque sube y aparece; agua, equipos y rótulos le siguen.
    final enter = _introAt(0, 0.55);
    final layered = enter < 1;
    if (layered) {
      canvas.saveLayer(
        backdrop,
        Paint()..color = Colors.white.withValues(alpha: enter),
      );
      canvas.translate(0, (1 - enter) * 26);
    }
    if (isSurface) {
      _paintSurface(canvas, size);
    } else {
      _paintWell(canvas, size);
    }
    if (layered) canvas.restore();
  }

  /// Avance 0..1 de un tramo de la entrada, con salida suave.
  double _introAt(double from, double to) => Curves.easeOutCubic.transform(
    ((intro - from) / (to - from)).clamp(0.0, 1.0).toDouble(),
  );

  // ---------------------------------------------------------------- layout

  /// Tamaño del bloque y origen para que quede centrado en el área libre. Se
  /// usa la pose base para que el encuadre no salte al girar.
  ({double half, double depth, Offset origin, Size footprint}) _layout(
    Size size, {
    required double depthFactor,
    required double headroom,
    double widthLimit = 0.56,
    double fill = 0.92,
  }) => captureSceneLayout(
    size: size,
    yaw: layoutYaw,
    pitch: layoutPitch,
    topInset: topInset,
    depthFactor: depthFactor,
    headroom: headroom,
    zoom: zoom,
    pan: pan,
    widthLimit: widthLimit,
    fill: fill,
  );

  Rect _boundsOf(List<Offset> points) {
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    for (final p in points) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  Offset _bilerp(List<Offset> q, double u, double v) {
    final top = Offset.lerp(q[0], q[1], u)!;
    final bottom = Offset.lerp(q[3], q[2], u)!;
    return Offset.lerp(top, bottom, v)!;
  }

  // -------------------------------------------------------------- texturas

  void _soilBand(Canvas canvas, List<Offset> q, {required double shade}) {
    final bounds = _boundsOf(q);
    canvas.drawPath(
      _poly(q),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(const Color(0xFF37433A), Colors.black, shade)!,
            Color.lerp(const Color(0xFF232C26), Colors.black, shade)!,
          ],
        ).createShader(bounds),
    );
    final strata = Paint()
      ..color = _Palette.soilText.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final v = i / 4 + math.sin(i * 1.7) * 0.04;
      canvas.drawLine(_bilerp(q, 0, v), _bilerp(q, 1, v), strata);
    }
  }

  void _aquiferBand(Canvas canvas, List<Offset> q, {required double shade}) {
    final bounds = _boundsOf(q);
    canvas.drawPath(
      _poly(q),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(const Color(0xFF15476A), Colors.black, shade)!,
            Color.lerp(const Color(0xFF0B2943), Colors.black, shade)!,
          ],
        ).createShader(bounds),
    );
    // Flujo subterráneo: ondas tenues que se desplazan sin reiniciarse.
    final current = Paint()
      ..color = const Color(
        0xFFA9DBFF,
      ).withValues(alpha: 0.07 + _flowNorm * 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var row = 0; row < 3; row++) {
      final v = 0.24 + row * 0.26;
      final line = Path();
      for (var s = 0; s <= 32; s++) {
        final u = s / 32;
        final pt = _bilerp(q, u, v);
        final y = pt.dy + math.sin(u * _tau * 2 - drift * _tau + row) * 1.6;
        if (s == 0) {
          line.moveTo(pt.dx, y);
        } else {
          line.lineTo(pt.dx, y);
        }
      }
      canvas.drawPath(line, current);
    }
  }

  void _rockBand(Canvas canvas, List<Offset> q, {required double shade}) {
    canvas.drawPath(
      _poly(q),
      Paint()
        ..color = Color.lerp(
          const Color(0xFF3A474C),
          Colors.black,
          shade * 0.35,
        )!,
    );
    canvas.save();
    canvas.clipPath(_poly(q));
    final hatch = Paint()
      ..color = _Palette.fog.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    final b = _boundsOf(q);
    for (var x = b.left - b.height; x < b.right; x += 9) {
      canvas.drawLine(Offset(x, b.bottom), Offset(x + b.height, b.top), hatch);
    }
    canvas.restore();
  }

  void _waterTableLine(Canvas canvas, List<Offset> q) {
    final line = Path();
    for (var s = 0; s <= 28; s++) {
      final u = s / 28;
      final pt = _bilerp(q, u, 0);
      final y = pt.dy + math.sin(u * _tau * 2 + phase * _tau * 2) * 1.4;
      if (s == 0) {
        line.moveTo(pt.dx, y);
      } else {
        line.lineTo(pt.dx, y);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = _Palette.aquifer.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFFBFE4FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  /// Caja isométrica pequeña (datalogger, bomba de superficie).
  Rect _box(
    Canvas canvas,
    _Iso iso, {
    required double x,
    required double z,
    required double w,
    required double d,
    required double h,
    required Color color,
    double y = 0,
  }) {
    final hw = w / 2, hd = d / 2;
    final top = [
      iso.p(x - hw, y + h, z - hd),
      iso.p(x + hw, y + h, z - hd),
      iso.p(x + hw, y + h, z + hd),
      iso.p(x - hw, y + h, z + hd),
    ];
    final fx = x + iso.sx * hw;
    final xSide = [
      iso.p(fx, y + h, z - hd),
      iso.p(fx, y + h, z + hd),
      iso.p(fx, y, z + hd),
      iso.p(fx, y, z - hd),
    ];
    final fz = z + iso.sz * hd;
    final zSide = [
      iso.p(x - hw, y + h, fz),
      iso.p(x + hw, y + h, fz),
      iso.p(x + hw, y, fz),
      iso.p(x - hw, y, fz),
    ];
    canvas.drawPath(
      _poly(xSide),
      Paint()..color = Color.lerp(color, Colors.black, 0.35)!,
    );
    canvas.drawPath(
      _poly(zSide),
      Paint()..color = Color.lerp(color, Colors.black, 0.18)!,
    );
    canvas.drawPath(_poly(top), Paint()..color = color);
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawPath(_poly(top), edge);
    return _boundsOf([...top, ...xSide, ...zSide]);
  }

  /// Cilindro vertical en el mismo espacio del pozo (bomba, sonda, ducto).
  Rect _paintColumn(
    Canvas canvas,
    _Iso iso, {
    required double x,
    required double z,
    required double y0,
    required double y1,
    required double radius,
    required Color color,
  }) {
    final low = math.min(y0, y1);
    final high = math.max(y0, y1);
    final top = iso.ring(high, radius, x: x, z: z);
    final bottom = iso.ring(low, radius, x: x, z: z);
    final shade = Rect.fromLTRB(
      math.min(top.left, bottom.left),
      top.top,
      math.max(top.right, bottom.right),
      bottom.bottom,
    );
    if (bottom.center.dy - top.center.dy < 1.5) {
      canvas.drawOval(top, Paint()..color = color);
      return top;
    }
    final body = Path()
      ..moveTo(top.left, top.center.dy)
      ..lineTo(top.right, top.center.dy)
      ..lineTo(bottom.right, bottom.center.dy)
      ..lineTo(bottom.left, bottom.center.dy)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(color, Colors.black, 0.42)!,
            color,
            Color.lerp(color, Colors.white, 0.22)!,
            Color.lerp(color, Colors.black, 0.2)!,
          ],
          stops: const [0, 0.34, 0.62, 1],
        ).createShader(shade),
    );
    canvas.drawOval(
      bottom,
      Paint()..color = Color.lerp(color, Colors.black, 0.32)!,
    );
    canvas.drawOval(
      top,
      Paint()..color = Color.lerp(color, Colors.white, 0.18)!,
    );
    return shade;
  }

  // ------------------------------------------------------------------ pozo

  void _paintWell(Canvas canvas, Size size) {
    final meters = profile.depth;
    final depthFactor = meters == null
        ? 2.4
        : 2.15 + ((meters - 12) / 140).clamp(0.0, 1.0) * 0.7;
    final l = _layout(
      size,
      depthFactor: depthFactor,
      headroom: 36,
      widthLimit: 0.7,
      fill: 0.99,
    );
    final iso = _Iso(
      l.origin,
      yaw + math.sin(phase * _tau) * 0.015,
      pitch,
      scale: zoom,
    );
    final half = l.half;
    final known = profile.depth != null;
    final blockPx = l.depth;
    final wellPx = known ? blockPx * 0.9 : blockPx;

    final candidates = <double>[
      ?profile.pumpDepth,
      ?profile.sensorDepth,
      ?levelMeters,
      ?levelMax,
    ];
    final deepest = candidates.isEmpty ? 0.0 : candidates.reduce(math.max);
    final depthM = profile.depth ?? math.max(30.0, deepest * 1.3);
    final m2px = wellPx / depthM;
    double yAt(double meters) => -(meters.clamp(0.0, depthM).toDouble() * m2px);

    final levelY = levelMeters == null ? null : yAt(levelMeters!);
    final bottomY = -wellPx;
    // La napa del terreno va siempre un tramo bajo el agua del pozo y la
    // sigue con retardo: al bajar el nivel se ve cuánta napa se extrae.
    final napaGap = math.max(10.0, wellPx * 0.06);
    final napaY = levelMeters == null
        ? null
        : math.max(
            (known ? bottomY : -blockPx) + 2,
            math.min(
                  levelY! - napaGap * 0.6,
                  yAt(napaMeters ?? levelMeters!) - napaGap,
                ) +
                math.sin(phase * _tau) * (0.6 + _flowNorm * 1.2),
          );
    final blockBottom = -blockPx;
    final outerR = half * 0.25;
    final innerR = outerR * 0.78;
    final axis = iso.p(0, 0, 0);

    // Sombra.
    canvas.drawOval(
      Rect.fromCenter(
        center: iso.p(0, blockBottom, 0) + const Offset(0, 18),
        width: half * 3.1 * iso.scale,
        height: half * 3.1 * iso.ps * 0.6 * iso.scale,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    final sceneBounds = Offset.zero & size;
    if (!known) canvas.saveLayer(sceneBounds, Paint());

    final waterIn = _introAt(0.35, 0.9);
    final gearIn = _introAt(0.3, 0.75);
    final waterY = levelY == null
        ? null
        : bottomY + (levelY - bottomY) * waterIn;
    final water = _waterTone;

    List<Offset> Function(double, double) xPlane(
      double x,
      double z0,
      double z1,
    ) =>
        (y0, y1) => [
          iso.p(x, y0, z0),
          iso.p(x, y0, z1),
          iso.p(x, y1, z1),
          iso.p(x, y1, z0),
        ];
    List<Offset> Function(double, double) zPlane(
      double z,
      double x0,
      double x1,
    ) =>
        (y0, y1) => [
          iso.p(x0, y0, z),
          iso.p(x1, y0, z),
          iso.p(x1, y1, z),
          iso.p(x0, y1, z),
        ];
    double depthOf(double x, double z) => x * iso.sy + z * iso.cy;
    bool facing(double nx, double nz) => nx * iso.sy + nz * iso.cy > 0.001;

    // Cara del bloque por bandas: suelo, acuífero y bajo el fondo.
    void paintStrata(List<Offset> Function(double, double) band, double shade) {
      final dryBottom = napaY ?? (known ? bottomY : blockBottom);
      _soilBand(canvas, band(0, dryBottom), shade: shade);
      if (napaY != null) {
        final wetBottom = known ? bottomY : blockBottom;
        if (wetBottom < napaY) {
          _aquiferBand(canvas, band(napaY, wetBottom), shade: shade);
        }
      }
      if (known) _rockBand(canvas, band(bottomY, blockBottom), shade: shade);
      if (napaY != null) _waterTableLine(canvas, band(napaY, napaY - 1));
      canvas.drawPath(
        _poly(band(0, blockBottom)),
        Paint()
          ..color = _Palette.fog.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke,
      );
    }

    // Sección del pozo sobre una cara del corte: interior, agua y entubado.
    final hollows = <Path>[];
    void paintSection(bool alongZ) {
      final hollow = alongZ ? xPlane(0, 0, innerR) : zPlane(0, 0, innerR);
      final shell = alongZ
          ? xPlane(0, innerR, outerR)
          : zPlane(0, innerR, outerR);
      final inside = hollow(0, bottomY);
      final insidePath = _poly(inside);
      hollows.add(insidePath);
      canvas.drawPath(
        insidePath,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E434C), Color(0xFF122B32), Color(0xFF0B1C21)],
          ).createShader(_boundsOf(inside)),
      );
      if (waterY != null && waterY > bottomY + 1) {
        final wet = hollow(waterY, bottomY);
        final wetPath = _poly(wet);
        final wetBounds = _boundsOf(wet);
        canvas.drawPath(
          wetPath,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                water.withValues(alpha: 0.62 + _flowNorm * 0.18),
                water.withValues(alpha: 0.42 + _flowNorm * 0.14),
                const Color(0xFF0B3550).withValues(alpha: 0.9),
              ],
              stops: const [0, 0.45, 1],
            ).createShader(wetBounds),
        );
        canvas.save();
        canvas.clipPath(wetPath);
        for (var i = 0; i < 3; i++) {
          final t = (drift * 0.35 + i / 3) % 1;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(
                wetBounds.center.dx,
                wetBounds.top + t * wetBounds.height,
              ),
              width: wetBounds.width * 1.2,
              height: 12,
            ),
            Paint()
              ..color = _Palette.fog.withValues(
                alpha: (0.05 + _flowNorm * 0.06) * math.sin(t * math.pi),
              )
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          );
        }
        canvas.restore();
        canvas.drawLine(
          wet[0],
          wet[1],
          Paint()
            ..color = _Palette.fog.withValues(alpha: 0.85)
            ..strokeWidth = 1.3,
        );
      }

      final wall = shell(0, bottomY);
      canvas.drawPath(
        _poly(wall),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF5F7576), Color(0xFFD3E0E0), Color(0xFF6F8687)],
          ).createShader(_boundsOf(wall)),
      );
      final screenTop = math.min(
        levelY ?? bottomY * 0.7,
        bottomY + (-bottomY) * 0.32,
      );
      final slot = Paint()
        ..color = const Color(0xFF0A1A1F)
        ..strokeWidth = 1.2;
      for (var y = bottomY + 6; y < screenTop - 2; y += 5) {
        final row = shell(y, y);
        canvas.drawLine(
          Offset.lerp(row[0], row[1], 0.2)!,
          Offset.lerp(row[0], row[1], 0.8)!,
          slot,
        );
      }
      canvas.drawPath(
        _poly(wall),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      if (known) {
        final floor = alongZ
            ? xPlane(0, 0, outerR)(bottomY, bottomY)
            : zPlane(0, 0, outerR)(bottomY, bottomY);
        canvas.drawLine(
          floor[0],
          floor[1],
          Paint()
            ..color = _Palette.fog.withValues(alpha: 0.75)
            ..strokeWidth = 1.6,
        );
      }
    }

    final tags = <_Tag>[];

    // Equipos dentro del pozo, a escala del entubado.
    final logger = (x: -half * 0.58, z: half * 0.40);
    final sensorAt = (x: innerR * 0.2, z: innerR * 0.6);
    void paintSensor() {
      if (profile.sensorDepth == null) return;
      final sy = yAt(profile.sensorDepth!);
      final probeR = innerR * 0.07;
      final probeH = innerR * 0.85;
      canvas.drawLine(
        iso.p(sensorAt.x, 2, sensorAt.z),
        iso.p(sensorAt.x, sy + probeH / 2, sensorAt.z),
        Paint()
          ..color = _Palette.sensor.withValues(alpha: 0.6)
          ..strokeWidth = math.max(0.7, probeR * iso.scale * 0.4),
      );
      final probe = _paintColumn(
        canvas,
        iso,
        x: sensorAt.x,
        z: sensorAt.z,
        y0: sy - probeH / 2,
        y1: sy + probeH / 2,
        radius: probeR,
        color: _Palette.sensor,
      );
      hits.rect(ScenePart.sensor, probe.inflate(6));
      // La tarjeta del sensor va justo debajo de la de la bomba para no
      // taparla, aunque el sensor esté instalado más arriba.
      final anchor = iso.p(sensorAt.x, sy, sensorAt.z);
      final pumpAt = profile.pumpDepth == null
          ? null
          : iso.p(0, yAt(profile.pumpDepth!), 0).dy;
      tags.add(
        _Tag(
          ScenePart.sensor,
          'SENSOR DE NIVEL',
          _m(profile.sensorDepth!),
          anchor,
          _Palette.sensor,
          lift: pumpAt == null ? 0 : math.min(0, anchor.dy - pumpAt - 1),
          left: true,
          nudge: 28,
        ),
      );
    }

    final pumpDepth = profile.pumpDepth;
    final pumpY = pumpDepth == null ? null : yAt(pumpDepth);
    final dry =
        pumpDepth != null && levelMeters != null && pumpDepth < levelMeters!;
    const mouthY = 3.0;
    const headY = 22.0;
    final hasFlow = flow != null;
    final pumpR = innerR * 0.26;
    final pumpH = innerR * 1.1;
    final ductR = (innerR * 0.1 * ((profile.ductInches ?? 3) / 4))
        .clamp(innerR * 0.055, innerR * 0.15)
        .toDouble();
    final neckR = math.min(pumpR * 0.72, ductR * 1.7);
    final neckH = pumpR * 0.7;
    final pumpTop = pumpY == null ? null : pumpY + pumpH / 2;
    final ductFrom = pumpTop != null
        ? pumpTop + neckH
        : (levelY ?? bottomY * 0.55);
    final accent = dry ? _Palette.coral : _Palette.flow;
    final ductColor = Color.lerp(
      _Palette.steel,
      accent,
      0.22 + _flowNorm * 0.25,
    )!;
    final showDuct = pumpY != null || hasFlow;

    void paintPump() {
      if (pumpY != null) {
        final body = _paintColumn(
          canvas,
          iso,
          x: 0,
          z: 0,
          y0: pumpY - pumpH / 2,
          y1: pumpTop!,
          radius: pumpR,
          color: _Palette.steel,
        );
        // Rejilla de aspiración: las lamas giran con el caudal acumulado.
        final right = Offset(iso.cy, -iso.sy);
        final toward = Offset(iso.sy, iso.cy);
        final intakeLow = pumpY - pumpH * 0.42;
        final intakeHigh = pumpY - pumpH * 0.08;
        for (var k = 0; k < 6; k++) {
          final phi = ((travel * 1.4 + k / 6) % 1) * math.pi;
          final dir = right * math.cos(phi) + toward * math.sin(phi);
          canvas.drawLine(
            iso.p(dir.dx * pumpR, intakeLow, dir.dy * pumpR),
            iso.p(dir.dx * pumpR, intakeHigh, dir.dy * pumpR),
            Paint()
              ..color = const Color(
                0xFF203238,
              ).withValues(alpha: 0.55 * math.sin(phi))
              ..strokeWidth = 1,
          );
        }
        canvas.drawArc(
          iso.ring(pumpY, pumpR),
          0,
          math.pi,
          false,
          Paint()
            ..color = accent.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
        // Cabezal de descarga: une la bomba con el ducto.
        _paintColumn(
          canvas,
          iso,
          x: 0,
          z: 0,
          y0: pumpTop,
          y1: pumpTop + neckH,
          radius: neckR,
          color: Color.lerp(_Palette.steel, Colors.black, 0.15)!,
        );
        hits.rect(ScenePart.pump, body.inflate(6));
        final submergence = levelMeters == null
            ? null
            : pumpDepth! - levelMeters!;
        final pumpNotes = <String>[
          if (profile.ductInches != null)
            'ducto ${_inches(profile.ductInches!)}',
          if (submergence != null && !dry) '${_m(submergence)} bajo el agua',
        ];
        tags.add(
          _Tag(
            ScenePart.pump,
            dry ? 'BOMBA · EN SECO' : 'BOMBA',
            _m(pumpDepth!),
            iso.p(0, pumpY, 0),
            dry ? _Palette.coral : _Palette.pump,
            detail: pumpNotes.isEmpty ? null : pumpNotes.join(' · '),
            left: true,
            nudge: 28,
          ),
        );
      }
      if (showDuct && ductFrom < 0) {
        _paintColumn(
          canvas,
          iso,
          x: 0,
          z: 0,
          y0: ductFrom - 0.5,
          y1: 0,
          radius: ductR,
          color: ductColor,
        );
      }
    }

    // Lo que se ve por el corte: superficie del agua, equipos y el cuarto
    // de columna de agua del frente como un volumen translúcido.
    void paintInterior() {
      if (waterY != null && hollows.isNotEmpty) {
        final clip = hollows.reduce(
          (a, b) => Path.combine(PathOperation.union, a, b),
        );
        final amp = 0.4 + _agitation * 0.8;
        final sheet = Path();
        for (var s = 0; s <= 30; s++) {
          final a = math.pi / 2 + s / 30 * math.pi * 1.5;
          final r = innerR * (1 + math.sin(a * 3 + drift * _tau * 2) * 0.02);
          final pt = iso.p(
            math.cos(a) * r,
            waterY + math.sin(a * 2 + phase * _tau * 3) * amp,
            math.sin(a) * r,
          );
          if (s == 0) {
            sheet.moveTo(pt.dx, pt.dy);
          } else {
            sheet.lineTo(pt.dx, pt.dy);
          }
        }
        final center = iso.p(0, waterY, 0);
        sheet
          ..lineTo(center.dx, center.dy)
          ..close();
        canvas.save();
        canvas.clipPath(clip);
        canvas.drawPath(
          sheet,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.4),
              colors: [
                _Palette.fog.withValues(alpha: 0.4 + _flowNorm * 0.2),
                water.withValues(alpha: 0.55 + _flowNorm * 0.2),
                water.withValues(alpha: 0.32 + _flowNorm * 0.15),
              ],
              stops: const [0, 0.45, 1],
            ).createShader(iso.ring(waterY, innerR)),
        );
        canvas.drawPath(
          sheet,
          Paint()
            ..color = _Palette.fog.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1,
        );
        canvas.restore();
      }

      final layered = gearIn < 1;
      if (layered) {
        canvas.saveLayer(
          sceneBounds,
          Paint()..color = Colors.white.withValues(alpha: gearIn),
        );
      }
      if (depthOf(sensorAt.x, sensorAt.z) < 0) {
        paintSensor();
        paintPump();
      } else {
        paintPump();
        paintSensor();
      }
      if (layered) canvas.restore();

      if (waterY != null && waterY > bottomY + 1 && hollows.isNotEmpty) {
        Offset rim(double y, double a) =>
            iso.p(math.cos(a) * innerR, y, math.sin(a) * innerR);
        final front = Path();
        for (var s = 0; s <= 14; s++) {
          final pt = rim(waterY, s / 14 * math.pi / 2);
          if (s == 0) {
            front.moveTo(pt.dx, pt.dy);
          } else {
            front.lineTo(pt.dx, pt.dy);
          }
        }
        for (var s = 14; s >= 0; s--) {
          final pt = rim(bottomY, s / 14 * math.pi / 2);
          front.lineTo(pt.dx, pt.dy);
        }
        front.close();
        canvas.drawPath(
          front,
          Paint()..color = water.withValues(alpha: 0.10 + _flowNorm * 0.06),
        );
        final lid = Path();
        final center = iso.p(0, waterY, 0);
        lid.moveTo(center.dx, center.dy);
        for (var s = 0; s <= 14; s++) {
          final pt = rim(waterY, s / 14 * math.pi / 2);
          lid.lineTo(pt.dx, pt.dy);
        }
        lid.close();
        canvas.drawPath(
          lid,
          Paint()..color = water.withValues(alpha: 0.16 + _flowNorm * 0.08),
        );
        final edge = Path();
        for (var s = 0; s <= 14; s++) {
          final pt = rim(waterY, s / 14 * math.pi / 2);
          if (s == 0) {
            edge.moveTo(pt.dx, pt.dy);
          } else {
            edge.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(
          edge,
          Paint()
            ..color = _Palette.fog.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    // El cuadrante (+x, +z) del bloque está cortado para ver el pozo por
    // dentro. Caras del corte, luego el interior, luego las caras cercanas.
    final cuts = [
      if (facing(1, 0))
        (
          quad: xPlane(0, 0, half),
          shade: 0.42,
          alongZ: true,
          depth: depthOf(0, half / 2),
        ),
      if (facing(0, 1))
        (
          quad: zPlane(0, 0, half),
          shade: 0.16,
          alongZ: false,
          depth: depthOf(half / 2, 0),
        ),
    ]..sort((a, b) => a.depth.compareTo(b.depth));
    for (final cut in cuts) {
      paintStrata(cut.quad, cut.shade);
      paintSection(cut.alongZ);
    }
    paintInterior();
    final sides =
        [
            (
              quad: xPlane(half, -half, 0),
              shade: 0.28,
              nx: 1.0,
              nz: 0.0,
              depth: depthOf(half, -half / 2),
            ),
            (
              quad: xPlane(-half, -half, half),
              shade: 0.28,
              nx: -1.0,
              nz: 0.0,
              depth: depthOf(-half, 0),
            ),
            (
              quad: zPlane(half, -half, 0),
              shade: 0.0,
              nx: 0.0,
              nz: 1.0,
              depth: depthOf(-half / 2, half),
            ),
            (
              quad: zPlane(-half, -half, half),
              shade: 0.0,
              nx: 0.0,
              nz: -1.0,
              depth: depthOf(0, -half),
            ),
          ].where((f) => facing(f.nx, f.nz)).toList()
          ..sort((a, b) => a.depth.compareTo(b.depth));
    for (final side in sides) {
      paintStrata(side.quad, side.shade);
    }

    if (levelY != null) {
      hits.rect(ScenePart.level, iso.ring(levelY, innerR).inflate(6));
    }
    if (known) {
      hits.rect(ScenePart.depth, iso.ring(bottomY, outerR).inflate(8));
    }

    // Terreno en L, con la boca del pozo y la losa cortadas igual que el
    // bloque.
    List<Offset> groundAt(double y) => [
      iso.p(-half, y, -half),
      iso.p(half, y, -half),
      iso.p(half, y, 0),
      iso.p(0, y, 0),
      iso.p(0, y, half),
      iso.p(-half, y, half),
    ];
    final ground = groundAt(0);
    final groundPath = _poly(ground);
    canvas.drawPath(
      groundPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F4B40), Color(0xFF213A32)],
        ).createShader(_boundsOf(ground)),
    );
    canvas.drawPath(
      groundPath,
      Paint()
        ..color = _Palette.fog.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke,
    );
    canvas.save();
    canvas.clipPath(
      Path.combine(PathOperation.union, groundPath, _poly(groundAt(6))),
    );
    canvas.drawOval(
      iso.ring(0.4, outerR * 2.15),
      Paint()..color = const Color(0xFF24302C),
    );
    canvas.drawOval(
      iso.ring(1.4, outerR * 1.92),
      Paint()..color = const Color(0xFF4C635C),
    );
    canvas.drawOval(
      iso.ring(1.4, outerR * 1.92),
      Paint()
        ..color = const Color(0xFFD5E4DC).withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawOval(
      iso.ring(3.6, outerR * 1.08),
      Paint()..color = const Color(0xFF1C2826),
    );
    final collar = iso.ring(4.6, outerR * 0.96);
    canvas.drawOval(collar, Paint()..color = const Color(0xFF8E9C96));
    canvas.drawOval(
      iso.ring(5.1, outerR * 0.78),
      Paint()..color = const Color(0xFFC5D0CB),
    );
    canvas.drawOval(
      collar,
      Paint()
        ..color = const Color(0xFFF2F7F4).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    final mouth = iso.ring(4.2, innerR * 0.72);
    canvas.drawOval(mouth, Paint()..color = const Color(0xFF071418));
    canvas.drawOval(
      mouth,
      Paint()
        ..color = const Color(0xFF9AA8A4).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.restore();

    if (!known) {
      // Sin ficha: el fondo no se conoce y se desvanece.
      final fadeTop = iso.p(0, blockBottom * 0.82, 0).dy;
      final fadeBottom =
          _boundsOf([
            for (final x in [-half, half])
              for (final z in [-half, half]) iso.p(x, blockBottom, z),
          ]).bottom +
          20;
      final fade = Rect.fromLTRB(0, fadeTop, size.width, fadeBottom);
      canvas.drawRect(
        fade,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0x99000000)],
          ).createShader(fade),
      );
      canvas.restore();
    }

    // El ducto sale por el centro de la boca hasta el cabezal.
    if (showDuct) {
      _paintColumn(
        canvas,
        iso,
        x: 0,
        z: 0,
        y0: 0,
        y1: hasFlow ? headY : mouthY,
        radius: ductR,
        color: ductColor,
      );
    }

    // Datalogger con cable al sensor.
    final loggerBase = iso.p(logger.x, 0, logger.z);
    if (profile.sensorDepth != null) {
      _dashed(
        canvas,
        iso.p(sensorAt.x, 4, sensorAt.z),
        loggerBase,
        Paint()
          ..color = _Palette.sensor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
    _paintLogger(
      canvas,
      iso,
      logger.x,
      logger.z,
      pole: (x: -half * 0.88, z: half * 0.84),
    );

    // Impulsión en superficie: flujómetro y descarga, sobre terreno firme.
    if (hasFlow) {
      final outlet = (x: half * 0.70, z: -half * 0.62);
      final lane = -half * 0.14;
      final route = <Offset>[
        iso.p(0, headY, 0),
        iso.p(0, headY, lane),
        iso.p(outlet.x - 10, headY, lane),
        iso.p(outlet.x, headY, lane - 10),
        iso.p(outlet.x, headY, outlet.z),
      ];
      _paintPool(canvas, iso, outlet.x, outlet.z, half * 0.22);
      _paintPipe(
        canvas,
        route,
        moving: true,
        width: (ductR * 2 * iso.scale - 1).clamp(1.6, 7.0).toDouble(),
      );
      final meterX = half * 0.36;
      final meterAt = iso.p(meterX, headY, lane);
      _dashed(
        canvas,
        iso.p(meterX, 0, lane),
        loggerBase,
        Paint()
          ..color = _Palette.flow.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      canvas.drawLine(
        meterAt,
        iso.p(meterX, 0, lane),
        Paint()
          ..color = const Color(0xFF6E8586)
          ..strokeWidth = 2,
      );
      final r = _paintFlowmeter(canvas, meterAt);
      _paintDischarge(canvas, iso, outlet.x, headY, outlet.z);
      hits.rect(
        ScenePart.flowmeter,
        Rect.fromCircle(center: meterAt, radius: r + 8),
      );
      tags.add(
        _Tag(
          ScenePart.flowmeter,
          'FLUJÓMETRO',
          formatLitersPerSecond(flow!),
          meterAt,
          _Palette.flow,
          detail: _flowmeterDetail(),
          lift: 74,
          live: true,
        ),
      );
    }

    // Rótulos de nivel anclados en la cara del corte que se ve.
    Offset onCut(double y, double t) {
      if (facing(0, 1)) return iso.p(innerR * t, y, 0);
      if (facing(1, 0)) return iso.p(0, y, innerR * t);
      return iso.p(0, y, 0);
    }

    if (levelY != null) {
      final column = known ? profile.depth! - levelMeters! : null;
      tags.add(
        _Tag(
          ScenePart.level,
          'NIVEL FREÁTICO',
          '${levelMeters!.toStringAsFixed(2)} m',
          onCut(levelY, 0.7),
          _Palette.level,
          live: true,
        ),
      );
      if (column != null && column > 0) {
        tags.add(
          _Tag(
            ScenePart.level,
            'COLUMNA DE AGUA',
            _m(column),
            onCut((levelY + bottomY) / 2, 0.55),
            _Palette.wellWater,
            live: true,
          ),
        );
      }
    }
    if (known) {
      tags.add(
        _Tag(
          ScenePart.depth,
          'FONDO DEL POZO',
          _m(depthM),
          onCut(bottomY, outerR / innerR * 0.95),
          _Palette.fog,
        ),
      );
    }

    _paintDepthRuler(canvas, iso, half, wellPx, depthM, faded: !known);
    _paintTags(canvas, size, tags, axisX: axis.dx, clearance: outerR + 26);
  }

  /// Tablero eléctrico en terreno: recibe la energía desde un poste y
  /// aloja el datalogger, visible por la mirilla de la puerta.
  Rect _paintLogger(
    Canvas canvas,
    _Iso iso,
    double x,
    double z, {
    required ({double x, double z}) pole,
  }) {
    const plinth = 4.0;
    const w = 24.0, d = 12.0, h = 34.0;
    const top = plinth + h;
    final color = _Palette.linkColor(link);

    // Poste y acometida.
    const poleH = 56.0;
    final poleBase = iso.p(pole.x, 0, pole.z);
    final poleTop = iso.p(pole.x, poleH, pole.z);
    final wood = Paint()
      ..color = const Color(0xFF8C9A97)
      ..strokeWidth = 2.6 * iso.scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(poleBase, poleTop, wood);
    final armA = iso.p(pole.x - 7, poleH - 4, pole.z);
    final armB = iso.p(pole.x + 7, poleH - 4, pole.z);
    canvas.drawLine(armA, armB, wood..strokeWidth = 1.8 * iso.scale);
    final entry = iso.p(x, top - 6, z - iso.sz * d / 2);
    final mid = Offset.lerp(armB, entry, 0.5)! + Offset(0, 10 * iso.scale);
    final cable = Path()
      ..moveTo(armB.dx, armB.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, entry.dx, entry.dy);
    canvas.drawPath(
      cable,
      Paint()
        ..color = const Color(0xFF1C2B2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * iso.scale,
    );
    hits.rect(
      ScenePart.power,
      _boundsOf([poleBase, poleTop, armA, armB]).inflate(8),
    );

    // Base de hormigón y gabinete.
    _box(
      canvas,
      iso,
      x: x,
      z: z,
      w: w + 4,
      d: d + 4,
      h: plinth,
      color: const Color(0xFF7D8B8B),
    );
    final cabinet = _box(
      canvas,
      iso,
      x: x,
      z: z,
      y: plinth,
      w: w,
      d: d,
      h: h,
      color: const Color(0xFFD3DCDB),
    );
    _box(
      canvas,
      iso,
      x: x,
      z: z,
      y: top,
      w: w + 3,
      d: d + 3,
      h: 1.6,
      color: const Color(0xFFB9C5C4),
    );

    // Puerta en la cara frontal visible.
    final fz = z + iso.sz * d / 2;
    Offset door(double u, double v) => iso.p(x + u, v, fz);
    List<Offset> quad(double u0, double v0, double u1, double v1) => [
      door(u0, v0),
      door(u1, v0),
      door(u1, v1),
      door(u0, v1),
    ];
    canvas.drawPath(
      _poly(quad(-w / 2 + 2, plinth + 2, w / 2 - 2, top - 2)),
      Paint()
        ..color = const Color(0xFF7F8F90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.drawLine(
      door(w / 2 - 4.5, plinth + h * 0.42),
      door(w / 2 - 4.5, plinth + h * 0.58),
      Paint()
        ..color = const Color(0xFF55656A)
        ..strokeWidth = 1.6 * iso.scale
        ..strokeCap = StrokeCap.round,
    );

    // Mirilla con el datalogger dentro.
    canvas.drawPath(
      _poly(quad(-8, top - 15, 6, top - 5)),
      Paint()..color = const Color(0xFF0E1E22),
    );
    canvas.drawPath(
      _poly(quad(-6, top - 13.5, 1.5, top - 6.5)),
      Paint()..color = const Color(0xFF2F5F57),
    );
    final blink = (math.sin(phase * _tau * 6) + 1) / 2;
    canvas.drawCircle(
      door(3.6, top - 8),
      1.4 * iso.scale,
      Paint()..color = color.withValues(alpha: 0.4 + blink * 0.6),
    );

    // Señal de riesgo eléctrico.
    canvas.drawPath(
      _poly([door(-3, plinth + 7), door(3, plinth + 7), door(0, plinth + 13)]),
      Paint()..color = _Palette.sensor.withValues(alpha: 0.9),
    );

    // Antena de transmisión.
    final head = iso.p(x - w / 2 + 4, top + 1.6, z);
    final tip = iso.p(x - w / 2 + 6, top + 20, z);
    canvas.drawLine(
      head,
      tip,
      Paint()
        ..color = _Palette.steel
        ..strokeWidth = 1.4,
    );
    // Brillo que late en la punta: muestra el estado del enlace e invita a
    // tocar el tablero para ver su ficha.
    final glow = (phase * 4) % 1;
    canvas.drawCircle(
      tip,
      (5 + blink * 2.5) * iso.scale,
      Paint()
        ..color = color.withValues(alpha: 0.28 + blink * 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      tip,
      (3 + glow * 9) * iso.scale,
      Paint()
        ..color = color.withValues(alpha: (1 - glow) * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.drawCircle(tip, 2.2 * iso.scale, Paint()..color = color);
    canvas.drawCircle(
      tip - Offset(0.6, 0.6) * iso.scale,
      0.8 * iso.scale,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    final area = cabinet.expandToInclude(
      Rect.fromCircle(center: tip, radius: 6),
    );
    hits.rect(ScenePart.logger, area.inflate(6));
    return area;
  }

  // --------------------------------------------------- piezas compartidas

  void _paintPipe(
    Canvas canvas,
    List<Offset> route, {
    required bool moving,
    double gauge = 1,
    double? width,
  }) {
    final path = Path()..moveTo(route.first.dx, route.first.dy);
    for (final p in route.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    width ??= ((profile.ductInches ?? 3) * 1.05 * gauge)
        .clamp(1.6, 5.0)
        .toDouble();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF6E8586)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 1
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final active = moving && _flowing;
    canvas.drawPath(
      path,
      Paint()
        ..color = active
            ? _Palette.flow.withValues(alpha: 0.35 + _flowNorm * 0.45)
            : const Color(0xFF2A3B3D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width - 1
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (!active) return;
    final metric = path.computeMetrics().firstOrNull;
    if (metric == null || metric.length < 1) return;
    // Agua en la cañería: trazos tenues que avanzan con el caudal acumulado,
    // así acelerar o frenar no los hace saltar.
    const period = 26.0;
    const dash = 10.0;
    final offset = (travel * 70) % period;
    final stream = Paint()
      ..color = _Palette.fog.withValues(alpha: 0.30 + _flowNorm * 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, width * 0.32)
      ..strokeCap = StrokeCap.round;
    for (var d = offset - period; d < metric.length; d += period) {
      final a = math.max(0.0, d);
      final b = math.min(metric.length, d + dash);
      if (b - a < 1) continue;
      canvas.drawPath(metric.extractPath(a, b), stream);
    }
  }

  double _paintFlowmeter(Canvas canvas, Offset at) {
    final r = ((profile.flowmeterInches ?? 3) * 1.8)
        .clamp(6.0, 12.0)
        .toDouble();
    canvas.drawCircle(at, r + 2.5, Paint()..color = const Color(0xFF0B1A1D));
    canvas.drawCircle(
      at,
      r + 2.5,
      Paint()
        ..color = _Palette.flow.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    // Dial: el arco y la aguja marcan el caudal respecto del máximo.
    const start = math.pi * 0.75;
    const span = math.pi * 1.5;
    final dial = Rect.fromCircle(center: at, radius: r - 1);
    canvas.drawArc(
      dial,
      start,
      span,
      false,
      Paint()
        ..color = _Palette.faint.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    if (_q > 0.01) {
      canvas.drawArc(
        dial,
        start,
        span * _flowNorm,
        false,
        Paint()
          ..color = _Palette.flow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    final angle = start + span * _flowNorm;
    canvas.drawLine(
      at,
      at + Offset(math.cos(angle), math.sin(angle)) * (r - 2.5),
      Paint()
        ..color = _flowing ? _Palette.fog : _Palette.faint
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at, 1.6, Paint()..color = _Palette.fog);
    return r;
  }

  void _paintPool(Canvas canvas, _Iso iso, double x, double z, double r) {
    final pool = iso.ring(0.5, r, x: x, z: z);
    canvas.drawOval(
      pool,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _Palette.wellWater.withValues(alpha: 0.6),
            _Palette.wellWater.withValues(alpha: 0.2),
          ],
        ).createShader(pool),
    );
    canvas.drawOval(
      pool,
      Paint()
        ..color = _Palette.fog.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke,
    );
    if (!_flowing) return;
    canvas.save();
    canvas.clipPath(Path()..addOval(pool));
    for (var i = 0; i < 3; i++) {
      final t = (travel * 0.8 + i / 3) % 1;
      canvas.drawOval(
        Rect.fromCenter(
          center: pool.center,
          width: pool.width * t,
          height: pool.height * t,
        ),
        Paint()
          ..color = _Palette.fog.withValues(alpha: (1 - t) * t * 1.2)
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
  }

  void _paintDischarge(
    Canvas canvas,
    _Iso iso,
    double x,
    double fromY,
    double z,
  ) {
    if (!_flowing) return;
    final a = iso.p(x, fromY, z);
    final b = iso.p(x, 1, z);
    final width = 2 + _flowNorm * 6;
    canvas.drawLine(
      a,
      b,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _Palette.fog.withValues(alpha: 0.85),
            _Palette.wellWater.withValues(alpha: 0.35),
          ],
        ).createShader(Rect.fromPoints(a, b).inflate(width))
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Regla de profundidad sobre la arista visible más a la izquierda.
  void _paintDepthRuler(
    Canvas canvas,
    _Iso iso,
    double half,
    double wellPx,
    double depthM, {
    required bool faded,
  }) {
    // El cuadrante (+x, +z) está cortado: su esquina no existe.
    (double, double) solid((double, double) c) =>
        c.$1 > 0 && c.$2 > 0 ? (c.$1, 0) : c;
    final edges = [
      solid((iso.sx * half, -iso.sz * half)),
      solid((-iso.sx * half, iso.sz * half)),
    ];
    final edge = edges.reduce(
      (a, b) => iso.p(a.$1, 0, a.$2).dx < iso.p(b.$1, 0, b.$2).dx ? a : b,
    );
    const steps = [1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0];
    final step = steps.firstWhere((s) => depthM / s <= 6, orElse: () => 500);
    final tick = Paint()
      ..color = _Palette.faint.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var m = 0.0; m <= depthM + 0.001; m += step) {
      final y = -(m / depthM) * wellPx;
      final at = iso.p(edge.$1, y, edge.$2);
      final fade = faded ? (1 - (m / depthM) * 0.8) : 1.0;
      canvas.drawLine(at, at + const Offset(-6, 0), tick);
      _text(
        canvas,
        '${m.toStringAsFixed(0)} m',
        at + const Offset(-9, 0),
        _Palette.faint.withValues(alpha: 0.85 * fade),
        size: 10,
        alignRight: true,
      );
    }
  }

  /// Rótulos junto a cada parte, a ambos lados del eje, apilados sin
  /// superponerse. Las guías son cortas y se dibujan sobre la escena.
  void _paintTags(
    Canvas canvas,
    Size size,
    List<_Tag> tags, {
    required double axisX,
    required double clearance,
  }) {
    final shown = _introAt(0.62, 1) * tagsShown;
    if (shown <= 0.01) return;
    final layered = shown < 1;
    if (layered) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: shown),
      );
      canvas.translate(0, (1 - shown) * 8);
    }
    final pulse = (phase * 6) % 1;
    // Primero todas las guías y después todas las tarjetas: ninguna línea
    // queda nunca sobre un rótulo.
    final cards = <VoidCallback>[];
    bool onLeft(_Tag t) => t.left ?? t.anchor.dx <= axisX;
    final left = tags.where(onLeft).toList();
    final right = tags.where((t) => !onLeft(t)).toList();
    for (final (side, isLeft) in [(left, true), (right, false)]) {
      side.sort(
        (a, b) => (a.anchor.dy - a.lift).compareTo(b.anchor.dy - b.lift),
      );
      var cursor = topInset - 4;
      for (final tag in side) {
        final layout = _tagLayout(tag);
        final cy = math.max(
          tag.anchor.dy - tag.lift,
          cursor + layout.height / 2,
        );
        cursor = cy + layout.height / 2 + 6;
        final edgeX = isLeft
            ? math.min(axisX - clearance, tag.anchor.dx - 18) - tag.nudge
            : math.max(axisX + clearance, tag.anchor.dx + 18) + tag.nudge;
        // Arriba a la derecha están los controles de vista.
        final rightEdge = cy - layout.height / 2 < _controlsBottom
            ? 58.0
            : 12.0;
        var rectLeft = isLeft ? edgeX - layout.width : edgeX;
        rectLeft = rectLeft
            .clamp(12.0, math.max(12.0, size.width - layout.width - rightEdge))
            .toDouble();
        final rect = Rect.fromLTWH(
          rectLeft,
          cy - layout.height / 2,
          layout.width,
          layout.height,
        );
        final focused = focus == tag.part;
        final cardOnLeft = rect.center.dx < tag.anchor.dx;
        final attach = Offset(
          cardOnLeft ? rect.right : rect.left,
          rect.center.dy,
        );
        final guide = Path()
          ..moveTo(tag.anchor.dx, tag.anchor.dy)
          ..lineTo(attach.dx + (cardOnLeft ? 8 : -8), attach.dy)
          ..lineTo(attach.dx, attach.dy);
        canvas.drawPath(
          guide,
          Paint()
            ..color = const Color(0xFF040C0F).withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
        canvas.drawPath(
          guide,
          Paint()
            ..color = tag.color.withValues(alpha: focused ? 0.95 : 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = focused ? 1.4 : 0.9,
        );
        canvas.drawCircle(
          tag.anchor,
          focused ? 3.4 : 2.4,
          Paint()..color = tag.color,
        );
        if (tag.live) {
          canvas.drawCircle(
            tag.anchor,
            3 + pulse * 6,
            Paint()
              ..color = tag.color.withValues(alpha: (1 - pulse) * 0.45)
              ..style = PaintingStyle.stroke,
          );
        }
        cards.add(
          () => _drawTag(
            canvas,
            rect,
            tag,
            layout,
            focused: focused,
            pulse: pulse,
          ),
        );
        if (shown > 0.5) hits.rect(tag.part, rect.inflate(2));
      }
    }
    for (final card in cards) {
      card();
    }
    if (layered) canvas.restore();
  }

  ({
    double width,
    double height,
    TextPainter caption,
    TextPainter value,
    TextPainter? detail,
  })
  _tagLayout(_Tag tag) {
    TextPainter painter(String text, TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);
    final caption = painter(
      tag.caption,
      TextStyle(
        color: tag.color.withValues(alpha: 0.9),
        fontSize: 8.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
    final value = painter(
      tag.value,
      const TextStyle(
        color: _Palette.fog,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
    final detail = tag.detail == null
        ? null
        : painter(
            tag.detail!,
            TextStyle(
              color: _Palette.fog.withValues(alpha: 0.6),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          );
    final width =
        [
          caption.width + _tagMark,
          value.width,
          detail?.width ?? 0,
        ].reduce(math.max) +
        18;
    final height = caption.height + value.height + (detail?.height ?? 0) + 8;
    return (
      width: width,
      height: height,
      caption: caption,
      value: value,
      detail: detail,
    );
  }

  /// Espacio reservado antes de la leyenda para la marca en vivo / ficha.
  static const _tagMark = 10.0;

  /// Borde inferior de la columna de controles de vista (5 botones).
  static const _controlsBottom = 12.0 + 5 * 36 + 8;

  void _drawTag(
    Canvas canvas,
    Rect rect,
    _Tag tag,
    ({
      double width,
      double height,
      TextPainter caption,
      TextPainter value,
      TextPainter? detail,
    })
    layout, {
    required bool focused,
    required double pulse,
  }) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(
      rrect.shift(const Offset(0, 1.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = focused
            ? Color.lerp(_Palette.card, _Palette.fog, 0.10)!
            : _Palette.card.withValues(alpha: 0.66),
    );
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..color = tag.color.withValues(alpha: focused ? 0.45 : 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    var y = rect.top + 4;
    final mark = Offset(rect.left + 12, y + layout.caption.height / 2);
    if (tag.live) {
      canvas.drawCircle(
        mark,
        2.2 + pulse * 3,
        Paint()..color = tag.color.withValues(alpha: (1 - pulse) * 0.35),
      );
      canvas.drawCircle(mark, 2.2, Paint()..color = tag.color);
    } else {
      canvas.drawCircle(
        mark,
        2,
        Paint()
          ..color = _Palette.faint.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    layout.caption.paint(canvas, Offset(rect.left + 9 + _tagMark, y));
    y += layout.caption.height;
    layout.value.paint(canvas, Offset(rect.left + 9, y));
    y += layout.value.height;
    layout.detail?.paint(canvas, Offset(rect.left + 9, y));
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor,
    Color color, {
    double size = 11,
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    var left = alignRight ? anchor.dx - painter.width : anchor.dx;
    left = left.clamp(4.0, math.max(4.0, _size.width - painter.width - 4));
    painter.paint(canvas, Offset(left, anchor.dy - painter.height / 2));
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    final dir = to - from;
    final len = dir.distance;
    if (len < 0.01) return;
    final unit = dir / len;
    for (var d = 0.0; d < len; d += dash + gap) {
      canvas.drawLine(
        from + unit * d,
        from + unit * math.min(d + dash, len),
        paint,
      );
    }
  }

  String _m(double meters) =>
      '${meters.toStringAsFixed(meters >= 100 ? 0 : 1)} m';

  String _inches(double v) => formatInches(v);

  String? _flowmeterDetail() {
    final bits = <String>[
      if (profile.flowmeterInches != null) _inches(profile.flowmeterInches!),
      if (totalCubicMeters != null)
        'total ${formatCubicMeters(totalCubicMeters!)}',
    ];
    return bits.isEmpty ? null : bits.join(' · ');
  }

  // ------------------------------------------------------------ superficial

  void _paintSurface(Canvas canvas, Size size) {
    final l = _layout(size, depthFactor: 1.15, headroom: 48, widthLimit: 0.68);
    final iso = _Iso(
      l.origin,
      yaw + math.sin(phase * _tau) * 0.015,
      pitch,
      scale: zoom,
    );
    final h = l.half;
    final depthPx = l.depth;
    final c = h * 0.42;
    final bedY = -depthPx * 0.62;
    final bankBottom = -depthPx;

    final hasLevel = levelMeters != null;
    final scaleMax = math.max(
      0.5,
      math.max(levelMax ?? 0, levelMeters ?? 0) * 1.35,
    );
    // Sin lectura se dibuja una lámina media para que el cauce no se vea seco.
    // El valor en metros solo aparece cuando el punto sí mide nivel.
    final fill =
        (hasLevel
            ? (levelMeters! / scaleMax).clamp(0.06, 0.95).toDouble()
            : 0.42) *
        _introAt(0.35, 0.9);
    final waterY = bedY * (1 - fill);
    final water = _waterTone;

    canvas.drawOval(
      Rect.fromCenter(
        center: iso.p(0, bankBottom, 0) + const Offset(0, 18),
        width: h * 3.1 * iso.scale,
        height: h * 3.1 * iso.ps * 0.6 * iso.scale,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // Pared interior del cauce que mira al observador y lecho.
    final wallX = -iso.sx * c;
    final wall = [
      iso.p(wallX, 0, -h),
      iso.p(wallX, 0, h),
      iso.p(wallX, bedY, h),
      iso.p(wallX, bedY, -h),
    ];
    _soilBand(canvas, wall, shade: 0.45);
    canvas.drawPath(
      _poly([
        iso.p(-c, bedY, -h),
        iso.p(c, bedY, -h),
        iso.p(c, bedY, h),
        iso.p(-c, bedY, h),
      ]),
      Paint()..color = const Color(0xFF14262A),
    );

    // Lámina de agua.
    if (fill > 0) {
      final sheet = [
        iso.p(-c, waterY, -h),
        iso.p(c, waterY, -h),
        iso.p(c, waterY, h),
        iso.p(-c, waterY, h),
      ];
      final sheetPath = _poly(sheet);
      canvas.drawPath(
        sheetPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              water.withValues(alpha: 0.45),
              water.withValues(alpha: 0.75),
            ],
          ).createShader(_boundsOf(sheet)),
      );
      canvas.save();
      canvas.clipPath(sheetPath);
      // Corriente: líneas largas que avanzan de forma continua y se
      // desvanecen en los extremos, sin cortes ni reinicios.
      final lanes = [-0.55, -0.18, 0.2, 0.55];
      const period = 0.58;
      const dash = 0.28;
      for (var i = 0; i < lanes.length; i++) {
        final offset = (travel * 0.9 + i * 0.13) % period;
        for (var u0 = -period + offset; u0 < 1; u0 += period) {
          final a = u0.clamp(0.0, 1.0).toDouble();
          final b = (u0 + dash).clamp(0.0, 1.0).toDouble();
          if (b - a < 0.005) continue;
          final mid = (a + b) / 2;
          final line = Path();
          for (var s = 0; s <= 8; s++) {
            final u = a + (b - a) * s / 8;
            final pt = iso.p(lanes[i] * c, waterY, -h + u * 2 * h);
            if (s == 0) {
              line.moveTo(pt.dx, pt.dy);
            } else {
              line.lineTo(pt.dx, pt.dy);
            }
          }
          canvas.drawPath(
            line,
            Paint()
              ..color = _Palette.fog.withValues(
                alpha: (0.10 + _flowNorm * 0.14) * math.sin(mid * math.pi),
              )
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0
              ..strokeCap = StrokeCap.round,
          );
        }
      }
      canvas.restore();
    }

    // La tierra es maciza: su cara lateral va sobre el lecho y la lámina.
    final side = iso.xFace(h, 0, bankBottom);
    _soilBand(canvas, side, shade: 0.28);
    canvas.drawPath(
      _poly(side),
      Paint()
        ..color = _Palette.fog.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke,
    );

    // Cara frontal con la sección en U del cauce.
    final zf = iso.sz * h;
    final front = [
      iso.p(-h, 0, zf),
      iso.p(-c, 0, zf),
      iso.p(-c, bedY, zf),
      iso.p(c, bedY, zf),
      iso.p(c, 0, zf),
      iso.p(h, 0, zf),
      iso.p(h, bankBottom, zf),
      iso.p(-h, bankBottom, zf),
    ];
    final frontPath = _poly(front);
    canvas.save();
    canvas.clipPath(frontPath);
    _soilBand(canvas, iso.zFace(h, 0, bankBottom), shade: 0);
    canvas.restore();
    canvas.drawPath(
      frontPath,
      Paint()
        ..color = _Palette.fog.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke,
    );
    if (fill > 0) {
      final section = [
        iso.p(-c, waterY, zf),
        iso.p(c, waterY, zf),
        iso.p(c, bedY, zf),
        iso.p(-c, bedY, zf),
      ];
      final sectionPath = _poly(section);
      canvas.drawPath(
        sectionPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              water.withValues(alpha: 0.75),
              const Color(0xFF1D5A8F).withValues(alpha: 0.8),
            ],
          ).createShader(_boundsOf(section)),
      );
      if (hasLevel) hits.add(ScenePart.level, sectionPath);
      final crest = Path();
      for (var s = 0; s <= 22; s++) {
        final u = s / 22;
        final pt = _bilerp(section, u, 0);
        final y =
            pt.dy +
            math.sin(u * _tau * 1.5 - drift * _tau) * (0.8 + _agitation);
        if (s == 0) {
          crest.moveTo(pt.dx, y);
        } else {
          crest.lineTo(pt.dx, y);
        }
      }
      canvas.drawPath(
        crest,
        Paint()
          ..color = _Palette.fog.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // Riberas.
    for (final sign in [-1.0, 1.0]) {
      final a = sign * c;
      final b = sign * h;
      final bank = [
        iso.p(math.min(a, b), 0, -h),
        iso.p(math.max(a, b), 0, -h),
        iso.p(math.max(a, b), 0, h),
        iso.p(math.min(a, b), 0, h),
      ];
      canvas.drawPath(
        _poly(bank),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2F4B40), Color(0xFF213A32)],
          ).createShader(_boundsOf(bank)),
      );
      canvas.drawPath(
        _poly(bank),
        Paint()
          ..color = _Palette.fog.withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke,
      );
    }

    final tags = <_Tag>[];
    final axis = iso.p(0, 0, 0);

    // Sensor de nivel sobre el cauce y datalogger en la ribera.
    final logger = (x: -c - (h - c) * 0.5, z: h * 0.45);
    if (hasLevel) {
      final postX = -c - 6;
      const postZ = 0.0;
      const armY = 54.0;
      final base = iso.p(postX, 0, postZ);
      final topPt = iso.p(postX, armY, postZ);
      final sensorPt = iso.p(-c * 0.15, armY, postZ);
      final post = Paint()
        ..color = _Palette.steel
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(base, topPt, post);
      canvas.drawLine(topPt, sensorPt, post);
      _box(
        canvas,
        iso,
        x: -c * 0.15,
        z: postZ,
        w: 6,
        d: 4,
        h: 3.5,
        y: armY - 1,
        color: _Palette.sensor,
      );
      final target = iso.p(-c * 0.15, waterY, postZ);
      for (var i = 0; i < 3; i++) {
        final t = (phase * 4 + i / 3) % 1;
        final at = Offset.lerp(sensorPt + const Offset(0, 9), target, t)!;
        canvas.drawArc(
          Rect.fromCenter(center: at, width: 12, height: 5),
          0,
          math.pi,
          false,
          Paint()
            ..color = _Palette.sensor.withValues(alpha: 0.7 * (1 - t))
            ..style = PaintingStyle.stroke,
        );
      }
      hits.rect(
        ScenePart.sensor,
        Rect.fromCenter(center: sensorPt, width: 30, height: 26),
      );
      tags.add(
        _Tag(
          ScenePart.sensor,
          'SENSOR DE NIVEL',
          'sobre el cauce',
          sensorPt,
          _Palette.sensor,
          lift: 80,
        ),
      );
      _dashed(
        canvas,
        base,
        iso.p(logger.x, 0, logger.z),
        Paint()
          ..color = _Palette.sensor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      tags.add(
        _Tag(
          ScenePart.level,
          'ALTURA DE AGUA',
          '${levelMeters!.toStringAsFixed(2)} m',
          iso.p(-c, waterY, zf),
          _Palette.level,
          lift: -110,
          live: true,
        ),
      );
    }
    _paintLogger(
      canvas,
      iso,
      logger.x,
      logger.z,
      pole: (x: -c - (h - c) * 0.88, z: h * 0.86),
    );

    // Toma, bomba, flujómetro y estanque solo si el punto mide caudal.
    if (flow != null) {
      final pumpAt = (x: c + (h - c) * 0.38, z: h * 0.15);
      const headY = 18.0;
      final outlet = (x: c + (h - c) * 0.55, z: -h * 0.62);
      final intakeY = waterY - 6;
      final route = <Offset>[
        iso.p(c * 0.35, intakeY, pumpAt.z),
        iso.p(c * 0.35, headY, pumpAt.z),
        iso.p(pumpAt.x, headY, pumpAt.z),
        iso.p(pumpAt.x, headY, outlet.z + 10),
        iso.p(outlet.x, headY, outlet.z),
      ];
      _paintPool(canvas, iso, outlet.x, outlet.z, (h - c) * 0.32);
      _paintPipe(canvas, route, moving: true);
      _box(
        canvas,
        iso,
        x: pumpAt.x,
        z: pumpAt.z,
        w: 16,
        d: 12,
        h: 12,
        y: headY - 6,
        color: _Palette.steel,
      );
      final meterAt = iso.p(pumpAt.x, headY, (pumpAt.z + outlet.z) / 2);
      final r = _paintFlowmeter(canvas, meterAt);
      _paintDischarge(canvas, iso, outlet.x, headY, outlet.z);
      final intake = iso.p(c * 0.35, waterY, pumpAt.z);
      if (_flowing) {
        for (var i = 0; i < 2; i++) {
          final t = (phase * 3 + i / 2) % 1;
          canvas.drawOval(
            Rect.fromCenter(
              center: intake,
              width: 6 + t * 26,
              height: (6 + t * 26) * iso.ps,
            ),
            Paint()
              ..color = _Palette.fog.withValues(alpha: (1 - t) * 0.6)
              ..style = PaintingStyle.stroke,
          );
        }
      }
      hits.rect(ScenePart.intake, Rect.fromCircle(center: intake, radius: 14));
      hits.rect(
        ScenePart.flowmeter,
        Rect.fromCircle(center: meterAt, radius: r + 8),
      );
      tags.add(
        _Tag(
          ScenePart.flowmeter,
          'FLUJÓMETRO',
          formatLitersPerSecond(flow!),
          meterAt,
          _Palette.flow,
          detail: _flowmeterDetail(),
          lift: 96,
          live: true,
        ),
      );
      tags.add(
        _Tag(
          ScenePart.intake,
          'TOMA',
          'captación',
          intake,
          _Palette.flow,
          lift: -120,
        ),
      );
    }

    _paintTags(canvas, size, tags, axisX: axis.dx, clearance: c * 0.6);
  }

  @override
  bool shouldRepaint(covariant _CaptureStagePainter old) => true;
}
