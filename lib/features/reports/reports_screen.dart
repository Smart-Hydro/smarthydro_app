import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/files/save_file.dart';
import '../../core/brand.dart';
import '../../shared/ui/capture_point_picker.dart';
import '../../shared/ui/hydro_ui.dart';
import '../../shared/widgets/hydro_glass.dart';
import '../../shared/widgets/hydro_glyph.dart';
import '../dashboard/capture_stage.dart' show formatCl;
import '../dashboard/point_meta.dart';

const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _monthsShort = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

const _recordsGlyphColor = Color(0xFFC5D5D4);

DateTime reportsDateOf(Map<String, dynamic> r) =>
    DateTime.tryParse(
      '${r['date_time'] ?? r['date_time_medition'] ?? ''}',
    )?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

List<MapEntry<DateTime, List<Map<String, dynamic>>>> reportsGroupByDay(
  List<Map<String, dynamic>> records,
) {
  final groups = <DateTime, List<Map<String, dynamic>>>{};
  for (final r in records) {
    final t = reportsDateOf(r);
    groups.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(r);
  }
  return groups.entries.toList(growable: false);
}

double? reportsMeanFlow(List<Map<String, dynamic>> records) {
  final values = <double>[];
  for (final r in records) {
    final raw = r['flow'];
    final n = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
    if (n != null) values.add(n);
  }
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

/// Registros del punto: lecturas del período y descarga en Excel.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    required this.api,
    required this.token,
    required this.points,
    this.showBack = true,
    this.embedded = false,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final List<Map<String, dynamic>> points;

  /// En el shell de escritorio el rail reemplaza a Volver.
  final bool showBack;

  /// Paleta sobre el pozo: sin HydroPage ni Volver.
  final bool embedded;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _Period { today, week, month, custom }

class _ReportsScreenState extends State<ReportsScreen> {
  int? _pointId;
  _Period _period = _Period.week;
  DateTimeRange _range = _rangeFor(_Period.week);
  List<Map<String, dynamic>> _records = const [];
  PointVariables _variables = PointVariables.unknownCatalog;
  bool _loading = true;
  String? _busy;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (widget.points.isNotEmpty) _pointId = _toInt(widget.points.first['id']);
    _load(reloadVariables: true);
  }

  Map<String, dynamic> get _point => widget.points.firstWhere(
    (p) => _toInt(p['id']) == _pointId,
    orElse: () => const {},
  );

  String get _title => _point['title']?.toString() ?? 'Punto';

  static DateTimeRange _rangeFor(_Period p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (p) {
      _Period.today => DateTimeRange(start: today, end: now),
      _Period.week => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: now,
      ),
      _ => DateTimeRange(
        start: today.subtract(const Duration(days: 30)),
        end: now,
      ),
    };
  }

  Future<void> _load({bool reloadVariables = false}) async {
    final id = _pointId;
    final request = ++_request;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (reloadVariables) {
        try {
          _variables = PointVariables.fromJson(
            await widget.api.pointVariables(widget.token, id),
          );
        } on SmartHydroApiException {
          _variables = PointVariables.unknownCatalog;
        }
      }
      final records = await widget.api.pointRecords(
        widget.token,
        id,
        start: _range.start,
        end: _range.end,
        limit: 500,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _choosePeriod(_Period p) async {
    if (p == _Period.custom) {
      final selected = await showHydroDateRange(
        context: context,
        firstDate: DateTime(2015),
        lastDate: DateTime.now(),
        initialDateRange: _range,
        helpText: 'Elige hasta 31 días',
        saveText: 'Ver registros',
      );
      if (!mounted || selected == null) return;
      if (selected.duration.inDays > 30) {
        _toast('El rango máximo es de 31 días.');
        return;
      }
      setState(() {
        _period = p;
        _range = selected;
      });
    } else {
      setState(() {
        _period = p;
        _range = _rangeFor(p);
      });
    }
    _load();
  }

  String get _fileBase =>
      '${safeFileName(_title)}_${_iso(_range.start)}_${_iso(_range.end)}';

  Future<void> _downloadXlsx() => _save(
    () => widget.api.recordsWorkbook(
      widget.token,
      _pointId!,
      start: _range.start,
      end: _range.end,
    ),
    '$_fileBase.xlsx',
    SmartHydroApi.xlsxMime,
    'xlsx',
  );

  Future<void> _downloadCsv() => _save(
    () async => Uint8List.fromList(utf8.encode(_csv())),
    '$_fileBase.csv',
    'text/csv',
    'csv',
  );

  Future<void> _save(
    Future<Uint8List> Function() load,
    String name,
    String mime,
    String key,
  ) async {
    setState(() => _busy = key);
    try {
      await saveBytes(await load(), name, mime);
      _toast('Descargado $name');
    } on SmartHydroApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo preparar el archivo.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _csv() {
    final v = _variables;
    final header = [
      'Fecha/hora',
      if (v.hasFlow) 'Caudal (L/s)',
      if (v.hasTotal) 'Totalizado (m³)',
      if (v.hasTotal) 'Variación (m³)',
      if (v.hasLevel) 'Nivel (m)',
      if (v.hasLevel) 'Nivel freático (m)',
    ];
    String cell(dynamic x) => '"${'${x ?? ''}'.replaceAll('"', '""')}"';
    final lines = [
      header.map(cell).join(';'),
      for (final r in _records)
        [
          _stamp(_dateOf(r)),
          if (v.hasFlow) r['flow'],
          if (v.hasTotal) r['total'],
          if (v.hasTotal) r['total_diff'],
          if (v.hasLevel) r['nivel'],
          if (v.hasLevel) r['water_table'],
        ].map(cell).join(';'),
    ];
    return '\uFEFF${lines.join('\r\n')}';
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _refreshButton() => IconButton(
    tooltip: 'Actualizar registros',
    onPressed: _busy != null ? null : () => _load(),
    icon: const Icon(Icons.refresh_rounded, color: HydroTone.faint),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: _refreshButton(),
            ),
          ),
          Expanded(child: _body()),
        ],
      );
    }
    return HydroPage(
      title: 'Registros',
      showBack: widget.showBack,
      maxWidth: 1180,
      titleLeading: const HydroGlyph(
        kind: HydroGlyphKind.registros,
        color: _recordsGlyphColor,
        size: 40,
        keyPrefix: 'reports-glyph',
      ),
      subtitle: widget.points.length > 1
          ? CapturePointFilter(
              points: widget.points,
              selectedId: _pointId,
              onChanged: (id) {
                setState(() => _pointId = id);
                _load(reloadVariables: true);
              },
            )
          : Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HydroText.subtitle,
            ),
      trailing: _refreshButton(),
      body: _body(),
    );
  }

  Widget _body() {
    if (_pointId == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: _ReportsEmpty(
          title: 'Sin puntos',
          message: 'Tu cuenta todavía no tiene puntos asignados.',
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 980;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          _ReportsToolbar(
            period: _period,
            range: _range,
            onChanged: _choosePeriod,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: wide
                ? Row(
                    key: const ValueKey('reports-layout-wide'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 300, child: _sidebar()),
                      const SizedBox(width: 14),
                      Expanded(child: _tablePane()),
                    ],
                  )
                : Column(
                    key: const ValueKey('reports-layout-narrow'),
                    children: [
                      _sidebar(),
                      const SizedBox(height: 12),
                      Expanded(child: _tablePane()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sidebar() {
    final mean = reportsMeanFlow(_records);
    DateTime? last;
    for (final r in _records) {
      final t = reportsDateOf(r);
      if (last == null || t.isAfter(last)) last = t;
    }
    return HydroGlassLight(
      key: const ValueKey('reports-pulse'),
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _PulseStat(
                label: 'Lecturas',
                value: _loading
                    ? '…'
                    : formatCl(_records.length.toDouble(), 0),
                tone: IkoluColors.cyan,
              ),
              _PulseStat(
                label: 'Última',
                value: last == null
                    ? '—'
                    : '${_two(last.hour)}:${_two(last.minute)}',
                tone: HydroTone.fog,
              ),
              if (_variables.hasFlow)
                _PulseStat(
                  label: 'Caudal',
                  value: mean == null ? '—' : formatCl(mean, 1),
                  tone: IkoluColors.connected,
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy != null ? null : _downloadXlsx,
            style: FilledButton.styleFrom(
              backgroundColor: IkoluColors.cyan,
              foregroundColor: const Color(0xFF041014),
              minimumSize: const Size.fromHeight(42),
              shape: const StadiumBorder(),
            ),
            child: _busy == 'xlsx'
                ? HydroSpinner(size: 16, strokeWidth: 2)
                : const Text(
                    'Descargar Excel',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy != null || _records.isEmpty ? null : _downloadCsv,
            style: TextButton.styleFrom(
              foregroundColor: HydroTone.fog,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              minimumSize: const Size.fromHeight(40),
              shape: const StadiumBorder(),
            ),
            child: _busy == 'csv'
                ? HydroSpinner(size: 16, strokeWidth: 2)
                : const Text('CSV', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (_records.length >= 500) ...[
            const SizedBox(height: 10),
            const HydroHint(
              'Se muestran las 500 más recientes. El Excel trae todas.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _tablePane() {
    final v = _variables;
    final lines = <_TableLine>[
      for (final entry in reportsGroupByDay(_records)) ...[
        _TableLine.day(entry.key, entry.value.length),
        for (final r in entry.value) _TableLine.row(r),
      ],
    ];
    Widget inner;
    if (_loading) {
      inner = const Padding(
        padding: EdgeInsets.all(16),
        child: HydroSkeleton(
          inline: true,
          hero: false,
          kpis: 0,
          chart: false,
          rows: 8,
        ),
      );
    } else if (_error != null) {
      inner = _ReportsEmpty(
        title: 'No pudimos cargar los registros',
        message: _error!,
        action: ('Reintentar', _load),
      );
    } else if (_records.isEmpty) {
      inner = const _ReportsEmpty(
        title: 'Sin lecturas en este período',
        message: 'Prueba con otro rango de fechas.',
      );
    } else {
      inner = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: _ColumnsHeader(variables: v),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemCount: lines.length,
              itemBuilder: (context, i) {
                final line = lines[i];
                if (line.day != null) {
                  return _DayHeader(day: line.day!, count: line.count);
                }
                return _RecordRow(record: line.record!, variables: v);
              },
            ),
          ),
        ],
      );
    }
    return SizedBox.expand(
      child: HydroGlassLight(
        key: const ValueKey('reports-table'),
        radius: 16,
        padding: EdgeInsets.zero,
        child: SizedBox.expand(child: inner),
      ),
    );
  }
}

class _TableLine {
  const _TableLine.day(this.day, this.count) : record = null;
  const _TableLine.row(this.record) : day = null, count = 0;

  final DateTime? day;
  final int count;
  final Map<String, dynamic>? record;
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
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: HydroTone.faint,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsEmpty extends StatelessWidget {
  const _ReportsEmpty({
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HydroGlyph(
              kind: HydroGlyphKind.registros,
              color: _recordsGlyphColor,
              size: 56,
              keyPrefix: 'reports-empty',
            ),
            const SizedBox(height: 12),
            Text(title, style: HydroText.section, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            HydroHint(message),
            if (action != null) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: action!.$2,
                style: TextButton.styleFrom(
                  foregroundColor: HydroTone.fog,
                  backgroundColor: IkoluColors.cyan.withValues(alpha: 0.14),
                  shape: const StadiumBorder(),
                ),
                child: Text(action!.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportsToolbar extends StatelessWidget {
  const _ReportsToolbar({
    required this.period,
    required this.range,
    required this.onChanged,
  });

  final _Period period;
  final DateTimeRange range;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = {
      _Period.today: 'Hoy',
      _Period.week: '7 días',
      _Period.month: '31 días',
      _Period.custom: 'Fechas',
    };
    return HydroGlassLight(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final e in labels.entries)
            _PeriodPill(
              label: e.value,
              selected: period == e.key,
              onTap: () => onChanged(e.key),
            ),
          Text(
            '${_short(range.start)} – ${_short(range.end)}',
            style: const TextStyle(
              color: HydroTone.faint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: HydroMotion.of(context, HydroMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: IkoluColors.cyan.withValues(alpha: selected ? 0.22 : 0.06),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: IkoluColors.cyan.withValues(alpha: selected ? 0.7 : 0.16),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? HydroTone.fog : HydroTone.faint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColumnsHeader extends StatelessWidget {
  const _ColumnsHeader({required this.variables});

  final PointVariables variables;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: HydroTone.faint,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: 56, child: Text('Hora', style: style)),
          if (variables.hasFlow)
            const Expanded(
              child: Text('Caudal', textAlign: TextAlign.right, style: style),
            ),
          if (variables.hasTotal)
            const Expanded(
              flex: 2,
              child: Text(
                'Totalizado',
                textAlign: TextAlign.right,
                style: style,
              ),
            ),
          if (variables.hasLevel)
            const Expanded(
              child: Text('Nivel', textAlign: TextAlign.right, style: style),
            ),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.count});

  final DateTime day;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
    child: Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: IkoluColors.cyan,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_weekdays[day.weekday - 1]} ${day.day} ${_monthsShort[day.month - 1]}',
          style: const TextStyle(
            color: IkoluColors.cyanSoft,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count lecturas',
          style: const TextStyle(color: HydroTone.faint, fontSize: 10.5),
        ),
      ],
    ),
  );
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.variables});

  final Map<String, dynamic> record;
  final PointVariables variables;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final t = _dateOf(r);
    final error = r['is_error'] == true;
    String value(dynamic v, int d, String unit) {
      final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
      return n == null ? '—' : '${formatCl(n, d)} $unit';
    }

    const style = TextStyle(
      color: HydroTone.fog,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: error
            ? IkoluColors.incident.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              '${_two(t.hour)}:${_two(t.minute)}',
              style: style.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (variables.hasFlow)
            Expanded(
              child: Text(
                value(r['flow'], 2, 'L/s'),
                textAlign: TextAlign.right,
                style: style,
              ),
            ),
          if (variables.hasTotal)
            Expanded(
              flex: 2,
              child: Text(
                value(r['total'], 1, 'm³'),
                textAlign: TextAlign.right,
                style: style,
              ),
            ),
          if (variables.hasLevel)
            Expanded(
              child: Text(
                value(r['nivel'] ?? r['water_table'], 2, 'm'),
                textAlign: TextAlign.right,
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}

DateTime _dateOf(Map<String, dynamic> r) => reportsDateOf(r);

String _two(int n) => n.toString().padLeft(2, '0');

String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _short(DateTime d) =>
    '${d.day} ${_monthsShort[d.month - 1]}${d.year != DateTime.now().year ? ' ${d.year}' : ''}';

String _stamp(DateTime d) => '${_iso(d)} ${_two(d.hour)}:${_two(d.minute)}';

int? _toInt(dynamic value) => value is int ? value : int.tryParse('$value');
