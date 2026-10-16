import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../shared/widgets/hydro_glass.dart';

/// Corte de la consola: críticas o atención.
enum AvisosLens { critical, attention }

/// Cuántos registros entran en el análisis. No es el historial completo.
const avisoRecordLimit = 100;

/// Resumen de críticas y atención en la muestra. La pantalla no lo imprime.
String avisosHeadline({required int critical, required int attention}) {
  if (critical == 0 && attention == 0) {
    return 'Sin incidencias en estos registros';
  }
  final parts = <String>[
    if (critical > 0) critical == 1 ? '1 crítica' : '$critical críticas',
    if (attention > 0)
      attention == 1 ? '1 en atención' : '$attention en atención',
  ];
  return parts.join(' · ');
}

/// Los más nuevos primero, recortados al límite de la consola.
List<Map<String, dynamic>> avisoLatestRecords(
  List<Map<String, dynamic>> events, {
  int limit = avisoRecordLimit,
}) {
  final copy = [...events];
  copy.sort((a, b) {
    final left = _when(a);
    final right = _when(b);
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  });
  if (limit <= 0 || copy.length <= limit) return copy;
  return copy.sublist(0, limit);
}

/// Parte entera más cercana. Cero si no hay total.
int avisoShare(int part, int total) {
  if (total <= 0 || part <= 0) return 0;
  return ((part * 100) / total).round();
}

const _chartMonths = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// Día del gráfico con mes corto, p. ej. `15 oct`.
String avisoChartDayLabel(DateTime day) =>
    '${day.day} ${_chartMonths[day.month - 1]}';

/// Hora corta para la fila. [now] fija el reloj en pruebas.
String avisoWhen(DateTime? time, {DateTime? now}) {
  if (time == null) return 'Sin fecha';
  final clock = now ?? DateTime.now();
  final delta = clock.difference(time);
  if (delta.inSeconds < 60 && delta.inSeconds > -60) return 'Ahora';
  if (!delta.isNegative && delta.inMinutes < 60) {
    final minutes = delta.inMinutes;
    return minutes <= 1 ? 'hace 1 min' : 'hace $minutes min';
  }
  final today = DateTime(clock.year, clock.month, clock.day);
  final day = DateTime(time.year, time.month, time.day);
  if (day == today && !delta.isNegative && delta.inHours < 24) {
    final hours = delta.inHours;
    return hours <= 1 ? 'hace 1 h' : 'hace $hours h';
  }
  final clockTime = _hhmm(time);
  if (day == today) return clockTime;
  if (day == today.subtract(const Duration(days: 1))) return 'Ayer $clockTime';
  return '${time.day} ${_month(time.month)} $clockTime';
}

/// Agrupa el día: Hoy, Ayer, o «15 oct».
String avisoDayLabel(DateTime? time, {DateTime? now}) {
  if (time == null) return 'Sin fecha';
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  final day = DateTime(time.year, time.month, time.day);
  if (day == today) return 'Hoy';
  if (day == today.subtract(const Duration(days: 1))) return 'Ayer';
  return '${time.day} ${_month(time.month)}';
}

String avisoEventLabel(String? type) => switch (type) {
  'DISCONNECTION' => 'Desconexión',
  'RECONNECTION' => 'Reconexión',
  'MEASUREMENT_ERROR' => 'Error de medición',
  'COUNTER_RESET' => 'Reinicio de contador',
  'MASSIVE_JUMP_BLOCKED' => 'Salto bloqueado',
  'TOKEN_REFRESH' => 'Token',
  'API_ERROR' => 'Error de API',
  _ => 'Evento',
};

