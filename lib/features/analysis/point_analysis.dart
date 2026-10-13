import 'dart:math' as math;

/// Una lectura del punto (`/api/ik/point/<id>/records/`).
class AnalysisSample {
  const AnalysisSample({
    required this.at,
    this.flow,
    this.total,
    this.level,
    this.isError = false,
    this.loggerAt,
  });

  factory AnalysisSample.fromJson(Map<String, dynamic> json) {
    final at =
        DateTime.tryParse(
          '${json['date_time'] ?? json['date_time_medition']}',
        )?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return AnalysisSample(
      at: at,
      flow: _opt(json['flow']),
      total: _opt(json['total']),
      level: _opt(json['nivel']),
      isError: json['is_error'] == true,
      loggerAt: DateTime.tryParse(
        '${json['date_time_last_logger']}',
      )?.toLocal(),
    );
  }

  final DateTime at;
  final double? flow;
  final double? total;
  final double? level;
  final bool isError;
  final DateTime? loggerAt;
}

enum FindingLevel { critical, warning, info, ok }

/// Un hallazgo del análisis: qué pasó, cuándo y qué revisar.
class AnalysisFinding {
  const AnalysisFinding({
    required this.level,
    required this.title,
    required this.detail,
    this.at,
    this.action,
  });

  final FindingLevel level;
  final String title;
  final String detail;
  final DateTime? at;
  final String? action;
}

class AnalysisGap {
  const AnalysisGap(this.start, this.end);

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

/// Resultado del análisis de rendimiento y errores de un punto.
class PointAnalysis {
  const PointAnalysis({
    required this.samples,
    required this.start,
    required this.end,
    required this.interval,
    required this.coverage,
    required this.gaps,
    required this.findings,
    required this.score,
    this.operatingHoursPerDay,
    this.startsPerDay,
    this.avgOperatingFlow,
    this.maxFlow,
    this.p95Flow,
    this.consumption,
    this.staticLevel,
    this.dynamicLevel,
    this.drawdown,
    this.specificCapacity,
    this.hourlyFlow,
    this.hourlyOn,
    this.hourlySamples,
    this.operatingThreshold,
    this.operatingHours,
    this.starts,
    this.days = 1,
    this.flowReadings = 0,
    this.runningReadings = 0,
    this.totalFirst,
    this.totalLast,
    this.totalResets = 0,
    this.restingReadings = 0,
    this.pumpingReadings = 0,
  });

  final List<AnalysisSample> samples;
  final DateTime start;
  final DateTime end;
  final Duration interval;
  final double coverage;
  final List<AnalysisGap> gaps;
  final List<AnalysisFinding> findings;
  final int score;

  final double? operatingHoursPerDay;
  final double? startsPerDay;
  final double? avgOperatingFlow;
  final double? maxFlow;
  final double? p95Flow;
  final double? consumption;
  final double? staticLevel;
  final double? dynamicLevel;
  final double? drawdown;
  final double? specificCapacity;

  /// Caudal promedio por hora del día (0..23); nulo si no hay caudal.
  final List<double?>? hourlyFlow;

  /// Fracción de las lecturas de cada hora con la bomba encendida.
  final List<double?>? hourlyOn;

  /// Lecturas de caudal que cayeron en cada hora del día.
  final List<int>? hourlySamples;

  /// Caudal sobre el cual se considera la bomba encendida (L/s).
  final double? operatingThreshold;

  /// Horas totales de bombeo en el período.
  final double? operatingHours;

  /// Arranques totales en el período.
  final int? starts;

  /// Días que abarca el período (puede incluir un día en curso).
  final double days;

  /// Lecturas con caudal y, de ellas, las con la bomba encendida.
  final int flowReadings;
  final int runningReadings;

  /// Totalizador en la primera y la última lectura del período (m³).
  final double? totalFirst;
  final double? totalLast;

  /// Veces que el totalizador retrocedió; esos tramos no se restan.
  final int totalResets;

  /// Lecturas de nivel con la bomba detenida y encendida.
  final int restingReadings;
  final int pumpingReadings;

