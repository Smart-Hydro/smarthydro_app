import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/dashboard/point_history_sheet.dart';

void main() {
  test('lee un día del calendario y omite métricas sin dato', () {
    final day = HistoryDay.fromJson({
      'date': '2026-10-09',
      'has_data': true,
      'consumption_m3': 182.4,
      'records_count': 96,
      'avg_flow_lps': '4.2',
      'first_record': '2026-10-09T00:05:00',
      'last_record': '2026-10-09T23:55:00',
    });
    expect(day.date, DateTime(2026, 10, 9));
    expect(day.consumption, 182.4);
    expect(day.avgFlow, 4.2);
    expect(day.avgLevel, isNull);
    expect(day.records, 96);
    expect(day.first, isNotNull);
  });

  test('solo muestra métricas de variables que el punto tiene', () {
    final days = [
      HistoryDay.fromJson({
        'date': '2026-10-09',
        'has_data': true,
        'consumption_m3': 50,
        'records_count': 10,
        'avg_flow_lps': 3.1,
        'avg_nivel_m': 22.4,
      }),
    ];
    expect(
      historyMetricsFor(days, hasFlow: false, hasLevel: true, hasTotal: false),
      [HistoryMetric.level],
    );
    expect(
      historyMetricsFor(days, hasFlow: true, hasLevel: false, hasTotal: true),
      [HistoryMetric.consumption, HistoryMetric.flow],
    );
    expect(
      historyMetricsFor(days, hasFlow: false, hasLevel: false, hasTotal: false),
      [HistoryMetric.records],
    );
  });

  test('resume el período: total, promedio, pico y cobertura', () {
    final summary = HistorySummary.of([
      HistoryDay.fromJson({
        'date': '2026-10-07',
        'has_data': true,
        'consumption_m3': 100,
        'records_count': 90,
      }),
      HistoryDay.fromJson({
        'date': '2026-10-08',
        'has_data': false,
        'consumption_m3': 0,
        'records_count': 0,
      }),
      HistoryDay.fromJson({
        'date': '2026-10-09',
        'has_data': true,
        'consumption_m3': 200,
        'records_count': 96,
      }),
    ]);
    expect(summary.total, 300);
    expect(summary.dailyAverage, 150);
    expect(summary.peak?.date, DateTime(2026, 10, 9));
    expect(summary.daysWithData, 2);
    expect(summary.days, 3);
    expect(summary.records, 186);
  });
}
