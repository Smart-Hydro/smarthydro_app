import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/brand.dart';
import '../../shared/ui/hydro_ui.dart';
import 'capture_stage.dart' show formatCl;

const _deep = Color(0xFF0B3550);

const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _weekdaysLong = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const _months = [
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

/// Abre el historial diario del punto. Solo muestra las métricas de las
/// variables que el punto tiene; [onReplayDay] carga ese día en el visor.
Future<void> showPointHistorySheet(
  BuildContext context, {
  required SmartHydroApi api,
  required String token,
  required int pointId,
  String? pointTitle,
  bool hasFlow = true,
  bool hasLevel = true,
  bool hasTotal = true,
  ValueChanged<DateTime>? onReplayDay,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => PointHistorySheet(
      load: (days) => api.pointCalendar(token, pointId, days: days),
      pointTitle: pointTitle,
      hasFlow: hasFlow,
      hasLevel: hasLevel,
      hasTotal: hasTotal,
      onReplayDay: onReplayDay,
    ),
  );
}

/// Un día del calendario del punto (`/api/ik/point/<id>/calendar/`).
class HistoryDay {
  const HistoryDay({
    required this.date,
    required this.hasData,
    this.consumption,
    this.avgFlow,
    this.maxFlow,
    this.avgLevel,
    this.records = 0,
    this.first,
    this.last,
  });

  factory HistoryDay.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse('${json['date']}') ?? DateTime(1970);
    final hasData = json['has_data'] == true || _num(json['records_count']) > 0;
    return HistoryDay(
      date: DateTime(date.year, date.month, date.day),
      hasData: hasData,
      consumption: hasData ? _opt(json['consumption_m3']) : null,
      avgFlow: _opt(json['avg_flow_lps']),
      maxFlow: _opt(json['max_flow_lps']),
      avgLevel: _opt(json['avg_nivel_m']),
      records: _num(json['records_count']).round(),
      first: DateTime.tryParse('${json['first_record']}')?.toLocal(),
      last: DateTime.tryParse('${json['last_record']}')?.toLocal(),
    );
  }

  final DateTime date;
  final bool hasData;
  final double? consumption;
  final double? avgFlow;
  final double? maxFlow;
  final double? avgLevel;
  final int records;
  final DateTime? first;
  final DateTime? last;
}

/// Totales del período mostrados en la cabecera del historial.
class HistorySummary {
  const HistorySummary({
    required this.total,
    required this.dailyAverage,
    required this.peak,
    required this.daysWithData,
    required this.days,
    required this.records,
  });

  factory HistorySummary.of(List<HistoryDay> days) {
    final withData = days.where((d) => d.hasData).toList();
    var total = 0.0;
    HistoryDay? peak;
    for (final day in withData) {
      final c = day.consumption ?? 0;
      total += c;
      if (c > 0 && (peak == null || c > (peak.consumption ?? 0))) peak = day;
    }
    return HistorySummary(
      total: total,
      dailyAverage: withData.isEmpty ? 0 : total / withData.length,
      peak: peak,
      daysWithData: withData.length,
      days: days.length,
      records: days.fold(0, (sum, d) => sum + d.records),
    );
  }

  final double total;
  final double dailyAverage;
  final HistoryDay? peak;
  final int daysWithData;
  final int days;
  final int records;
}

/// Métricas que el historial puede mostrar según las variables del punto.
enum HistoryMetric {
  consumption('Consumo', 'm³', IkoluColors.cyan, 1),
  flow('Caudal', 'L/s', HydroTone.accent, 2),
  level('Nivel', 'm', Color(0xFFB7A6FF), 2),
  records('Registros', '', Color(0xFF8FE3CF), 0);

  const HistoryMetric(this.label, this.unit, this.color, this.decimals);

  final String label;
  final String unit;
  final Color color;
  final int decimals;

  double? of(HistoryDay day) => switch (this) {
    HistoryMetric.consumption => day.hasData ? day.consumption : null,
    HistoryMetric.flow => day.avgFlow,
    HistoryMetric.level => day.avgLevel,
    HistoryMetric.records => day.hasData ? day.records.toDouble() : null,
  };

