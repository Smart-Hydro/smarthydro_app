import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/brand.dart';
import '../../../shared/ui/hydro_ui.dart';
import '../../../shared/widgets/hydro_glass.dart';
import '../../../shared/widgets/liquid_nav.dart';
import '../point_link.dart';

/// Conteos de red para el hub Apps (preview filtrable por punto).
class AppsHubSummary {
  const AppsHubSummary({
    required this.pointCount,
    required this.onlineCount,
    required this.attentionCount,
    required this.complianceWatchCount,
    required this.openTicketCount,
  });

  final int pointCount;
  final int onlineCount;
  final int attentionCount;
  final int complianceWatchCount;
  final int openTicketCount;

  factory AppsHubSummary.fromNetwork({
    required List<Map<String, dynamic>> points,
    required List<Map<String, dynamic>> openTickets,
    required List<Map<String, dynamic>> compliance,
  }) {
    var online = 0;
    var attention = 0;
    for (final point in points) {
      if (pointLinkOf(point) == PointLink.connected) {
        online += 1;
      } else {
        attention += 1;
      }
    }
    var watch = 0;
    for (final item in compliance) {
      final raw = item['compliance_warning'];
      final map = raw is Map
          ? raw.map((k, v) => MapEntry('$k', v))
          : const <String, dynamic>{};
      final level = map['level']?.toString();
      if (level == 'warning' || level == 'critical') watch += 1;
    }
    return AppsHubSummary(
      pointCount: points.length,
      onlineCount: online,
      attentionCount: attention,
      complianceWatchCount: watch,
      openTicketCount: openTickets.length,
    );
  }
}

enum _HydroGlyphKind {
  ubicaciones,
  analisis,
  cumplimiento,
  asistente,
  soporte,
  registros,
  informes,
}

/// Página Apps: resumen hidráulico con preview de red (filtrable por punto).
class AppsHub extends StatelessWidget {
  const AppsHub({
    required this.summary,
    required this.onOpenApp,
    super.key,
  });

