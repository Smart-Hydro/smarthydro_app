/// Cumplimiento DGA (MEE) de un punto.
///
/// Replica las reglas del backend (`validate_frequency` del cron DGA):
/// según el estándar, qué mediciones deben enviarse y en qué horario. Con la
/// planilla DGA del período (cada medición con su comprobante) se cuenta
/// cuántos reportes esperados tienen comprobante, cuáles quedaron sin él y
/// en qué horas no hubo dato.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

enum DgaStandard {
  mayor,
  medio,
  menor,
  muyPequenos,
  sinEstandar,
  unknown;

  static DgaStandard parse(dynamic raw) {
    final s = '${raw ?? ''}'.trim().toUpperCase();
    return switch (s) {
      'MAYOR' => mayor,
      'MEDIO' => medio,
      'MENOR' => menor,
      'CAUDALES_MUY_PEQUENOS' || 'CMP' => muyPequenos,
      'SIN_ESTANDAR' || '' => sinEstandar,
      _ => unknown,
    };
  }

  String get label => switch (this) {
    mayor => 'Mayor',
    medio => 'Medio',
    menor => 'Menor',
    muyPequenos => 'Caudales muy pequeños',
    sinEstandar => 'Sin estándar',
    unknown => 'No informado',
  };

  /// Cada cuánto debe llegar un reporte a la DGA.
  String get cadence => switch (this) {
    mayor || sinEstandar => 'un reporte cada hora',
    medio => 'un reporte al día (00:00)',
    menor => 'un reporte al mes (día 1)',
    muyPequenos => 'dos reportes al año (1 de enero y 1 de julio)',
    unknown => 'cadencia no informada',
  };

  /// Si el horario [hour] (inicio de hora, hora de Chile) exige un reporte.
  bool expectsAt(DateTime hour) => switch (this) {
    mayor || sinEstandar => true,
    medio => hour.hour == 0,
    menor => hour.day == 1 && hour.hour == 0,
    muyPequenos =>
      (hour.month == 1 || hour.month == 7) && hour.day == 1 && hour.hour == 0,
    unknown => false,
  };

  /// Si una medición tomada en [at] es la que se envía a la DGA para su hora.
  bool sends(DateTime at, int frequencyMinutes) {
    final hourStart = DateTime(at.year, at.month, at.day, at.hour);
    if (!expectsAt(hourStart)) return false;
    return frequencyMinutes >= 60
        ? at.minute == 0
        : at.minute < frequencyMinutes;
  }
}

/// Una fila de la planilla DGA: una medición y su comprobante.
class DgaRow {
  const DgaRow({
    required this.at,
    this.flow,
    this.total,
    this.waterTable,
    this.voucher,
  });

  /// Hora de Chile (reloj de pared).
  final DateTime at;
  final double? flow;
  final double? total;
  final double? waterTable;
  final String? voucher;

  bool get hasVoucher => isValidVoucher(voucher);
}

bool isValidVoucher(String? v) {
  final s = (v ?? '').trim();
  return s.isNotEmpty && s != '-' && s != '...' && s.toLowerCase() != 'null';
}

/// Un intento de envío reciente (`modules.m2` del punto).
class DgaAttempt {
  const DgaAttempt({
    required this.at,
    this.flow,
    this.total,
    this.waterTable,
    this.voucher,
    this.response,
    this.queued = false,
  });

  factory DgaAttempt.fromJson(Map<String, dynamic> json) => DgaAttempt(
    at: parseWallClock(json['date_time_medition']) ?? DateTime(1970),
    flow: _num(json['flow']),
    total: _num(json['total']),
    waterTable: _num(json['water_table']),
    voucher: json['n_voucher']?.toString(),
    response: json['return_dga']?.toString(),
    queued: json['send_dga'] == true,
  );

  final DateTime at;
  final double? flow;
  final double? total;
  final double? waterTable;
  final String? voucher;
  final String? response;
  final bool queued;

  DgaAttemptStatus get status {
    if (isValidVoucher(voucher)) return DgaAttemptStatus.sent;
    final r = (response ?? '').toLowerCase();
    if (r.contains('error') || r.contains('rechaz') || r.contains('fail')) {
      return DgaAttemptStatus.error;
    }
    if (queued) return DgaAttemptStatus.queued;
    return r.isEmpty ? DgaAttemptStatus.queued : DgaAttemptStatus.error;
  }
}

enum DgaAttemptStatus { sent, queued, error }

enum DgaSlotState { delivered, noVoucher, noData, inProgress }

/// Un tramo seguido de reportes con el mismo problema.
class DgaGap {
  const DgaGap(this.kind, this.start, this.end, this.count);

  final DgaSlotState kind;
  final DateTime start;
  final DateTime end;
  final int count;
}

class DgaDay {
  const DgaDay(this.date, this.slots);

  final DateTime date;
  final List<(DateTime, DgaSlotState)> slots;

