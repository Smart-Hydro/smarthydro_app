import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/brand.dart';
import '../../shared/navigation/hydro_page_route.dart';
import '../../shared/ui/hydro_ui.dart';
import '../../shared/widgets/chile_shield.dart';
import '../../shared/widgets/hydro_glass.dart';
import 'point_compliance_screen.dart';

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
            if (_loading && _points.isEmpty)
              const HydroSkeletonCards(height: 112)
            else if (_loading)
              const HydroLinearBar(),
            if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
            if (!_loading && _error == null && _points.isEmpty)
              const _EmptyCompliance(),
            for (final point in _visiblePoints) ...[
              _CompliancePointCard(
                point: point,
                onTap: () => Navigator.of(context).push<void>(
                  hydroPageRoute(
                    PointComplianceScreen(
                      api: widget.api,
                      token: widget.token,
                      pointId: _toInt(point['point_id']),
                      pointTitle: point['point_name']?.toString(),
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
    selectedColor: IkoluColors.cyan,
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

int _toInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

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