  final AppsHubSummary summary;
  final ValueChanged<int> onOpenApp;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);

    return HydroFrame(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return CustomScrollView(
            key: wide
                ? const ValueKey('apps-hub-wide')
                : const ValueKey('apps-hub-narrow'),
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(22, 12, 22, 2),
                  child: Text(
                    'Herramientas para tu red hídrica',
                    style: TextStyle(
                      color: Color(0xFFE8F2F1),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.35,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(22, 0, 22, 8),
                  child: Text(
                    'Cada vista es filtrable por punto · un vistazo de tu red',
                    style: TextStyle(
                      color: Color(0xFF9AB0B1),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: _NetworkPulseStrip(summary: summary),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: _HydroTipCard(
                    key: const ValueKey('apps-hub-tip'),
                    text:
                        'Todo lo de adentro se filtra por punto: elige uno y '
                        'la herramienta muestra solo su telemetría, DGA o SLA.',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: wide ? 2 : 1,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: wide ? 148 : 138,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final app = liquidDesktopApps[index];
                    final kind = _glyphKindFor(index);
                    return _Entrance(
                      index: index,
                      reduce: reduce,
                      child: _AppSummaryCard(
                        app: app,
                        kind: kind,
                        metric: _metricFor(index, summary),
                        onTap: () => onOpenApp(index),
                      ),
                    );
                  }, childCount: liquidDesktopApps.length),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static _HydroGlyphKind _glyphKindFor(int index) =>
      _HydroGlyphKind.values[index.clamp(0, _HydroGlyphKind.values.length - 1)];

  static String _metricFor(int index, AppsHubSummary s) => switch (index) {
        0 => '${s.pointCount} puntos · red completa',
        1 => '${s.onlineCount} en línea · ${s.attentionCount} con aviso',
        2 => s.complianceWatchCount == 0
            ? 'Sin alertas DGA'
            : '${s.complianceWatchCount} en vigilancia',
        3 => 'N1 · contexto de tus puntos',
        4 => s.openTicketCount == 0
            ? 'Sin tickets abiertos'
            : '${s.openTicketCount} abiertos',
        5 => '${s.pointCount} puntos · export CSV',
        6 => 'Pronto · reportes de red',
        _ => '',
      };
}

class _NetworkPulseStrip extends StatelessWidget {
  const _NetworkPulseStrip({required this.summary});

  final AppsHubSummary summary;

  @override
  Widget build(BuildContext context) {
    return HydroGlassLight(
      radius: 16,
      strength: 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _PulseStat(
              label: 'Puntos',
              value: '${summary.pointCount}',
              tone: IkoluColors.cyan,
            ),
          ),
          _pulseDivider(),
          Expanded(
            child: _PulseStat(
              label: 'En línea',
              value: '${summary.onlineCount}',
              tone: IkoluColors.connected,
            ),
          ),
          _pulseDivider(),
          Expanded(
            child: _PulseStat(
              label: 'Aviso',
              value: '${summary.attentionCount}',
              tone: IkoluColors.warning,
            ),
          ),
          _pulseDivider(),
          Expanded(
            child: _PulseStat(
              label: 'SLA',
              value: '${summary.openTicketCount}',
              tone: IkoluColors.incident,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pulseDivider() => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Colors.white.withValues(alpha: 0.08),
      );
}

class _PulseStat extends StatelessWidget {
  const _PulseStat({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: tone,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9AB0B1),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HydroTipCard extends StatelessWidget {
  const _HydroTipCard({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return HydroGlassLight(
      radius: 18,
      strength: 0.9,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CustomPaint(
              painter: const _WaveMarkPainter(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cómo se usa',
                  style: TextStyle(
                    color: IkoluColors.cyanSoft.withValues(alpha: 0.95),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFD5E6E4),
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSummaryCard extends StatefulWidget {
  const _AppSummaryCard({
    required this.app,
    required this.kind,
    required this.metric,
    required this.onTap,
  });

  final LiquidAppShortcut app;
  final _HydroGlyphKind kind;
  final String metric;
  final VoidCallback onTap;

  @override
  State<_AppSummaryCard> createState() => _AppSummaryCardState();
}

class _AppSummaryCardState extends State<_AppSummaryCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final muted = widget.app.comingSoon;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: (!reduce && _hover && !muted) ? 1.012 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(22),
            splashColor: widget.app.color.withValues(alpha: 0.10),
            highlightColor: widget.app.color.withValues(alpha: 0.05),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                // Card light: velo claro + tinte suave del color de la app.
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: muted ? 0.06 : 0.10),
                    widget.app.color.withValues(alpha: muted ? 0.05 : 0.12),
                    const Color(0xFF0C1A1E).withValues(alpha: 0.35),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: muted ? 0.06 : (_hover ? 0.18 : 0.12),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Opacity(
                      opacity: muted ? 0.7 : 1,
                      child: _HydroGlyphBadge(
                        kind: widget.kind,
                        color: widget.app.color,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.app.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: muted
                                        ? const Color(0xFFB7C9C8)
                                        : const Color(0xFFF2FAF8),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              if (muted) ...[
                                const SizedBox(width: 8),
                                _SoonChip(color: widget.app.color),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.metric,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.app.color.withValues(alpha: 0.98),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.app.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB7C9C8),
                              fontSize: 11,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (widget.app.adornments.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                for (final tag in widget.app.adornments.take(3))
                                  _AdornChip(
                                    label: tag,
                                    color: widget.app.color,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      muted ? 'Pronto' : 'Ver',
                      style: TextStyle(
                        color: muted
                            ? const Color(0xFF6F8584)
                            : IkoluColors.cyanSoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    CustomPaint(
                      size: const Size(14, 14),
                      painter: _ChevronPainter(
                        color: muted
                            ? const Color(0xFF6F8584)
                            : IkoluColors.cyanSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdornChip extends StatelessWidget {
  const _AdornChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Color.lerp(color, Colors.white, 0.45),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _SoonChip extends StatelessWidget {
  const _SoonChip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.16),
      ),
      child: Text(
        'Pronto',
        style: TextStyle(
          color: color.withValues(alpha: 0.95),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.index,
    required this.reduce,
    required this.child,
  });

  final int index;
  final bool reduce;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduce) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + index * 40),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _HydroGlyphBadge extends StatefulWidget {
  const _HydroGlyphBadge({required this.kind, required this.color});

  final _HydroGlyphKind kind;
  final Color color;

  @override
  State<_HydroGlyphBadge> createState() => _HydroGlyphBadgeState();
}

class _HydroGlyphBadgeState extends State<_HydroGlyphBadge>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  /// Segundos acumulados (nunca vuelve a 0) → líquido continuo.
  double _seconds = 0;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce == _reduce && _ticker != null) return;
    _reduce = reduce;
    _ticker?.dispose();
    _ticker = null;
    if (reduce) {
      _seconds = 1.2;
      return;
    }
    _ticker = createTicker((elapsed) {
      final next = elapsed.inMicroseconds / 1e6;
      if ((next - _seconds).abs() < 0.008) return;
      setState(() => _seconds = next);
    })..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyName = 'hydro-glyph-${widget.kind.name}';
    return SizedBox(
      key: ValueKey(keyName),
      width: 64,
      height: 64,
      child: CustomPaint(
        painter: _HydroGlyphPainter(
          kind: widget.kind,
          color: widget.color,
          seconds: _seconds,
        ),
      ),
    );
  }
}

class _HydroGlyphPainter extends CustomPainter {
  _HydroGlyphPainter({
    required this.kind,
    required this.color,
    required this.seconds,
  });

  final _HydroGlyphKind kind;
  final Color color;
  /// Tiempo continuo en segundos (sin wrap 0→1).
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    // Velocidades suaves distintas; sin periodo que “cierre” de golpe.
    final turn = seconds * 0.55;
    final drift = seconds * 0.38;

    // Borde orgánico tipo gota/agua, flujo continuo.
    final blob = _waterBlobPath(c, r * 0.86, turn, drift);
    final halo = _waterBlobPath(c, r * 0.94, turn + 0.4, drift + 0.2);

    canvas.drawPath(
      halo,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    final fill = Paint()
      ..shader = ui.Gradient.radial(
        Offset(c.dx - r * 0.2, c.dy - r * 0.25),
        r * 1.35,
        [
          Color.lerp(color, Colors.white, 0.32)!,
          color,
          Color.lerp(color, IkoluColors.navy, 0.2)!,
        ],
        const [0, 0.55, 1],
      );
    canvas.drawPath(blob, fill);

    // Ribete agua: trazo claro ondulado sobre el borde.
    canvas.drawPath(
      blob,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, r * 0.07)
        ..color = Colors.white.withValues(alpha: 0.38),
    );

    // Nivel interno continuo.
    final levelY = c.dy + r * (0.14 - 0.07 * math.sin(turn));
    final water = Path()
      ..moveTo(c.dx - r * 0.7, levelY)
      ..cubicTo(
        c.dx - r * 0.25,
        levelY - r * 0.12 * math.cos(turn),
        c.dx + r * 0.15,
        levelY + r * 0.12 * math.sin(turn),
        c.dx + r * 0.7,
        levelY - r * 0.03,
      )
      ..lineTo(c.dx + r * 0.7, c.dy + r * 0.7)
      ..lineTo(c.dx - r * 0.7, c.dy + r * 0.7)
      ..close();
    canvas.save();
    canvas.clipPath(blob);
    canvas.drawPath(
      water,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    canvas.restore();

    const glyph = Color(0xFFF4FFFC);
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, r * 0.09)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = glyph.withValues(alpha: 0.94);

    final fillInk = Paint()..color = glyph.withValues(alpha: 0.96);

    switch (kind) {
      case _HydroGlyphKind.ubicaciones:
        _paintNetwork(canvas, c, r, ink, fillInk, turn);
      case _HydroGlyphKind.analisis:
        _paintWaveBars(canvas, c, r, ink, turn);
      case _HydroGlyphKind.cumplimiento:
        _paintGauge(canvas, c, r, ink, fillInk, turn);
      case _HydroGlyphKind.asistente:
        _paintPulseNode(canvas, c, r, ink, fillInk, turn);
      case _HydroGlyphKind.soporte:
        _paintLifeline(canvas, c, r, ink, turn);
      case _HydroGlyphKind.registros:
        _paintLayers(canvas, c, r, ink, turn);
      case _HydroGlyphKind.informes:
        _paintSheetWave(canvas, c, r, ink, turn);
    }
  }

  Path _waterBlobPath(
    Offset c,
    double radius,
    double turn,
    double drift,
  ) {
    const steps = 48;
    final path = Path();
    Offset? first;
    Offset? prev;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final ang = t * math.pi * 2;
      // Armónicos lentos: flujo continuo, sin pop.
      final wobble = 1 +
          0.055 * math.sin(ang * 2 + turn) +
          0.035 * math.cos(ang * 3 - drift) +
          0.02 * math.sin(ang + turn * 0.7);
      final p = Offset(
        c.dx + math.cos(ang) * radius * wobble,
        c.dy + math.sin(ang) * radius * wobble,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
        first = p;
        prev = p;
      } else {
        final mid = Offset((prev!.dx + p.dx) / 2, (prev.dy + p.dy) / 2);
        path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
        prev = p;
      }
    }
    if (first != null && prev != null) {
      path.quadraticBezierTo(prev.dx, prev.dy, first.dx, first.dy);
    }
    path.close();
    return path;
  }

  void _paintNetwork(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    Paint fill,
    double turn,
  ) {
    final bob = 0.03 * math.sin(turn);
    final hubs = [
      Offset(c.dx, c.dy - r * (0.28 + bob)),
      Offset(c.dx - r * 0.34, c.dy + r * (0.22 - bob * 0.5)),
      Offset(c.dx + r * 0.34, c.dy + r * (0.22 + bob * 0.5)),
    ];
    for (final h in hubs.skip(1)) {
      canvas.drawLine(hubs.first, h, ink);
    }
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ink.strokeWidth
      ..color = ink.color;
    for (final h in hubs) {
      canvas.drawCircle(h, r * 0.11, fill);
      canvas.drawCircle(h, r * 0.11, rim);
    }
  }

  void _paintWaveBars(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    double turn,
  ) {
    final xs = [-0.34, -0.12, 0.12, 0.34];
    final hs = [0.22, 0.42, 0.3, 0.48];
    for (var i = 0; i < xs.length; i++) {
      final h = r * (hs[i] + 0.07 * math.sin(turn + i * 0.9));
      final x = c.dx + r * xs[i];
      canvas.drawLine(
        Offset(x, c.dy + r * 0.32),
        Offset(x, c.dy + r * 0.32 - h),
        ink,
      );
    }
    final wave = Path()
      ..moveTo(c.dx - r * 0.42, c.dy - r * 0.18)
      ..cubicTo(
        c.dx - r * 0.1,
        c.dy - r * (0.32 + 0.06 * math.sin(turn)),
        c.dx + r * 0.1,
        c.dy - r * (0.02 - 0.06 * math.cos(turn)),
        c.dx + r * 0.42,
        c.dy - r * 0.2,
      );
    canvas.drawPath(wave, ink);
  }

  void _paintGauge(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    Paint fill,
    double turn,
  ) {
    final rect = Rect.fromCircle(center: c, radius: r * 0.42);
    canvas.drawArc(rect, math.pi * 0.85, math.pi * 1.3, false, ink);
    // Aguja oscila suave (sin salto): 0.35±0.18
    final needle = 0.35 + 0.18 * math.sin(turn);
    final ang = math.pi * (0.85 + 1.3 * needle);
    canvas.drawLine(
      c,
      Offset(c.dx + math.cos(ang) * r * 0.32, c.dy + math.sin(ang) * r * 0.32),
      ink,
    );
    canvas.drawCircle(c, r * 0.07, fill);
  }

  void _paintPulseNode(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    Paint fill,
    double turn,
  ) {
    // Respiración continua (radio sin reinicio).
    final breath = 0.16 + 0.03 * math.sin(turn);
    canvas.drawCircle(
      c,
      r * (breath + 0.18),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFF4FFFC).withValues(
          alpha: 0.28 + 0.12 * math.cos(turn),
        ),
    );
    canvas.drawCircle(c, r * breath, fill);
    final sat = Offset(
      c.dx + math.cos(turn) * r * 0.28,
      c.dy + math.sin(turn) * r * 0.18 - r * 0.05,
    );
    canvas.drawCircle(sat, r * 0.08, fill);
    canvas.drawLine(c, sat, ink);
  }

  void _paintLifeline(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    double turn,
  ) {
    final k = 0.06 * math.sin(turn);
    final path = Path()
      ..moveTo(c.dx - r * 0.42, c.dy + r * 0.06)
      ..lineTo(c.dx - r * 0.18, c.dy + r * 0.06)
      ..lineTo(c.dx - r * 0.06, c.dy - r * (0.28 + k))
      ..lineTo(c.dx + r * 0.08, c.dy + r * (0.3 - k))
      ..lineTo(c.dx + r * 0.2, c.dy - r * 0.08)
      ..lineTo(c.dx + r * 0.42, c.dy - r * 0.08);
    canvas.drawPath(path, ink);
  }

  void _paintLayers(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    double turn,
  ) {
    for (var i = 0; i < 3; i++) {
      final y = c.dy - r * 0.22 + i * r * 0.22 + r * 0.02 * math.sin(turn + i);
      final w = r * (0.5 - i * 0.04);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(c.dx, y),
            width: w * 2,
            height: r * 0.14,
          ),
          Radius.circular(r * 0.06),
        ),
        ink,
      );
    }
  }

  void _paintSheetWave(
    Canvas canvas,
    Offset c,
    double r,
    Paint ink,
    double turn,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: r * 0.7, height: r * 0.9),
        Radius.circular(r * 0.12),
      ),
      ink,
    );
    for (var i = 0; i < 3; i++) {
      final y = c.dy - r * 0.18 + i * r * 0.18;
      final path = Path()
        ..moveTo(c.dx - r * 0.22, y)
        ..cubicTo(
          c.dx - r * 0.05,
          y - r * 0.04 * math.sin(turn + i),
          c.dx + r * 0.05,
          y + r * 0.04 * math.cos(turn + i),
          c.dx + r * 0.22,
          y,
        );
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _HydroGlyphPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.kind != kind ||
      oldDelegate.color != color;
}

/// Marca tip: ondas, no gota Material.
class _WaveMarkPainter extends CustomPainter {
  const _WaveMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      c,
      r * 0.92,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r,
          [
            IkoluColors.cyan.withValues(alpha: 0.35),
            IkoluColors.cyan.withValues(alpha: 0.05),
          ],
        ),
    );
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = IkoluColors.cyanSoft;
    for (var i = 0; i < 3; i++) {
      final y = c.dy - r * 0.2 + i * r * 0.22;
      final path = Path()
        ..moveTo(c.dx - r * 0.45, y)
        ..cubicTo(
          c.dx - r * 0.15,
          y - r * 0.16,
          c.dx + r * 0.15,
          y + r * 0.16,
          c.dx + r * 0.45,
          y,
        );
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveMarkPainter oldDelegate) => false;
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final path = Path()
      ..moveTo(size.width * 0.3, size.height * 0.2)
      ..lineTo(size.width * 0.7, size.height * 0.5)
      ..lineTo(size.width * 0.3, size.height * 0.8);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) =>
      oldDelegate.color != color;
}