/// Primer punto citado por el evento.
int? avisoPointId(Map<String, dynamic> item) {
  int? read(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null || '$value'.isEmpty || '$value' == 'null') return null;
    return int.tryParse('$value');
  }

  int? fromMap(Map<dynamic, dynamic> map) {
    final direct = read(map['point_id']) ?? read(map['catchment_point_id']);
    if (direct != null && direct > 0) return direct;
    for (final key in ['point', 'catchment_point']) {
      final value = map[key];
      final asId = read(value);
      if (asId != null && asId > 0) return asId;
      if (value is Map) {
        final nested = read(value['id']) ?? read(value['point_id']);
        if (nested != null && nested > 0) return nested;
      }
    }
    final points = map['points'];
    if (points is List) {
      for (final point in points) {
        final asId = read(point);
        if (asId != null && asId > 0) return asId;
        if (point is Map) {
          final nested = read(point['id']) ?? read(point['point_id']);
          if (nested != null && nested > 0) return nested;
        }
      }
    }
    final ticket = map['ticket'];
    if (ticket is Map) return fromMap(ticket);
    return null;
  }

  return fromMap(item);
}

String avisoPointName(Map<String, dynamic> item) {
  String? text(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty || raw == 'null') return null;
    return raw;
  }

  final point = item['point'];
  if (point is Map) {
    for (final key in ['display_name', 'title', 'name']) {
      final found = text(point[key]);
      if (found != null) return found;
    }
  }
  for (final key in ['point_title', 'point_name']) {
    final found = text(item[key]);
    if (found != null) return found;
  }
  return '';
}

/// Clave estable para separar puntos, con o sin id.
String avisoPointKey(Map<String, dynamic> item) {
  final id = avisoPointId(item);
  if (id != null) return 'id:$id';
  final name = avisoPointName(item);
  return name.isEmpty ? 'none' : 'name:$name';
}

/// `critical`, `warning` o `info`.
String avisoSeverity(Map<String, dynamic> event) {
  final raw = '${event['severity'] ?? ''}'.toUpperCase();
  if (raw == 'CRITICAL' || raw == 'ALERT') return 'critical';
  if (raw == 'WARNING') return 'warning';
  return 'info';
}

/// Varias respuestas iguales del mismo punto, contadas como una.
class AvisoCluster {
  const AvisoCluster({
    required this.pointKey,
    required this.pointId,
    required this.pointName,
    required this.eventType,
    required this.severity,
    required this.title,
    required this.events,
  });

  final String pointKey;
  final int? pointId;
  final String pointName;
  final String eventType;
  final String severity;
  final String title;

  /// De la más nueva a la más antigua.
  final List<Map<String, dynamic>> events;

  int get weight => events.length;

  DateTime? get latest => _when(events.isEmpty ? null : events.first);

  String get kind => avisoEventLabel(eventType);

  String get identity => '$pointKey|$eventType|$severity';
}