  String format(double v) =>
      unit.isEmpty ? formatCl(v, decimals) : '${formatCl(v, decimals)} $unit';
}

/// Métricas visibles: solo las de variables que el punto tiene y con dato.
/// Si no hay ninguna, queda la cantidad de registros.
List<HistoryMetric> historyMetricsFor(
  List<HistoryDay> days, {
  required bool hasFlow,
  required bool hasLevel,
  required bool hasTotal,
}) {
  final metrics = [
    if (hasTotal && days.any((d) => (d.consumption ?? 0) > 0))
      HistoryMetric.consumption,
    if (hasFlow && days.any((d) => d.avgFlow != null)) HistoryMetric.flow,
    if (hasLevel && days.any((d) => d.avgLevel != null)) HistoryMetric.level,
  ];
  return metrics.isEmpty ? const [HistoryMetric.records] : metrics;
}

class PointHistorySheet extends StatefulWidget {
  const PointHistorySheet({
    required this.load,
    this.pointTitle,
    this.hasFlow = true,
    this.hasLevel = true,
    this.hasTotal = true,
    this.onReplayDay,
    this.onClose,
    this.bare = false,
    super.key,
  });

  final Future<List<Map<String, dynamic>>> Function(int days) load;
  final String? pointTitle;
  final bool hasFlow;
  final bool hasLevel;
  final bool hasTotal;
  final ValueChanged<DateTime>? onReplayDay;
  final VoidCallback? onClose;

  /// Sin marco ni título: va dentro de [PointToolSheet].
  final bool bare;

  @override
  State<PointHistorySheet> createState() => _PointHistorySheetState();
}

