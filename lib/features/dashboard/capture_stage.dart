import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/brand.dart';
import 'point_link.dart';

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
}

/// Vista singular del punto: una lámina isométrica interactiva.
///
/// Un bloque de terreno en corte que gira 360° al arrastrar y acompaña al
/// puntero. Solo se dibuja lo que el punto tiene: el pozo usa su ficha real
/// (profundidad, bomba, sensor, ductos) y las variables con dato; lo que no
/// existe no aparece. Al pasar el puntero o tocar una parte se explica qué es.
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

  /// Espacio reservado arriba para controles superpuestos.
  final double topInset;

  @override
  State<CaptureStage> createState() => _CaptureStageState();
}

class _CaptureStageState extends State<CaptureStage>
    with TickerProviderStateMixin {
  static const _baseYaw = 0.66;
  static const _basePitch = 0.46;

  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..addListener(_ease);

  late final AnimationController _playPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  final _SceneHits _hits = _SceneHits();
  bool _hovered = false;
  bool _touched = false;
  Offset _pointer = Offset.zero;
  double _dragYaw = 0;
  double _dragPitch = 0;
  double _yaw = _baseYaw;
  double _pitch = _basePitch;
  ScenePart? _hoverPart;
  ScenePart? _pinnedPart;

  /// Valores mostrados: siguen a los del replay con suavidad para que el
  /// agua suba y baje de forma continua entre registros.
  double? _level;
  double? _shownFlow;
  double _levelMotion = 0;

  double get _targetYaw => _baseYaw + _dragYaw + _pointer.dx * 0.12;
  double get _targetPitch =>
      (_basePitch + _dragPitch + _pointer.dy * 0.06).clamp(0.20, 0.92);

  void _ease() {
    _yaw += (_targetYaw - _yaw) * 0.14;
    _pitch += (_targetPitch - _pitch) * 0.14;

    final level = widget.levelMeters;
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
      _level = widget.levelMeters;
      _shownFlow = widget.flowLitersPerSecond;
    });
  }

  @override
  void initState() {
    super.initState();
    _level = widget.levelMeters;
    _shownFlow = widget.flowLitersPerSecond;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
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
    super.dispose();
  }

  void _onHover(PointerHoverEvent event, Size size) {
    if (size.isEmpty) return;
    _pointer = Offset(
      (event.localPosition.dx / size.width) * 2 - 1,
      (event.localPosition.dy / size.height) * 2 - 1,
    );
    final part = _hits.at(event.localPosition);
    if (part != _hoverPart) setState(() => _hoverPart = part);
    _snapIfStatic();
  }

  void _onTapUp(TapUpDetails details) {
    final part = _hits.at(details.localPosition);
    setState(() => _pinnedPart = part == _pinnedPart ? null : part);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _dragYaw -= details.delta.dx * 0.009;
    _dragPitch = (_dragPitch + details.delta.dy * 0.004).clamp(-0.28, 0.46);
    if (!_touched) setState(() => _touched = true);
    _snapIfStatic();
  }

  /// Vuelve a la pose base por el camino más corto, sin dar vueltas extra.
  void _reset() {
    const tau = math.pi * 2;
    final turns = (_dragYaw / tau).roundToDouble();
    _yaw -= turns * tau;
    _dragYaw = 0;
    _dragPitch = 0;
    _pointer = Offset.zero;
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

  ({String title, String? value, String body, Color color}) _explain(
    ScenePart part,
  ) {
    final p = widget.profile;
    final level = widget.levelMeters;
    final flow = widget.flowLitersPerSecond;
    switch (part) {
      case ScenePart.level:
        return widget.isSurface
            ? (
                title: 'Altura de agua',
                value: level == null ? null : '${level.toStringAsFixed(2)} m',
                body:
                    'Altura de la lámina de agua en el cauce medida por el '
                    'sensor. Sube con crecidas y baja en estiaje.',
                color: _Palette.level,
              )
            : (
                title: 'Nivel freático',
                value: level == null ? null : '${level.toStringAsFixed(2)} m',
                body:
                    'Profundidad desde la superficie hasta el agua del '
                    'acuífero. Más metros significa que el agua está más '
                    'abajo.',
                color: _Palette.level,
              );
      case ScenePart.sensor:
        return (
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
        return (
          title: 'Bomba',
          value: p.pumpDepth == null
              ? null
              : submergence == null
              ? 'a ${_m(p.pumpDepth!)}'
              : submergence >= 0
              ? 'a ${_m(p.pumpDepth!)} · ${_m(submergence)} bajo el agua'
              : 'a ${_m(p.pumpDepth!)} · sobre el nivel',
          body:
              'Extrae el agua del pozo y la impulsa a la superficie. Debe '
              'quedar bajo el nivel freático; si el agua baja de la bomba, '
              'trabaja en seco.',
          color: _Palette.pump,
        );
      case ScenePart.depth:
        return (
          title: 'Fondo del pozo',
          value: p.depth == null ? null : _m(p.depth!),
          body: 'Profundidad total perforada, medida desde la superficie.',
          color: _Palette.fog,
        );
      case ScenePart.casing:
        return (
          title: 'Entubación',
          value: null,
          body:
              'Tubo que sostiene las paredes del pozo. El tramo ranurado '
              '(criba) deja entrar el agua del acuífero.',
          color: _Palette.steel,
        );
      case ScenePart.aquifer:
        return (
          title: 'Acuífero · zona saturada',
          value: null,
          body:
              'Terreno bajo el nivel freático cuyos poros están llenos de '
              'agua. Desde aquí el pozo se recarga.',
          color: _Palette.aquifer,
        );
      case ScenePart.soil:
        return (
          title: 'Zona no saturada',
          value: null,
          body:
              'Terreno sobre el nivel freático: sus poros tienen aire y el '
              'agua solo lo atraviesa al infiltrarse.',
          color: _Palette.soilText,
        );
      case ScenePart.rock:
        return (
          title: 'Bajo el fondo',
          value: null,
          body: 'Terreno bajo la perforación, fuera del alcance del pozo.',
          color: _Palette.faint,
        );
      case ScenePart.logger:
        return (
          title: 'Datalogger',
          value: pointLinkLabel(widget.link),
          body:
              'Registra las mediciones del sensor y del flujómetro y las '
              'transmite a SmartHydro.',
          color: _Palette.linkColor(widget.link),
        );
      case ScenePart.flowmeter:
        return (
          title: 'Flujómetro',
          value: flow == null ? null : '${flow.toStringAsFixed(2)} L/s',
          body:
              'Mide el caudal que sale por la impulsión y acumula el volumen '
              'total extraído (m³).',
          color: _Palette.flow,
        );
      case ScenePart.water:
        return (
          title: 'Cauce',
          value: null,
          body:
              'Curso de agua superficial. Las líneas sobre la lámina muestran '
              'la corriente; más rápidas, más caudal.',
          color: _Palette.surfaceWater,
        );
      case ScenePart.intake:
        return (
          title: 'Toma',
          value: flow == null ? null : '${flow.toStringAsFixed(2)} L/s',
          body: 'Punto donde se capta el agua del cauce hacia la impulsión.',
          color: _Palette.flow,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final focus = _hoverPart ?? _pinnedPart;
    return Semantics(
      container: true,
      label: _semantics(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return MouseRegion(
            cursor: _hoverPart == null
                ? SystemMouseCursors.grab
                : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) {
              _pointer = Offset.zero;
              setState(() {
                _hovered = false;
                _hoverPart = null;
              });
            },
            onHover: (event) => _onHover(event, size),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: _onPanUpdate,
              onTapUp: _onTapUp,
              onDoubleTap: _reset,
              child: ExcludeSemantics(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedBuilder(
                      animation: Listenable.merge([_flow, _playPulse]),
                      builder: (context, _) {
                        final alive = widget.playing
                            ? 0.55 + _playPulse.value * 0.45
                            : _playPulse.value * 0.45;
                        return CustomPaint(
                          painter: _CaptureStagePainter(
                            phase: _flow.value,
                            yaw: _yaw,
                            pitch: _pitch,
                            layoutYaw: _baseYaw,
                            layoutPitch: _basePitch,
                            topInset: widget.topInset,
                            levelMeters: _level,
                            levelMotion: _levelMotion,
                            levelMin: widget.levelMin,
                            levelMax: widget.levelMax,
                            textScaler: textScaler,
                            flow: _shownFlow,
                            isSurface: widget.isSurface,
                            link: widget.link,
                            profile: widget.profile,
                            hovered: _hovered,
                            alive: alive,
                            focus: focus,
                            hits: _hits,
                          ),
                          child: const SizedBox.expand(),
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
                                  child: AnimatedOpacity(
                                    opacity: _touched ? 0.35 : 0.75,
                                    duration: const Duration(milliseconds: 500),
                                    child: const _HintRow(),
                                  ),
                                )
                              : _InfoCard(
                                  key: ValueKey(focus),
                                  info: _explain(focus),
                                  pinned: _pinnedPart == focus,
                                  onClose: () =>
                                      setState(() => _pinnedPart = null),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
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
          'Arrastra para girar · toca una parte para saber qué es',
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

  final ({String title, String? value, String body, Color color}) info;
  final bool pinned;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _Palette.card.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: info.color.withValues(alpha: 0.45)),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 18),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 34,
                margin: const EdgeInsets.only(top: 2, right: 10),
                decoration: BoxDecoration(
                  color: info.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
}

/// Proyección axonométrica con giro (yaw) e inclinación (pitch). `y` es la
/// altura en píxeles (negativa bajo el terreno).
class _Iso {
  _Iso(this.origin, double yaw, double pitch)
    : cy = math.cos(yaw),
      sy = math.sin(yaw),
      ps = math.sin(pitch),
      pc = math.cos(pitch);

  final Offset origin;
  final double cy;
  final double sy;
  final double ps;
  final double pc;

  /// Signo de las caras laterales que miran al observador.
  double get sx => sy >= 0 ? 1 : -1;
  double get sz => cy >= 0 ? 1 : -1;

  Offset p(double x, double y, double z) {
    final xr = x * cy - z * sy;
    final zr = x * sy + z * cy;
    return Offset(origin.dx + xr, origin.dy - y * pc + zr * ps);
  }

  /// Óvalo de un círculo horizontal: la proyección no depende del giro.
  Rect ring(double y, double radius, {double x = 0, double z = 0}) =>
      Rect.fromCenter(
        center: p(x, y, z),
        width: radius * 2,
        height: radius * 2 * ps,
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
  });

  /// Desplaza el rótulo hacia arriba (positivo) o abajo para sacarlo de la
  /// figura cuando hay espacio libre.
  final double lift;
  final ScenePart part;
  final String caption;
  final String value;
  final String? detail;
  final Offset anchor;
  final Color color;
}

/// Granos deterministas (u, v en 0..1) para texturizar caras de terreno.
final List<Offset> _grain = List.generate(240, (i) {
  double fract(double v) => v - v.floorToDouble();
  return Offset(
    fract(math.sin(i * 12.9898) * 43758.5453),
    fract(math.sin(i * 78.233 + 1.3) * 12543.217),
  );
});

class _CaptureStagePainter extends CustomPainter {
  _CaptureStagePainter({
    required this.phase,
    required this.yaw,
    required this.pitch,
    required this.layoutYaw,
    required this.layoutPitch,
    required this.topInset,
    required this.levelMeters,
    required this.levelMotion,
    required this.levelMin,
    required this.levelMax,
    required this.textScaler,
    required this.flow,
    required this.isSurface,
    required this.link,
    required this.profile,
    required this.hovered,
    required this.alive,
    required this.focus,
    required this.hits,
  });

  final double phase;
  final double yaw;
  final double pitch;
  final double layoutYaw;
  final double layoutPitch;
  final double topInset;
  final double? levelMeters;
  final double levelMotion;
  final double? levelMin;
  final double? levelMax;
  final TextScaler textScaler;
  final double? flow;
  final bool isSurface;
  final PointLink link;
  final CaptureProfile profile;
  final bool hovered;
  final double alive;
  final ScenePart? focus;
  final _SceneHits hits;

  static const _tau = math.pi * 2;

  Size _size = Size.zero;

  double get _q => (flow ?? 0).clamp(0.0, double.infinity).toDouble();

  bool get _flowing => _q > 0.01 && link != PointLink.gap;

  /// 0..1 respecto del caudal máximo configurado (o 50 L/s por defecto).
  double get _flowNorm {
    final max = profile.maxFlow ?? 50;
    return (_q / max).clamp(0.0, 1.0).toDouble();
  }

  /// Vida del agua: base + replay + movimiento real del nivel.
  double get _agitation => (0.25 + alive * 0.5 + levelMotion).clamp(0.0, 1.4);

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    hits.clear();
    final backdrop = Offset.zero & size;
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(backdrop.deflate(10), const Radius.circular(20)),
      Paint()
        ..color = hovered
            ? IkoluColors.cyan.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (isSurface) {
      _paintSurface(canvas, size);
    } else {
      _paintWell(canvas, size);
    }
  }

  // ---------------------------------------------------------------- layout

  /// Tamaño del bloque y origen para que quede centrado en el área libre. Se
  /// usa la pose base para que el encuadre no salte al girar.
  ({double half, double depth, Offset origin}) _layout(
    Size size, {
    required double depthShare,
    required double headroom,
    double widthShare = 0.27,
    double heightShare = 0.32,
  }) {
    final top = topInset;
    const bottom = 70.0;
    final availH = math.max(160.0, size.height - top - bottom);
    final spread = math.sin(layoutYaw).abs() + math.cos(layoutYaw).abs();
    var half = math.min(
      size.width * widthShare,
      math.min(availH * heightShare, 200.0),
    );
    final diamond = 2 * half * spread * math.sin(layoutPitch);
    var depth =
        (availH - diamond - headroom) * depthShare / math.cos(layoutPitch);
    if (depth < 90) {
      depth = 90;
      half *= 0.85;
    }
    final probe = _Iso(Offset.zero, layoutYaw, layoutPitch);
    final corners = [
      for (final x in [-half, half])
        for (final z in [-half, half])
          for (final y in [headroom, -depth]) probe.p(x, y, z),
    ];
    final bounds = _boundsOf(corners);
    final target = Offset(size.width / 2, top + availH / 2);
    return (half: half, depth: depth, origin: target - bounds.center);
  }

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
    final sand = <Offset>[];
    final pebbles = <Offset>[];
    for (var i = 0; i < 150; i++) {
      final g = _grain[i];
      (i % 9 == 0 ? pebbles : sand).add(_bilerp(q, g.dx, g.dy));
    }
    canvas.drawPoints(
      PointMode.points,
      sand,
      Paint()
        ..color = _Palette.soilText.withValues(alpha: 0.22)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPoints(
      PointMode.points,
      pebbles,
      Paint()
        ..color = const Color(0xFF8C7F63).withValues(alpha: 0.45)
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round,
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
    final pores = <Offset>[];
    for (var i = 100; i < 240; i++) {
      final g = _grain[i];
      pores.add(_bilerp(q, g.dx, g.dy));
    }
    canvas.drawPoints(
      PointMode.points,
      pores,
      Paint()
        ..color = const Color(0xFF9BD3FF).withValues(alpha: 0.28)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    // Flujo subterráneo: trazos que avanzan lentamente por la napa.
    final dash = Paint()
      ..color = const Color(0xFFA9DBFF).withValues(alpha: 0.30)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var row = 0; row < 4; row++) {
      final v = 0.18 + row * 0.22;
      for (var k = 0; k < 5; k++) {
        final u = ((k / 5) + phase * (0.3 + row * 0.05)) % 1;
        final a = _bilerp(q, u, v);
        final b = _bilerp(q, math.min(1, u + 0.07), v);
        canvas.drawLine(a, b, dash);
      }
    }
  }

  void _rockBand(Canvas canvas, List<Offset> q, {required double shade}) {
    canvas.drawPath(
      _poly(q),
      Paint()
        ..color = Color.lerp(const Color(0xFF1C2224), Colors.black, shade)!,
    );
    canvas.save();
    canvas.clipPath(_poly(q));
    final hatch = Paint()
      ..color = _Palette.fog.withValues(alpha: 0.07)
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

  // ------------------------------------------------------------------ pozo

  void _paintWell(Canvas canvas, Size size) {
    final l = _layout(size, depthShare: 1, headroom: 40);
    final iso = _Iso(l.origin, yaw + math.sin(phase * _tau) * 0.015, pitch);
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
    final blockBottom = -blockPx;
    final outerR = half * 0.25;
    final innerR = outerR * 0.78;
    final axis = iso.p(0, 0, 0);

    // Sombra.
    canvas.drawOval(
      Rect.fromCenter(
        center: iso.p(0, blockBottom, 0) + const Offset(0, 18),
        width: half * 3.1,
        height: half * 3.1 * iso.ps * 0.6,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    final sceneBounds = Offset.zero & size;
    if (!known) canvas.saveLayer(sceneBounds, Paint());

    // Caras del bloque por bandas: suelo, acuífero y bajo el fondo.
    for (final isX in [true, false]) {
      List<Offset> band(double y0, double y1) =>
          isX ? iso.xFace(half, y0, y1) : iso.zFace(half, y0, y1);
      final shade = isX ? 0.28 : 0.0;
      final dryBottom = levelY ?? (known ? bottomY : blockBottom);
      final dry = band(0, dryBottom);
      _soilBand(canvas, dry, shade: shade);
      hits.add(ScenePart.soil, _poly(dry));
      if (levelY != null) {
        final wetBottom = known ? bottomY : blockBottom;
        if (wetBottom < levelY) {
          final wet = band(levelY, wetBottom);
          _aquiferBand(canvas, wet, shade: shade);
          hits.add(ScenePart.aquifer, _poly(wet));
        }
      }
      if (known) {
        final rock = band(bottomY, blockBottom);
        _rockBand(canvas, rock, shade: shade);
        hits.add(ScenePart.rock, _poly(rock));
      }
      if (levelY != null) _waterTableLine(canvas, band(levelY, levelY - 1));
      canvas.drawPath(
        _poly(band(0, blockBottom)),
        Paint()
          ..color = _Palette.fog.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke,
      );
    }

    // Superficie del terreno.
    final top = [
      iso.p(-half, 0, -half),
      iso.p(half, 0, -half),
      iso.p(half, 0, half),
      iso.p(-half, 0, half),
    ];
    canvas.drawPath(
      _poly(top),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F4B40), Color(0xFF213A32)],
        ).createShader(_boundsOf(top)),
    );
    canvas.drawPoints(
      PointMode.points,
      [for (var i = 0; i < 90; i++) _bilerp(top, _grain[i].dx, _grain[i].dy)],
      Paint()
        ..color = const Color(0xFF6E9A7E).withValues(alpha: 0.25)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      _poly(top),
      Paint()
        ..color = _Palette.fog.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke,
    );

    // Cono de nivel: el plano freático se extiende alrededor del pozo.
    if (levelY != null) {
      final cone = iso.ring(levelY, outerR * 2.6);
      canvas.drawOval(
        cone,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _Palette.aquifer.withValues(alpha: 0.45),
              _Palette.aquifer.withValues(alpha: 0),
            ],
          ).createShader(cone),
      );
    }

    // Pozo en corte: perforación, entubación, agua y equipos.
    final ringTop = iso.ring(0, outerR);
    final ringBottom = iso.ring(bottomY, outerR);
    final hole = Path()
      ..addOval(ringBottom)
      ..addRect(
        Rect.fromLTRB(
          ringTop.left,
          ringTop.center.dy,
          ringTop.right,
          ringBottom.center.dy,
        ),
      )
      ..addOval(ringTop);
    canvas.drawPath(hole, Paint()..color = const Color(0xFF030A0C));
    final innerTop = iso.ring(0, innerR);
    final innerBottom = iso.ring(bottomY, innerR);
    canvas.drawRect(
      Rect.fromLTRB(
        innerTop.left,
        innerTop.center.dy,
        innerTop.right,
        innerBottom.center.dy,
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF0A1A1F), Color(0xFF13272D), Color(0xFF081418)],
        ).createShader(innerTop),
    );

    if (levelY != null) _paintWellWater(canvas, iso, innerR, levelY, bottomY);
    _paintCasing(canvas, iso, outerR, innerR, bottomY, levelY);
    hits.add(ScenePart.casing, hole);
    if (levelY != null) {
      hits.rect(ScenePart.level, iso.ring(levelY, innerR).inflate(6));
    }
    if (known) {
      canvas.drawOval(
        ringBottom,
        Paint()
          ..color = _Palette.fog.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      hits.rect(ScenePart.depth, ringBottom.inflate(8));
    }

    final tags = <_Tag>[];

    // Sensor de nivel colgado de su cable hasta el datalogger.
    final logger = (x: -half * 0.58, z: half * 0.40);
    final sensorX = -innerR * 0.45;
    if (profile.sensorDepth != null) {
      final sy = yAt(profile.sensorDepth!);
      final at = iso.p(sensorX, sy, 0);
      canvas.drawLine(
        iso.p(sensorX, 4, 0),
        at,
        Paint()
          ..color = _Palette.sensor.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
      final pulse = (phase * 3) % 1;
      canvas.drawCircle(
        at,
        5 + pulse * 10,
        Paint()
          ..color = _Palette.sensor.withValues(alpha: (1 - pulse) * 0.5)
          ..style = PaintingStyle.stroke,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: at, width: 7, height: 15),
          const Radius.circular(3.5),
        ),
        Paint()..color = _Palette.sensor,
      );
      hits.rect(
        ScenePart.sensor,
        Rect.fromCenter(center: at, width: 26, height: 30),
      );
      tags.add(
        _Tag(
          ScenePart.sensor,
          'SENSOR DE NIVEL',
          _m(profile.sensorDepth!),
          at,
          _Palette.sensor,
        ),
      );
    }

    // Bomba sumergible.
    final pumpDepth = profile.pumpDepth;
    final pumpX = innerR * 0.40;
    final pumpY = pumpDepth == null ? null : yAt(pumpDepth);
    final dry =
        pumpDepth != null && levelMeters != null && pumpDepth < levelMeters!;
    if (pumpY != null) {
      final jitter = _flowing ? math.sin(phase * _tau * 40) * 0.5 : 0.0;
      final at = iso.p(pumpX, pumpY, 0) + Offset(jitter, 0);
      final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: at, width: 11, height: 30),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            colors: [_Palette.steel, _Palette.steel.withValues(alpha: 0.55)],
          ).createShader(body.outerRect),
      );
      canvas.drawLine(
        at + const Offset(-5.5, 6),
        at + const Offset(5.5, 6),
        Paint()
          ..color = dry ? _Palette.coral : _Palette.flow
          ..strokeWidth = 2,
      );
      if (_flowing && !dry && levelY != null) {
        _paintBubbles(canvas, iso, pumpX, pumpY, levelY, innerR);
      }
      hits.rect(ScenePart.pump, body.outerRect.inflate(10));
      final submergence = levelMeters == null
          ? null
          : pumpDepth! - levelMeters!;
      tags.add(
        _Tag(
          ScenePart.pump,
          dry ? 'BOMBA · EN SECO' : 'BOMBA',
          _m(pumpDepth!),
          at,
          dry ? _Palette.coral : _Palette.pump,
          detail: submergence == null || dry
              ? null
              : '${_m(submergence)} bajo el agua',
        ),
      );
    }

    // Columna de impulsión hasta el cabezal.
    const headY = 26.0;
    final hasFlow = flow != null;
    if (pumpY != null || hasFlow) {
      final from = pumpY != null ? pumpY + 15 : (levelY ?? bottomY * 0.6);
      _paintPipe(canvas, [
        iso.p(pumpX, from, 0),
        iso.p(pumpX, hasFlow ? headY - 8 : 10, 0),
      ], moving: hasFlow);
    }

    // Brocal y losa.
    canvas.drawOval(
      iso.ring(1, outerR * 1.9),
      Paint()..color = const Color(0xFF3A4F4B),
    );
    canvas.drawOval(
      iso.ring(1, outerR * 1.9),
      Paint()
        ..color = _Palette.fog.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke,
    );
    final collar = iso.ring(3, outerR);
    canvas.drawOval(collar, Paint()..color = const Color(0xFF8FA5A6));
    canvas.drawOval(
      iso.ring(3, innerR),
      Paint()..color = const Color(0xFF040C0F),
    );
    if (levelY == null) {
      canvas.drawOval(
        iso.ring(3, innerR),
        Paint()
          ..color = _Palette.fog.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke,
      );
    }

    if (!known) {
      // Sin ficha: el fondo no se conoce y se desvanece.
      final fadeTop = iso.p(0, blockBottom * 0.62, 0).dy;
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
            colors: [Color(0x00000000), Color(0xFF000000)],
          ).createShader(fade),
      );
      canvas.restore();
    }

    // Datalogger con cable al sensor.
    final loggerBase = iso.p(logger.x, 0, logger.z);
    if (profile.sensorDepth != null) {
      _dashed(
        canvas,
        iso.p(sensorX, 4, 0),
        loggerBase,
        Paint()
          ..color = _Palette.sensor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
    final loggerRect = _paintLogger(canvas, iso, logger.x, logger.z);
    tags.add(
      _Tag(
        ScenePart.logger,
        'DATALOGGER',
        pointLinkLabel(link),
        loggerRect.topCenter,
        _Palette.linkColor(link),
      ),
    );

    // Impulsión en superficie: flujómetro y descarga.
    if (hasFlow) {
      final outlet = (x: half * 0.70, z: -half * 0.62);
      final route = <Offset>[
        iso.p(pumpX, headY - 8, 0),
        iso.p(pumpX + 10, headY, 0),
        iso.p(outlet.x - 10, headY, 0),
        iso.p(outlet.x, headY, -10),
        iso.p(outlet.x, headY, outlet.z),
      ];
      _paintPool(canvas, iso, outlet.x, outlet.z, half * 0.22);
      _paintPipe(canvas, route, moving: true);
      final meterAt = iso.p(half * 0.36, headY, 0);
      _dashed(
        canvas,
        iso.p(half * 0.36, 0, 0),
        loggerBase,
        Paint()
          ..color = _Palette.flow.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      canvas.drawLine(
        meterAt,
        iso.p(half * 0.36, 0, 0),
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
          '${flow!.toStringAsFixed(2)} L/s',
          meterAt,
          _Palette.flow,
        ),
      );
    }

    if (levelY != null) {
      final column = known ? profile.depth! - levelMeters! : null;
      tags.add(
        _Tag(
          ScenePart.level,
          'NIVEL FREÁTICO',
          '${levelMeters!.toStringAsFixed(2)} m',
          iso.p(-innerR, levelY, 0),
          _Palette.level,
          detail: column == null || column <= 0
              ? null
              : 'columna de agua ${_m(column)}',
        ),
      );
    }
    if (known) {
      tags.add(
        _Tag(
          ScenePart.depth,
          'FONDO DEL POZO',
          _m(depthM),
          iso.p(outerR, bottomY, 0),
          _Palette.fog,
        ),
      );
    }

    _paintDepthRuler(canvas, iso, half, wellPx, depthM, faded: !known);
    _paintTags(canvas, size, tags, axisX: axis.dx, clearance: outerR + 26);
  }

  void _paintWellWater(
    Canvas canvas,
    _Iso iso,
    double radius,
    double levelY,
    double bottomY,
  ) {
    final surface = iso.ring(levelY, radius);
    final floor = iso.ring(bottomY, radius);
    if (floor.center.dy - surface.center.dy < 2) return;
    final body = Path()
      ..addOval(floor)
      ..addRect(
        Rect.fromLTRB(
          surface.left,
          surface.center.dy,
          surface.right,
          floor.center.dy,
        ),
      );
    final bounds = Rect.fromLTRB(
      surface.left,
      surface.top,
      surface.right,
      floor.bottom,
    );
    const water = _Palette.wellWater;
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            water.withValues(alpha: 0.22),
            water.withValues(alpha: 0.62),
            water.withValues(alpha: 0.40),
            water.withValues(alpha: 0.14),
          ],
          stops: const [0, 0.38, 0.7, 1],
        ).createShader(bounds),
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.40),
          ],
        ).createShader(bounds),
    );

    // Luz que desciende suavemente por la columna.
    canvas.save();
    canvas.clipPath(body);
    final columnH = floor.center.dy - surface.center.dy;
    for (var i = 0; i < 4; i++) {
      final t = (phase * (0.5 + _agitation * 0.6) + i / 4) % 1;
      final band = Rect.fromCenter(
        center: Offset(surface.center.dx, surface.center.dy + t * columnH),
        width: surface.width * 1.1,
        height: surface.height * 1.8,
      );
      canvas.drawOval(
        band,
        Paint()
          ..color = _Palette.fog.withValues(alpha: 0.07 * math.sin(t * math.pi))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.restore();

    // Lámina: menisco luminoso con oleaje que crece al moverse el nivel.
    final amp = 0.8 + _agitation * 2.2;
    final wobble = Path();
    for (var s = 0; s <= 36; s++) {
      final a = s / 36 * _tau;
      final r = 1 + math.sin(a * 3 + phase * _tau * (2 + _agitation)) * 0.02;
      final pt = Offset(
        surface.center.dx + math.cos(a) * surface.width / 2 * r,
        surface.center.dy +
            math.sin(a) * surface.height / 2 * r +
            math.sin(a * 2 + phase * _tau * 3) * amp * 0.5,
      );
      if (s == 0) {
        wobble.moveTo(pt.dx, pt.dy);
      } else {
        wobble.lineTo(pt.dx, pt.dy);
      }
    }
    wobble.close();
    canvas.drawPath(
      wobble,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [
            _Palette.fog.withValues(alpha: 0.55),
            water.withValues(alpha: 0.65),
            water.withValues(alpha: 0.40),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(surface),
    );
    canvas.save();
    canvas.clipPath(wobble);
    final speed = 0.8 + _flowNorm * 1.2 + _agitation;
    for (var i = 0; i < 3; i++) {
      final t = (phase * speed * 2 + i / 3) % 1;
      canvas.drawOval(
        Rect.fromCenter(
          center: surface.center,
          width: surface.width * (0.15 + t * 0.95),
          height: surface.height * (0.15 + t * 0.95),
        ),
        Paint()
          ..color = _Palette.fog.withValues(alpha: (1 - t) * 0.45)
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
    canvas.drawPath(
      wobble,
      Paint()
        ..color = _Palette.fog.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  void _paintCasing(
    Canvas canvas,
    _Iso iso,
    double outerR,
    double innerR,
    double bottomY,
    double? levelY,
  ) {
    final top = iso.ring(0, outerR);
    final bottom = iso.ring(bottomY, outerR);
    final innerTop = iso.ring(0, innerR);
    final metal = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF5F7576), Color(0xFFC9D8D9), Color(0xFF6F8687)],
      ).createShader(Rect.fromLTRB(top.left, 0, innerTop.left, 1));
    final metalR = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF6F8687), Color(0xFFAFC0C1), Color(0xFF4D6061)],
      ).createShader(Rect.fromLTRB(innerTop.right, 0, top.right, 1));
    final leftWall = Rect.fromLTRB(
      top.left,
      top.center.dy,
      innerTop.left,
      bottom.center.dy,
    );
    final rightWall = Rect.fromLTRB(
      innerTop.right,
      top.center.dy,
      top.right,
      bottom.center.dy,
    );
    canvas.drawRect(leftWall, metal);
    canvas.drawRect(rightWall, metalR);

    // Criba: ranuras en el tramo inferior, bajo el nivel.
    final screenTop = math.min(
      levelY ?? bottomY * 0.7,
      bottomY + (-bottomY) * 0.32,
    );
    final slot = Paint()
      ..color = const Color(0xFF0A1A1F)
      ..strokeWidth = 1.4;
    for (var y = bottomY + 6; y < screenTop - 2; y += 5) {
      final ly = iso.p(0, y, 0).dy;
      canvas.drawLine(
        Offset(leftWall.left + 1.5, ly),
        Offset(leftWall.right - 1, ly),
        slot,
      );
      canvas.drawLine(
        Offset(rightWall.left + 1, ly),
        Offset(rightWall.right - 1.5, ly),
        slot,
      );
    }
    canvas.drawArc(
      bottom,
      0,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFF8FA5A6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _paintBubbles(
    Canvas canvas,
    _Iso iso,
    double x,
    double fromY,
    double toY,
    double radius,
  ) {
    final span = toY - fromY;
    if (span <= 4) return;
    final count = 5 + (_flowNorm * 8).round();
    for (var i = 0; i < count; i++) {
      final seed = i * 0.6180339;
      final t = (phase * (1.2 + _flowNorm * 1.6) + seed) % 1;
      final wobble = math.sin((t * 6 + seed * 10) * math.pi) * radius * 0.2;
      final at = iso.p(x - radius * 0.3 + wobble, fromY + span * t, 0);
      canvas.drawCircle(
        at,
        0.8 + t * 1.8,
        Paint()
          ..color = _Palette.fog.withValues(alpha: 0.6 * math.sin(t * math.pi))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
    }
  }

  Rect _paintLogger(Canvas canvas, _Iso iso, double x, double z) {
    final rect = _box(
      canvas,
      iso,
      x: x,
      z: z,
      w: 16,
      d: 10,
      h: 24,
      color: const Color(0xFFDDE7E6),
    );
    final head = iso.p(x, 24, z);
    final tip = iso.p(x + 4, 46, z);
    canvas.drawLine(
      head,
      tip,
      Paint()
        ..color = _Palette.steel
        ..strokeWidth = 1.4,
    );
    final color = _Palette.linkColor(link);
    canvas.drawCircle(tip, 2.4, Paint()..color = color);
    if (link == PointLink.connected) {
      final t = (phase * 2) % 1;
      canvas.drawArc(
        Rect.fromCircle(center: tip, radius: 5 + t * 10),
        -math.pi * 0.85,
        math.pi * 0.7,
        false,
        Paint()
          ..color = color.withValues(alpha: (1 - t) * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }
    final blink = (math.sin(phase * _tau * 6) + 1) / 2;
    canvas.drawCircle(
      iso.p(x, 14, z + iso.sz * 5.2),
      2,
      Paint()..color = color.withValues(alpha: 0.4 + blink * 0.6),
    );
    final area = rect.expandToInclude(Rect.fromCircle(center: tip, radius: 6));
    hits.rect(ScenePart.logger, area.inflate(6));
    return area;
  }

  // --------------------------------------------------- piezas compartidas

  void _paintPipe(Canvas canvas, List<Offset> route, {required bool moving}) {
    final path = Path()..moveTo(route.first.dx, route.first.dy);
    for (final p in route.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final width = ((profile.ductInches ?? 3) * 1.4).clamp(3.0, 9.0).toDouble();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF6E8586)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 2
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
    final count = math.max(3, (metric.length / 18).round());
    final speed = 0.35 + _flowNorm * 1.1 + alive * 0.4;
    final dot = Paint()..color = _Palette.fog.withValues(alpha: 0.85);
    for (var i = 0; i < count; i++) {
      final t = (phase * speed * 3 + i / count) % 1;
      final tangent = metric.getTangentForOffset(metric.length * t);
      if (tangent == null) continue;
      canvas.drawCircle(tangent.position, width * 0.22 + 0.6, dot);
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
    final sweep = _flowing ? phase * _tau * (2 + _flowNorm * 6) : -math.pi / 2;
    canvas.drawLine(
      at,
      at + Offset(math.cos(sweep), math.sin(sweep)) * r,
      Paint()
        ..color = _flowing ? _Palette.flow : _Palette.faint
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
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
      final t = (phase * (2 + _flowNorm * 3) + i / 3) % 1;
      canvas.drawOval(
        Rect.fromCenter(
          center: pool.center,
          width: pool.width * t,
          height: pool.height * t,
        ),
        Paint()
          ..color = _Palette.fog.withValues(alpha: (1 - t) * 0.55)
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
    for (var i = 0; i < 5; i++) {
      final t = (phase * 6 + i / 5) % 1;
      canvas.drawCircle(
        Offset.lerp(a, b, t)! + Offset(math.sin(i * 2.1) * width * 0.4, 0),
        1 + width * 0.18,
        Paint()..color = _Palette.fog.withValues(alpha: 0.8 * (1 - t * 0.6)),
      );
    }
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
    final edges = [
      (iso.sx * half, -iso.sz * half),
      (-iso.sx * half, iso.sz * half),
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
    final left = tags.where((t) => t.anchor.dx <= axisX).toList();
    final right = tags.where((t) => t.anchor.dx > axisX).toList();
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
            ? math.min(axisX - clearance, tag.anchor.dx - 18)
            : math.max(axisX + clearance, tag.anchor.dx + 18);
        var rectLeft = isLeft ? edgeX - layout.width : edgeX;
        rectLeft = rectLeft
            .clamp(12.0, math.max(12.0, size.width - layout.width - 12))
            .toDouble();
        final rect = Rect.fromLTWH(
          rectLeft,
          cy - layout.height / 2,
          layout.width,
          layout.height,
        );
        final focused = focus == tag.part;
        final attach = Offset(isLeft ? rect.right : rect.left, rect.center.dy);
        final guide = Path()
          ..moveTo(tag.anchor.dx, tag.anchor.dy)
          ..lineTo(attach.dx + (isLeft ? 8 : -8), attach.dy)
          ..lineTo(attach.dx, attach.dy);
        canvas.drawPath(
          guide,
          Paint()
            ..color = const Color(0xFF040C0F).withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        canvas.drawPath(
          guide,
          Paint()
            ..color = tag.color.withValues(alpha: focused ? 1 : 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = focused ? 1.6 : 1.1,
        );
        canvas.drawCircle(
          tag.anchor,
          focused ? 4 : 3,
          Paint()..color = tag.color,
        );
        canvas.drawCircle(
          tag.anchor,
          focused ? 8 : 5.5,
          Paint()
            ..color = tag.color.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke,
        );
        _drawTag(canvas, rect, tag, layout, focused: focused);
        hits.rect(tag.part, rect.inflate(2));
      }
    }
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
        color: tag.color,
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
      ),
    );
    final value = painter(
      tag.value,
      const TextStyle(
        color: _Palette.fog,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
    final detail = tag.detail == null
        ? null
        : painter(
            tag.detail!,
            TextStyle(
              color: _Palette.fog.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          );
    final width =
        [caption.width, value.width, detail?.width ?? 0].reduce(math.max) + 22;
    final height = caption.height + value.height + (detail?.height ?? 0) + 10;
    return (
      width: width,
      height: height,
      caption: caption,
      value: value,
      detail: detail,
    );
  }

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
  }) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = _Palette.card.withValues(alpha: 0.95),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = tag.color.withValues(alpha: focused ? 0.9 : 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = focused ? 1.4 : 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left + 5, rect.top + 6, 3, rect.height - 12),
        const Radius.circular(1.5),
      ),
      Paint()..color = tag.color,
    );
    var y = rect.top + 5;
    layout.caption.paint(canvas, Offset(rect.left + 13, y));
    y += layout.caption.height;
    layout.value.paint(canvas, Offset(rect.left + 13, y));
    y += layout.value.height;
    layout.detail?.paint(canvas, Offset(rect.left + 13, y));
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

  // ------------------------------------------------------------ superficial

  void _paintSurface(Canvas canvas, Size size) {
    final l = _layout(
      size,
      depthShare: 0.38,
      headroom: 50,
      widthShare: 0.34,
      heightShare: 0.44,
    );
    final iso = _Iso(l.origin, yaw + math.sin(phase * _tau) * 0.015, pitch);
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
    final fill = hasLevel
        ? (levelMeters! / scaleMax).clamp(0.06, 0.95).toDouble()
        : 0.0;
    final waterY = bedY * (1 - fill);
    const water = _Palette.surfaceWater;

    canvas.drawOval(
      Rect.fromCenter(
        center: iso.p(0, bankBottom, 0) + const Offset(0, 18),
        width: h * 3.1,
        height: h * 3.1 * iso.ps * 0.6,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // Cara lateral exterior (el cauce corre a lo largo de z).
    final side = iso.xFace(h, 0, bankBottom);
    _soilBand(canvas, side, shade: 0.28);
    hits.add(ScenePart.soil, _poly(side));

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
    if (hasLevel) {
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
      hits.add(ScenePart.water, sheetPath);
      canvas.save();
      canvas.clipPath(sheetPath);
      final moving = _flowing;
      final speed = moving ? 0.5 + _flowNorm * 2.0 + alive * 0.4 : 0.06;
      final streak = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.5;
      for (var i = 0; i < 16; i++) {
        final lane = ((i * 0.618) % 1) * 2 - 1;
        final t = (phase * speed * 2 + i / 16) % 1;
        final z0 = -h * 1.1 + t * 2.3 * h;
        final len = h * (0.10 + _flowNorm * 0.2);
        streak.color = _Palette.fog.withValues(
          alpha: 0.5 * math.sin(t * math.pi),
        );
        canvas.drawLine(
          iso.p(lane * c * 0.85, waterY, z0),
          iso.p(lane * c * 0.85, waterY, z0 + len),
          streak,
        );
      }
      for (var k = 0; k < 5; k++) {
        final z = -h + ((phase * (speed + 0.1) + k / 5) % 1) * 2 * h;
        final wave = Path();
        for (var s = 0; s <= 18; s++) {
          final u = s / 18;
          final pt = iso.p(
            -c + u * 2 * c,
            waterY + math.sin(u * _tau + phase * _tau * 3) * (1 + _agitation),
            z,
          );
          if (s == 0) {
            wave.moveTo(pt.dx, pt.dy);
          } else {
            wave.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(
          wave,
          Paint()
            ..color = _Palette.fog.withValues(alpha: 0.14)
            ..style = PaintingStyle.stroke,
        );
      }
      // Destellos.
      for (var i = 0; i < 6; i++) {
        final g = _grain[i * 7];
        final tw = (math.sin(phase * _tau * 3 + i * 1.9) + 1) / 2;
        canvas.drawCircle(
          iso.p(-c + g.dx * 2 * c, waterY, -h + g.dy * 2 * h),
          0.8 + tw * 1.4,
          Paint()..color = Colors.white.withValues(alpha: tw * 0.55),
        );
      }
      canvas.restore();
    }

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
    hits.add(ScenePart.soil, frontPath);
    canvas.drawPath(
      frontPath,
      Paint()
        ..color = _Palette.fog.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke,
    );
    if (hasLevel) {
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
      canvas.save();
      canvas.clipPath(sectionPath);
      for (var i = 0; i < 18; i++) {
        final g = _grain[i * 5 + 3];
        final drift = (g.dx + phase * (0.2 + _flowNorm)) % 1;
        canvas.drawCircle(
          _bilerp(section, drift, 0.1 + g.dy * 0.85),
          1,
          Paint()..color = _Palette.fog.withValues(alpha: 0.25),
        );
      }
      canvas.restore();
      hits.add(ScenePart.level, sectionPath);
      final crest = Path();
      for (var s = 0; s <= 22; s++) {
        final u = s / 22;
        final pt = _bilerp(section, u, 0);
        final y =
            pt.dy +
            math.sin(u * _tau * 1.5 + phase * _tau * (2 + _agitation)) *
                (1 + _agitation * 1.5);
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
      canvas.drawPoints(
        PointMode.points,
        [
          for (var i = 0; i < 40; i++)
            _bilerp(bank, _grain[i + 60].dx, _grain[i + 60].dy),
        ],
        Paint()
          ..color = const Color(0xFF6E9A7E).withValues(alpha: 0.25)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
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
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: sensorPt + const Offset(0, 4),
            width: 14,
            height: 9,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = _Palette.sensor,
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
        ),
      );
    }
    final loggerRect = _paintLogger(canvas, iso, logger.x, logger.z);
    tags.add(
      _Tag(
        ScenePart.logger,
        'DATALOGGER',
        pointLinkLabel(link),
        loggerRect.topCenter,
        _Palette.linkColor(link),
        lift: 70,
      ),
    );

    // Toma, bomba, flujómetro y estanque solo si el punto mide caudal.
    if (flow != null) {
      final pumpAt = (x: c + (h - c) * 0.38, z: h * 0.15);
      const headY = 18.0;
      final outlet = (x: c + (h - c) * 0.55, z: -h * 0.62);
      final intakeY = hasLevel ? waterY - 6 : bedY + 6;
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
      final intake = iso.p(c * 0.35, hasLevel ? waterY : bedY, pumpAt.z);
      if (_flowing && hasLevel) {
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
          '${flow!.toStringAsFixed(2)} L/s',
          meterAt,
          _Palette.flow,
          lift: 80,
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
