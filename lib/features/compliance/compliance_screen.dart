import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/smarthydro_api.dart';
import '../../shared/navigation/hydro_page_route.dart';
import '../../shared/theme/chile_palette.dart';
import '../../shared/widgets/chile_shield.dart';
import '../../shared/widgets/hydro_entrance.dart';
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
    final visible = _visiblePoints;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const ChileShield(size: 22, soft: true),
            const SizedBox(width: 10),
            Expanded(child: Text(_title)),
          ],
        ),
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
            HydroEntrance(
              child: _ComplianceHero(
                title: _title,
                pointCount: visible.length,
              ),
            ),
            const SizedBox(height: 14),
            HydroEntrance(
              delay: const Duration(milliseconds: 60),
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Solo cumplimiento activo'),
                subtitle: const Text(
                  'Oculta autorizaciones fuera de vigencia',
                  style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
                ),
                activeTrackColor: ChilePalette.inkBlue.withValues(alpha: 0.55),
                value: _activeOnly,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  setState(() => _activeOnly = value);
                  _load();
                },
              ),
            ),
            if (types.length > 1) ...[
              const SizedBox(height: 4),
              HydroEntrance(
                delay: const Duration(milliseconds: 90),
                child: Wrap(
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
                          agency: type,
                          onTap: () => setState(() => _typeFilter = type),
                        ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_loading) const HydroLoading(),
            if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
            if (!_loading && _error == null && _points.isEmpty)
              const _EmptyCompliance(),
            for (var i = 0; i < visible.length; i++) ...[
              HydroEntrance(
                delay: Duration(milliseconds: 110 + i * 45),
                child: _CompliancePointCard(
                  point: visible[i],
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push<void>(
                      hydroPageRoute(
                        _ComplianceDetailScreen(
                          api: widget.api,
                          token: widget.token,
                          point: visible[i],
                        ),
                      ),
                    );
                  },
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

class _ComplianceHero extends StatelessWidget {
  const _ComplianceHero({required this.title, required this.pointCount});

  final String title;
  final int pointCount;

  @override
  Widget build(BuildContext context) => HydroGlass(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    radius: 18,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ChileAccentBar(height: 3, opacity: 0.5),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ChilePalette.blueWash(0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ChilePalette.goldWash(0.35)),
              ),
              child: const ChileShield(size: 28, soft: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    pointCount == 1
                        ? '1 punto con configuración normativa'
                        : '$pointCount puntos con configuración normativa',
                    style: const TextStyle(
                      color: Color(0xFF9AB0B1),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.agency,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? agency;

  @override
  Widget build(BuildContext context) {
    final accent = switch (agency) {
      'DGA' => ChilePalette.inkBlue,
      'SMA' => ChilePalette.inkRed,
      _ => const Color(0xFF66E0C2),
    };
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onTap();
      },
      selectedColor: accent,
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF081316) : const Color(0xFFB7C8C7),
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: const Color(0xFF1A3035),
      side: BorderSide(
        color: selected
            ? accent.withValues(alpha: 0.0)
            : accent.withValues(alpha: 0.22),
      ),
    );
  }
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
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        splashColor: ChilePalette.blueWash(0.12),
        highlightColor: ChilePalette.blueWash(0.06),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF132E35).withValues(alpha: 0.9),
                Color.lerp(
                      const Color(0xFF09171B),
                      ChilePalette.blue,
                      0.06,
                    ) ??
                    const Color(0xFF09171B),
              ],
            ),
            border: Border.all(
              color: ChilePalette.blueWash(0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ChileAccentBar(height: 2.5, opacity: 0.42),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const ChileShield(size: 24, soft: true),
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
                  runSpacing: 6,
                  children: [
                    if (types is List)
                      for (final type in types) _AgencyChip(label: '$type'),
                    if (point['standard'] != null)
                      _AgencyChip(label: '${point['standard']}', muted: true),
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
        border: Border.all(color: color.withValues(alpha: 0.28)),
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
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final target = ratio ?? 0;
    return Column(
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
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: const Color(0xFF26383A),
              valueColor: AlwaysStoppedAnimation<Color>(
                ratio == null ? const Color(0xFF3A4E50) : color,
              ),
            ),
          ),
        ),
      ],
    );
  }
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
        title: Row(
          children: [
            const ChileShield(size: 20, soft: true),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                point['point_name']?.toString() ?? 'Cumplimiento',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: HydroFrame(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            HydroEntrance(
              child: HydroGlass(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                radius: 18,
                child: Column(
                  children: [
                    const ChileAccentBar(height: 2.5, opacity: 0.45),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const ChileShield(size: 30, soft: true),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading) const HydroLoading(),
            if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
            HydroEntrance(
              delay: const Duration(milliseconds: 70),
              child: _ComplianceSection(
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
                          muted: true,
                        ),
                        _AgencyChip(
                          label: 'Origen: ${point['type_dga'] ?? '—'}',
                          muted: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            HydroEntrance(
              delay: const Duration(milliseconds: 100),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 días')),
                  ButtonSegment(value: 30, label: Text('30 días')),
                  ButtonSegment(value: 90, label: Text('90 días')),
                ],
                selected: {_days},
                onSelectionChanged: (selection) {
                  HapticFeedback.selectionClick();
                  setState(() => _days = selection.first);
                  _load();
                },
              ),
            ),
            const SizedBox(height: 12),
            HydroEntrance(
              delay: const Duration(milliseconds: 130),
              child: _ComplianceSection(
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
                            color: ChilePalette.inkRed,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (sorted.isNotEmpty && authFlow != null && authFlow > 0) ...[
              const SizedBox(height: 12),
              HydroEntrance(
                delay: const Duration(milliseconds: 160),
                child: _ComplianceSection(
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
                      color: ChilePalette.inkBlue,
                      fillColor: ChilePalette.inkBlue,
                      maxY: _chartMax(
                        sorted
                            .map((r) => _numOrNull(r['flow']))
                            .whereType<num>(),
                        authFlow,
                      ),
                      limit: authFlow,
                    ),
                  ),
                ),
              ),
            ],
            if (sorted.any(
              (r) => _numOrNull(r['water_table'] ?? r['nivel']) != null,
            )) ...[
              const SizedBox(height: 12),
              HydroEntrance(
                delay: const Duration(milliseconds: 190),
                child: _ComplianceSection(
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
                              (r) =>
                                  _numOrNull(r['water_table'] ?? r['nivel']),
                            )
                            .whereType<num>(),
                        null,
                      ),
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
                  style: const TextStyle(color: Color(0xFFFFC46B), fontSize: 12),
                ),
              ),
            HydroEntrance(
              delay: const Duration(milliseconds: 210),
              child: _measurementList(
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
            ),
            const SizedBox(height: 12),
            HydroEntrance(
              delay: const Duration(milliseconds: 240),
              child: _measurementList(
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
                    leading: Icon(
                      Icons.water_drop_outlined,
                      color: title.contains('Sobre')
                          ? ChilePalette.inkRed
                          : ChilePalette.inkBlue,
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
              color: ChilePalette.red.withValues(alpha: 0.72),
              strokeWidth: 1.4,
              dashArray: const [6, 5],
            ),
        ],
      ),
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => const Color(0xFF12252A),
          getTooltipItems: (spots) => [
            for (final spot in spots)
              LineTooltipItem(
                spot.y.toStringAsFixed(spot.y >= 100 ? 0 : 2),
                TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.18,
          color: color,
          barWidth: 2.2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: fillColor.withValues(alpha: 0.12),
          ),
        ),
      ],
    ),
    duration: MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 520),
    curve: Curves.easeOutCubic,
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
      border: Border.all(color: color.withValues(alpha: 0.22)),
    ),
    child: Text(
      '$value $label',
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _AgencyChip extends StatelessWidget {
  const _AgencyChip({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final upper = label.toUpperCase();
    final Color fill;
    final Color border;
    final Color text;
    if (upper == 'DGA') {
      fill = ChilePalette.blueWash(0.18);
      border = ChilePalette.blueWash(0.4);
      text = ChilePalette.inkBlue;
    } else if (upper == 'SMA') {
      fill = ChilePalette.redWash(0.14);
      border = ChilePalette.redWash(0.35);
      text = ChilePalette.inkRed;
    } else if (muted) {
      fill = const Color(0xFF1A3035);
      border = Colors.white.withValues(alpha: 0.06);
      text = const Color(0xFFB7C8C7);
    } else {
      fill = const Color(0xFF1A3035);
      border = ChilePalette.goldWash(0.25);
      text = const Color(0xFFE8F2F1);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ComplianceSection extends StatelessWidget {
  const _ComplianceSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    decoration: BoxDecoration(
      color: const Color(0xFF112328),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ChilePalette.blueWash(0.16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ChileAccentBar(height: 2, opacity: 0.35),
        const SizedBox(height: 10),
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
  Widget build(BuildContext context) => HydroEntrance(
    child: HydroGlass(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const ChileShield(size: 36, soft: true),
          const SizedBox(height: 14),
          const Text(
            'No hay puntos con configuración DGA/SMA para mostrar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9AB0B1), height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => HydroGlass(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
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