class _PointHistorySheetState extends State<PointHistorySheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  final ScrollController _scroll = ScrollController();

  int _days = 7;
  List<HistoryDay> _history = const [];
  bool _loading = true;
  String? _error;
  int? _selected;
  HistoryMetric _metric = HistoryMetric.consumption;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _reveal.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<HistoryMetric> get _metrics => historyMetricsFor(
    _history,
    hasFlow: widget.hasFlow,
    hasLevel: widget.hasLevel,
    hasTotal: widget.hasTotal,
  );

  Future<void> _fetch() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.load(_days);
      if (!mounted || request != _request) return;
      final days = rows.map(HistoryDay.fromJson).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      setState(() {
        _history = days;
        _loading = false;
        _selected = _lastWithData(days);
        final metrics = _metrics;
        if (!metrics.contains(_metric)) _metric = metrics.first;
      });
      if (MediaQuery.of(context).disableAnimations) {
        _reveal.value = 1;
      } else {
        _reveal.forward(from: 0);
      }
    } on SmartHydroApiException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = 'No pudimos cargar el historial.';
        _loading = false;
      });
    }
  }

  static int? _lastWithData(List<HistoryDay> days) {
    for (var i = days.length - 1; i >= 0; i--) {
      if (days[i].hasData) return i;
    }
    return days.isEmpty ? null : days.length - 1;
  }

  void _select(int index, {bool scrollUp = false}) {
    if (index == _selected) return;
    setState(() => _selected = index);
    if (scrollUp && _scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bare) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: HydroTabs<int>(
                values: const [7, 14, 30],
                selected: _days,
                label: (v) => '${v}d',
                onChanged: (value) {
                  if (value == _days) return;
                  setState(() => _days = value);
                  _fetch();
                },
              ),
            ),
          ),
          Flexible(
            child: HydroSwap(
              state: _loading
                  ? 'loading'
                  : (_error == null ? 'ready' : 'error'),
              child: _body(),
            ),
          ),
        ],
      );
    }
    final media = MediaQuery.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: media.size.height * 0.9,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF12292F), Color(0xFF0B1B20)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(
              top: BorderSide(color: HydroTone.accent.withValues(alpha: 0.18)),
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x99000000), blurRadius: 30),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(),
                Flexible(
                  child: HydroSwap(
                    state: _loading
                        ? 'loading'
                        : (_error == null ? 'ready' : 'error'),
                    child: _body(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 0),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: HydroTone.fog.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Historial',
                      style: TextStyle(
                        color: HydroTone.fog,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    if (widget.pointTitle != null)
                      Text(
                        widget.pointTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HydroTone.faint,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              HydroTabs<int>(
                values: const [7, 14, 30],
                selected: _days,
                label: (v) => '${v}d',
                onChanged: (value) {
                  if (value == _days) return;
                  setState(() => _days = value);
                  _fetch();
                },
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed:
                    widget.onClose ?? () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: HydroTone.faint,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const _LoadingSkeleton();
    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: 'No pudimos cargar el historial',
        message: _error!,
        action: ('Reintentar', _fetch),
      );
    }
    final summary = HistorySummary.of(_history);
    if (summary.daysWithData == 0) {
      return _Message(
        icon: Icons.event_busy_rounded,
        title: 'Sin registros en estos $_days días',
        message: _days < 30
            ? 'El punto no envió datos en este período. Prueba con 30 días.'
            : 'El punto no envió datos en el último mes.',
        action: _days < 30
            ? (
                'Ver 30 días',
                () {
                  setState(() => _days = 30);
                  _fetch();
                },
              )
            : null,
      );
    }
    final metrics = _metrics;
    final selected = _selected == null ? null : _history[_selected!];
    final max = _maxOf(_history, _metric);
    var section = 0;
    Widget reveal(Widget child) =>
        HydroReveal(animation: _reveal, index: section++, child: child);

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [
        if (metrics.length > 1) ...[
          reveal(
            _MetricTabs(
              metrics: metrics,
              selected: _metric,
              onChanged: (m) => setState(() => _metric = m),
            ),
          ),
          const SizedBox(height: 16),
        ],
        reveal(
          _Hero(
            key: ValueKey('hero-$_days-${_metric.name}'),
            metric: _metric,
            days: _history,
            summary: summary,
          ),
        ),
        const SizedBox(height: 18),
        reveal(
          _HistoryChart(
            key: ValueKey('chart-$_days-${_metric.name}'),
            days: _history,
            metric: _metric,
            selected: _selected,
            onSelect: _select,
          ),
        ),
        const SizedBox(height: 14),
        if (selected != null)
          reveal(
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _DayDetail(
                key: ValueKey(selected.date),
                day: selected,
                metrics: metrics,
                average: summary.dailyAverage,
                showDelta: metrics.contains(HistoryMetric.consumption),
                onReplay: widget.onReplayDay == null || !selected.hasData
                    ? null
                    : () {
                        (widget.onClose ??
                            () => Navigator.of(context).maybePop())();
                        widget.onReplayDay!(selected.date);
                      },
              ),
            ),
          ),
        const SizedBox(height: 22),
        reveal(
          Row(
            children: [
              const Text(
                'Día a día',
                style: TextStyle(
                  color: HydroTone.fog,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${summary.daysWithData} de ${summary.days} con datos',
                style: const TextStyle(
                  color: HydroTone.faint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        for (var i = _history.length - 1; i >= 0; i--)
          reveal(
            _DayRow(
              day: _history[i],
              metric: _metric,
              max: max,
              selected: i == _selected,
              onTap: () => _select(i, scrollUp: true),
            ),
          ),
      ],
    );
  }
}

double _maxOf(List<HistoryDay> days, HistoryMetric metric) {
  var max = 0.0;
  for (final d in days) {
    max = math.max(max, metric.of(d) ?? 0);
    if (metric == HistoryMetric.flow) max = math.max(max, d.maxFlow ?? 0);
  }
  return max;
}

// ------------------------------------------------------------- piezas

/// Selector de período: texto con una línea que se desliza bajo el elegido.
class _MetricTabs extends StatelessWidget {
  const _MetricTabs({
    required this.metrics,
    required this.selected,
    required this.onChanged,
  });

  final List<HistoryMetric> metrics;
  final HistoryMetric selected;
  final ValueChanged<HistoryMetric> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 18,
    children: [
      for (final m in metrics)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(m),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: m == selected ? m.color : Colors.transparent,
                    border: Border.all(
                      color: m == selected
                          ? m.color
                          : HydroTone.faint.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: m == selected ? HydroTone.fog : HydroTone.faint,
                    fontSize: 13,
                    fontWeight: m == selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                  child: Text(m.label),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

/// Cifra principal del período para la métrica elegida y dos datos de apoyo.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.metric,
    required this.days,
    required this.summary,
    super.key,
  });

  final HistoryMetric metric;
  final List<HistoryDay> days;
  final HistorySummary summary;

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final d in days)
        if (metric.of(d) != null) (day: d, v: metric.of(d)!),
    ];
    final mean = values.isEmpty
        ? 0.0
        : values.map((e) => e.v).reduce((a, b) => a + b) / values.length;
    final top = values.isEmpty
        ? null
        : values.reduce((a, b) => b.v > a.v ? b : a);

    final (
      String caption,
      double value,
      List<(String, String)> facts,
    ) = switch (metric) {
      HistoryMetric.consumption => (
        'Consumo del período',
        summary.total,
        [
          ('Promedio diario', metric.format(summary.dailyAverage)),
          if (summary.peak != null)
            (
              'Día pico · ${_shortDate(summary.peak!.date)}',
              metric.format(summary.peak!.consumption ?? 0),
            ),
        ],
      ),
      HistoryMetric.flow => (
        'Caudal promedio',
        mean,
        [
          () {
            final peak = days
                .where((d) => d.maxFlow != null)
                .fold<HistoryDay?>(
                  null,
                  (a, b) => a == null || b.maxFlow! > a.maxFlow! ? b : a,
                );
            return peak == null
                ? ('Día más alto', top == null ? '—' : metric.format(top.v))
                : (
                    'Máximo · ${_shortDate(peak.date)}',
                    metric.format(peak.maxFlow!),
                  );
          }(),
        ],
      ),
      HistoryMetric.level => (
        'Nivel promedio',
        mean,
        [
          if (values.isNotEmpty)
            (
              'Rango diario',
              '${formatCl(values.map((e) => e.v).reduce(math.min), 2)}'
                  ' – ${metric.format(values.map((e) => e.v).reduce(math.max))}',
            ),
        ],
      ),
      HistoryMetric.records => (
        'Registros del período',
        summary.records.toDouble(),
        [
          (
            'Promedio diario',
            formatCl(
              summary.daysWithData == 0
                  ? 0
                  : summary.records / summary.daysWithData,
              0,
            ),
          ),
        ],
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: const TextStyle(
            color: HydroTone.faint,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, shown, _) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: formatCl(shown, metric.decimals),
                    style: const TextStyle(
                      color: HydroTone.fog,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                  if (metric.unit.isNotEmpty)
                    TextSpan(
                      text: ' ${metric.unit}',
                      style: TextStyle(
                        color: metric.color,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 22,
          runSpacing: 8,
          children: [
            for (final (label, text) in facts) _Fact(label: label, value: text),
            _Fact(
              label: 'Cobertura',
              value: '${summary.daysWithData}/${summary.days} días',
              progress: summary.days == 0
                  ? 0
                  : summary.daysWithData / summary.days,
            ),
          ],
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.progress});

  final String label;
  final String value;
  final double? progress;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: HydroTone.faint,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          color: HydroTone.fog,
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      if (progress != null) ...[
        const SizedBox(height: 4),
        SizedBox(
          width: 64,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2.5,
              color: progress! >= 1
                  ? IkoluColors.connected
                  : IkoluColors.warning,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
      ],
    ],
  );
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({
    required this.days,
    required this.metric,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<HistoryDay> days;
  final HistoryMetric metric;
  final int? selected;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void pick(Offset local) {
          if (days.isEmpty) return;
          final i = (local.dx / width * days.length).floor().clamp(
            0,
            days.length - 1,
          );
          onSelect(i);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => pick(d.localPosition),
          onHorizontalDragStart: (d) => pick(d.localPosition),
          onHorizontalDragUpdate: (d) => pick(d.localPosition),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, grow, _) => TweenAnimationBuilder<double>(
              tween: Tween(end: (selected ?? -1).toDouble()),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, focus, _) => CustomPaint(
                size: Size(width, 170),
                painter: _ChartPainter(
                  days: days,
                  metric: metric,
                  selected: selected,
                  focus: focus,
                  grow: grow,
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.days,
    required this.metric,
    required this.selected,
    required this.focus,
    required this.grow,
    required this.textScaler,
  });

  final List<HistoryDay> days;
  final HistoryMetric metric;
  final int? selected;
  final double focus;
  final double grow;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    const top = 26.0;
    const bottom = 20.0;
    final plot = Rect.fromLTRB(0, top, size.width, size.height - bottom);
    final n = days.length;
    final slot = plot.width / n;
    final maxValue = math.max(_maxOf(days, metric), 0.0001);
    final values = [for (final d in days) metric.of(d)];
    final present = values.whereType<double>().toList();
    final average = present.isEmpty
        ? null
        : present.reduce((a, b) => a + b) / present.length;
    double yOf(double v) => plot.bottom - (v / maxValue) * plot.height;

    canvas.drawLine(
      Offset(0, plot.bottom),
      Offset(size.width, plot.bottom),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 1,
    );

    if (focus >= 0) {
      final x = slot * focus;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 1, plot.top - 4, slot - 2, plot.height + 4),
          const Radius.circular(8),
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              metric.color.withValues(alpha: 0.0),
              metric.color.withValues(alpha: 0.08),
            ],
          ).createShader(plot),
      );
    }

    final barW = math.max(3.0, math.min(slot * 0.5, 22.0));
    for (var i = 0; i < n; i++) {
      final cx = slot * (i + 0.5);
      final v = values[i];
      final isSel = i == selected;
      if (v == null) {
        canvas.drawCircle(
          Offset(cx, plot.bottom - 3),
          1.8,
          Paint()
            ..color = HydroTone.faint.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke,
        );
        continue;
      }
      final t = ((grow * 1.35) - (i / n) * 0.35).clamp(0.0, 1.0);
      final eased = Curves.easeOutBack.transform(t).clamp(0.0, 1.06);
      final h = math.max(2.0, (plot.bottom - yOf(v)) * eased);
      final rect = Rect.fromLTWH(cx - barW / 2, plot.bottom - h, barW, h);
      final radius = Radius.circular(math.min(5, barW / 2));
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: radius,
        topRight: radius,
      );
      if (isSel) {
        canvas.drawRRect(
          rrect.inflate(2),
          Paint()
            ..color = metric.color.withValues(alpha: 0.32)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      final dim = selected == null || isSel ? 1.0 : 0.5;
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              metric.color.withValues(alpha: 0.95 * dim),
              metric.color.withValues(alpha: 0.22 * dim),
            ],
          ).createShader(rect),
      );
      if (metric == HistoryMetric.flow && days[i].maxFlow != null) {
        final my = plot.bottom - (plot.bottom - yOf(days[i].maxFlow!)) * t;
        canvas.drawLine(
          Offset(cx - barW / 2, my),
          Offset(cx + barW / 2, my),
          Paint()
            ..color = HydroTone.fog.withValues(alpha: 0.55 * dim)
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    if (average != null && average > 0) {
      final y = yOf(average);
      final dash = Paint()
        ..color = HydroTone.fog.withValues(alpha: 0.28)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 3.5, size.width), y),
          dash,
        );
      }
      _label(
        canvas,
        'prom. ${formatCl(average, metric.decimals)}',
        Offset(0, y - 2),
        color: HydroTone.fog.withValues(alpha: 0.55),
        above: true,
      );
    }

    if (selected != null && values[selected!] != null) {
      final v = values[selected!]!;
      final cx = slot * (selected! + 0.5);
      final y = yOf(v) * grow + plot.bottom * (1 - grow);
      final painter = _painter(
        metric.format(v),
        const TextStyle(
          color: Color(0xFF06222B),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      );
      final w = painter.width + 14;
      final left = (cx - w / 2)
          .clamp(0.0, math.max(0.0, size.width - w))
          .toDouble();
      final bubble = Rect.fromLTWH(left, math.max(0.0, y - 26), w, 20);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bubble, const Radius.circular(10)),
        Paint()..color = metric.color,
      );
      painter.paint(
        canvas,
        Offset(bubble.left + 7, bubble.center.dy - painter.height / 2),
      );
    }

    final every = n <= 7 ? 1 : (n <= 14 ? 2 : 5);
    for (var i = 0; i < n; i++) {
      final isSel = i == selected;
      final fromEnd = n - 1 - i;
      if (!isSel && fromEnd % every != 0) continue;
      if (!isSel && selected != null && (i - selected!).abs() < every) {
        continue;
      }
      final d = days[i].date;
      _label(
        canvas,
        n <= 7 ? _weekdays[d.weekday - 1] : '${d.day}',
        Offset(slot * (i + 0.5), size.height - bottom + 5),
        color: isSel ? HydroTone.fog : HydroTone.faint.withValues(alpha: 0.7),
        center: true,
        bold: isSel,
      );
    }
  }

  TextPainter _painter(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    required Color color,
    bool center = false,
    bool above = false,
    bool bold = false,
  }) {
    final p = _painter(
      text,
      TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      ),
    );
    final dx = center ? at.dx - p.width / 2 : at.dx;
    final dy = above ? at.dy - p.height : at.dy;
    p.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.grow != grow ||
      old.focus != focus ||
      old.selected != selected ||
      old.metric != metric ||
      old.days != days;
}