/// Agrupa por punto, tipo y severidad. El peso es cuántas veces ocurrió.
List<AvisoCluster> avisoClusters(List<Map<String, dynamic>> events) {
  final order = <String>[];
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final event in events) {
    final key =
        '${avisoPointKey(event)}|${event['event_type'] ?? ''}|${avisoSeverity(event)}';
    groups
        .putIfAbsent(key, () {
          order.add(key);
          return [];
        })
        .add(event);
  }
  final clusters = <AvisoCluster>[];
  for (final key in order) {
    final items = [...groups[key]!];
    items.sort((a, b) {
      final left = _when(a);
      final right = _when(b);
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    final head = items.first;
    final name = avisoPointName(head);
    clusters.add(
      AvisoCluster(
        pointKey: avisoPointKey(head),
        pointId: avisoPointId(head),
        pointName: name.isEmpty ? 'Sin punto' : name,
        eventType: head['event_type']?.toString() ?? '',
        severity: avisoSeverity(head),
        title:
            _text(head['title']) ??
            avisoEventLabel(head['event_type']?.toString()),
        events: List.unmodifiable(items),
      ),
    );
  }
  clusters.sort((a, b) {
    final left = a.latest;
    final right = b.latest;
    if (left == null && right == null) return b.weight.compareTo(a.weight);
    if (left == null) return 1;
    if (right == null) return -1;
    final byTime = right.compareTo(left);
    if (byTime != 0) return byTime;
    return b.weight.compareTo(a.weight);
  });
  return clusters;
}

/// Consola de registros de los dispositivos. Sin soporte.
class AvisosInbox extends StatefulWidget {
  const AvisosInbox({
    required this.summary,
    required this.events,
    required this.loading,
    required this.onRefresh,
    this.eventsError,
    this.onOpenPoint,
    this.showHeading = true,
    this.lockedPointId,
    this.now,
    super.key,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> events;
  final bool loading;
  final String? eventsError;
  final Future<void> Function() onRefresh;
  final ValueChanged<int>? onOpenPoint;

  /// En el punto, la pantalla ya trae el título.
  final bool showHeading;

  /// Si viene, la consola no ofrece otros puntos.
  final int? lockedPointId;

  /// Reloj de prueba. En la app es el momento actual.
  final DateTime? now;

  @override
  State<AvisosInbox> createState() => _AvisosInboxState();
}

class _AvisosInboxState extends State<AvisosInbox> {
  var _lens = AvisosLens.critical;
  var _picked = false;
  String? _pointKey;
  String? _openKey;

  @override
  void didUpdateWidget(AvisosInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pointKey == null) return;
    final stillThere = avisoClusters(
      widget.events,
    ).any((cluster) => cluster.pointKey == _pointKey);
    if (!stillThere) {
      _pointKey = null;
      _openKey = null;
    }
  }

  static const _stageMaxWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    final clock = widget.now ?? DateTime.now();
    final days = _int(widget.summary['period_days'], 7);
    final sample = avisoLatestRecords(widget.events);
    final points = _points(sample, widget.lockedPointId);
    final pointKey = _activePoint(points, sample);
    final scoped = _scoped(sample, widget.lockedPointId, pointKey);
    final critical = scoped
        .where((event) => avisoSeverity(event) == 'critical')
        .length;
    final attention = scoped
        .where((event) => avisoSeverity(event) == 'warning')
        .length;
    final other = scoped.length - critical - attention;
    final shown = _shown(critical, attention);
    final clusters = avisoClusters(
      scoped,
    ).where((cluster) => _matches(cluster, shown)).toList();
    final visible = clusters.fold<int>(
      0,
      (sum, cluster) => sum + cluster.weight,
    );
    final span = days < 1 ? 7 : days;
    final chartDays = _filledDays(scoped, limit: span);
    final failed = widget.eventsError != null;
    final onTab = widget.showHeading;
    final wide = MediaQuery.sizeOf(context).width >= 980;

    final body = <Widget>[
      if (critical + attention + other > 0) ...[
        _SampleChart(
          critical: critical,
          attention: attention,
          other: other,
          days: chartDays,
          wide: wide,
        ),
        const SizedBox(height: 14),
      ],
      if (points.length > 1 && pointKey != null) ...[
        _PointPicker(
          points: points,
          selected: pointKey,
          onSelect: (key) => setState(() {
            _pointKey = key;
            _openKey = null;
          }),
        ),
        const SizedBox(height: 14),
      ],
      _SplitLens(
        critical: critical,
        attention: attention,
        lens: shown,
        onCritical: () => setState(() {
          _picked = true;
          _lens = AvisosLens.critical;
          _openKey = null;
        }),
        onAttention: () => setState(() {
          _picked = true;
          _lens = AvisosLens.attention;
          _openKey = null;
        }),
      ),
      const SizedBox(height: 14),
      if (failed)
        _Note(
          message: widget.eventsError!,
          onRetry: () => widget.onRefresh(),
        ),
      if (clusters.isEmpty && widget.loading)
        const _Bones()
      else if (clusters.isEmpty && !failed)
        _Calm(lens: shown)
      else
        for (final block in _byDay(clusters, clock)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              block.label,
              style: const TextStyle(
                color: Color(0xFF9AB0B1),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final cluster in block.clusters) ...[
            _ClusterCard(
              cluster: cluster,
              share: avisoShare(cluster.weight, visible),
              open: _openKey == cluster.identity,
              now: clock,
              onToggle: () => setState(() {
                _openKey = _openKey == cluster.identity
                    ? null
                    : cluster.identity;
              }),
              onOpenPoint: widget.onOpenPoint,
            ),
            const SizedBox(height: 8),
          ],
        ],
    ];

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minH = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              wide ? 24 : 20,
              onTab ? (wide ? 24 : 12) : 4,
              wide ? 24 : 20,
              onTab ? (wide ? 40 : 96) : 32,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minH - (onTab ? 48 : 16)),
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  key: const ValueKey('avisos-stage'),
                  constraints: const BoxConstraints(maxWidth: _stageMaxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: body,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Un punto a la vez. Si no hay elección, el de la lectura más nueva.
  String? _activePoint(
    List<_PointOption> points,
    List<Map<String, dynamic>> events,
  ) {
    if (widget.lockedPointId != null || points.isEmpty) return null;
    if (_pointKey != null && points.any((point) => point.key == _pointKey)) {
      return _pointKey;
    }
    return _newestPointKey(events) ?? points.first.key;
  }

  /// Sin elección, el corte que ese punto sí tiene.
  AvisosLens _shown(int critical, int attention) {
    if (_picked) return _lens;
    if (critical > 0) return AvisosLens.critical;
    if (attention > 0) return AvisosLens.attention;
    return AvisosLens.critical;
  }

  bool _matches(AvisoCluster cluster, AvisosLens lens) => switch (lens) {
    AvisosLens.critical => cluster.severity == 'critical',
    AvisosLens.attention => cluster.severity == 'warning',
  };
}

class _SampleChart extends StatelessWidget {
  const _SampleChart({
    required this.critical,
    required this.attention,
    required this.other,
    required this.days,
    this.wide = false,
  });

  final int critical;
  final int attention;
  final int other;
  final List<_DayCount> days;
  final bool wide;

  int get _total => critical + attention + other;

  Widget _severityBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Severidad',
          style: TextStyle(
            color: Color(0xFF9AB0B1),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _MixDonut(
              critical: critical,
              attention: attention,
              other: other,
              total: _total,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  _SeverityLegendRow(
                    color: IkoluColors.incident,
                    label: 'Críticas',
                    count: critical,
                  ),
                  const SizedBox(height: 8),
                  _SeverityLegendRow(
                    color: IkoluColors.warning,
                    label: 'Atención',
                    count: attention,
                  ),
                  if (other > 0) ...[
                    const SizedBox(height: 8),
                    _SeverityLegendRow(
                      color: IkoluColors.info,
                      label: 'Seguimiento',
                      count: other,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _activityBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Actividad',
              style: TextStyle(
                color: Color(0xFF9AB0B1),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Text(
              days.length == 1 ? '1 día' : '${days.length} días',
              style: const TextStyle(
                color: Color(0xFF7E9496),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DayBars(days: days),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stacked = !wide || days.isEmpty;
    return HydroGlass(
      radius: 20,
      padding: EdgeInsets.fromLTRB(wide ? 18 : 14, 16, wide ? 18 : 14, 16),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _severityBlock(),
                if (days.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0x1AFFFFFF)),
                  const SizedBox(height: 12),
                  _activityBlock(),
                ],
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: _severityBlock()),
                  const SizedBox(width: 12),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0x1AFFFFFF),
                  ),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: _activityBlock()),
                ],
              ),
            ),
    );
  }
}