  int count(DgaSlotState s) => slots.where((x) => x.$2 == s).length;
  int get expected =>
      slots.where((x) => x.$2 != DgaSlotState.inProgress).length;
  double? get ratio =>
      expected == 0 ? null : count(DgaSlotState.delivered) / expected;
}

class DgaCompliance {
  const DgaCompliance({
    required this.standard,
    required this.start,
    required this.end,
    required this.days,
    required this.gaps,
    required this.rows,
    required this.sent,
    this.maxFlow,
    this.exceedances = 0,
    this.nearLimit = 0,
    this.volume,
  });

  final DgaStandard standard;
  final DateTime start;
  final DateTime end;
  final List<DgaDay> days;
  final List<DgaGap> gaps;

  /// Todas las mediciones de la planilla, en orden cronológico.
  final List<DgaRow> rows;

  /// Mediciones que corresponden a un reporte DGA (las que se envían).
  final List<DgaRow> sent;

  final double? maxFlow;

  /// Mediciones sobre el caudal autorizado.
  final int exceedances;

  /// Mediciones entre el 90 % y el 100 % del caudal autorizado.
  final int nearLimit;

  /// Volumen del período según el totalizador (m³).
  final double? volume;

  int count(DgaSlotState s) => days.fold(0, (sum, d) => sum + d.count(s));
  int get expected => days.fold(0, (sum, d) => sum + d.expected);
  int get delivered => count(DgaSlotState.delivered);
  double? get rate => expected == 0 ? null : delivered / expected;

  DgaRow? get lastVoucher {
    for (final r in sent.reversed) {
      if (r.hasVoucher) return r;
    }
    return null;
  }
}

/// Evalúa el cumplimiento del período [start, end) con las filas de la
/// planilla DGA. Las horas desde [now] menos [grace] se consideran en
/// proceso (el cron envía cada pocos minutos).
DgaCompliance analyzeDgaCompliance(
  List<DgaRow> raw, {
  required DgaStandard standard,
  required int frequencyMinutes,
  required DateTime start,
  required DateTime end,
  double? authorizedFlow,
  DateTime? now,
  Duration grace = const Duration(minutes: 75),
}) {
  final clock = now ?? DateTime.now();
  final limit = end.isAfter(clock) ? clock : end;
  final rows = [...raw]..sort((a, b) => a.at.compareTo(b.at));
  final sent = [
    for (final r in rows)
      if (standard.sends(r.at, frequencyMinutes)) r,
  ];
  final byHour = <DateTime, List<DgaRow>>{};
  for (final r in sent) {
    byHour.putIfAbsent(_hourOf(r.at), () => []).add(r);
  }

  final days = <DgaDay>[];
  for (
    var d = DateTime(start.year, start.month, start.day);
    d.isBefore(limit);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final slots = <(DateTime, DgaSlotState)>[];
    for (var h = 0; h < 24; h++) {
      final hour = DateTime(d.year, d.month, d.day, h);
      if (hour.isBefore(start) || !hour.isBefore(limit)) continue;
      if (!standard.expectsAt(hour)) continue;
      final hits = byHour[hour] ?? const [];
      final state = hits.any((r) => r.hasVoucher)
          ? DgaSlotState.delivered
          : clock.difference(hour) < grace
          ? DgaSlotState.inProgress
          : hits.isEmpty
          ? DgaSlotState.noData
          : DgaSlotState.noVoucher;
      slots.add((hour, state));
    }
    days.add(DgaDay(d, slots));
  }

  final gaps = <DgaGap>[];
  DgaGap? open;
  for (final day in days) {
    for (final (hour, state) in day.slots) {
      final bad =
          state == DgaSlotState.noData || state == DgaSlotState.noVoucher;
      if (bad && open != null && open.kind == state) {
        open = DgaGap(state, open.start, hour, open.count + 1);
      } else {
        if (open != null) gaps.add(open);
        open = bad ? DgaGap(state, hour, hour, 1) : null;
      }
    }
  }
  if (open != null) gaps.add(open);

  final flows = rows.map((r) => r.flow).whereType<double>().toList();
  var exceed = 0;
  var near = 0;
  if (authorizedFlow != null && authorizedFlow > 0) {
    for (final q in flows) {
      if (q > authorizedFlow) {
        exceed++;
      } else if (q >= authorizedFlow * 0.9) {
        near++;
      }
    }
  }
  double? volume;
  final totals = rows.map((r) => r.total).whereType<double>().toList();
  if (totals.length > 1) {
    var v = 0.0;
    for (var i = 1; i < totals.length; i++) {
      final d = totals[i] - totals[i - 1];
      if (d > 0) v += d;
    }
    volume = v;
  }

  return DgaCompliance(
    standard: standard,
    start: start,
    end: limit,
    days: days,
    gaps: gaps,
    rows: rows,
    sent: sent,
    maxFlow: flows.isEmpty ? null : flows.reduce(math.max),
    exceedances: exceed,
    nearLimit: near,
    volume: volume,
  );
}