  int count(FindingLevel level) =>
      findings.where((f) => f.level == level).length;
}

/// Analiza las lecturas de un período. Solo evalúa las variables que el
/// punto tiene ([hasFlow], [hasLevel], [hasTotal]).
PointAnalysis analyzePoint(
  List<AnalysisSample> raw, {
  required DateTime start,
  required DateTime end,
  required bool hasFlow,
  required bool hasLevel,
  required bool hasTotal,
  double? frequencyMinutes,
  double? maxFlowLimit,
  double? wellDepth,
  DateTime? now,
}) {
  final samples = [...raw]..sort((a, b) => a.at.compareTo(b.at));
  final findings = <AnalysisFinding>[];
  final interval = _interval(samples, frequencyMinutes);
  final gapLimit = Duration(
    seconds: math
        .max(interval.inSeconds * 2.5, interval.inSeconds + 600)
        .round(),
  );

  // ----------------------------------------------------------- transmisión
  final gaps = <AnalysisGap>[];
  for (var i = 1; i < samples.length; i++) {
    final a = samples[i - 1].at;
    final b = samples[i].at;
    if (b.difference(a) > gapLimit) gaps.add(AnalysisGap(a, b));
  }
  final clock = now ?? DateTime.now();
  final periodEnd = end.isAfter(clock) ? clock : end;
  final span = periodEnd.difference(start);
  final expected = span.inSeconds / math.max(1, interval.inSeconds);
  final coverage = samples.isEmpty
      ? 0.0
      : (samples.length / math.max(1, expected)).clamp(0.0, 1.0).toDouble();

  if (samples.isNotEmpty) {
    final silence = periodEnd.difference(samples.last.at);
    if (silence > gapLimit && end.isAfter(clock.subtract(gapLimit))) {
      findings.add(
        AnalysisFinding(
          level: silence > const Duration(hours: 6)
              ? FindingLevel.critical
              : FindingLevel.warning,
          title: 'Sin transmitir hace ${_duration(silence)}',
          detail:
              'El último registro llegó el ${_stamp(samples.last.at)}. '
              'Se esperaba uno cada ${_duration(interval)}.',
          at: samples.last.at,
          action: 'Revisa energía, señal y antena del datalogger.',
        ),
      );
    }
  }
  if (gaps.isNotEmpty) {
    final lost = gaps.fold(Duration.zero, (sum, g) => sum + g.duration);
    final longest = gaps.reduce((a, b) => a.duration > b.duration ? a : b);
    findings.add(
      AnalysisFinding(
        level: longest.duration > const Duration(hours: 6)
            ? FindingLevel.warning
            : FindingLevel.info,
        title:
            '${gaps.length} ${gaps.length == 1 ? 'corte' : 'cortes'} de '
            'transmisión',
        detail:
            'Suman ${_duration(lost)} sin datos. El más largo duró '
            '${_duration(longest.duration)}, desde el ${_stamp(longest.start)}.',
        at: longest.start,
        action: gaps.length >= 5
            ? 'Cortes frecuentes suelen indicar señal débil o energía '
                  'intermitente.'
            : null,
      ),
    );
  }

  final flagged = samples.where((s) => s.isError).toList();
  if (flagged.isNotEmpty) {
    findings.add(
      AnalysisFinding(
        level: flagged.length > samples.length * 0.05
            ? FindingLevel.warning
            : FindingLevel.info,
        title: 'El equipo marcó ${flagged.length} lecturas con error',
        detail:
            'Primera el ${_stamp(flagged.first.at)}. Esas lecturas pueden '
            'traer valores inválidos.',
        at: flagged.first.at,
        action: 'Revisa el cableado del sensor y la configuración del canal.',
      ),
    );
  }

  final lags = [
    for (final s in samples)
      if (s.loggerAt != null) s.at.difference(s.loggerAt!).abs().inMinutes,
  ];
  if (lags.length >= 10) {
    final lag = _median(lags.map((e) => e.toDouble()).toList());
    if (lag > 60) {
      findings.add(
        AnalysisFinding(
          level: FindingLevel.info,
          title: 'Reloj del datalogger desfasado',
          detail:
              'La hora del equipo difiere en ${_duration(Duration(minutes: lag.round()))} '
              'de la hora de recepción.',
          action: 'Sincroniza la hora del datalogger.',
        ),
      );
    }
  }

  bool continuous(int i) =>
      i > 0 && samples[i].at.difference(samples[i - 1].at) <= gapLimit;
  double dtHours(int i) =>
      samples[i].at.difference(samples[i - 1].at).inSeconds / 3600;
  final days = math.max(1.0, span.inMinutes / 1440);

  // ------------------------------------------------------------- caudal
  double? operatingHoursPerDay;
  double? startsPerDay;
  double? avgOperatingFlow;
  double? maxFlow;
  double? p95Flow;
  List<double?>? hourlyFlow;
  List<double?>? hourlyOn;
  List<int>? hourlySamples;
  double? operatingHours;
  int? startCount;
  var threshold = 0.05;
  var runningReadings = 0;
  final flows = [
    for (final s in samples)
      if (s.flow != null) s.flow!,
  ];
  if (hasFlow && flows.isNotEmpty) {
    maxFlow = flows.reduce(math.max);
    threshold = math.max(0.05, maxFlow * 0.02);
    final sorted = [...flows]..sort();
    p95Flow = sorted[((sorted.length - 1) * 0.95).round()];
    final running = flows.where((q) => q > threshold).toList();
    runningReadings = running.length;
    avgOperatingFlow = running.isEmpty
        ? 0
        : running.reduce((a, b) => a + b) / running.length;

    var hours = 0.0;
    var starts = 0;
    for (var i = 1; i < samples.length; i++) {
      if (!continuous(i)) continue;
      final prev = samples[i - 1].flow;
      final cur = samples[i].flow;
      if (prev == null || cur == null) continue;
      if (prev > threshold) hours += dtHours(i);
      if (prev <= threshold && cur > threshold) starts++;
    }
    operatingHours = hours;
    startCount = starts;
    operatingHoursPerDay = hours / days;
    startsPerDay = starts / days;

    final buckets = List.generate(24, (_) => <double>[]);
    for (final s in samples) {
      if (s.flow != null) buckets[s.at.hour].add(s.flow!);
    }
    hourlyFlow = [
      for (final b in buckets)
        b.isEmpty ? null : b.reduce((a, c) => a + c) / b.length,
    ];
    hourlyOn = [
      for (final b in buckets)
        b.isEmpty ? null : b.where((q) => q > threshold).length / b.length,
    ];
    hourlySamples = [for (final b in buckets) b.length];

    final negative = samples.where((s) => (s.flow ?? 0) < 0).toList();
    if (negative.isNotEmpty) {
      findings.add(
        AnalysisFinding(
          level: FindingLevel.critical,
          title: 'Caudal negativo en ${negative.length} lecturas',
          detail:
              'Un caudal bajo cero no es físico. Primera el '
              '${_stamp(negative.first.at)}.',
          at: negative.first.at,
          action: 'Revisa la escala y el sentido del sensor de caudal.',
        ),
      );
    }
    if (maxFlowLimit != null && maxFlowLimit > 0) {
      final over = samples
          .where((s) => (s.flow ?? 0) > maxFlowLimit * 1.05)
          .toList();
      if (over.isNotEmpty) {
        final peak = over.reduce((a, b) => a.flow! > b.flow! ? a : b);
        findings.add(
          AnalysisFinding(
            level: FindingLevel.warning,
            title: 'Caudal sobre el máximo configurado',
            detail:
                '${over.length} lecturas superan ${_n(maxFlowLimit, 1)} L/s. '
                'El pico fue ${_n(peak.flow!, 2)} L/s el ${_stamp(peak.at)}.',
            at: peak.at,
            action: 'Verifica el régimen de extracción y el límite autorizado.',
          ),
        );
      }
    }
    final frozen = _frozenRun(
      samples,
      (s) => s.flow,
      minRun: 12,
      ignore: (v) => v <= threshold,
    );
    if (frozen != null) {
      findings.add(
        AnalysisFinding(
          level: FindingLevel.warning,
          title: 'Caudal congelado',
          detail:
              'Repitió exactamente ${_n(frozen.value, 2)} L/s en '
              '${frozen.length} lecturas seguidas desde el ${_stamp(frozen.at)}.',
          at: frozen.at,
          action: 'Un valor que no varía suele ser un sensor trabado.',
        ),
      );
    }
    if (startsPerDay > 12) {
      findings.add(
        AnalysisFinding(
          level: FindingLevel.warning,
          title: 'Muchos arranques de bomba',
          detail:
              'Promedia ${_n(startsPerDay, 1)} arranques por día. Los ciclos '
              'cortos desgastan el motor y el arrancador.',
          action: 'Revisa el control de nivel o el presostato.',
        ),
      );
    }
  }

  // --------------------------------------------------------- totalizador
  double? consumption;
  double? totalFirst;
  double? totalLast;
  var totalResets = 0;
  final totals = [
    for (final s in samples)
      if (s.total != null) s,
  ];
  if (hasTotal && totals.length >= 2) {
    var sum = 0.0;
    final regressions = <AnalysisSample>[];
    for (var i = 1; i < totals.length; i++) {
      final d = totals[i].total! - totals[i - 1].total!;
      if (d < -0.5) {
        regressions.add(totals[i]);
      } else if (d > 0) {
        sum += d;
      }
    }
    consumption = sum;
    totalFirst = totals.first.total;
    totalLast = totals.last.total;
    totalResets = regressions.length;
    if (regressions.isNotEmpty) {
      findings.add(
        AnalysisFinding(
          level: FindingLevel.critical,
          title: 'El totalizador retrocedió',
          detail:
              'Bajó ${regressions.length} '
              '${regressions.length == 1 ? 'vez' : 'veces'}; la primera el '
              '${_stamp(regressions.first.at)}. Un totalizador solo debería subir.',
          at: regressions.first.at,
          action: 'Puede ser un reinicio del equipo o un cambio de medidor.',
        ),
      );
    }

    if (hasFlow && flows.isNotEmpty) {
      var integrated = 0.0;
      var stalled = Duration.zero;
      var stalledLongest = Duration.zero;
      DateTime? stalledAt;
      DateTime? runStart;
      for (var i = 1; i < samples.length; i++) {
        if (!continuous(i)) {
          stalled = Duration.zero;
          continue;
        }
        final a = samples[i - 1];
        final b = samples[i];
        if (a.flow != null) integrated += a.flow! * dtHours(i) * 3.6;
        final moving = (a.flow ?? 0) > threshold;
        final counted =
            a.total != null && b.total != null && b.total! > a.total!;
        if (moving && !counted && a.total != null && b.total != null) {
          if (stalled == Duration.zero) runStart = a.at;
          stalled += b.at.difference(a.at);
          if (stalled > stalledLongest) {
            stalledLongest = stalled;
            stalledAt = runStart;
          }
        } else {
          stalled = Duration.zero;
        }
      }
      if (stalledLongest >= const Duration(hours: 2)) {
        findings.add(
          AnalysisFinding(
            level: FindingLevel.warning,
            title: 'El totalizador no avanzó con caudal',
            detail:
                'Hubo caudal durante ${_duration(stalledLongest)} sin que el '
                'totalizador sumara volumen.',
            at: stalledAt,
            action: 'Revisa la salida de pulsos del flujómetro.',
          ),
        );
      }
      if (integrated > 5 && sum > 0) {
        final gap = (sum - integrated).abs() / math.max(sum, integrated);
        if (gap > 0.15) {
          findings.add(
            AnalysisFinding(
              level: FindingLevel.warning,
              title: 'Caudal y totalizador no cuadran',
              detail:
                  'El totalizador suma ${_n(sum, 1)} m³ y el caudal integrado '
                  'da ${_n(integrated, 1)} m³ (${(gap * 100).round()} % de '
                  'diferencia).',
              action:
                  'Suele deberse al factor de pulsos o a la escala del sensor.',
            ),
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------- nivel
  double? staticLevel;
  double? dynamicLevel;
  double? drawdown;
  double? specificCapacity;
  var restingReadings = 0;
  var pumpingReadings = 0;
  final levels = [
    for (final s in samples)
      if (s.level != null) s,
  ];
  if (hasLevel && levels.isNotEmpty) {
    final resting = [
      for (final s in levels)
        if (!hasFlow || (s.flow ?? 0) <= threshold) s.level!,
    ];
    final pumping = [
      for (final s in levels)
        if (hasFlow && (s.flow ?? 0) > threshold) s.level!,
    ];
    restingReadings = resting.length;
    pumpingReadings = pumping.length;
    if (resting.isNotEmpty) staticLevel = _median(resting);
    if (pumping.isNotEmpty) dynamicLevel = _median(pumping);
    if (staticLevel != null && dynamicLevel != null) {
      drawdown = dynamicLevel - staticLevel;
      if (drawdown > 0.05 && (avgOperatingFlow ?? 0) > 0) {
        specificCapacity = avgOperatingFlow! / drawdown;
      }
    }

    final outside = levels
        .where(
          (s) => s.level! < 0 || (wellDepth != null && s.level! > wellDepth),
        )
        .toList();
    if (outside.isNotEmpty) {
      findings.add(
        AnalysisFinding(
          level: FindingLevel.critical,
          title: 'Nivel fuera del pozo',
          detail: wellDepth == null
              ? '${outside.length} lecturas de nivel bajo cero.'
              : '${outside.length} lecturas fuera de 0–${_n(wellDepth, 0)} m '
                    '(profundidad del pozo).',
          at: outside.first.at,
          action: 'Revisa la calibración y el largo de cable del sensor.',
        ),
      );
    }
    final jumpLimit = math.max(5.0, (wellDepth ?? 0) * 0.2);
    var jumps = 0;
    DateTime? jumpAt;
    for (var i = 1; i < samples.length; i++) {
      final a = samples[i - 1].level;
      final b = samples[i].level;
      if (a == null || b == null || !continuous(i)) continue;
      if ((b - a).abs() > jumpLimit) {
        jumps++;
        jumpAt ??= samples[i].at;
      }
    }
    if (jumps > 0) {
      findings.add(
        AnalysisFinding(
          level: FindingLevel.warning,
          title: 'Saltos bruscos de nivel',
          detail:
              '$jumps cambios de más de ${_n(jumpLimit, 0)} m entre lecturas '
              'seguidas. El agua no se mueve tan rápido.',
          at: jumpAt,
          action: 'Suele ser ruido eléctrico o un sensor con humedad.',
        ),
      );
    }
    final frozen = _frozenRun(samples, (s) => s.level, minRun: 48);
    if (frozen != null) {
      findings.add(
        AnalysisFinding(
          level: FindingLevel.info,
          title: 'Nivel sin variación',
          detail:
              'Marcó ${_n(frozen.value, 2)} m en ${frozen.length} lecturas '
              'seguidas desde el ${_stamp(frozen.at)}.',
          at: frozen.at,
          action: 'Confirma que el sensor responde.',
        ),
      );
    }
  }

  // ---------------------------------------------------------------- puntaje
  var score = 100.0;
  for (final f in findings) {
    score -= switch (f.level) {
      FindingLevel.critical => 28,
      FindingLevel.warning => 12,
      FindingLevel.info => 3,
      FindingLevel.ok => 0,
    };
  }
  score -= (1 - coverage) * 30;
  findings.sort((a, b) => a.level.index.compareTo(b.level.index));

  return PointAnalysis(
    samples: samples,
    start: start,
    end: periodEnd,
    interval: interval,
    coverage: coverage,
    gaps: gaps,
    findings: findings,
    score: score.clamp(0, 100).round(),
    operatingHoursPerDay: operatingHoursPerDay,
    startsPerDay: startsPerDay,
    avgOperatingFlow: avgOperatingFlow,
    maxFlow: maxFlow,
    p95Flow: p95Flow,
    consumption: consumption,
    staticLevel: staticLevel,
    dynamicLevel: dynamicLevel,
    drawdown: drawdown,
    specificCapacity: specificCapacity,
    hourlyFlow: hourlyFlow,
    hourlyOn: hourlyOn,
    hourlySamples: hourlySamples,
    operatingThreshold: hasFlow && flows.isNotEmpty ? threshold : null,
    operatingHours: operatingHours,
    starts: startCount,
    days: days,
    flowReadings: hasFlow ? flows.length : 0,
    runningReadings: runningReadings,
    totalFirst: totalFirst,
    totalLast: totalLast,
    totalResets: totalResets,
    restingReadings: restingReadings,
    pumpingReadings: pumpingReadings,
  );
}

Duration _interval(List<AnalysisSample> samples, double? minutes) {
  if (minutes != null && minutes > 0) {
    return Duration(seconds: (minutes * 60).round());
  }
  if (samples.length < 3) return const Duration(minutes: 15);
  final deltas = [
    for (var i = 1; i < samples.length; i++)
      samples[i].at.difference(samples[i - 1].at).inSeconds.toDouble(),
  ].where((d) => d > 0).toList();
  if (deltas.isEmpty) return const Duration(minutes: 15);
  return Duration(seconds: _median(deltas).round().clamp(60, 86400));
}

({double value, int length, DateTime at})? _frozenRun(
  List<AnalysisSample> samples,
  double? Function(AnalysisSample) read, {
  required int minRun,
  bool Function(double value)? ignore,
}) {
  ({double value, int length, DateTime at})? best;
  double? value;
  var length = 0;
  DateTime? at;
  for (final s in samples) {
    final v = read(s);
    if (v != null && v == value && !(ignore?.call(v) ?? false)) {
      length++;
    } else {
      value = v;
      length = v == null ? 0 : 1;
      at = s.at;
    }
    if (length >= minRun && (best == null || length > best.length)) {
      best = (value: value!, length: length, at: at!);
    }
  }
  return best;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

String _n(double v, int decimals) {
  final fixed = v.abs().toStringAsFixed(decimals).split('.');
  final digits = fixed.first;
  final out = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  if (fixed.length > 1) out.write(',${fixed[1]}');
  return out.toString();
}

String _duration(Duration d) {
  if (d.inDays >= 1) {
    final h = d.inHours % 24;
    return h == 0 ? '${d.inDays} d' : '${d.inDays} d $h h';
  }
  if (d.inHours >= 1) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  return '${math.max(1, d.inMinutes)} min';
}

String _stamp(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

double? _opt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}
