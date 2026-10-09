import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/point_link.dart';

void main() {
  test('una regla configurada no pinta el punto como incidencia', () {
    final point = {
      'alerts_count': 4,
      'active': true,
      'latest_telemetry': {
        'date_time_medition': '2026-10-08T12:00:00',
        'days_not_connection': 0,
        'is_error': false,
        'flow': 12.4,
      },
    };

    expect(pointLinkOf(point), PointLink.connected);
  });

  test('sin lectura vigente es un hueco', () {
    final point = {
      'alerts_count': 0,
      'latest_telemetry': {
        'date_time_medition': null,
        'days_not_connection': 0,
        'is_error': false,
      },
    };

    expect(pointLinkOf(point), PointLink.gap);
  });

  test('la última lectura con error es una incidencia', () {
    final point = {
      'latest_telemetry': {
        'date_time_medition': '2026-10-08T12:00:00',
        'days_not_connection': 0,
        'is_error': true,
      },
    };

    expect(pointLinkOf(point), PointLink.incident);
  });

  test('días sin conexión marcan hueco aunque la regla exista', () {
    final point = {
      'alerts_count': 2,
      'latest_telemetry': {
        'date_time_medition': '2026-10-01T12:00:00',
        'days_not_connection': 3,
        'is_error': false,
      },
    };

    expect(pointLinkOf(point), PointLink.gap);
  });
}