class _SeverityLegendRow extends StatelessWidget {
  const _SeverityLegendRow({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final quiet = count == 0;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: quiet ? color.withValues(alpha: 0.35) : color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: quiet
                  ? const Color(0xFF7E9496)
                  : const Color(0xFFD5E6E4),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: quiet ? const Color(0xFF7E9496) : color,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _MixDonut extends StatelessWidget {
  const _MixDonut({
    required this.critical,
    required this.attention,
    required this.other,
    required this.total,
  });

  final int critical;
  final int attention;
  final int other;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      height: 108,
      child: CustomPaint(
        painter: _DonutPainter(
          critical: critical,
          attention: attention,
          other: other,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                  color: Color(0xFFF4FBFA),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'eventos',
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
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.critical,
    required this.attention,
    required this.other,
  });

  final int critical;
  final int attention;
  final int other;

  @override
  void paint(Canvas canvas, Size size) {
    final arc = Offset.zero & size;
    final ring = arc.deflate(8);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = const Color(0xFF1A3338);
    canvas.drawArc(ring, 0, math.pi * 2, false, track);
    final total = critical + attention + other;
    if (total <= 0) return;
    final slices = <(int, Color)>[
      (critical, IkoluColors.incident),
      (attention, IkoluColors.warning),
      (other, IkoluColors.info),
    ].where((slice) => slice.$1 > 0).toList();
    final gap = slices.length > 1 ? 0.08 : 0.0;
    var start = -math.pi / 2;
    for (final (value, color) in slices) {
      final sweep = (value / total) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.butt
        ..color = color;
      final drawn = math.max(0.0, sweep - gap);
      canvas.drawArc(ring, start, drawn, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.critical != critical ||
      oldDelegate.attention != attention ||
      oldDelegate.other != other;
}

class _DayBars extends StatelessWidget {
  const _DayBars({required this.days});

  final List<_DayCount> days;

  static const _chartH = 96.0;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final peak = days.fold<int>(1, (maxCount, day) {
      return day.total > maxCount ? day.total : maxCount;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('aviso-day-bar'),
          height: _chartH,
          child: CustomPaint(
            painter: _DayBarsPainter(days: days, peak: peak),
            child: const SizedBox.expand(
              child: ColoredBox(
                key: ValueKey('aviso-day-bar-fill'),
                color: Color(0x00000000),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: Text(
                  avisoChartDayLabel(day.day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB7C9C8),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayBarsPainter extends CustomPainter {
  const _DayBarsPainter({required this.days, required this.peak});

  final List<_DayCount> days;
  final int peak;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty || peak <= 0 || size.width <= 0 || size.height <= 0) {
      return;
    }
    final slotW = size.width / days.length;
    final barW = (slotW * 0.55).clamp(10.0, 28.0);
    final topPad = 16.0;
    final chartH = size.height - topPad;

    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      if (day.total <= 0) continue;
      final ratio = day.total / peak;
      final factor = ratio < 0.32 ? 0.32 : ratio;
      final barH = chartH * factor;
      final cx = slotW * i + slotW / 2;
      final left = cx - barW / 2;
      final top = size.height - barH;

      // Track
      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, topPad, barW, chartH),
        const Radius.circular(6),
      );
      canvas.drawRRect(track, Paint()..color = const Color(0xFF1A3338));

      var y = size.height;
      void slice(int count, Color color) {
        if (count <= 0) return;
        final h = barH * (count / day.total);
        y -= h;
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(left, y, barW, h),
          topLeft: y <= top + 0.5 ? const Radius.circular(6) : Radius.zero,
          topRight: y <= top + 0.5 ? const Radius.circular(6) : Radius.zero,
        );
        canvas.drawRRect(rect, Paint()..color = color);
      }

      slice(day.critical, IkoluColors.incident);
      slice(day.attention, IkoluColors.warning);
      slice(day.other, IkoluColors.info);

      final label = TextPainter(
        text: TextSpan(
          text: '${day.total}',
          style: TextStyle(
            color: _tone(day),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slotW);
      label.paint(
        canvas,
        Offset(cx - label.width / 2, top - label.height - 2),
      );
    }
  }

  Color _tone(_DayCount day) {
    if (day.critical >= day.attention && day.critical >= day.other) {
      return IkoluColors.incident;
    }
    if (day.attention >= day.other) return IkoluColors.warning;
    return IkoluColors.info;
  }

  @override
  bool shouldRepaint(covariant _DayBarsPainter oldDelegate) =>
      oldDelegate.peak != peak || oldDelegate.days != days;
}

class _PointOption {
  const _PointOption(this.key, this.name, this.count, this.latest);

  final String key;
  final String name;
  final int count;
  final DateTime? latest;
}

class _PointPicker extends StatelessWidget {
  const _PointPicker({
    required this.points,
    required this.selected,
    required this.onSelect,
  });

  final List<_PointOption> points;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final current = points.firstWhere(
      (point) => point.key == selected,
      orElse: () => points.first,
    );
    return HydroGlass(
      key: const ValueKey('aviso-point-picker'),
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: () => _open(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Punto de captación',
                  style: TextStyle(
                    color: Color(0xFF9AB0B1),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  current.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE8F2F1),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${current.count}',
            style: const TextStyle(
              color: IkoluColors.cyanSoft,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Icon(Icons.unfold_more_rounded, color: Color(0xFF91A8AA)),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF102328),
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => _PointSheet(points: points, selected: selected),
    );
    if (picked != null && picked != selected) onSelect(picked);
  }
}

class _PointSheet extends StatefulWidget {
  const _PointSheet({required this.points, required this.selected});

  final List<_PointOption> points;
  final String selected;

  @override
  State<_PointSheet> createState() => _PointSheetState();
}

class _PointSheetState extends State<_PointSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    final visible = [
      for (final point in widget.points)
        if (needle.isEmpty || point.name.toLowerCase().contains(needle)) point,
    ];
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Punto de captación',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Buscar punto',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Text(
                        'Ningún punto con ese nombre',
                        style: TextStyle(color: Color(0xFF9AB0B1)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final point = visible[index];
                        final chosen = point.key == widget.selected;
                        return ListTile(
                          key: ValueKey('aviso-point-${point.key}'),
                          selected: chosen,
                          title: Text(
                            point.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            '${point.count}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          onTap: () => Navigator.pop(context, point.key),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayBlock {
  const _DayBlock(this.label, this.clusters);

  final String label;
  final List<AvisoCluster> clusters;
}

class _DayCount {
  const _DayCount(this.day, this.critical, this.attention, this.other);

  final DateTime day;
  final int critical;
  final int attention;
  final int other;

  int get total => critical + attention + other;
}

List<_DayBlock> _byDay(List<AvisoCluster> clusters, DateTime now) {
  final order = <String>[];
  final groups = <String, List<AvisoCluster>>{};
  for (final cluster in clusters) {
    final label = avisoDayLabel(cluster.latest, now: now);
    groups
        .putIfAbsent(label, () {
          order.add(label);
          return [];
        })
        .add(cluster);
  }
  return [for (final label in order) _DayBlock(label, groups[label]!)];
}

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({
    required this.cluster,
    required this.share,
    required this.open,
    required this.now,
    required this.onToggle,
    required this.onOpenPoint,
  });

  final AvisoCluster cluster;
  final int share;
  final bool open;
  final DateTime now;
  final VoidCallback onToggle;
  final ValueChanged<int>? onOpenPoint;

  @override
  Widget build(BuildContext context) {
    final tone = _tone(cluster.severity);
    final message = _text(cluster.events.first['message']) ?? '';
    final detail = message.isEmpty || message == cluster.title ? '' : message;
    final pointId = cluster.pointId;
    return HydroGlass(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Mark(
                  icon: _icon(cluster),
                  color: tone,
                  live: cluster.weight > 1,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cluster.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE8F2F1),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${cluster.pointName} · ${cluster.kind}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tone,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'última ${avisoWhen(cluster.latest, now: now)}',
                        style: const TextStyle(
                          color: Color(0xFF8FA3A4),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (cluster.weight > 1)
                      Text(
                        '×${cluster.weight}',
                        style: TextStyle(
                          color: tone,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    Text(
                      '$share%',
                      style: const TextStyle(
                        color: Color(0xFFC5D5D4),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Icon(
                      open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: const Color(0xFF91A8AA),
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 4,
              child: _WeightBar(share: share, color: tone),
            ),
          ),
          if (detail.isNotEmpty && !open) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB7C8C7),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (open) ...[
            const SizedBox(height: 10),
            for (final event in cluster.events.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HistoryLine(event: event, now: now, color: tone),
              ),
            if (cluster.events.length > 8)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'y ${cluster.events.length - 8} anteriores',
                  style: const TextStyle(
                    color: Color(0xFF8FA3A4),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (pointId != null && onOpenPoint != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => onOpenPoint!(pointId),
                  style: TextButton.styleFrom(
                    foregroundColor: IkoluColors.cyan,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Ver punto'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _WeightBar extends StatelessWidget {
  const _WeightBar({required this.share, required this.color});

  final int share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final filled = share.clamp(4, 100).toInt();
    final rest = 100 - filled;
    return Row(
      children: [
        Expanded(
          flex: filled,
          child: ColoredBox(color: color.withValues(alpha: 0.9)),
        ),
        if (rest > 0)
          Expanded(
            flex: rest,
            child: const ColoredBox(color: Color(0x14FFFFFF)),
          ),
      ],
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({
    required this.event,
    required this.now,
    required this.color,
  });

  final Map<String, dynamic> event;
  final DateTime now;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final message = _text(event['message']) ?? '';
    final title = _text(event['title']) ?? '';
    final detail = message.isEmpty || message == title ? title : message;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                avisoWhen(_when(event), now: now),
                style: const TextStyle(
                  color: Color(0xFFC5D5D4),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (detail.isNotEmpty)
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFF9AB0B1),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

(IconData, Color) _infoFace(String? type) => switch (type) {
  'RECONNECTION' => (Icons.sensors_rounded, IkoluColors.connected),
  'DISCONNECTION' => (Icons.sensors_off_rounded, IkoluColors.info),
  'TOKEN_REFRESH' => (Icons.key_rounded, IkoluColors.info),
  'API_ERROR' => (Icons.cloud_off_rounded, IkoluColors.info),
  _ => (Icons.info_outline_rounded, IkoluColors.info),
};

IconData _icon(AvisoCluster cluster) => switch (cluster.severity) {
  'critical' => Icons.error_outline_rounded,
  'warning' => Icons.warning_amber_rounded,
  _ => _infoFace(cluster.eventType).$1,
};

Color _tone(String severity) => switch (severity) {
  'critical' => IkoluColors.incident,
  'warning' => IkoluColors.warning,
  _ => IkoluColors.info,
};

class _Mark extends StatelessWidget {
  const _Mark({required this.icon, required this.color, required this.live});

  final IconData icon;
  final Color color;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: live ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _SplitLens extends StatelessWidget {
  const _SplitLens({
    required this.critical,
    required this.attention,
    required this.lens,
    required this.onCritical,
    required this.onAttention,
  });

  final int critical;
  final int attention;
  final AvisosLens lens;
  final VoidCallback onCritical;
  final VoidCallback onAttention;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF102328),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF2A4A50)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _LensHalf(
                  key: const ValueKey('aviso-lens-critical'),
                  icon: Icons.error_outline_rounded,
                  label: 'Críticas',
                  count: critical,
                  color: IkoluColors.incident,
                  selected: lens == AvisosLens.critical,
                  onTap: onCritical,
                ),
              ),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0xFF2A4A50),
              ),
              Expanded(
                child: _LensHalf(
                  key: const ValueKey('aviso-lens-attention'),
                  icon: Icons.warning_amber_rounded,
                  label: 'Atención',
                  count: attention,
                  color: IkoluColors.warning,
                  selected: lens == AvisosLens.attention,
                  onTap: onAttention,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LensHalf extends StatelessWidget {
  const _LensHalf({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = selected ? color : const Color(0xFF9AB0B1);
    return Material(
      color: selected ? color.withValues(alpha: 0.2) : const Color(0x00000000),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: tone, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tone,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  color: tone,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Calm extends StatelessWidget {
  const _Calm({required this.lens});

  final AvisosLens lens;

  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (lens) {
      AvisosLens.critical => (
        'No hay críticas',
        'Cuando un dispositivo corte o falle la medición, queda en este corte.',
      ),
      AvisosLens.attention => (
        'No hay advertencias',
        'Las respuestas en atención de los dispositivos aparecen aquí.',
      ),
    };
    return HydroGlass(
      radius: 16,
      child: Column(
        children: [
          const Icon(Icons.terminal_rounded, color: IkoluColors.cyan),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9AB0B1), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HydroGlass(
        radius: 16,
        onTap: onRetry,
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: IkoluColors.incident,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            const Icon(Icons.refresh_rounded, color: Color(0xFF91A8AA)),
          ],
        ),
      ),
    );
  }
}

class _Bones extends StatelessWidget {
  const _Bones();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < 3; index++) ...[
          HydroGlass(
            radius: 16,
            child: const SizedBox(height: 48, width: double.infinity),
          ),
          if (index != 2) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

List<Map<String, dynamic>> _scoped(
  List<Map<String, dynamic>> events,
  int? lockedPointId,
  String? pointKey,
) {
  return [
    for (final event in events)
      if (lockedPointId == null || avisoPointId(event) == lockedPointId)
        if (pointKey == null || avisoPointKey(event) == pointKey) event,
  ];
}

List<_PointOption> _points(
  List<Map<String, dynamic>> events,
  int? lockedPointId,
) {
  if (lockedPointId != null) return const [];
  final order = <String>[];
  final counts = <String, int>{};
  final names = <String, String>{};
  final latest = <String, DateTime>{};
  for (final event in events) {
    final key = avisoPointKey(event);
    final name = avisoPointName(event);
    counts[key] = (counts[key] ?? 0) + 1;
    names.putIfAbsent(key, () => name.isEmpty ? 'Sin punto' : name);
    final when = _when(event);
    final known = latest[key];
    if (when != null && (known == null || when.isAfter(known))) {
      latest[key] = when;
    }
    if (!order.contains(key)) order.add(key);
  }
  final options = [
    for (final key in order)
      _PointOption(key, names[key]!, counts[key]!, latest[key]),
  ];
  options.sort((a, b) {
    final left = a.latest;
    final right = b.latest;
    if (left == null && right == null) return b.count.compareTo(a.count);
    if (left == null) return 1;
    if (right == null) return -1;
    final byTime = right.compareTo(left);
    if (byTime != 0) return byTime;
    return b.count.compareTo(a.count);
  });
  return options;
}

String? _newestPointKey(List<Map<String, dynamic>> events) {
  DateTime? bestTime;
  String? bestKey;
  for (final event in events) {
    final when = _when(event);
    if (when == null) continue;
    if (bestTime == null || when.isAfter(bestTime)) {
      bestTime = when;
      bestKey = avisoPointKey(event);
    }
  }
  return bestKey;
}

List<_DayCount> _filledDays(
  List<Map<String, dynamic>> events, {
  required int limit,
}) {
  if (events.isEmpty || limit <= 0) return const [];
  final buckets = <DateTime, List<int>>{};
  for (final event in events) {
    final when = _when(event);
    if (when == null) continue;
    final day = DateTime(when.year, when.month, when.day);
    final slot = buckets.putIfAbsent(day, () => [0, 0, 0]);
    final severity = avisoSeverity(event);
    if (severity == 'critical') {
      slot[0] += 1;
    } else if (severity == 'warning') {
      slot[1] += 1;
    } else {
      slot[2] += 1;
    }
  }
  final days = buckets.keys.toList()..sort();
  final kept = days.length > limit ? days.sublist(days.length - limit) : days;
  return [
    for (final day in kept)
      if (buckets[day]!.fold<int>(0, (sum, value) => sum + value) > 0)
        _DayCount(day, buckets[day]![0], buckets[day]![1], buckets[day]![2]),
  ];
}

DateTime? _when(Map<String, dynamic>? event) {
  if (event == null) return null;
  return DateTime.tryParse(
    '${event['created'] ?? event['created_at'] ?? ''}',
  )?.toLocal();
}

int _int(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

String? _text(dynamic value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty || raw == 'null') return null;
  return raw;
}

String _hhmm(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _month(int month) => switch (month) {
  1 => 'ene',
  2 => 'feb',
  3 => 'mar',
  4 => 'abr',
  5 => 'may',
  6 => 'jun',
  7 => 'jul',
  8 => 'ago',
  9 => 'sep',
  10 => 'oct',
  11 => 'nov',
  _ => 'dic',
};
