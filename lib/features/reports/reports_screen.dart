import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/files/save_file.dart';
import '../../shared/ui/hydro_ui.dart';
import '../../shared/widgets/hydro_glass.dart';
import '../dashboard/capture_stage.dart' show formatCl;
import '../dashboard/point_meta.dart';

const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _monthsShort = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

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
    icon: const Icon(Icons.refresh_rounded),
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
    subtitle: widget.points.length > 1
        ? PopupMenuButton<int>(
            tooltip: 'Cambiar punto',
            color: HydroTone.menu,
            onSelected: (id) {
              setState(() => _pointId = id);
              _load(reloadVariables: true);
            },
            itemBuilder: (_) => [
              for (final p in widget.points)
                PopupMenuItem<int>(
                  value: _toInt(p['id']),
                  child: Text(
                    '${p['title'] ?? 'Punto'}',
                    style: TextStyle(
                      color: _toInt(p['id']) == _pointId
                          ? HydroTone.accent
                          : HydroTone.fog,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HydroTone.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.expand_more_rounded,
                  color: HydroTone.accent,
                  size: 16,
                ),
              ],
            ),
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
      return const HydroMessage(
        icon: Icons.water_drop_outlined,
        title: 'Sin puntos',
        message: 'Tu cuenta todavía no tiene puntos asignados.',
      );
    }
    final v = _variables;
    final groups = <DateTime, List<Map<String, dynamic>>>{};
    for (final r in _records) {
      final t = _dateOf(r);
      groups.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(r);
    }
    final children = <Widget>[
      _PeriodTabs(selected: _period, onChanged: _choosePeriod),
      const SizedBox(height: 14),
      Text(
        '${_short(_range.start)} – ${_short(_range.end)}',
        style: const TextStyle(
          color: HydroTone.fog,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        _loading
            ? 'Cargando lecturas…'
            : '${formatCl(_records.length.toDouble(), 0)} lecturas'
                  '${_records.length >= 500 ? ' · se muestran las 500 más recientes, el Excel trae todas' : ''}',
        style: const TextStyle(
          color: HydroTone.faint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy != null ? null : _downloadXlsx,
              style: FilledButton.styleFrom(
                backgroundColor: HydroTone.accent,
                foregroundColor: const Color(0xFF06222B),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _busy == 'xlsx'
                  ? const HydroSpinner(size: 16, strokeWidth: 2)
                  : const Icon(Icons.download_rounded, size: 18),
              label: const Text(
                'Descargar Excel',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: _busy != null || _records.isEmpty ? null : _downloadCsv,
            style: TextButton.styleFrom(
              foregroundColor: HydroTone.accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            ),
            child: _busy == 'csv'
                ? const HydroSpinner(size: 16, strokeWidth: 2)
                : const Text('CSV'),
          ),
        ],
      ),
      const SizedBox(height: 22),
    ];

    final Widget content;
    if (_loading) {
      content = const HydroSkeleton(
        inline: true,
        hero: false,
        kpis: 0,
        chart: false,
        rows: 8,
      );
    } else if (_error != null) {
      content = HydroMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No pudimos cargar los registros',
        message: _error!,
        action: ('Reintentar', _load),
      );
    } else if (_records.isEmpty) {
      content = const HydroMessage(
        icon: Icons.event_busy_rounded,
        title: 'Sin lecturas en este período',
        message: 'Prueba con otro rango de fechas.',
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ColumnsHeader(variables: v),
          for (final entry in groups.entries) ...[
            _DayHeader(day: entry.key, count: entry.value.length),
            for (final r in entry.value) _RecordRow(record: r, variables: v),
          ],
        ],
      );
    }
    children.add(
      HydroSwap(
        state: _loading
            ? 'loading'
            : _error != null
            ? 'error'
            : '$_pointId-${_range.start}-${_range.end}',
        child: content,
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: children,
    );
  }
}

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.selected, required this.onChanged});

  final _Period selected;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = {
      _Period.today: 'Hoy',
      _Period.week: '7 días',
      _Period.month: '31 días',
      _Period.custom: 'Elegir fechas',
    };
    return Wrap(
      spacing: 4,
      children: [
        for (final e in labels.entries)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged(e.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (e.key == _Period.custom) ...[
                        Icon(
                          Icons.date_range_rounded,
                          size: 14,
                          color: e.key == selected
                              ? HydroTone.fog
                              : HydroTone.faint,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        e.value,
                        style: TextStyle(
                          color: e.key == selected
                              ? HydroTone.fog
                              : HydroTone.faint,
                          fontSize: 12.5,
                          fontWeight: e.key == selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: e.key == selected ? 16 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: HydroTone.accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Row(
      children: [
        Text(
          '${_weekdays[day.weekday - 1]} ${day.day} ${_monthsShort[day.month - 1]}',
          style: const TextStyle(
            color: HydroTone.accent,
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HydroTone.hair)),
      ),
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
          SizedBox(
            width: 18,
            child: error
                ? const Tooltip(
                    message: 'El equipo marcó esta lectura con error',
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 13,
                      color: Color(0xFFFF847A),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

DateTime _dateOf(Map<String, dynamic> r) =>
    DateTime.tryParse(
      '${r['date_time'] ?? r['date_time_medition'] ?? ''}',
    )?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

String _two(int n) => n.toString().padLeft(2, '0');

String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _short(DateTime d) =>
    '${d.day} ${_monthsShort[d.month - 1]}${d.year != DateTime.now().year ? ' ${d.year}' : ''}';

String _stamp(DateTime d) => '${_iso(d)} ${_two(d.hour)}:${_two(d.minute)}';

int? _toInt(dynamic value) => value is int ? value : int.tryParse('$value');
