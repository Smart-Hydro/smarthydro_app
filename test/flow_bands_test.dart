import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/compliance/flow_bands.dart';

void main() {
  const authorized = 10;

  test('separa sobre el caudal y cercano al límite', () {
    final records = [
      {'date_time': '2026-10-01T10:00:00', 'flow': 10.5},
      {'date_time': '2026-10-02T10:00:00', 'flow': 9.2},
      {'date_time': '2026-10-03T10:00:00', 'flow': 10},
      {'date_time': '2026-10-04T10:00:00', 'flow': 4},
      {'date_time': '2026-10-05T10:00:00', 'flow': null},
    ];

    final over = readingsInBand(records, authorized, FlowBand.over);
    final near = readingsInBand(records, authorized, FlowBand.near);

    expect(over.map((row) => row['flow']), [10.5]);
    expect(near.map((row) => row['flow']), [10, 9.2]);
  });

  test('si el detalle remoto viene vacío, muestra las lecturas del período', () {
    final period = [
      {'date_time': '2026-10-08T08:00:00', 'flow': 12},
      {'date_time': '2026-10-08T09:00:00', 'flow': 9.5},
    ];

    final over = visibleBandReadings(
      periodRecords: period,
      remoteRows: const [],
      authorized: authorized,
      band: FlowBand.over,
    );
    final near = visibleBandReadings(
      periodRecords: period,
      remoteRows: const [],
      authorized: authorized,
      band: FlowBand.near,
    );

    expect(over.single['flow'], 12);
    expect(near.single['flow'], 9.5);
  });

  test('el detalle remoto se muestra cuando sí trae filas', () {
    final remote = [
      {'date_time': '2026-09-01T08:00:00', 'flow': 14},
    ];

    final over = visibleBandReadings(
      periodRecords: const [
        {'date_time': '2026-10-08T08:00:00', 'flow': 11},
      ],
      remoteRows: remote,
      authorized: authorized,
      band: FlowBand.over,
    );

    expect(over.single['flow'], 14);
  });
}
