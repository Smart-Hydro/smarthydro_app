import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../shared/widgets/hydro_glass.dart';

import '../../core/api/smarthydro_api.dart';

class SmartAnalysisScreen extends StatefulWidget {
  const SmartAnalysisScreen({
    required this.api,
    required this.token,
    required this.points,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final List<Map<String, dynamic>> points;

  @override
  State<SmartAnalysisScreen> createState() => _SmartAnalysisScreenState();
}

class _SmartAnalysisScreenState extends State<SmartAnalysisScreen> {
  int? _pointId;
  int _days = 7;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _calendar = const [];

  @override
  void initState() {
    super.initState();
    if (widget.points.isNotEmpty) _pointId = _toInt(widget.points.first['id']);
    _load();
  }

  Future<void> _load() async {
    final pointId = _pointId;
    if (pointId == null) {
      setState(() {
        _calendar = const [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.pointCalendar(
        widget.token,
        pointId,
        days: _days,
      );
      if (!mounted) return;
      setState(() {
        _calendar = rows;
        _loading = false;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? selectedPoint;
    for (final point in widget.points) {
      if (_toInt(point['id']) == _pointId) {
        selectedPoint = point;
        break;
      }
    }
    final chartRows = _calendar
        .where((day) => day['has_data'] == true)
        .toList(growable: false);
    final maxConsumption = chartRows.fold<double>(
      0,
      (maximum, day) => _number(day['consumption_m3']) > maximum
          ? _number(day['consumption_m3'])
          : maximum,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Análisis')),
      body: HydroFrame(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            DropdownButtonFormField<int>(
              initialValue: _pointId,
              decoration: const InputDecoration(
                labelText: 'Punto de captación',
              ),
              items: [
                for (final point in widget.points)
                  DropdownMenuItem<int>(
                    value: _toInt(point['id']),
                    child: Text(point['title']?.toString() ?? 'Punto'),
                  ),
              ],
              onChanged: (value) {
                setState(() => _pointId = value);
                _load();
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 días')),
                ButtonSegment(value: 30, label: Text('30 días')),
              ],
              selected: {_days},
              onSelectionChanged: (selection) {
                setState(() => _days = selection.first);
                _load();
              },
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: HydroLoading()),
              )
            else if (_error != null)
              _AnalysisError(message: _error!, onRetry: _load)
            else if (_calendar.isEmpty)
              const _AnalysisEmpty()
            else ...[
              _AnalysisSummary(
                pointName: selectedPoint?['title']?.toString() ?? 'Punto',
                daysWithData: chartRows.length,
                totalVolume: chartRows.fold<double>(
                  0,
                  (sum, day) => sum + _number(day['consumption_m3']),
                ),
                latestDate: _calendar.last['date']?.toString() ?? '',
              ),
              const SizedBox(height: 14),
              _AnalysisCard(
                title: 'Consumo diario',
                subtitle:
                    'Los días sin registro se muestran aparte; no se interpolan.',
                child: SizedBox(
                  height: 235,
                  child: chartRows.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay registros de consumo en este período.',
                          ),
                        )
                      : BarChart(
                          BarChartData(
                            maxY: maxConsumption <= 0
                                ? 1
                                : maxConsumption * 1.2,
                            minY: 0,
                            gridData: const FlGridData(
                              show: true,
                              drawVerticalLine: false,
                            ),
                            borderData: FlBorderData(show: false),
                            titlesData: const FlTitlesData(
                              topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            barGroups: [
                              for (
                                var index = 0;
                                index < _calendar.length;
                                index++
                              )
                                BarChartGroupData(
                                  x: index,
                                  barRods: [
                                    BarChartRodData(
                                      toY: _calendar[index]['has_data'] == true
                                          ? _number(
                                              _calendar[index]['consumption_m3'],
                                            )
                                          : 0,
                                      width: _calendar.length > 20 ? 5 : 11,
                                      borderRadius: BorderRadius.circular(4),
                                      color:
                                          _calendar[index]['has_data'] == true
                                          ? IkoluColors.cyan
                                          : const Color(0xFF26383A),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              _AnalysisCard(
                title: 'Detalle por día',
                subtitle: 'Caudal, nivel y consumo reportados por Core API.',
                child: Column(
                  children: [for (final day in _calendar) _DayRow(day: day)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalysisSummary extends StatelessWidget {
  const _AnalysisSummary({
    required this.pointName,
    required this.daysWithData,
    required this.totalVolume,
    required this.latestDate,
  });

  final String pointName;
  final int daysWithData;
  final double totalVolume;
  final String latestDate;

  @override
  Widget build(BuildContext context) => _AnalysisCard(
    title: pointName,
    subtitle: 'Último día del período: $latestDate',
    child: Row(
      children: [
        Expanded(
          child: _AnalysisMetric(
            label: 'Días con datos',
            value: '$daysWithData',
          ),
        ),
        Expanded(
          child: _AnalysisMetric(
            label: 'Volumen del período',
            value: '${totalVolume.toStringAsFixed(1)} m³',
          ),
        ),
      ],
    ),
  );
}

class _AnalysisMetric extends StatelessWidget {
  const _AnalysisMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
    ],
  );
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final Map<String, dynamic> day;

  @override
  Widget build(BuildContext context) {
    final hasData = day['has_data'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              day['date_formatted']?.toString() ??
                  day['date']?.toString() ??
                  '—',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              hasData
                  ? '${_number(day['consumption_m3']).toStringAsFixed(1)} m³'
                  : 'Sin medición',
              style: TextStyle(
                color: hasData
                    ? const Color(0xFFE8F2F1)
                    : const Color(0xFF809798),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              hasData ? '${day['avg_flow_lps'] ?? '—'} L/s' : '—',
              style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              hasData
                  ? '${day['avg_water_table_m'] ?? day['avg_nivel_m'] ?? '—'} m'
                  : '—',
              style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF112328),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _AnalysisError extends StatelessWidget {
  const _AnalysisError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _AnalysisCard(
    title: 'No se pudo cargar el análisis',
    subtitle: message,
    child: Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Reintentar'),
      ),
    ),
  );
}

class _AnalysisEmpty extends StatelessWidget {
  const _AnalysisEmpty();

  @override
  Widget build(BuildContext context) => const _AnalysisCard(
    title: 'Sin puntos para analizar',
    subtitle: 'Tu cuenta todavía no tiene puntos asignados.',
    child: SizedBox.shrink(),
  );
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value');
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
