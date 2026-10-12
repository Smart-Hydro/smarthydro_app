import 'dart:math' as math;

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

/// Vista singular del punto: una lámina isométrica interactiva.
///
/// Un bloque de terreno en corte que se gira arrastrando y que acompaña al
/// puntero. El pozo muestra su profundidad real, el nivel freático como un
/// plano que atraviesa el acuífero, el sensor y la bomba a su cota, y la
/// impulsión hasta el flujómetro y la descarga. La captación superficial
/// muestra el cauce en sección con su altura de agua y la corriente.
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

  bool _hovered = false;
  bool _dragging = false;
  bool _touched = false;
  Offset _pointer = Offset.zero;
  double _dragYaw = 0;
  double _dragPitch = 0;
  double _yaw = _baseYaw;
  double _pitch = _basePitch;
  DateTime _lastInteraction = DateTime.fromMillisecondsSinceEpoch(0);

  double get _targetYaw =>
      (_baseYaw + _dragYaw + _pointer.dx * 0.12).clamp(0.16, 1.40);
  double get _targetPitch =>
      (_basePitch + _dragPitch + _pointer.dy * 0.06).clamp(0.26, 0.80);

  /// Suaviza la cámara hacia el objetivo y, tras unos segundos sin tocar,
  /// la devuelve con calma a la pose isométrica.
  void _ease() {
    final idle =
        !_dragging &&
        DateTime.now().difference(_lastInteraction) >
            const Duration(seconds: 3);
    if (idle) {
      _dragYaw *= 0.96;
      _dragPitch *= 0.96;
    }
    _yaw += (_targetYaw - _yaw) * 0.14;
    _pitch += (_targetPitch - _pitch) * 0.14;
  }

  void _snapIfStatic() {
    if (_flow.isAnimating) return;
    setState(() {
      _yaw = _targetYaw;
      _pitch = _targetPitch;
    });
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
    if (_dragging || size.isEmpty) return;
    _pointer = Offset(
      (event.localPosition.dx / size.width) * 2 - 1,
      (event.localPosition.dy / size.height) * 2 - 1,
    );
    _snapIfStatic();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _dragYaw = (_dragYaw - details.delta.dx * 0.006).clamp(-0.55, 0.75);
    _dragPitch = (_dragPitch + details.delta.dy * 0.004).clamp(-0.22, 0.36);
    _lastInteraction = DateTime.now();
    if (!_touched) setState(() => _touched = true);
    _snapIfStatic();
  }

  void _reset() {
    _dragYaw = 0;
    _dragPitch = 0;
    _pointer = Offset.zero;
    _lastInteraction = DateTime.fromMillisecondsSinceEpoch(0);
    _snapIfStatic();
  }

  String _semantics() {
    final p = widget.profile;
    final parts = <String>[
      widget.isSurface ? 'Captación superficial' : 'Pozo subterráneo',
      widget.levelMeters == null
          ? 'sin nivel'
          : 'nivel ${widget.levelMeters!.toStringAsFixed(2)} metros',
      widget.flowLitersPerSecond == null
          ? 'sin caudal'
          : 'caudal ${widget.flowLitersPerSecond!.toStringAsFixed(2)} litros por segundo',
      if (p.depth != null) 'profundidad ${p.depth!.toStringAsFixed(1)} metros',
      if (p.pumpDepth != null)
        'bomba a ${p.pumpDepth!.toStringAsFixed(1)} metros',
      if (p.sensorDepth != null)
        'sensor a ${p.sensorDepth!.toStringAsFixed(1)} metros',
      pointLinkLabel(widget.link),
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return Semantics(
      container: true,
      label: _semantics(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) {
              _pointer = Offset.zero;
              setState(() => _hovered = false);
            },
            onHover: (event) => _onHover(event, size),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => _dragging = true,
              onPanUpdate: _onPanUpdate,
              onPanEnd: (_) {
                _dragging = false;
                _lastInteraction = DateTime.now();
              },
              onPanCancel: () => _dragging = false,
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
                            levelMeters: widget.levelMeters,
                            levelFill: widget.levelFill,
                            levelMin: widget.levelMin,
                            levelMax: widget.levelMax,
                            textScaler: textScaler,
                            flow: widget.flowLitersPerSecond,
                            isSurface: widget.isSurface,
                            link: widget.link,
                            profile: widget.profile,
                            hovered: _hovered,
                            alive: alive,
                          ),
                          child: const SizedBox.expand(),
                        );
                      },
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 14,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _touched ? 0 : 0.7,
                          duration: const Duration(milliseconds: 500),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.threed_rotation_rounded,
                                size: 14,
                                color: Color(0xFF9AB0B1),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Arrastra para girar',
                                style: TextStyle(
                                  color: Color(0xFF9AB0B1),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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

/// Proyección axonométrica con giro (yaw) e inclinación (pitch). `y` es la
/// altura en píxeles (negativa bajo el terreno).
class _Iso {
  _Iso(this.origin, double yaw, double pitch)
    : _cy = math.cos(yaw),
      _sy = math.sin(yaw),
      ps = math.sin(pitch),
      pc = math.cos(pitch);

  final Offset origin;
  final double _cy;
  final double _sy;
  final double ps;
  final double pc;

  Offset p(double x, double y, double z) {
    final xr = x * _cy - z * _sy;
    final zr = x * _sy + z * _cy;
    return Offset(origin.dx + xr, origin.dy - y * pc + zr * ps);
  }

  /// Óvalo de un círculo horizontal: la proyección no depende del giro.
  Rect ring(double y, double radius, {double x = 0, double z = 0}) =>
      Rect.fromCenter(
        center: p(x, y, z),
        width: radius * 2,
        height: radius * 2 * ps,
      );

  Path quad(List<Offset> points) => Path()..addPolygon(points, true);
}

class _Marker {
  _Marker(this.text, this.anchor, this.color, {this.strong = false});

  final String text;
  final Offset anchor;
  final Color color;
  final bool strong;
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
    required this.levelFill,
    required this.levelMin,
    required this.levelMax,
    required this.textScaler,
    required this.flow,
    required this.isSurface,
    required this.link,
    required this.profile,
    required this.hovered,
    required this.alive,
  });

  final double phase;
  final double yaw;
  final double pitch;
  final double layoutYaw;
  final double layoutPitch;
  final double topInset;
  final double? levelMeters;
  final double? levelFill;
  final double? levelMin;
  final double? levelMax;
  final TextScaler textScaler;
  final double? flow;
  final bool isSurface;
  final PointLink link;
  final CaptureProfile profile;
  final bool hovered;
  final double alive;

  static const _tau = math.pi * 2;
  static const _surfaceCard = Color(0xFF12252A);
  static const _blue = Color(0xFF69B9FF);
  static const _fog = Color(0xFFE8F2F1);
  static const _faint = Color(0xFF9AB0B1);
  static const _coral = Color(0xFFFF847A);
  static const _soilTop = Color(0xFF1A3634);
  static const _soilDeep = Color(0xFF0B1B1E);
  static const _steel = Color(0xFFB4C7C8);

  Color get _accent => isSurface ? _blue : IkoluColors.cyan;

  double get _q => (flow ?? 0).clamp(0.0, double.infinity).toDouble();

  bool get _flowing => _q > 0.01 && link != PointLink.gap;

  /// 0..1 respecto del caudal máximo configurado (o 50 L/s por defecto).
  double get _flowNorm {
    final max = profile.maxFlow ?? 50;
    return (_q / max).clamp(0.0, 1.0).toDouble();
  }

  Size _size = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
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
            ? _accent.withValues(alpha: 0.20)
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

  /// Calcula el tamaño del bloque y su origen para que quede centrado en el
  /// área libre. Se usa la pose base para que el encuadre no salte al girar.
  ({double half, double depth, Offset origin}) _layout(
    Size size, {
    required double depthShare,
    double widthShare = 0.27,
    double heightShare = 0.32,
    required double headroom,
  }) {
    final top = topInset;
    const bottom = 34.0;
    final availH = math.max(160.0, size.height - top - bottom);
    final spread = math.sin(layoutYaw).abs() + math.cos(layoutYaw).abs();
    var half = math.min(
      size.width * widthShare,
      math.min(availH * heightShare, 210.0),
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

  // ------------------------------------------------------------------ pozo

  void _paintWell(Canvas canvas, Size size) {
    final l = _layout(size, depthShare: 1, headroom: 30);
    final iso = _Iso(l.origin, yaw + math.sin(phase * _tau) * 0.02, pitch);
    final half = l.half;
    final depthPx = l.depth;

    final candidates = <double>[
      ?profile.pumpDepth,
      ?profile.sensorDepth,
      ?levelMeters,
      ?levelMax,
    ];
    final deepest = candidates.isEmpty ? 0.0 : candidates.reduce(math.max);
    final depthM = profile.depth ?? math.max(30.0, deepest * 1.3);
    final m2px = depthPx / depthM;
    double yAt(double meters) => -(meters.clamp(0.0, depthM).toDouble() * m2px);

    final levelY = levelMeters == null ? null : yAt(levelMeters!);
    final radius = half * 0.2;
    final bottomY = -depthPx;

    _paintBlock(canvas, iso, half, depthPx, aquiferTop: levelY);

    // Hueco del pozo: el interior se ve "en rayos X" a través del terreno.
    final shaftTop = iso.ring(0, radius);
    final shaftBottom = iso.ring(bottomY, radius);
    final shaft = Path()
      ..addOval(shaftBottom)
      ..addRect(
        Rect.fromLTRB(
          shaftTop.left,
          shaftTop.center.dy,
          shaftTop.right,
          shaftBottom.center.dy,
        ),
      )
      ..addOval(shaftTop);
    canvas.drawPath(
      shaft,
      Paint()..color = const Color(0xFF040C0F).withValues(alpha: 0.88),
    );

    if (levelY != null) {
      _paintWellWater(canvas, iso, radius, levelY, bottomY);
    }

    _paintReplayBand(canvas, iso, radius, yAt);

    // Fuste de vidrio.
    final wall = Paint()
      ..color = _fog.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawLine(
      Offset(shaftTop.left, shaftTop.center.dy),
      Offset(shaftBottom.left, shaftBottom.center.dy),
      wall,
    );
    canvas.drawLine(
      Offset(shaftTop.right, shaftTop.center.dy),
      Offset(shaftBottom.right, shaftBottom.center.dy),
      wall,
    );
    canvas.drawArc(shaftBottom, 0, math.pi, false, wall);
    final glint = shaftTop.left + shaftTop.width * 0.78;
    canvas.drawLine(
      Offset(glint, shaftTop.center.dy + 8),
      Offset(glint, shaftBottom.center.dy - 6),
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _fog.withValues(alpha: 0.22 + alive * 0.1),
                _fog.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTRB(
                glint - 1,
                shaftTop.top,
                glint + 1,
                shaftBottom.bottom,
              ),
            )
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // Losa y brocal.
    canvas.drawOval(
      iso.ring(1, radius * 1.9),
      Paint()..color = const Color(0xFF2A4542).withValues(alpha: 0.9),
    );
    canvas.drawOval(
      iso.ring(1, radius * 1.9),
      Paint()
        ..color = _fog.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke,
    );
    canvas.drawOval(
      iso.ring(2, radius),
      Paint()..color = const Color(0xFF051013),
    );
    canvas.drawOval(
      iso.ring(2, radius),
      Paint()
        ..color = _fog.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    final markersLeft = <_Marker>[];
    final markersRight = <_Marker>[];

    // Sensor de nivel colgado de su cable.
    if (profile.sensorDepth != null) {
      final sx = -radius * 0.45;
      final sy = yAt(profile.sensorDepth!);
      final top = iso.p(sx, 2, 0);
      final at = iso.p(sx, sy, 0);
      canvas.drawLine(
        top,
        at,
        Paint()
          ..color = _fog.withValues(alpha: 0.28)
          ..strokeWidth = 1,
      );
      final pulse = (phase * 3) % 1;
      canvas.drawCircle(
        at,
        4 + pulse * 10,
        Paint()
          ..color = _accent.withValues(alpha: (1 - pulse) * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: at, width: 6, height: 12),
          const Radius.circular(3),
        ),
        Paint()..color = _accent,
      );
      markersLeft.add(
        _Marker('Sensor ${_m(profile.sensorDepth!)}', at, _accent),
      );
    }

    // Bomba e impulsión.
    final pumpDepth = profile.pumpDepth;
    final pumpX = radius * 0.42;
    final pumpY = pumpDepth == null ? null : yAt(pumpDepth);
    final dry =
        pumpDepth != null && levelMeters != null && pumpDepth < levelMeters!;
    if (pumpY != null) {
      final jitter = _flowing ? math.sin(phase * _tau * 40) * 0.6 : 0.0;
      final at = iso.p(pumpX, pumpY, 0) + Offset(jitter, 0);
      final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: at, width: 9, height: 26),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            colors: [_steel, _steel.withValues(alpha: 0.55)],
          ).createShader(body.outerRect),
      );
      canvas.drawLine(
        at + const Offset(-4.5, 4),
        at + const Offset(4.5, 4),
        Paint()
          ..color = dry ? _coral : _accent
          ..strokeWidth = 2,
      );
      if (_flowing && !dry && levelY != null) {
        _paintBubbles(canvas, iso, pumpX, pumpY, levelY, radius);
      }
      if (dry) {
        markersRight.add(
          _Marker(
            'Bomba ${_m(pumpDepth)} · sobre el nivel',
            at,
            _coral,
            strong: true,
          ),
        );
      } else {
        markersRight.add(_Marker('Bomba ${_m(pumpDepth!)}', at, _steel));
      }
    }

    // Recorrido del agua: bomba → superficie → flujómetro → descarga.
    final riseFrom = pumpY == null ? (levelY ?? bottomY * 0.6) : pumpY + 13;
    final headY = 26.0;
    final outlet = (x: half * 0.70, z: -half * 0.62);
    final route = <Offset>[
      iso.p(pumpX, riseFrom, 0),
      iso.p(pumpX, headY - 8, 0),
      iso.p(pumpX + 10, headY, 0),
      iso.p(outlet.x - 10, headY, 0),
      iso.p(outlet.x, headY, -10),
      iso.p(outlet.x, headY, outlet.z),
    ];
    _paintPool(canvas, iso, outlet.x, outlet.z, half * 0.22);
    _paintPipe(canvas, route);
    _paintFlowmeter(canvas, iso.p(half * 0.38, headY, 0));
    _paintDischarge(canvas, iso, outlet.x, headY, outlet.z);

    if (levelY != null) {
      markersLeft.add(
        _Marker(
          'Nivel freático ${levelMeters!.toStringAsFixed(2)} m',
          iso.p(-radius, levelY, 0),
          _accent,
          strong: true,
        ),
      );
    } else {
      markersLeft.add(
        _Marker(
          'Sin lectura de nivel',
          iso.p(-radius, bottomY * 0.4, 0),
          _faint,
        ),
      );
    }
    markersRight.add(
      _Marker(
        profile.depth == null
            ? 'Fondo ~${_m(depthM)}'
            : 'Profundidad ${_m(depthM)}',
        iso.p(radius, bottomY, 0),
        _faint,
      ),
    );

    _paintDepthRuler(canvas, iso, half, depthPx);
    _paintMarkers(canvas, size, markersLeft, left: true);
    _paintMarkers(canvas, size, markersRight, left: false);
  }

  void _paintWellWater(
    Canvas canvas,
    _Iso iso,
    double radius,
    double levelY,
    double bottomY,
  ) {
    final inner = radius - 2;
    final surface = iso.ring(levelY, inner);
    final floor = iso.ring(bottomY, inner);
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
    // Volumen cilíndrico: bordes oscuros y centro luminoso.
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _accent.withValues(alpha: 0.16),
            _accent.withValues(alpha: 0.46),
            _accent.withValues(alpha: 0.30),
            _accent.withValues(alpha: 0.10),
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
            Colors.black.withValues(alpha: 0.35),
          ],
        ).createShader(bounds),
    );

    // Bandas de luz que descienden lentamente por la columna.
    canvas.save();
    canvas.clipPath(body);
    final columnH = floor.center.dy - surface.center.dy;
    for (var i = 0; i < 3; i++) {
      final t = (phase * (0.6 + alive * 0.6) + i / 3) % 1;
      final cy = surface.center.dy + t * columnH;
      final band = Rect.fromCenter(
        center: Offset(surface.center.dx, cy),
        width: surface.width,
        height: surface.height * 1.6,
      );
      canvas.drawOval(
        band,
        Paint()
          ..color = _fog.withValues(alpha: 0.05 * math.sin(t * math.pi))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.restore();

    // Superficie del agua: lámina elíptica, ondas concéntricas y brillo.
    canvas.drawOval(
      surface,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [
            _fog.withValues(alpha: 0.42 + alive * 0.15),
            _accent.withValues(alpha: 0.50),
            _accent.withValues(alpha: 0.32),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(surface),
    );
    canvas.save();
    canvas.clipRect(surface);
    final speed = 1.0 + _flowNorm * 1.5 + alive;
    for (var i = 0; i < 3; i++) {
      final t = (phase * speed * 2 + i / 3) % 1;
      final ring = Rect.fromCenter(
        center: surface.center,
        width: surface.width * (0.18 + t * 0.9),
        height: surface.height * (0.18 + t * 0.9),
      );
      canvas.drawOval(
        ring,
        Paint()
          ..color = _fog.withValues(alpha: (1 - t) * 0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
    canvas.drawOval(
      surface,
      Paint()
        ..color = _fog.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
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
    final count = 4 + (_flowNorm * 8).round();
    for (var i = 0; i < count; i++) {
      final seed = i * 0.6180339;
      final t = (phase * (1.6 + _flowNorm * 2) + seed) % 1;
      final wobble = math.sin((t * 6 + seed * 10) * math.pi) * radius * 0.25;
      final at = iso.p(x - radius * 0.3 + wobble, fromY + span * t, 0);
      canvas.drawCircle(
        at,
        0.8 + t * 1.6,
        Paint()
          ..color = _fog.withValues(alpha: 0.55 * math.sin(t * math.pi))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
    }
  }

  void _paintReplayBand(
    Canvas canvas,
    _Iso iso,
    double radius,
    double Function(double meters) yAt,
  ) {
    if (levelMin == null || levelMax == null || levelMax! <= levelMin!) return;
    final a = iso.p(-radius - 5, yAt(levelMin!), 0);
    final b = iso.p(-radius - 5, yAt(levelMax!), 0);
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = _accent.withValues(alpha: 0.55)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  // --------------------------------------------------- piezas compartidas

  /// Bloque de terreno en corte con estratos y, si hay nivel, el acuífero
  /// saturado bajo el plano freático.
  void _paintBlock(
    Canvas canvas,
    _Iso iso,
    double half,
    double depthPx, {
    double? aquiferTop,
  }) {
    final h = half;
    final d = -depthPx;
    final top = [
      iso.p(-h, 0, -h),
      iso.p(h, 0, -h),
      iso.p(h, 0, h),
      iso.p(-h, 0, h),
    ];
    final right = [
      iso.p(h, 0, -h),
      iso.p(h, 0, h),
      iso.p(h, d, h),
      iso.p(h, d, -h),
    ];
    final front = [
      iso.p(-h, 0, h),
      iso.p(h, 0, h),
      iso.p(h, d, h),
      iso.p(-h, d, h),
    ];

    // Sombra en el suelo.
    final shadowCenter = iso.p(0, d - 6, 0);
    canvas.drawOval(
      Rect.fromCenter(
        center: shadowCenter + const Offset(0, 14),
        width: h * 3.2,
        height: h * 3.2 * iso.ps * 0.7,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    void face(List<Offset> pts, double light) {
      final path = iso.quad(pts);
      final bounds = _boundsOf(pts);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(
                _soilTop,
                Colors.white,
                light * 0.08,
              )!.withValues(alpha: 0.78),
              _soilDeep.withValues(alpha: 0.72),
            ],
          ).createShader(bounds),
      );
      // Estratos.
      final strata = Paint()
        ..color = _fog.withValues(alpha: 0.05)
        ..strokeWidth = 1;
      for (var i = 1; i < 6; i++) {
        final t = i / 6 + math.sin(i * 1.7) * 0.03;
        canvas.drawLine(
          Offset.lerp(pts[0], pts[3], t)!,
          Offset.lerp(pts[1], pts[2], t)!,
          strata,
        );
      }
      if (aquiferTop != null && aquiferTop > d) {
        final t = (aquiferTop / d).clamp(0.0, 1.0);
        final wet = [
          Offset.lerp(pts[0], pts[3], t)!,
          Offset.lerp(pts[1], pts[2], t)!,
          pts[2],
          pts[3],
        ];
        canvas.drawPath(
          iso.quad(wet),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _accent.withValues(alpha: 0.20),
                _accent.withValues(alpha: 0.05),
              ],
            ).createShader(_boundsOf(wet)),
        );
        // Línea freática que ondula suavemente sobre la cara.
        final a = wet[0];
        final b = wet[1];
        final line = Path()..moveTo(a.dx, a.dy);
        for (var s = 1; s <= 24; s++) {
          final u = s / 24;
          final pt = Offset.lerp(a, b, u)!;
          line.lineTo(
            pt.dx,
            pt.dy + math.sin(u * _tau * 2 + phase * _tau * 2) * 1.2,
          );
        }
        canvas.drawPath(
          line,
          Paint()
            ..color = _accent.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = _fog.withValues(alpha: 0.10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    face(right, 0);
    face(front, 1);

    // Plano freático atravesando el bloque.
    if (aquiferTop != null && aquiferTop > d) {
      final plane = [
        iso.p(-h, aquiferTop, -h),
        iso.p(h, aquiferTop, -h),
        iso.p(h, aquiferTop, h),
        iso.p(-h, aquiferTop, h),
      ];
      canvas.drawPath(
        iso.quad(plane),
        Paint()..color = _accent.withValues(alpha: 0.07 + alive * 0.04),
      );
    }

    // Superficie del terreno.
    canvas.drawPath(
      iso.quad(top),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF26443F), const Color(0xFF1B3431)],
        ).createShader(_boundsOf(top)),
    );
    canvas.drawPath(
      iso.quad(top),
      Paint()
        ..color = _fog.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintPipe(Canvas canvas, List<Offset> route) {
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
    canvas.drawPath(
      path,
      Paint()
        ..color = _flowing
            ? _accent.withValues(alpha: 0.30 + _flowNorm * 0.45)
            : const Color(0xFF2A3B3D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width - 1
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (!_flowing) return;
    final metric = path.computeMetrics().firstOrNull;
    if (metric == null) return;
    final count = 6 + (_flowNorm * 14).round();
    final speed = 0.35 + _flowNorm * 1.1 + alive * 0.4;
    final dot = Paint()..color = _fog.withValues(alpha: 0.85);
    for (var i = 0; i < count; i++) {
      final t = (phase * speed * 3 + i / count) % 1;
      final tangent = metric.getTangentForOffset(metric.length * t);
      if (tangent == null) continue;
      canvas.drawCircle(tangent.position, width * 0.22 + 0.6, dot);
    }
  }

  void _paintFlowmeter(Canvas canvas, Offset at) {
    final r = ((profile.flowmeterInches ?? 3) * 1.6)
        .clamp(5.0, 11.0)
        .toDouble();
    canvas.drawCircle(at, r + 2, Paint()..color = const Color(0xFF0B1A1D));
    canvas.drawCircle(
      at,
      r + 2,
      Paint()
        ..color = _steel.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final sweep = _flowing ? phase * _tau * (2 + _flowNorm * 6) : 0.0;
    canvas.drawLine(
      at,
      at + Offset(math.cos(sweep), math.sin(sweep)) * r,
      Paint()
        ..color = _flowing ? _accent : _faint
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintPool(Canvas canvas, _Iso iso, double x, double z, double r) {
    final pool = iso.ring(0.5, r, x: x, z: z);
    canvas.drawOval(
      pool,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _accent.withValues(alpha: 0.55),
            _accent.withValues(alpha: 0.18),
          ],
        ).createShader(pool),
    );
    canvas.drawOval(
      pool,
      Paint()
        ..color = _fog.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke,
    );
    if (!_flowing) return;
    canvas.save();
    canvas.clipPath(Path()..addOval(pool));
    for (var i = 0; i < 3; i++) {
      final t = (phase * (2 + _flowNorm * 3) + i / 3) % 1;
      final ring = Rect.fromCenter(
        center: pool.center,
        width: pool.width * t,
        height: pool.height * t,
      );
      canvas.drawOval(
        ring,
        Paint()
          ..color = _fog.withValues(alpha: (1 - t) * 0.55)
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
            _fog.withValues(alpha: 0.85),
            _accent.withValues(alpha: 0.35),
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
        Paint()..color = _fog.withValues(alpha: 0.8 * (1 - t * 0.6)),
      );
    }
  }

  void _paintDepthRuler(Canvas canvas, _Iso iso, double half, double depthPx) {
    final top = iso.p(-half, 0, half);
    final bottom = iso.p(-half, -depthPx, half);
    final tick = Paint()
      ..color = _faint.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    const steps = 5;
    for (var i = 0; i <= steps; i++) {
      final at = Offset.lerp(top, bottom, i / steps)!;
      canvas.drawLine(at, at + const Offset(-5, 0), tick);
    }
    _chip(
      canvas,
      '0 m',
      top + const Offset(-8, 0),
      _faint,
      alignRight: true,
      small: true,
    );
  }

  /// Rótulos con guía, apilados sin superponerse en su columna.
  void _paintMarkers(
    Canvas canvas,
    Size size,
    List<_Marker> markers, {
    required bool left,
  }) {
    if (markers.isEmpty) return;
    markers.sort((a, b) => a.anchor.dy.compareTo(b.anchor.dy));
    const gap = 24.0;
    final ys = <double>[];
    for (final m in markers) {
      final y = ys.isEmpty ? m.anchor.dy : math.max(m.anchor.dy, ys.last + gap);
      ys.add(y);
    }
    final overflow = ys.last - (size.height - 24);
    if (overflow > 0) {
      for (var i = 0; i < ys.length; i++) {
        ys[i] -= overflow;
      }
    }
    final columnX = left
        ? math.max(size.width * 0.20, size.width / 2 - 260)
        : math.min(size.width * 0.80, size.width / 2 + 260);
    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      final end = Offset(
        left
            ? math.min(columnX, m.anchor.dx - 18)
            : math.max(columnX, m.anchor.dx + 18),
        ys[i],
      );
      final elbow = Offset(left ? end.dx + 10 : end.dx - 10, ys[i]);
      final guide = Path()
        ..moveTo(m.anchor.dx, m.anchor.dy)
        ..lineTo(elbow.dx, elbow.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(
        guide,
        Paint()
          ..color = m.color.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.drawCircle(m.anchor, 2, Paint()..color = m.color);
      _chip(
        canvas,
        m.text,
        end + Offset(left ? -4 : 4, 0),
        m.color,
        alignRight: left,
        small: !m.strong,
      );
    }
  }

  // ------------------------------------------------------------ superficial

  void _paintSurface(Canvas canvas, Size size) {
    final l = _layout(
      size,
      depthShare: 0.38,
      headroom: 34,
      widthShare: 0.34,
      heightShare: 0.44,
    );
    final iso = _Iso(l.origin, yaw + math.sin(phase * _tau) * 0.02, pitch);
    final h = l.half;
    final depthPx = l.depth;
    final c = h * 0.42; // medio ancho del cauce
    final bedY = -depthPx * 0.62;
    final bankBottom = -depthPx;

    final scaleMax = math.max(
      0.5,
      math.max(levelMax ?? 0, levelMeters ?? 0) * 1.35,
    );
    final fill = levelMeters != null
        ? (levelMeters! / scaleMax).clamp(0.06, 0.95).toDouble()
        : (levelFill ?? 0.3).clamp(0.06, 0.95).toDouble();
    final waterY = bedY * (1 - fill);

    // Sombra.
    canvas.drawOval(
      Rect.fromCenter(
        center: iso.p(0, bankBottom - 6, 0) + const Offset(0, 14),
        width: h * 3.2,
        height: h * 3.2 * iso.ps * 0.7,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    final soil = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1A3634), Color(0xFF0B1B1E)],
      ).createShader(_boundsOf([iso.p(0, 0, h), iso.p(0, bankBottom, h)]));
    final edge = Paint()
      ..color = _fog.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke;

    // Cara derecha (x = +h).
    final right = iso.quad([
      iso.p(h, 0, -h),
      iso.p(h, 0, h),
      iso.p(h, bankBottom, h),
      iso.p(h, bankBottom, -h),
    ]);
    canvas.drawPath(right, soil);
    canvas.drawPath(right, edge);

    // Pared interior izquierda del cauce (x = -c, mira hacia +x).
    final innerWall = iso.quad([
      iso.p(-c, 0, -h),
      iso.p(-c, 0, h),
      iso.p(-c, bedY, h),
      iso.p(-c, bedY, -h),
    ]);
    canvas.drawPath(innerWall, Paint()..color = const Color(0xFF16302E));
    // Lecho.
    canvas.drawPath(
      iso.quad([
        iso.p(-c, bedY, -h),
        iso.p(c, bedY, -h),
        iso.p(c, bedY, h),
        iso.p(-c, bedY, h),
      ]),
      Paint()..color = const Color(0xFF0E2124),
    );

    // Lámina de agua.
    final water = [
      iso.p(-c, waterY, -h),
      iso.p(c, waterY, -h),
      iso.p(c, waterY, h),
      iso.p(-c, waterY, h),
    ];
    final waterPath = iso.quad(water);
    canvas.drawPath(
      waterPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _accent.withValues(alpha: 0.35),
            _accent.withValues(alpha: 0.62),
          ],
        ).createShader(_boundsOf(water)),
    );
    canvas.save();
    canvas.clipPath(waterPath);
    final speed = _flowing ? 0.6 + _flowNorm * 2.2 + alive * 0.5 : 0.08;
    final streak = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    for (var i = 0; i < 14; i++) {
      final lane = ((i * 0.618) % 1) * 2 - 1;
      final t = (phase * speed * 2 + i / 14) % 1;
      final z0 = -h + t * 2.2 * h - 0.1 * h;
      final len = h * (0.10 + _flowNorm * 0.18);
      final a = iso.p(lane * c * 0.85, waterY, z0);
      final b = iso.p(lane * c * 0.85, waterY, z0 + len);
      streak.color = _fog.withValues(alpha: 0.45 * math.sin(t * math.pi));
      canvas.drawLine(a, b, streak);
    }
    // Ondas transversales.
    for (var k = 0; k < 4; k++) {
      final z = -h + ((phase * speed + k / 4) % 1) * 2 * h;
      final wave = Path();
      for (var s = 0; s <= 16; s++) {
        final u = s / 16;
        final x = -c + u * 2 * c;
        final pt = iso.p(
          x,
          waterY + math.sin(u * _tau + phase * _tau * 3) * 1.4,
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
          ..color = _fog.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();

    // Cara frontal (z = +h) con la sección en U del cauce.
    final frontLeft = [
      iso.p(-h, 0, h),
      iso.p(-c, 0, h),
      iso.p(-c, bedY, h),
      iso.p(c, bedY, h),
      iso.p(c, 0, h),
      iso.p(h, 0, h),
      iso.p(h, bankBottom, h),
      iso.p(-h, bankBottom, h),
    ];
    final frontPath = Path()..addPolygon(frontLeft, true);
    canvas.drawPath(frontPath, soil);
    final strata = Paint()
      ..color = _fog.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = bedY + (bankBottom - bedY) * (i / 4);
      canvas.drawLine(iso.p(-h, y, h), iso.p(h, y, h), strata);
    }
    canvas.drawPath(frontPath, edge);
    // Sección de agua en la cara frontal.
    final section = [
      iso.p(-c, waterY, h),
      iso.p(c, waterY, h),
      iso.p(c, bedY, h),
      iso.p(-c, bedY, h),
    ];
    canvas.drawPath(
      iso.quad(section),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _accent.withValues(alpha: 0.65),
            _accent.withValues(alpha: 0.25),
          ],
        ).createShader(_boundsOf(section)),
    );
    final crest = Path();
    for (var s = 0; s <= 20; s++) {
      final u = s / 20;
      final pt = iso.p(
        -c + u * 2 * c,
        waterY + math.sin(u * _tau * 1.5 + phase * _tau * (2 + alive)) * 1.6,
        h,
      );
      if (s == 0) {
        crest.moveTo(pt.dx, pt.dy);
      } else {
        crest.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
      crest,
      Paint()
        ..color = _fog.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    // Riberas.
    for (final side in [-1.0, 1.0]) {
      final inner = side * c;
      final outer = side * h;
      final bank = [
        iso.p(math.min(inner, outer), 0, -h),
        iso.p(math.max(inner, outer), 0, -h),
        iso.p(math.max(inner, outer), 0, h),
        iso.p(math.min(inner, outer), 0, h),
      ];
      canvas.drawPath(
        iso.quad(bank),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF26443F), Color(0xFF1B3431)],
          ).createShader(_boundsOf(bank)),
      );
      canvas.drawPath(
        iso.quad(bank),
        Paint()
          ..color = _fog.withValues(alpha: 0.14)
          ..style = PaintingStyle.stroke,
      );
    }

    // Toma en la ribera derecha: succión → bomba → flujómetro → estanque.
    final pumpAt = (x: c + (h - c) * 0.38, z: h * 0.15);
    final headY = 18.0;
    final outlet = (x: c + (h - c) * 0.55, z: -h * 0.62);
    final route = <Offset>[
      iso.p(c * 0.35, waterY - 6, pumpAt.z),
      iso.p(c * 0.35, headY, pumpAt.z),
      iso.p(pumpAt.x, headY, pumpAt.z),
      iso.p(pumpAt.x, headY, outlet.z + 10),
      iso.p(outlet.x, headY, outlet.z),
    ];
    _paintPool(canvas, iso, outlet.x, outlet.z, (h - c) * 0.32);
    _paintPipe(canvas, route);
    final pump = iso.p(pumpAt.x, headY, pumpAt.z);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: pump, width: 18, height: 12),
        const Radius.circular(4),
      ),
      Paint()..color = _steel,
    );
    _paintFlowmeter(canvas, iso.p(pumpAt.x, headY, (pumpAt.z + outlet.z) / 2));
    _paintDischarge(canvas, iso, outlet.x, headY, outlet.z);
    if (_flowing) {
      final intake = iso.p(c * 0.35, waterY, pumpAt.z);
      for (var i = 0; i < 2; i++) {
        final t = (phase * 3 + i / 2) % 1;
        canvas.drawOval(
          Rect.fromCenter(
            center: intake,
            width: 6 + t * 26,
            height: (6 + t * 26) * iso.ps,
          ),
          Paint()
            ..color = _fog.withValues(alpha: (1 - t) * 0.6)
            ..style = PaintingStyle.stroke,
        );
      }
    }

    final markersLeft = <_Marker>[
      _Marker(
        levelMeters == null
            ? 'Sin lectura de nivel'
            : 'Altura de agua ${levelMeters!.toStringAsFixed(2)} m',
        iso.p(-c, waterY, h),
        levelMeters == null ? _faint : _accent,
        strong: levelMeters != null,
      ),
    ];
    final markersRight = <_Marker>[
      _Marker('Toma', iso.p(c * 0.35, waterY, pumpAt.z), _steel),
    ];
    _paintMarkers(canvas, size, markersLeft, left: true);
    _paintMarkers(canvas, size, markersRight, left: false);
  }

  // ---------------------------------------------------------------- texto

  String _m(double meters) =>
      '${meters.toStringAsFixed(meters >= 100 ? 0 : 1)} m';

  void _chip(
    Canvas canvas,
    String text,
    Offset anchor,
    Color color, {
    bool small = false,
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: small ? 10.5 : 12,
          fontWeight: small ? FontWeight.w600 : FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 170);
    final w = painter.width + 14;
    final h = painter.height + 6;
    final left = (alignRight ? anchor.dx - w : anchor.dx)
        .clamp(12.0, math.max(12.0, _size.width - w - 12))
        .toDouble();
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, anchor.dy - h / 2, w, h),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = _surfaceCard.withValues(alpha: 0.9),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke,
    );
    painter.paint(canvas, Offset(left + 7, anchor.dy - h / 2 + 3));
  }

  @override
  bool shouldRepaint(covariant _CaptureStagePainter old) =>
      old.phase != phase ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.topInset != topInset ||
      old.levelMeters != levelMeters ||
      old.levelFill != levelFill ||
      old.levelMin != levelMin ||
      old.levelMax != levelMax ||
      old.textScaler != textScaler ||
      old.flow != flow ||
      old.isSurface != isSurface ||
      old.link != link ||
      old.profile != profile ||
      old.hovered != hovered ||
      old.alive != alive;
}
