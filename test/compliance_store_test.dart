import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/compliance/compliance_store.dart';
import 'package:smarthydro_app/features/compliance/dga_compliance.dart';

void main() {
  test('el listado fresco se reusa y Actualizar lo tira', () {
    var now = DateTime(2026, 4, 1, 12);
    final store = ComplianceStore(clock: () => now);
    expect(store.list('tok'), isNull);

    store.putList('tok', [
      {'point_id': 7, 'point_name': 'Norte'},
    ]);
    expect(store.listIsFresh('tok'), isTrue);
    expect(store.pointOnList('tok', 7)?['point_name'], 'Norte');

    now = now.add(const Duration(minutes: 6));
    expect(store.listIsFresh('tok'), isFalse);
    expect(store.list('tok'), isNotNull);

    store.invalidate('tok');
    expect(store.list('tok'), isNull);
  });

  test('la planilla del mes queda por punto y mes', () {
    final store = ComplianceStore();
    final month = DateTime(2026, 3, 1);
    final snap = ComplianceMonthSnap(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      compliance: analyzeDgaCompliance(
        const [],
        standard: DgaStandard.mayor,
        frequencyMinutes: 60,
        start: month,
        end: DateTime(2026, 4, 1),
        now: DateTime(2026, 3, 15),
      ),
    );
    store.putMonth('tok', 4, month, snap);
    expect(store.monthIsFresh('tok', 4, month), isTrue);
    expect(store.month('tok', 4, month)?.bytes.length, 3);
    expect(store.month('tok', 4, DateTime(2026, 2, 1)), isNull);
  });
}