/// Ficha del día elegido, integrada en la superficie (sin tarjeta propia).
class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.day,
    required this.metrics,
    required this.average,
    required this.showDelta,
    required this.onReplay,
    super.key,
  });

  final HistoryDay day;
  final List<HistoryMetric> metrics;
  final double average;
  final bool showDelta;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(day.date, DateTime.now());
    final consumption = day.consumption;
    final delta = !showDelta || consumption == null || average <= 0
        ? null
        : (consumption - average) / average;
    final stats = <(String, String, Color)>[
      for (final m in metrics)
        if (m != HistoryMetric.records && m.of(day) != null)
          (
            m == HistoryMetric.consumption ? 'Consumo' : '${m.label} prom.',
            m.format(m.of(day)!),
            m.color,
          ),
      if (metrics.contains(HistoryMetric.flow) && day.maxFlow != null)
        (
          'Caudal máx.',
          HistoryMetric.flow.format(day.maxFlow!),
          HydroTone.accent,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HydroTone.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _longDate(day.date),
                style: const TextStyle(
                  color: HydroTone.fog,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              if (today) const _Tag(label: 'Hoy', color: IkoluColors.cyan),
              if (!day.hasData)
                const _Tag(label: 'Sin datos', color: IkoluColors.warning),
              if (delta != null && delta.abs() >= 0.01)
                _Tag(
                  label:
                      '${delta > 0 ? '▲' : '▼'} '
                      '${(delta.abs() * 100).toStringAsFixed(0)}% vs prom.',
                  color: delta > 0
                      ? IkoluColors.warning
                      : IkoluColors.connected,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!day.hasData)
            const Text(
              'El punto no envió registros este día.',
              style: TextStyle(color: HydroTone.faint, fontSize: 12),
            )
          else ...[
            Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [
                for (final (label, value, color) in stats)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: HydroTone.faint,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (onReplay != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onReplay,
                  style: TextButton.styleFrom(
                    foregroundColor: IkoluColors.cyan,
                    backgroundColor: IkoluColors.cyan.withValues(alpha: 0.10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(
                    'Reproducir ${_shortDate(day.date)} en el visor',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// Fila de un día: fecha, un tubo con el agua del día y su valor.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.metric,
    required this.max,
    required this.selected,
    required this.onTap,
  });

  final HistoryDay day;
  final HistoryMetric metric;
  final double max;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = metric.of(day);
    final ratio = v == null || max <= 0 ? 0.0 : (v / max).clamp(0.0, 1.0);
    final today = DateUtils.isSameDay(day.date, DateTime.now());
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? metric.color.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${_weekdays[day.date.weekday - 1]} ',
                      style: TextStyle(
                        color: today ? IkoluColors.cyan : HydroTone.faint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: '${day.date.day}',
                      style: TextStyle(
                        color: day.hasData ? HydroTone.fog : HydroTone.faint,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: v == null
                  ? Text(
                      'sin registros',
                      style: TextStyle(
                        color: HydroTone.faint.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : _WaterTube(
                      ratio: ratio,
                      color: metric.color,
                      bright: selected,
                    ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 84,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  v == null ? '—' : metric.format(v),
                  maxLines: 1,
                  style: TextStyle(
                    color: v == null ? HydroTone.faint : HydroTone.fog,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tubo horizontal que se llena como agua: degradado profundo, un brillo
/// en la superficie y una ondulación suave en el frente.
class _WaterTube extends StatelessWidget {
  const _WaterTube({
    required this.ratio,
    required this.color,
    required this.bright,
  });

  final double ratio;
  final Color color;
  final bool bright;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: ratio),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (context, fill, _) => CustomPaint(
      size: const Size.fromHeight(10),
      painter: _TubePainter(fill: fill, color: color, bright: bright),
    ),
  );
}

class _TubePainter extends CustomPainter {
  _TubePainter({required this.fill, required this.color, required this.bright});

  final double fill;
  final Color color;
  final bool bright;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final tube = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(
      tube,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );
    if (fill <= 0) return;
    canvas.save();
    canvas.clipRRect(tube);
    final w = math.max(size.height, size.width * fill);
    final body = Path()..moveTo(0, 0);
    // Frente del agua con una ondulación leve.
    const steps = 8;
    for (var i = 0; i <= steps; i++) {
      final y = size.height * i / steps;
      final x = w + math.sin(i / steps * math.pi * 2) * 1.6;
      body.lineTo(x, y);
    }
    body
      ..lineTo(0, size.height)
      ..close();
    final alpha = bright ? 1.0 : 0.82;
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.95 * alpha),
            Color.lerp(color, _deep, 0.55)!.withValues(alpha: alpha),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawLine(
      Offset(size.height / 2, size.height * 0.28),
      Offset(math.max(size.height / 2, w - 3), size.height * 0.28),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35 * alpha)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TubePainter old) =>
      old.fill != fill || old.color != color || old.bright != bright;
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    physics: NeverScrollableScrollPhysics(),
    padding: EdgeInsets.fromLTRB(20, 6, 20, 28),
    child: HydroShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HydroBone(width: 120, height: 12),
          SizedBox(height: 8),
          HydroBone(width: 200, height: 34, radius: 10),
          SizedBox(height: 12),
          HydroBone(width: 260, height: 28, radius: 10),
          SizedBox(height: 20),
          HydroBone(height: 170, radius: 14),
        ],
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: HydroTone.accent, size: 30),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: HydroTone.fog,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: HydroTone.faint,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 14),
          TextButton(
            onPressed: action!.$2,
            style: TextButton.styleFrom(
              foregroundColor: HydroTone.accent,
              backgroundColor: HydroTone.accent.withValues(alpha: 0.10),
              shape: const StadiumBorder(),
            ),
            child: Text(action!.$1),
          ),
        ],
      ],
    ),
  );
}

// ------------------------------------------------------------ formato

String _shortDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// `Vie 9 oct` para el visor y el replay.
String historyShortDate(DateTime d) => _shortDate(d);

String _longDate(DateTime d) =>
    '${_weekdaysLong[d.weekday - 1]} ${d.day} de ${_months[d.month - 1]}';

double? _opt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

double _num(dynamic value) => _opt(value) ?? 0;
