import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/point_system.dart';

void main() {
  test('un evento coincide por el punto anidado o por el id', () {
    expect(
      systemItemMatchesPoint({
        'point': {'id': 12, 'title': 'Pozo'},
      }, 12),
      isTrue,
    );
    expect(systemItemMatchesPoint({'point_id': '12'}, 12), isTrue);
    expect(systemItemMatchesPoint({'id': 12, 'title': 'Otro'}, 12), isFalse);
  });

  test('un aviso de soporte coincide por los puntos del ticket', () {
    expect(
      systemItemMatchesPoint({
        'ticket': {
          'id': 99,
          'points': [
            {'id': 4},
          ],
        },
      }, 4),
      isTrue,
    );
    expect(
      systemItemMatchesPoint({
        'ticket': {
          'id': 4,
          'points': [
            {'id': 8},
          ],
        },
      }, 4),
      isFalse,
    );
  });
}
