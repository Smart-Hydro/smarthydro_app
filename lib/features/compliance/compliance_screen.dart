import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../shared/navigation/hydro_page_route.dart';
import '../../shared/widgets/chile_shield.dart';
import '../../shared/widgets/hydro_glass.dart';
import 'flow_bands.dart';

class ComplianceScreen extends StatefulWidget {
  const ComplianceScreen({required this.api, required this.token, super.key});

  final SmartHydroApi api;
  final String token;

  @override
  State<ComplianceScreen> createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> {
  List<Map<String, dynamic>> _points = const [];
  bool _loading = true;
  bool _activeOnly = false;
  String _typeFilter = 'ALL';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final points = await widget.api.compliancePoints(
        widget.token,
        activeOnly: _activeOnly,
      );
      if (!mounted) return;
      setState(() {
        _points = points;
        _loading = false;
        if (_typeFilter != 'ALL' && !_availableTypes.contains(_typeFilter)) {
          _typeFilter = 'ALL';
        }
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Set<String> get _availableTypes {
    final types = <String>{};
    for (final point in _points) {
      final raw = point['compliance_type'];
      if (raw is List) {
        for (final type in raw) {
          types.add('$type');
        }
      }
    }
    return types;
  }

  String get _title {
    final types = _availableTypes;
    if (types.contains('DGA') && types.contains('SMA')) return 'DGA / SMA';
    if (types.contains('SMA')) return 'Cumplimiento SMA';
    return 'Cumplimiento DGA';
  }

  List<Map<String, dynamic>> get _visiblePoints => _typeFilter == 'ALL'
      ? _points
      : _points
            .where((point) {
              final raw = point['compliance_type'];
              return raw is List &&
                  raw.map((type) => '$type').contains(_typeFilter);
            })
            .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final types = _availableTypes;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: HydroFrame(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Solo cumplimiento activo'),
              value: _activeOnly,
              onChanged: (value) {
                setState(() => _activeOnly = value);
                _load();
              },
            ),
            if (types.length > 1) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  _TypeChip(
                    label: 'Todos',
                    selected: _typeFilter == 'ALL',
                    onTap: () => setState(() => _typeFilter = 'ALL'),
                  ),
                  for (final type in ['DGA', 'SMA'])
                    if (types.contains(type))
                      _TypeChip(
                        label: type,
                        selected: _typeFilter == type,
                        onTap: () => setState(() => _typeFilter = type),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
            if (!_loading && _error == null && _points.isEmpty)
              const _EmptyCompliance(),
            for (final point in _visiblePoints) ...[
              _CompliancePointCard(
                point: point,
                onTap: () => Navigator.of(context).push<void>(
                  hydroPageRoute(
                    _ComplianceDetailScreen(
                      api: widget.api,
                      token: widget.token,
                      point: point,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    visualDensity: VisualDensity.compact,
    label: Text(label, style: const TextStyle(fontSize: 12)),
    selected: selected,
    onSelected: (_) => onTap(),
    selectedColor: const Color(0xFF66E0C2),
    labelStyle: TextStyle(
      color: selected ? const Color(0xFF081316) : const Color(0xFFB7C8C7),
      fontWeight: FontWeight.w700,
    ),
    backgroundColor: const Color(0xFF1A3035),
    side: BorderSide.none,
  );
}

class _CompliancePointCard extends StatelessWidget {
  const _CompliancePointCard({required this.point, required this.onTap});

  final Map<String, dynamic> point;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final warning = _warningLevel(point);
    final authFlow = _numOrNull(point['authorized_flow']);
    final currentFlow = _numOrNull(point['flow']) ?? 0;
    final flowRatio = authFlow != null && authFlow > 0
        ? (currentFlow / authFlow).clamp(0.0, 1.0).toDouble()
        : null;
    final pctTotal = _numOrNull(point['pct_consumed']);
    final types = point['compliance_type'];
    return Material(
      color: const Color(0xFF112328),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ChileShield(size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      point['point_name']?.toString() ?? 'Punto',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _WarningBadge(level: warning),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF91A8AA),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${point['client_name'] ?? 'Cliente'} · '
                '${point['project_id'] ?? 'Proyecto'}'
                '${point['code'] != null ? ' · ${point['code']}' : ''}',
                style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                children: [
                  if (types is List)
                    for (final type in types) _AgencyChip(label: '$type'),
                  if (point['standard'] != null)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${point['standard']}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      backgroundColor: const Color(0xFF1A3035),
                      side: BorderSide.none,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _LimitRow(
                label: 'Caudal actual / autorizado',
                value:
                    '${_fmt(currentFlow)} L/s · '
                    '${authFlow == null ? 'sin límite' : '${_fmt(authFlow)} L/s'}',
                ratio: flowRatio,
                color: _warningColor(warning),
              ),
              if (pctTotal != null) ...[
                const SizedBox(height: 10),
                _LimitRow(
                  label: 'Totalizado consumido / autorizado',
                  value:
                      '${_fmt(point['annual_consumption'])} m³ · '
                      '${pctTotal.toStringAsFixed(1)}%',
                  ratio: (pctTotal / 100).clamp(0.0, 1.0).toDouble(),
                  color: pctTotal >= 100
                      ? const Color(0xFFFF847A)
                      : pctTotal >= 85
                      ? const Color(0xFFFFC46B)
                      : const Color(0xFF66E0C2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningBadge extends StatelessWidget {
  const _WarningBadge({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      'critical' => const Color(0xFFFF847A),
      'warning' => const Color(0xFFFFC46B),
      'safe' => const Color(0xFF66E0C2),
      _ => const Color(0xFF91A8AA),
    };
    final label = switch (level) {
      'critical' => 'Excede',
      'warning' => 'Cerca del límite',
      'safe' => 'Dentro del límite',
      _ => 'Sin caudal autorizado',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
  });

  final String label;
  final String value;
  final double? ratio;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: ratio ?? 0,
          minHeight: 7,
          backgroundColor: const Color(0xFF26383A),
          valueColor: AlwaysStoppedAnimation<Color>(
            ratio == null ? const Color(0xFF3A4E50) : color,
          ),
        ),
      ),
    ],
  );
}

class _ComplianceDetailScreen extends StatefulWidget {
  const _ComplianceDetailScreen({
    required this.api,
    required this.token,
    required this.point,
  });

  final SmartHydroApi api;
  final String token;
  final Map<String, dynamic> point;

  @override
  State<_ComplianceDetailScreen> createState() =>
      _ComplianceDetailScreenState();
}

class _ComplianceDetailScreenState extends State<_ComplianceDetailScreen> {
  List<Map<String, dynamic>> _records = const [];
  Map<String, dynamic> _flowHistory = const {};
  Map<String, dynamic> _nearLimit = const {};
  int _days = 90;
  bool _loading = true;
  String? _error;
  String? _bandError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final id = _toInt(widget.point['point_id']);
    final now = DateTime.now();
    try {
      final records = await widget.api.pointRecords(
        widget.token,
        id,
        start: now.subtract(Duration(days: _days - 1)),
        end: now,
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }

    try {
      final bands = await Future.wait<Map<String, dynamic>>([
        widget.api.complianceFlowHistory(widget.token, id, days: _days),
        widget.api.complianceNearLimit(widget.token, id, days: _days),
      ]);
      if (!mounted) return;
      setState(() {
        _flowHistory = bands[0];
        _nearLimit = bands[1];
        _bandError = null;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() => _bandError = error.message);
    }
  }

  ({int total, int within, int near, int exceeded, double? compliancePct})
  _periodStats() {
    final authFlow = _numOrNull(widget.point['authorized_flow']);
    var total = 0;
    var within = 0;
    var near = 0;
    var exceeded = 0;
    if (authFlow != null && authFlow > 0) {
      for (final record in _records) {
        final flow = _numOrNull(record['flow']);
        if (flow == null) continue;
        total++;
        if (flow > authFlow) {
          exceeded++;
        } else if (flow >= authFlow * 0.9) {
          near++;
        } else {
          within++;
        }
      }
    }
    return (
      total: total,
      within: within,
      near: near,
      exceeded: exceeded,
      compliancePct: total == 0 ? null : within * 100 / total,
    );
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    final warning = _warningLevel(point);
    final authFlow = _numOrNull(point['authorized_flow']);
    final currentFlow = _numOrNull(point['flow']) ?? 0;
    final authTotal = _numOrNull(point['authorized_total']);
    final annual = _numOrNull(point['annual_consumption']) ?? 0;
    final pctTotal = _numOrNull(point['pct_consumed']);
    final stats = _periodStats();
    final sorted = [..._records]
      ..sort((a, b) => _dateOf(a).compareTo(_dateOf(b)));
    return Scaffold(
      appBar: AppBar(
        title: Text(point['point_name']?.toString() ?? 'Cumplimiento'),
      ),
      body: HydroFrame(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const ChileShield(size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    point['code']?.toString() ?? 'Autorización',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                _WarningBadge(level: warning),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
            _ComplianceSection(
              title: 'Estado actual',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LimitRow(
                    label: 'Caudal',
                    value:
                        '${_fmt(currentFlow)} L/s de '
                        '${authFlow == null ? 'sin límite' : '${_fmt(authFlow)} L/s autorizados'}',
                    ratio: authFlow != null && authFlow > 0
                        ? (currentFlow / authFlow).clamp(0.0, 1.0).toDouble()
                        : null,
                    color: _warningColor(warning),
                  ),
                  if (pctTotal != null) ...[
                    const SizedBox(height: 14),
                    _LimitRow(
                      label: 'Totalizado anual',
                      value:
                          '${_fmt(annual)} m³ de '
                          '${authTotal == null ? '—' : '${_fmt(authTotal)} m³'}',
                      ratio: (pctTotal / 100).clamp(0.0, 1.0).toDouble(),
                      color: pctTotal >= 100
                          ? const Color(0xFFFF847A)
                          : pctTotal >= 85
                          ? const Color(0xFFFFC46B)
                          : const Color(0xFF66E0C2),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AgencyChip(
                        label: 'Estándar: ${point['standard'] ?? '—'}',
                      ),
                      _AgencyChip(label: 'Origen: ${point['type_dga'] ?? '—'}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 días')),
                ButtonSegment(value: 30, label: Text('30 días')),
                ButtonSegment(value: 90, label: Text('90 días')),
              ],
              selected: {_days},
              onSelectionChanged: (selection) {
                setState(() => _days = selection.first);
                _load();
              },
            ),
            const SizedBox(height: 12),
            _ComplianceSection(
              title: 'Cumplimiento de los últimos $_days días',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (authFlow == null || authFlow <= 0)
                    const Text(
                      'Este punto no tiene caudal autorizado configurado, '
                      'por lo que no es posible evaluar el período.',
                      style: TextStyle(color: Color(0xFF9AB0B1)),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stats.compliancePct == null
                                ? 'Sin datos en el período'
                                : '${stats.compliancePct!.toStringAsFixed(1)}% '
                                      'dentro del límite',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: stats.compliancePct == null
                                  ? const Color(0xFF91A8AA)
                                  : stats.exceeded > 0
                                  ? const Color(0xFFFF847A)
                                  : const Color(0xFF66E0C2),
                            ),
                          ),
                        ),
                        Text(
                          '${stats.total} registros',
                          style: const TextStyle(
                            color: Color(0xFF9AB0B1),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatChip(
                          label: 'Dentro del límite',
                          value: '${stats.within}',
                          color: const Color(0xFF66E0C2),
                        ),
                        _StatChip(
                          label: 'Cerca del límite',
                          value: '${stats.near}',
                          color: const Color(0xFFFFC46B),
                        ),
                        _StatChip(
                          label: 'Excedidos',
                          value: '${stats.exceeded}',
                          color: const Color(0xFFFF847A),
                        ),
                        _StatChip(
                          label: 'Excedencias ($_days d)',
                          value: '${_flowHistory['count'] ?? 0}',
                          color: const Color(0xFFFF847A),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (sorted.isNotEmpty && authFlow != null && authFlow > 0) ...[
              const SizedBox(height: 12),
              _ComplianceSection(
                title: 'Caudal vs límite autorizado',
                child: SizedBox(
                  height: 200,
                  child: _SeriesChart(
                    spots: [
                      for (var i = 0; i < sorted.length; i++)
                        FlSpot(
                          i.toDouble(),
                          _numOrNull(sorted[i]['flow']) ?? 0,
                        ),
                    ],
                    color: const Color(0xFF69B9FF),
                    fillColor: const Color(0xFF69B9FF),
                    maxY: _chartMax(
                      sorted.map((r) => _numOrNull(r['flow'])).whereType<num>(),
                      authFlow,
                    ),
                    limit: authFlow,
                  ),
                ),
              ),
            ],
            if (sorted.any(
              (r) => _numOrNull(r['water_table'] ?? r['nivel']) != null,
            )) ...[
              const SizedBox(height: 12),
              _ComplianceSection(
                title: 'Nivel freático del período',
                child: SizedBox(
                  height: 170,
                  child: _SeriesChart(
                    spots: [
                      for (var i = 0; i < sorted.length; i++)
                        if (_numOrNull(
                              sorted[i]['water_table'] ?? sorted[i]['nivel'],
                            ) !=
                            null)
                          FlSpot(
                            i.toDouble(),
                            _numOrNull(
                                  sorted[i]['water_table'] ??
                                      sorted[i]['nivel'],
                                ) ??
                                0,
                          ),
                    ],
                    color: const Color(0xFF66E0C2),
                    fillColor: const Color(0xFF66E0C2),
                    maxY: _chartMax(
                      sorted
                          .map(
                            (r) => _numOrNull(r['water_table'] ?? r['nivel']),
                          )
                          .whereType<num>(),
                      null,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_bandError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'El detalle remoto no respondió. Se muestran las mediciones ya cargadas del período. $_bandError',
                  style: const TextStyle(
                    color: Color(0xFFFFC46B),
                    fontSize: 12,
                  ),
                ),
              ),
            _measurementList(
              'Sobre caudal autorizado',
              visibleBandReadings(
                periodRecords: _records,
                remoteRows: _mapList(_flowHistory['results']),
                authorized: authFlow,
                band: FlowBand.over,
              ),
              authorized: authFlow,
              remoteCount: _intOrNull(_flowHistory['count']),
            ),
            const SizedBox(height: 12),
            _measurementList(
              'Cercano al límite',
              visibleBandReadings(
                periodRecords: _records,
                remoteRows: _mapList(_nearLimit['results']),
                authorized: authFlow,
                band: FlowBand.near,
              ),
              authorized: authFlow,
              remoteCount: _intOrNull(_nearLimit['count']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _measurementList(
    String title,
    List<Map<String, dynamic>> rows, {
    required double? authorized,
    required int? remoteCount,
  }) {
    final shown = rows.length > 40 ? rows.sublist(0, 40) : rows;
    final total = remoteCount != null && remoteCount > rows.length
        ? remoteCount
        : rows.length;
    return _ComplianceSection(
      title: '$title ($total)',
      child: rows.isEmpty
          ? Text(
              authorized == null || authorized <= 0
                  ? 'Este punto no tiene caudal autorizado, así que no hay lecturas que comparar.'
                  : 'Ninguna medición de los últimos $_days días cae en este tramo.',
              style: const TextStyle(color: Color(0xFF9AB0B1)),
            )
          : Column(
              children: [
                for (final row in shown)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(
                      Icons.water_drop_outlined,
                      color: Color(0xFF66E0C2),
                    ),
                    title: Text(
                      _formatTimestamp(
                        row['date_time'] ?? row['date_time_medition'],
                      ),
                    ),
                    subtitle: Text(_shareOfLimit(row['flow'], authorized)),
                    trailing: Text(_display(row['flow'], 'L/s')),
                  ),
                if (rows.length > shown.length)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Se muestran las 40 más recientes de este tramo.',
                      style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SeriesChart extends StatelessWidget {
  const _SeriesChart({
    required this.spots,
    required this.color,
    required this.fillColor,
    required this.maxY,
    this.limit,
  });

  final List<FlSpot> spots;
  final Color color;
  final Color fillColor;
  final double maxY;
  final double? limit;

  @override
  Widget build(BuildContext context) => LineChart(
    LineChartData(
      minY: 0,
      maxY: maxY,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            getTitlesWidget: _leftTitle,
          ),
        ),
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          if (limit != null)
            HorizontalLine(
              y: limit!,
              color: const Color(0xFFFF847A),
              strokeWidth: 1.4,
              dashArray: [6, 5],
            ),
        ],
      ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: fillColor.withValues(alpha: 0.1),
          ),
        ),
      ],
    ),
  );

  static Widget _leftTitle(double value, TitleMeta meta) => Text(
    value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1),
    style: const TextStyle(color: Color(0xFF71898B), fontSize: 10),
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      '$value $label',
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _AgencyChip extends StatelessWidget {
  const _AgencyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    visualDensity: VisualDensity.compact,
    label: Text(label, style: const TextStyle(fontSize: 10)),
    backgroundColor: const Color(0xFF1A3035),
    side: BorderSide.none,
  );
}

class _ComplianceSection extends StatelessWidget {
  const _ComplianceSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF112328),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class _EmptyCompliance extends StatelessWidget {
  const _EmptyCompliance();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Text('No hay puntos con configuración DGA/SMA para mostrar.'),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF112328),
    child: ListTile(
      leading: const Icon(
        Icons.error_outline_rounded,
        color: Color(0xFFFF847A),
      ),
      title: Text(message),
      trailing: IconButton(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ),
  );
}

String _warningLevel(Map<String, dynamic> point) {
  final warning = point['compliance_warning'];
  if (warning is Map && warning['level'] is String) {
    return warning['level'] as String;
  }
  return 'unknown';
}

Color _warningColor(String level) => switch (level) {
  'critical' => const Color(0xFFFF847A),
  'warning' => const Color(0xFFFFC46B),
  'safe' => const Color(0xFF66E0C2),
  _ => const Color(0xFF3A4E50),
};

double _chartMax(Iterable<num> values, double? limit) {
  var max = values.isEmpty
      ? 1.0
      : values.reduce((a, b) => a > b ? a : b).toDouble();
  if (limit != null && limit > max) max = limit;
  if (max <= 0) max = 1;
  return max * 1.15;
}

DateTime _dateOf(Map<String, dynamic> record) =>
    DateTime.tryParse(record['date_time']?.toString() ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0);

int _toInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

int? _intOrNull(dynamic value) {
  if (value is int) return value;
  return int.tryParse('${value ?? ''}');
}

String _shareOfLimit(dynamic flow, double? authorized) {
  final value = _numOrNull(flow);
  if (value == null || authorized == null || authorized <= 0) {
    return 'Sin caudal autorizado para comparar';
  }
  final percent = value * 100 / authorized;
  return '${percent.toStringAsFixed(0)}% del caudal autorizado';
}

double? _numOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

String _fmt(dynamic value) {
  final number = _numOrNull(value);
  if (number == null) return '—';
  return number == number.roundToDouble()
      ? number.toStringAsFixed(0)
      : number.toStringAsFixed(2);
}

String _display(dynamic value, String unit) =>
    value == null ? 'Sin dato' : '$value $unit';

String _formatTimestamp(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'Fecha no disponible';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  return const {};
}

List<Map<String, dynamic>> _mapList(dynamic value) =>
    value is List ? value.map(_map).toList() : const [];
