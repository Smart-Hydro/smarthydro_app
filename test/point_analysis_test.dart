import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/features/analysis/point_analysis.dart';

final _start = DateTime(2026, 10, 5);
final _end = DateTime(2026, 10, 6);

/// Un día cada 15 min: bombea 8–18 h a 10 L/s, nivel 20 m en reposo y 25 m
/// bombeando, totalizador coherente con el caudal.
List<AnalysisSample> _healthyDay() {
  final out = <AnalysisSample>[];
  var total = 1000.0;
  for (var i = 0; i < 96; i++) {
    final at = _start.add(Duration(minutes: 15 * i));
    final on = at.hour >= 8 && at.hour < 18;
    final jitter = (i % 3 - 1) * 0.05;
    final flow = on ? 10 + jitter : 0.0;
    out.add(
      AnalysisSample(
        at: at,
        flow: flow,
        total: total,
        level: (on ? 25 : 20) + jitter,
      ),
    );
    total += flow * 0.25 * 3.6;
  }
  return out;
}

PointAnalysis _run(List<AnalysisSample> samples, {double? maxFlow}) =>
    analyzePoint(
      samples,
      start: _start,
      end: _end,
      hasFlow: true,
      hasLevel: true,
      hasTotal: true,
      frequencyMinutes: 15,
      maxFlowLimit: maxFlow,
      wellDepth: 80,
      now: _end,
    );

void main() {
  test('lee una lectura de la API', () {
    final s = AnalysisSample.fromJson({
      'date_time': '2026-10-05T08:15:00-03:00',
      'flow': '8.2',
      'total': 1234.5,
      'nivel': null,
      'is_error': true,
    });
    expect(s.flow, 8.2);
    expect(s.total, 1234.5);
    expect(s.level, isNull);
    expect(s.isError, isTrue);
  });

  test('un pozo sano no tiene hallazgos y calcula su rendimiento', () {
    final a = _run(_healthyDay(), maxFlow: 12);
    expect(a.findings.map((f) => f.title), isEmpty);
    expect(a.score, greaterThanOrEqualTo(95));
    expect(a.operatingHoursPerDay, closeTo(10, 0.5));
    expect(a.startsPerDay, closeTo(1, 0.01));
    expect(a.avgOperatingFlow, closeTo(10, 0.05));
    expect(a.consumption, closeTo(360, 2));
    expect(a.staticLevel, closeTo(20, 0.05));
    expect(a.dynamicLevel, closeTo(25, 0.05));
    expect(a.drawdown, closeTo(5, 0.1));
    expect(a.specificCapacity, closeTo(2, 0.05));
    expect(a.hourlyFlow![12], closeTo(10, 0.05));
    expect(a.hourlyFlow![3], 0);
  });

  test('detecta cortes, totalizador que retrocede y caudal excesivo', () {
    final day = _healthyDay();
    final samples = [
      ...day.take(20),
      ...day.skip(40).take(20),
      AnalysisSample(at: day[60].at, flow: 20, total: 10, level: 25),
      ...day.skip(61),
    ];
    final a = _run(samples, maxFlow: 12);
    final titles = a.findings.map((f) => f.title).toList();
    expect(titles.any((t) => t.contains('corte')), isTrue);
    expect(titles, contains('El totalizador retrocedió'));
    expect(titles, contains('Caudal sobre el máximo configurado'));
    expect(a.findings.first.level, FindingLevel.critical);
    expect(a.score, lessThan(70));
    expect(a.coverage, lessThan(0.85));
  });

  test('avisa cuando el equipo dejó de transmitir', () {
    final a = analyzePoint(
      _healthyDay().take(40).toList(),
      start: _start,
      end: _end,
      hasFlow: true,
      hasLevel: true,
      hasTotal: true,
      frequencyMinutes: 15,
      now: _end,
    );
    expect(a.findings.first.title, startsWith('Sin transmitir hace'));
    expect(a.findings.first.level, FindingLevel.critical);
  });

  test('solo revisa las variables que tiene el punto', () {
    final a = analyzePoint(
      _healthyDay(),
      start: _start,
      end: _end,
      hasFlow: false,
      hasLevel: true,
      hasTotal: false,
      frequencyMinutes: 15,
      now: _end,
    );
    expect(a.hourlyFlow, isNull);
    expect(a.consumption, isNull);
    expect(a.operatingHoursPerDay, isNull);
    expect(a.staticLevel, isNotNull);
  });
}
