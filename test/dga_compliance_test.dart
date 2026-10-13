import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/compliance/dga_compliance.dart';

Uint8List _xlsx(List<List<Object?>> rows) {
  final strings = <String>[];
  String cell(int r, int c, Object? v) {
    final ref = '${String.fromCharCode(65 + c)}${r + 1}';
    if (v == null) return '';
    if (v is num) return '<c r="$ref"><v>$v</v></c>';
    strings.add('$v');
    return '<c r="$ref" t="s"><v>${strings.length - 1}</v></c>';
  }

  final body = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    body.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      body.write(cell(r, c, rows[r][c]));
    }
    body.write('</row>');
  }
  final sheet =
      '<?xml version="1.0"?><worksheet><sheetData>$body</sheetData></worksheet>';
  final sst =
      '<?xml version="1.0"?><sst>${strings.map((s) => '<si><t>$s</t></si>').join()}</sst>';
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheet)))
    ..addFile(ArchiveFile.bytes('xl/sharedStrings.xml', utf8.encode(sst)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('lee la planilla DGA con comprobantes', () {
    final rows = parseDgaWorkbook(
      _xlsx([
        [
          'Fecha',
          'Caudal (l/s)',
          'Acumulado (m³)',
          'Nivel Freático (m)',
          'Comprobante',
        ],
        ['2026-10-05T10:00:00-03:00', 8.2, 1500.5, 24.1, 'ABC123'],
        ['2026-10-05T10:15:00-03:00', 8.4, 1508, null, '-'],
        [46300.5, 1, 2, 3, 'X9'],
      ]),
    );
    expect(rows, hasLength(3));
    expect(rows[0].at, DateTime(2026, 10, 5, 10));
    expect(rows[0].flow, 8.2);
    expect(rows[0].voucher, 'ABC123');
    expect(rows[0].hasVoucher, isTrue);
    expect(rows[1].hasVoucher, isFalse);
    expect(rows[1].waterTable, isNull);
    expect(rows[2].at.hour, 12);
  });

  test('estándar Mayor: un reporte por hora con la medición de los :00', () {
    final start = DateTime(2026, 10, 5);
    final end = DateTime(2026, 10, 6);
    final rows = <DgaRow>[
      for (var h = 0; h < 24; h++)
        for (final m in [0, 15, 30, 45])
          if (!(h >= 3 && h < 6))
            DgaRow(
              at: DateTime(2026, 10, 5, h, m),
              flow: h == 12 ? 13 : 8,
              total: 1000.0 + h * 4 + m / 15,
              voucher: m == 0 && h != 9 ? 'V$h' : '-',
            ),
    ];
    final c = analyzeDgaCompliance(
      rows,
      standard: DgaStandard.mayor,
      frequencyMinutes: 15,
      start: start,
      end: end,
      authorizedFlow: 12,
      now: DateTime(2026, 10, 7),
    );
    expect(c.expected, 24);
    expect(c.delivered, 20);
    expect(c.count(DgaSlotState.noData), 3);
    expect(c.count(DgaSlotState.noVoucher), 1);
    expect(c.gaps, hasLength(2));
    expect(c.gaps.first.kind, DgaSlotState.noData);
    expect(c.gaps.first.count, 3);
    expect(c.gaps.first.start, DateTime(2026, 10, 5, 3));
    expect(c.sent, hasLength(21));
    expect(c.exceedances, 4);
    expect(c.rate, closeTo(20 / 24, 1e-9));
  });

  test('estándar Medio: solo exige el reporte de las 00:00', () {
    final c = analyzeDgaCompliance(
      [
        for (var d = 1; d <= 3; d++)
          DgaRow(at: DateTime(2026, 10, d), voucher: d == 2 ? '-' : 'V$d'),
        DgaRow(at: DateTime(2026, 10, 1, 13), voucher: '-'),
      ],
      standard: DgaStandard.medio,
      frequencyMinutes: 60,
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 4),
      now: DateTime(2026, 10, 10),
    );
    expect(c.expected, 3);
    expect(c.delivered, 2);
    expect(c.count(DgaSlotState.noVoucher), 1);
  });

  test('la hora en curso queda en proceso y no cuenta como falta', () {
    final c = analyzeDgaCompliance(
      const [],
      standard: DgaStandard.mayor,
      frequencyMinutes: 60,
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 10, 6),
      now: DateTime(2026, 10, 5, 2, 30),
    );
    expect(c.count(DgaSlotState.noData), 2);
    expect(c.count(DgaSlotState.inProgress), 1);
    expect(c.expected, 2);
  });

  test('clasifica los intentos de envío recientes', () {
    expect(
      DgaAttempt.fromJson({
        'date_time_medition': '2026-10-05T10:00:00-03:00',
        'n_voucher': 'ABC',
        'return_dga': 'ok',
      }).status,
      DgaAttemptStatus.sent,
    );
    expect(
      DgaAttempt.fromJson({
        'date_time_medition': '2026-10-05T10:00:00-03:00',
        'n_voucher': '-',
        'return_dga': 'Error de validación',
      }).status,
      DgaAttemptStatus.error,
    );
    expect(
      DgaAttempt.fromJson({
        'date_time_medition': '2026-10-05T10:00:00-03:00',
        'n_voucher': '-',
        'send_dga': true,
      }).status,
      DgaAttemptStatus.queued,
    );
  });
}