DateTime _hourOf(DateTime t) => DateTime(t.year, t.month, t.day, t.hour);

// ------------------------------------------------------------ planilla

/// Lee la planilla DGA (`/api/interaction_detail_dga/`, XLSX): columnas
/// Fecha, Caudal, Acumulado, Nivel Freático y Comprobante.
List<DgaRow> parseDgaWorkbook(Uint8List bytes) {
  final table = readXlsxRows(bytes);
  var header = -1;
  for (var i = 0; i < math.min(table.length, 10); i++) {
    if (table[i].any((c) => (c ?? '').toLowerCase().contains('comprobante'))) {
      header = i;
      break;
    }
  }
  int col(String key, int fallback) {
    if (header < 0) return fallback;
    final i = table[header].indexWhere(
      (c) => (c ?? '').toLowerCase().contains(key),
    );
    return i < 0 ? fallback : i;
  }

  final cDate = col('fecha', 0);
  final cFlow = col('caudal', 1);
  final cTotal = col('acumulado', 2);
  final cLevel = col('nivel', 3);
  final cVoucher = col('comprobante', 4);
  String? at(List<String?> row, int i) => i < row.length ? row[i] : null;

  final out = <DgaRow>[];
  for (var i = header + 1; i < table.length; i++) {
    final row = table[i];
    final date = parseWallClock(at(row, cDate));
    if (date == null) continue;
    out.add(
      DgaRow(
        at: date,
        flow: _num(at(row, cFlow)),
        total: _num(at(row, cTotal)),
        waterTable: _num(at(row, cLevel)),
        voucher: at(row, cVoucher)?.trim(),
      ),
    );
  }
  return out;
}

/// Filas de la primera hoja de un XLSX como texto (celdas vacías = null).
List<List<String?>> readXlsxRows(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? text(String name) {
    final f = zip.findFile(name);
    return f == null ? null : utf8.decode(f.content, allowMalformed: true);
  }

  final shared = <String>[];
  final sst = text('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(sst)) {
      shared.add(_texts(si.group(1)!));
    }
  }
  var sheet = text('xl/worksheets/sheet1.xml');
  if (sheet == null) {
    final first =
        zip.files
            .where((f) => f.name.startsWith('xl/worksheets/sheet'))
            .map((f) => f.name)
            .toList()
          ..sort();
    if (first.isEmpty) return const [];
    sheet = text(first.first)!;
  }

  final rows = <List<String?>>[];
  final cell = RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true);
  for (final row in RegExp(
    r'<row\b[^>]*>(.*?)</row>',
    dotAll: true,
  ).allMatches(sheet)) {
    final values = <String?>[];
    for (final c in cell.allMatches(row.group(1)!)) {
      final attrs = c.group(1)!;
      final body = c.group(2) ?? '';
      final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(attrs)?.group(1);
      final type = RegExp(r'\bt="(\w+)"').firstMatch(attrs)?.group(1);
      final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body);
      String? value;
      if (type == 's' && v != null) {
        final i = int.tryParse(v.group(1)!);
        value = i != null && i < shared.length ? shared[i] : null;
      } else if (type == 'inlineStr') {
        value = _texts(body);
      } else if (v != null) {
        value = _unescape(v.group(1)!);
      }
      final index = ref == null ? values.length : _columnIndex(ref);
      while (values.length < index) {
        values.add(null);
      }
      if (values.length == index) {
        values.add(value);
      } else {
        values[index] = value;
      }
    }
    rows.add(values);
  }
  return rows;
}

String _texts(String xml) => RegExp(
  r'<t\b[^>]*>(.*?)</t>',
  dotAll: true,
).allMatches(xml).map((m) => _unescape(m.group(1)!)).join();

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

int _columnIndex(String letters) {
  var n = 0;
  for (final c in letters.codeUnits) {
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

/// Fecha y hora "de pared" (sin convertir zona): ISO con o sin offset,
/// `dd/mm/aaaa hh:mm` o número de serie de Excel.
DateTime? parseWallClock(dynamic raw) {
  if (raw == null) return null;
  final s = '$raw'.trim();
  if (s.isEmpty) return null;
  final iso = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?',
  ).firstMatch(s);
  if (iso != null) {
    int g(int i) => int.tryParse(iso.group(i) ?? '') ?? 0;
    return DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
  }
  final cl = RegExp(
    r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
  ).firstMatch(s);
  if (cl != null) {
    int g(int i) => int.tryParse(cl.group(i) ?? '') ?? 0;
    return DateTime(g(3), g(2), g(1), g(4), g(5), g(6));
  }
  final serial = double.tryParse(s);
  if (serial != null && serial > 20000 && serial < 80000) {
    final ms = (serial * 86400000).round();
    final base = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: ms));
    return DateTime(
      base.year,
      base.month,
      base.day,
      base.hour,
      base.minute,
      base.second,
    );
  }
  return null;
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final s = '$v'.trim();
  if (s.isEmpty || s == '-') return null;
  return double.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'));
}
