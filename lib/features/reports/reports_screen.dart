import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/smarthydro_api.dart';
import '../../shared/widgets/hydro_glass.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    required this.api,
    required this.token,
    required this.points,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final List<Map<String, dynamic>> points;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int? _pointId;
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );
  List<Map<String, dynamic>> _records = const [];
  bool _loading = true;
  bool _sharing = false;
  String? _error;

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
        _records = const [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await widget.api.pointRecords(
        widget.token,
        pointId,
        start: _range.start,
        end: _range.end,
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
  }

  Future<void> _chooseRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      helpText: 'Selecciona un rango de hasta 31 días',
      saveText: 'Cargar registros',
    );
    if (!mounted || selected == null) return;
    if (selected.duration.inDays > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El rango máximo por consulta es de 31 días.'),
        ),
      );
      return;
    }
    setState(() => _range = selected);
    _load();
  }

  Future<void> _shareCsv() async {
    if (_records.isEmpty || _pointId == null) return;
    setState(() => _sharing = true);
    try {
      final point = widget.points.firstWhere(
        (item) => _toInt(item['id']) == _pointId,
        orElse: () => const <String, dynamic>{},
      );
      final safeTitle = (point['title']?.toString() ?? 'punto').replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );
      final filename =
          'smarthydro_${safeTitle}_${_date(_range.start)}_${_date(_range.end)}.csv';
      final rows = <List<String>>[
        ['Punto', point['title']?.toString() ?? ''],
        ['Período', '${_date(_range.start)} a ${_date(_range.end)}'],
        [],
        [
          'Fecha/hora',
          'Caudal (L/s)',
          'Total (m³)',
          'Variación (m³)',
          'Nivel (m)',
          'Nivel freático (m)',
          'Error',
        ],
        for (final record in _records)
          [
            record['date_time']?.toString() ?? '',
            record['flow']?.toString() ?? '',
            record['total']?.toString() ?? '',
            record['total_diff']?.toString() ?? '',
            record['nivel']?.toString() ?? '',
            record['water_table']?.toString() ?? '',
            record['is_error']?.toString() ?? '',
          ],
      ];
      final csv =
          '\uFEFF${rows.map((row) => row.map(_csvField).join(';')).join('\r\n')}';
      await SharePlus.instance.share(
        ShareParams(
          title: 'Registros SmartHydro',
          text: 'Datos de ${point['title'] ?? 'punto SmartHydro'}',
          files: [
            XFile.fromData(
              utf8.encode(csv),
              mimeType: 'text/csv',
              name: filename,
            ),
          ],
          fileNameOverrides: [filename],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo preparar el archivo para compartir.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Descarga de registros'),
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
            DropdownButtonFormField<int>(
              initialValue: _pointId,
              decoration: const InputDecoration(labelText: 'Punto'),
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
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _chooseRange,
              icon: const Icon(Icons.date_range_rounded),
              label: Text('${_date(_range.start)} — ${_date(_range.end)}'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_records.length} registros cargados',
                    style: const TextStyle(color: Color(0xFF9AB0B1)),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _records.isEmpty || _sharing ? null : _shareCsv,
                  icon: _sharing
                      ? const HydroSpinner(size: 16)
                      : const Icon(Icons.share_rounded, size: 17),
                  label: const Text('Compartir CSV'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading) const HydroLinearBar(),
            if (_error != null) _ReportError(message: _error!, onRetry: _load),
            if (!_loading && _error == null && _records.isEmpty)
              const _ReportEmpty(),
            if (_records.length >= 500)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Se alcanzó el límite de 500 registros; reduce el período para revisar con mayor detalle.',
                  style: TextStyle(color: Color(0xFFFFC46B), fontSize: 11),
                ),
              ),
            if (_records.isNotEmpty) _RecordsTable(records: _records),
          ],
        ),
      ),
    );
  }
}

class _RecordsTable extends StatelessWidget {
  const _RecordsTable({required this.records});

  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: const [
        DataColumn(label: Text('Fecha/hora')),
        DataColumn(label: Text('Caudal')),
        DataColumn(label: Text('Total')),
        DataColumn(label: Text('Variación')),
        DataColumn(label: Text('Nivel')),
        DataColumn(label: Text('Error')),
      ],
      rows: [
        for (final record in records)
          DataRow(
            cells: [
              DataCell(Text(_formatDate(record['date_time']))),
              DataCell(Text(_value(record['flow'], 'L/s'))),
              DataCell(Text(_value(record['total'], 'm³'))),
              DataCell(Text(_value(record['total_diff'], 'm³'))),
              DataCell(
                Text(_value(record['nivel'] ?? record['water_table'], 'm')),
              ),
              DataCell(
                Icon(
                  record['is_error'] == true
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  color: record['is_error'] == true
                      ? const Color(0xFFFF847A)
                      : const Color(0xFF66E0C2),
                  size: 17,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _ReportEmpty extends StatelessWidget {
  const _ReportEmpty();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Text(
      'No hay registros para el punto y período seleccionados.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Color(0xFF9AB0B1)),
    ),
  );
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.error_outline_rounded, color: Color(0xFFFF847A)),
    title: Text(message),
    trailing: IconButton(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
    ),
  );
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
int? _toInt(dynamic value) => value is int ? value : int.tryParse('$value');
String _value(dynamic value, String unit) =>
    value == null ? '—' : '$value $unit';
String _formatDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '—';
  return '${_date(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _csvField(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
