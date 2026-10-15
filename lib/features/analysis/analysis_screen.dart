import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/brand.dart';
import '../../shared/ui/hydro_ui.dart';
import '../dashboard/capture_stage.dart' show CaptureProfile, formatCl;
import '../dashboard/point_meta.dart';
import 'point_analysis.dart';

/// Análisis del punto: rendimiento de la captación y búsqueda de errores
/// (cortes, sensores trabados, totalizador que no cuadra) sobre las
/// lecturas reales del período.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({
    required this.api,
    required this.token,
    required this.points,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final List<Map<String, dynamic>> points;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  int? _pointId;
  int _days = 7;
  bool _loading = true;
  String? _error;
  ({int done, int total})? _progress;
  PointAnalysis? _analysis;
  PointVariables _variables = PointVariables.unknownCatalog;
  int _request = 0;
  bool _showLevel = false;
  String? _explained;

  @override
  void initState() {
    super.initState();
    if (widget.points.isNotEmpty) _pointId = _toInt(widget.points.first['id']);
    _load();
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _point {
    for (final p in widget.points) {
      if (_toInt(p['id']) == _pointId) return p;
    }
    return null;
  }

  Future<void> _load() async {
    final id = _pointId;
    final request = ++_request;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _progress = null;
    });
    try {
      final point = _point ?? const {};
      var variables = PointVariables.unknownCatalog;
      CaptureProfile profile = const CaptureProfile();
      try {
        variables = PointVariables.fromJson(
          await widget.api.pointVariables(widget.token, id),
        );
      } catch (_) {}
      try {
        profile = CaptureProfile.fromConfig(
          await widget.api.pointConfig(widget.token, id),
        );
      } catch (_) {}

      final frequency = _toDouble(point['frecuency'] ?? point['frequency']);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final start = today.subtract(Duration(days: _days - 1));
      // La API entrega hasta 500 lecturas por consulta: se pide en tramos
      // que quepan completos según la frecuencia del punto.
      final perDay = 1440 / ((frequency ?? 15).clamp(1, 1440));
      final chunk = (480 / perDay).floor().clamp(1, 31);
      final ranges = <(DateTime, DateTime)>[];
      for (var s = start; !s.isAfter(today); s = s.add(Duration(days: chunk))) {
        final e = s.add(Duration(days: chunk - 1));
        ranges.add((s, e.isAfter(today) ? today : e));
      }
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < ranges.length; i++) {
        if (!mounted || request != _request) return;
        setState(() => _progress = (done: i, total: ranges.length));
        rows.addAll(
          await widget.api.pointRecords(
            widget.token,
            id,
            start: ranges[i].$1,
            end: ranges[i].$2,
          ),
        );
      }
      if (!mounted || request != _request) return;
      final analysis = analyzePoint(
        rows.map(AnalysisSample.fromJson).toList(),
        start: start,
        end: now,
        hasFlow: variables.hasFlow,
        hasLevel: variables.hasLevel,
        hasTotal: variables.hasTotal,
        frequencyMinutes: frequency,
        maxFlowLimit: profile.maxFlow,
        wellDepth: profile.depth,
      );
      setState(() {
        _variables = variables;
        _analysis = analysis;
        _explained = null;
        _loading = false;
        _showLevel = analysis.hourlyFlow == null;
      });
      if (MediaQuery.of(context).disableAnimations) {
        _reveal.value = 1;
      } else {
        _reveal.forward(from: 0);
      }
    } on SmartHydroApiException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = _point;
    return HydroPage(
      title: 'Análisis',
      subtitle: widget.points.length > 1
          ? _PointPicker(
              points: widget.points,
              selected: _pointId,
              onChanged: (id) {
                setState(() => _pointId = id);
                _load();
              },
            )
          : point == null
          ? null
          : Text(
              '${point['title'] ?? 'Punto'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HydroText.subtitle,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Actualizar análisis',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          HydroTabs<int>(
            values: const [7, 14, 30],
            selected: _days,
            label: (v) => '${v}d',
            onChanged: (v) {
              if (v == _days) return;
              setState(() => _days = v);
              _load();
            },
          ),
        ],
      ),
      body: HydroSwap(
        state: _loading ? 'loading' : (_error == null ? 'ready' : 'error'),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (widget.points.isEmpty) {
      return const HydroMessage(
        icon: Icons.water_drop_outlined,
        title: 'Sin puntos para analizar',
        message: 'Tu cuenta todavía no tiene puntos asignados.',
      );
    }
    if (_loading) {
      final p = _progress;
      return HydroSkeleton(
        caption: p == null
            ? 'Preparando análisis…'
            : 'Leyendo lecturas del período…',
        progress: p == null || p.total == 0 ? null : p.done / p.total,
        rows: 2,
      );
    }
    if (_error != null) {
      return HydroMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No pudimos analizar el punto',
        message: _error!,
        action: ('Reintentar', _load),
      );
    }
    final a = _analysis;
    if (a == null || a.samples.isEmpty) {
      return HydroMessage(
        icon: Icons.event_busy_rounded,
        title: 'Sin lecturas en estos $_days días',
        message: 'No hay datos para analizar en el período.',
        action: _days < 30
            ? (
                'Ver 30 días',
                () {
                  setState(() => _days = 30);
                  _load();
                },
              )
            : null,
      );
    }

    var section = 0;
    Widget reveal(Widget child) =>
        HydroReveal(animation: _reveal, index: section++, child: child);
    final hasFlowSeries = a.hourlyFlow != null;
    final hasLevelSeries =
        _variables.hasLevel && a.samples.any((s) => s.level != null);
    final kpis = _kpis(a);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        reveal(
          _Health(
            analysis: a,
            selected: _explained == 'Puntaje',
            onTap: () => setState(
              () => _explained = _explained == 'Puntaje' ? null : 'Puntaje',
            ),
          ),
        ),
        reveal(
          _Explanation(
            data: _explained == 'Puntaje' ? _scoreData(a) : null,
            onClose: () => setState(() => _explained = null),
          ),
        ),
        const SizedBox(height: 26),
        reveal(
          HydroSectionTitle(
            title: 'Hallazgos',
            trailing: a.findings.isEmpty
                ? null
                : '${a.findings.length} en el período',
          ),
        ),
        const SizedBox(height: 6),
        if (a.findings.isEmpty)
          reveal(
            const _FindingRow(
              finding: AnalysisFinding(
                level: FindingLevel.ok,
                title: 'Sin anomalías en el período',
                detail:
                    'Transmisión, sensores y totalizador se comportaron '
                    'como se espera.',
              ),
            ),
          )
        else
          for (final f in a.findings) reveal(_FindingRow(finding: f)),
        if (kpis.isNotEmpty) ...[
          const SizedBox(height: 26),
          reveal(const HydroSectionTitle(title: 'Rendimiento')),
          const SizedBox(height: 4),
          reveal(
            const HydroHint('Toca un indicador para ver cómo se calcula.'),
          ),
          const SizedBox(height: 12),
          reveal(
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                for (final k in kpis)
                  _Kpi(
                    data: k,
                    selected: _explained == k.label,
                    onTap: () => setState(
                      () => _explained = _explained == k.label ? null : k.label,
                    ),
                  ),
              ],
            ),
          ),
          reveal(
            _Explanation(
              data: [
                for (final k in kpis)
                  if (k.label == _explained) k,
              ].firstOrNull,
              onClose: () => setState(() => _explained = null),
            ),
          ),
        ],
        if (hasFlowSeries || hasLevelSeries) ...[
          const SizedBox(height: 28),
          reveal(
            Row(
              children: [
                const Expanded(
                  child: HydroSectionTitle(title: 'Línea de tiempo'),
                ),
                if (hasFlowSeries && hasLevelSeries)
                  _SeriesSwitch(
                    level: _showLevel,
                    onChanged: (v) => setState(() => _showLevel = v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          reveal(
            Text(
              a.gaps.isEmpty
                  ? 'Toca o desliza para ver cada lectura.'
                  : 'Las franjas rojas son cortes de transmisión.',
              style: TextStyle(
                color: HydroTone.faint.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          reveal(
            _Timeline(
              key: ValueKey('tl-$_days-$_pointId-$_showLevel'),
              analysis: a,
              level: _showLevel || !hasFlowSeries,
            ),
          ),
        ],
        if (hasFlowSeries) ...[
          const SizedBox(height: 28),
          reveal(const HydroSectionTitle(title: 'Perfil horario')),
          const SizedBox(height: 4),
          reveal(
            HydroHint(
              '${_peakHours(a.hourlyFlow!) ?? 'Sin bombeo en el período'}. '
              'Cada barra es el caudal promedio de esa hora, juntando todos '
              'los días del período. Toca o desliza sobre las barras.',
            ),
          ),
          const SizedBox(height: 12),
          reveal(
            _HourlyProfile(key: ValueKey('hp-$_days-$_pointId'), analysis: a),
          ),
        ],
        const SizedBox(height: 26),
        reveal(
          Text(
            'Calculado con ${formatCl(a.samples.length.toDouble(), 0)} '
            'lecturas · una cada ${_minutes(a.interval)} · '
            'cobertura ${(a.coverage * 100).round()} %',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HydroTone.faint.withValues(alpha: 0.7),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  _KpiData _scoreData(PointAnalysis a) {
    final steps = <_Step>[_Step('Parte de', '100')];
    for (final finding in a.findings) {
      final penalty = switch (finding.level) {
        FindingLevel.critical => 28,
        FindingLevel.warning => 12,
        FindingLevel.info => 3,
        FindingLevel.ok => 0,
      };
      if (penalty == 0) continue;
      steps.add(_Step(finding.title, '−$penalty'));
    }
    final missing = (1 - a.coverage) * 30;
    if (missing >= 0.05) {
      steps.add(
        _Step(
          'Falta de datos · cobertura ${(a.coverage * 100).round()} %',
          '−${formatCl(missing, 1)}',
        ),
      );
    }
    steps.add(_Step('100 menos esos descuentos', '${a.score}', result: true));
    return _KpiData(
      label: 'Puntaje',
      value: '${a.score}',
      color: HydroTone.faint,
      icon: Icons.donut_large_rounded,
      explain:
          'Empieza en 100. Cada problema resta 28, cada alerta 12 y cada '
          'observación 3. La cobertura incompleta resta hasta 30: si llegó '
          'el ${(a.coverage * 100).round()} % de las lecturas esperadas, '
          'se descuentan ${formatCl(missing, 1)} puntos. El resultado no '
          'baja de 0 ni sube de 100.',
      steps: steps,
    );
  }

  List<_KpiData> _kpis(PointAnalysis a) {
    final days = formatCl(
      a.days,
      (a.days - a.days.round()).abs() < 0.05 ? 0 : 1,
    );
    final daysText = '$days ${days == '1' ? 'día' : 'días'}';
    final threshold = a.operatingThreshold == null
        ? null
        : formatCl(a.operatingThreshold!, 2);
    final thresholdStep = threshold == null
        ? null
        : _Step('Bomba encendida sobre', '$threshold L/s');
    String n(int v) => formatCl(v.toDouble(), 0);
    return [
      if (a.operatingHoursPerDay != null)
        _KpiData(
          label: 'Bombeo diario',
          value: '${formatCl(a.operatingHoursPerDay!, 1)} h',
          hint: '${((a.operatingHoursPerDay! / 24) * 100).round()} % del día',
          color: HydroTone.faint,
          icon: Icons.schedule_rounded,
          explain:
              'Horas que la bomba estuvo funcionando, en promedio por día. '
              'La bomba cuenta como encendida cuando el caudal supera el 2 % '
              'del máximo del período (mínimo 0,05 L/s). Se suma el tiempo '
              'entre lecturas seguidas con la bomba encendida; los cortes de '
              'transmisión no se cuentan.',
          steps: [
            ?thresholdStep,
            _Step(
              'Horas con bomba encendida',
              '${formatCl(a.operatingHours ?? 0, 1)} h',
            ),
            _Step('Días del período', days),
            _Step(
              '${formatCl(a.operatingHours ?? 0, 1)} h ÷ $daysText',
              '${formatCl(a.operatingHoursPerDay!, 1)} h/día',
              result: true,
            ),
          ],
        ),
      if (a.startsPerDay != null)
        _KpiData(
          label: 'Arranques',
          value: '${formatCl(a.startsPerDay!, 1)} /día',
          hint: a.startsPerDay! > 12 ? 'ciclos cortos' : 'ritmo normal',
          color: a.startsPerDay! > 12 ? IkoluColors.warning : HydroTone.faint,
          icon: Icons.power_settings_new_rounded,
          explain:
              'Veces que la bomba partió: una lectura con la bomba detenida '
              'seguida de otra con la bomba encendida. Más de 12 al día son '
              'ciclos cortos, que desgastan el motor y suelen indicar un '
              'presostato o un control de nivel mal ajustado.',
          steps: [
            ?thresholdStep,
            _Step('Arranques contados', n(a.starts ?? 0)),
            _Step('Días del período', days),
            _Step(
              '${n(a.starts ?? 0)} ÷ $daysText',
              '${formatCl(a.startsPerDay!, 1)} por día',
              result: true,
            ),
          ],
        ),
      if (a.avgOperatingFlow != null && a.avgOperatingFlow! > 0)
        _KpiData(
          label: 'Caudal en operación',
          value: '${formatCl(a.avgOperatingFlow!, 2)} L/s',
          hint: a.p95Flow == null
              ? null
              : 'P95 ${formatCl(a.p95Flow!, 2)} · máx ${formatCl(a.maxFlow!, 2)}',
          color: HydroTone.faint,
          icon: Icons.water_drop_outlined,
          explain:
              'Promedio del caudal solo mientras la bomba está encendida, sin '
              'contar los ceros de cuando está detenida. El P95 indica que el '
              '95 % de las lecturas está bajo ese valor: es el máximo habitual '
              'sin picos aislados.',
          steps: [
            _Step('Lecturas de caudal', n(a.flowReadings)),
            ?thresholdStep,
            _Step('Lecturas con bomba encendida', n(a.runningReadings)),
            if (a.p95Flow != null)
              _Step(
                'P95 de todas las lecturas',
                '${formatCl(a.p95Flow!, 2)} L/s',
              ),
            if (a.maxFlow != null)
              _Step('Lectura más alta', '${formatCl(a.maxFlow!, 2)} L/s'),
            _Step(
              'Promedio de las ${n(a.runningReadings)} lecturas',
              '${formatCl(a.avgOperatingFlow!, 2)} L/s',
              result: true,
            ),
          ],
        ),
      if (a.consumption != null)
        _KpiData(
          label: 'Volumen extraído',
          value: '${formatCl(a.consumption!, 1)} m³',
          hint: '${formatCl(a.consumption! / a.days, 1)} m³/día',
          color: HydroTone.faint,
          icon: Icons.inventory_2_outlined,
          explain:
              'Suma de lo que avanzó el totalizador entre cada lectura y la '
              'siguiente. Si el totalizador retrocede (por un reinicio o un '
              'cambio de medidor), ese tramo no se resta.',
          steps: [
            if (a.totalFirst != null)
              _Step(
                'Totalizador al inicio',
                '${formatCl(a.totalFirst!, 1)} m³',
              ),
            if (a.totalLast != null)
              _Step('Totalizador al final', '${formatCl(a.totalLast!, 1)} m³'),
            if (a.totalResets > 0)
              _Step(
                'Retrocesos no restados',
                '${a.totalResets} ${a.totalResets == 1 ? 'vez' : 'veces'}',
              ),
            _Step(
              'Suma de avances',
              '${formatCl(a.consumption!, 1)} m³',
              result: true,
            ),
            _Step(
              '${formatCl(a.consumption!, 1)} m³ ÷ $daysText',
              '${formatCl(a.consumption! / a.days, 1)} m³/día',
            ),
          ],
        ),
      if (a.staticLevel != null)
        _KpiData(
          label: a.dynamicLevel == null ? 'Nivel medio' : 'Nivel estático',
          value: '${formatCl(a.staticLevel!, 2)} m',
          hint: a.dynamicLevel == null ? null : 'con la bomba detenida',
          color: HydroTone.faint,
          icon: Icons.straighten_rounded,
          explain: a.dynamicLevel == null
              ? 'Profundidad del agua medida desde la superficie: la mediana '
                    'de todas las lecturas de nivel. La mediana es el valor '
                    'del medio y no se deja arrastrar por lecturas aisladas.'
              : 'Profundidad del agua en reposo, medida desde la superficie. '
                    'Es la mediana de las lecturas de nivel tomadas con la '
                    'bomba detenida.',
          steps: [
            if (a.dynamicLevel != null) ?thresholdStep,
            _Step(
              a.dynamicLevel == null
                  ? 'Lecturas de nivel'
                  : 'Lecturas con bomba detenida',
              n(a.restingReadings),
            ),
            _Step('Mediana', '${formatCl(a.staticLevel!, 2)} m', result: true),
          ],
        ),
      if (a.drawdown != null && a.drawdown! > 0)
        _KpiData(
          label: 'Abatimiento',
          value: '${formatCl(a.drawdown!, 2)} m',
          hint: 'dinámico ${formatCl(a.dynamicLevel!, 2)} m',
          color: HydroTone.faint,
          icon: Icons.south_rounded,
          explain:
              'Cuánto baja el agua al bombear: el nivel dinámico (mediana con '
              'la bomba encendida) menos el nivel estático (mediana con la '
              'bomba detenida).',
          steps: [
            _Step(
              'Nivel dinámico · ${n(a.pumpingReadings)} lecturas',
              '${formatCl(a.dynamicLevel!, 2)} m',
            ),
            _Step(
              'Nivel estático · ${n(a.restingReadings)} lecturas',
              '${formatCl(a.staticLevel!, 2)} m',
            ),
            _Step(
              '${formatCl(a.dynamicLevel!, 2)} − ${formatCl(a.staticLevel!, 2)}',
              '${formatCl(a.drawdown!, 2)} m',
              result: true,
            ),
          ],
        ),
      if (a.specificCapacity != null)
        _KpiData(
          label: 'Caudal específico',
          value: '${formatCl(a.specificCapacity!, 2)} L/s/m',
          hint: 'rendimiento del pozo',
          color: HydroTone.faint,
          icon: Icons.speed_rounded,
          explain:
              'Litros por segundo que entrega el pozo por cada metro que baja '
              'el agua. Si baja con el tiempo, el pozo o la bomba están '
              'perdiendo rendimiento.',
          steps: [
            _Step(
              'Caudal en operación',
              '${formatCl(a.avgOperatingFlow!, 2)} L/s',
            ),
            _Step('Abatimiento', '${formatCl(a.drawdown!, 2)} m'),
            _Step(
              '${formatCl(a.avgOperatingFlow!, 2)} ÷ ${formatCl(a.drawdown!, 2)}',
              '${formatCl(a.specificCapacity!, 2)} L/s/m',
              result: true,
            ),
          ],
        ),
    ];
  }
}

// ------------------------------------------------------------- piezas

class _PointPicker extends StatelessWidget {
  const _PointPicker({
    required this.points,
    required this.selected,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> points;
  final int? selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    String title(int? id) {
      for (final p in points) {
        if (_toInt(p['id']) == id) return '${p['title'] ?? 'Punto'}';
      }
      return 'Elegir punto';
    }

    return PopupMenuButton<int>(
      tooltip: 'Cambiar punto',
      color: HydroTone.menu,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final p in points)
          PopupMenuItem<int>(
            value: _toInt(p['id']),
            child: Text(
              '${p['title'] ?? 'Punto'}',
              style: TextStyle(
                color: _toInt(p['id']) == selected
                    ? HydroTone.accent
                    : HydroTone.fog,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title(selected),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HydroTone.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(
            Icons.expand_more_rounded,
            color: HydroTone.accent,
            size: 16,
          ),
        ],
      ),
    );
  }
}

/// Estado general: anillo con el puntaje y un resumen de los hallazgos.
class _Health extends StatelessWidget {
  const _Health({
    required this.analysis,
    required this.selected,
    required this.onTap,
  });

  final PointAnalysis analysis;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final (label, color) = a.score >= 85
        ? ('Operación sana', IkoluColors.connected)
        : a.score >= 60
        ? ('Requiere atención', IkoluColors.warning)
        : ('Con problemas', IkoluColors.incident);
    final critical = a.count(FindingLevel.critical);
    final warnings = a.count(FindingLevel.warning);
    final summary = a.findings.isEmpty
        ? 'Sin anomalías detectadas en ${_periodDays(a)} días.'
        : [
            if (critical > 0)
              '$critical ${critical == 1 ? 'problema' : 'problemas'}',
            if (warnings > 0)
              '$warnings ${warnings == 1 ? 'alerta' : 'alertas'}',
            if (critical == 0 && warnings == 0)
              '${a.findings.length} '
                  '${a.findings.length == 1 ? 'observación' : 'observaciones'}',
          ].join(' · ');

    return Semantics(
      button: true,
      selected: selected,
      label: 'Puntaje ${a.score} de 100. Ver cómo se calcula.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: HydroMotion.of(context, HydroMotion.fast),
          curve: HydroMotion.curve,
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: selected ? 0.06 : 0),
          ),
          child: Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: a.score / 100),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => SizedBox.square(
                  dimension: 92,
                  child: CustomPaint(
                    painter: _RingPainter(progress: t, color: color),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(t * 100).round()}',
                            style: const TextStyle(
                              color: HydroTone.fog,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                          const Text(
                            'de 100',
                            style: TextStyle(
                              color: HydroTone.faint,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: HydroTone.faint.withValues(
                            alpha: selected ? 0.95 : 0.55,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      summary,
                      style: const TextStyle(
                        color: HydroTone.fog,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cobertura de datos ${(a.coverage * 100).round()} % · '
                      '${switch (a.gaps.length) {
                        0 => 'sin cortes',
                        1 => '1 corte',
                        final n => '$n cortes',
                      }}',
                      style: const TextStyle(
                        color: HydroTone.faint,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [color.withValues(alpha: 0.5), color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final AnalysisFinding finding;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (finding.level) {
      FindingLevel.critical => (
        IkoluColors.incident,
        Icons.error_outline_rounded,
      ),
      FindingLevel.warning => (
        IkoluColors.warning,
        Icons.warning_amber_rounded,
      ),
      FindingLevel.info => (IkoluColors.info, Icons.info_outline_rounded),
      FindingLevel.ok => (
        IkoluColors.connected,
        Icons.check_circle_outline_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HydroTone.hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finding.title,
                  style: const TextStyle(
                    color: HydroTone.fog,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  finding.detail,
                  style: TextStyle(
                    color: HydroTone.fog.withValues(alpha: 0.72),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                if (finding.action != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    finding.action!,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.95),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un paso del cálculo: qué dato entra y con qué valor.
class _Step {
  const _Step(this.label, this.value, {this.result = false});

  final String label;
  final String value;
  final bool result;
}

class _KpiData {
  const _KpiData({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.explain,
    required this.steps,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;
  final Color color;
  final IconData icon;
  final String explain;
  final List<_Step> steps;
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.data, required this.selected, required this.onTap});

  final _KpiData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${data.label} ${data.value}. Ver cómo se calcula.',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: HydroMotion.of(context, HydroMotion.fast),
        curve: HydroMotion.curve,
        constraints: const BoxConstraints(minWidth: 138),
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: selected ? 0.07 : 0),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(data.icon, size: 13, color: data.color),
                const SizedBox(width: 6),
                Text(
                  data.label,
                  style: const TextStyle(
                    color: HydroTone.faint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.info_outline_rounded,
                  size: 12,
                  color: HydroTone.faint.withValues(
                    alpha: selected ? 0.95 : 0.55,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              data.value,
              style: const TextStyle(
                color: HydroTone.fog,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            if (data.hint != null)
              Text(
                data.hint!,
                style: TextStyle(
                  color: HydroTone.faint.withValues(alpha: 0.8),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// "Cómo se calcula" del indicador elegido, con los valores reales.
class _Explanation extends StatelessWidget {
  const _Explanation({required this.data, required this.onClose});

  final _KpiData? data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final d = data;
    return AnimatedSize(
      duration: HydroMotion.of(context, const Duration(milliseconds: 260)),
      curve: HydroMotion.curve,
      alignment: Alignment.topCenter,
      child: d == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: HydroGlassLight(
                padding: const EdgeInsets.fromLTRB(16, 12, 6, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.functions_rounded,
                                size: 15,
                                color: HydroTone.faint,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Cómo se calcula · ${d.label}',
                                  style: const TextStyle(
                                    color: HydroTone.fog,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            d.explain,
                            style: TextStyle(
                              color: HydroTone.fog.withValues(alpha: 0.78),
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                          if (d.steps.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            for (final step in d.steps) _StepRow(step: step),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: HydroTone.faint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(top: step.result ? 8 : 5, bottom: 5),
    margin: EdgeInsets.only(top: step.result ? 4 : 0, right: 10),
    decoration: step.result
        ? const BoxDecoration(
            border: Border(top: BorderSide(color: HydroTone.hair)),
          )
        : null,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            step.label,
            style: TextStyle(
              color: step.result ? HydroTone.fog : HydroTone.faint,
              fontSize: 12,
              fontWeight: step.result ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          step.value,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: HydroTone.fog,
            fontSize: step.result ? 13.5 : 12.5,
            fontWeight: step.result ? FontWeight.w800 : FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _SeriesSwitch extends StatelessWidget {
  const _SeriesSwitch({required this.level, required this.onChanged});

  final bool level;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, bool on, Color color, VoidCallback onTap) =>
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? color : Colors.transparent,
                    border: Border.all(
                      color: on
                          ? color
                          : HydroTone.faint.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    color: on ? HydroTone.fog : HydroTone.faint,
                    fontSize: 12,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('Caudal', !level, HydroTone.accent, () => onChanged(false)),
        const SizedBox(width: 6),
        chip('Nivel', level, HydroTone.level, () => onChanged(true)),
      ],
    );
  }
}

/// Serie del período con los cortes de transmisión sombreados.
class _Timeline extends StatefulWidget {
  const _Timeline({required this.analysis, required this.level, super.key});

  final PointAnalysis analysis;
  final bool level;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  double? _cursor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void track(Offset p) =>
            setState(() => _cursor = (p.dx / width).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => track(d.localPosition),
          onHorizontalDragStart: (d) => track(d.localPosition),
          onHorizontalDragUpdate: (d) => track(d.localPosition),
          onHorizontalDragEnd: (_) {},
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => CustomPaint(
              size: Size(width, 170),
              painter: _TimelinePainter(
                analysis: widget.analysis,
                level: widget.level,
                reveal: t,
                cursor: _cursor,
                textScaler: MediaQuery.textScalerOf(context),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.analysis,
    required this.level,
    required this.reveal,
    required this.cursor,
    required this.textScaler,
  });

  final PointAnalysis analysis;
  final bool level;
  final double reveal;
  final double? cursor;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 24.0;
    const bottom = 18.0;
    final plot = Rect.fromLTRB(0, top, size.width, size.height - bottom);
    final a = analysis;
    final t0 = a.start.millisecondsSinceEpoch.toDouble();
    final t1 = math.max(t0 + 1, a.end.millisecondsSinceEpoch.toDouble());
    double xOf(DateTime t) =>
        plot.left + (t.millisecondsSinceEpoch - t0) / (t1 - t0) * plot.width;
    final color = level ? HydroTone.level : HydroTone.accent;
    final points = [
      for (final s in a.samples)
        if ((level ? s.level : s.flow) != null)
          (at: s.at, v: (level ? s.level : s.flow)!, error: s.isError),
    ];

    canvas.drawLine(
      Offset(0, plot.bottom),
      Offset(size.width, plot.bottom),
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );
    for (final g in a.gaps) {
      final x0 = xOf(g.start);
      final x1 = math.max(x0 + 2, xOf(g.end));
      canvas.drawRect(
        Rect.fromLTRB(x0, plot.top, x1, plot.bottom),
        Paint()..color = IkoluColors.incident.withValues(alpha: 0.12),
      );
      canvas.drawLine(
        Offset(x0, plot.bottom),
        Offset(x1, plot.bottom),
        Paint()
          ..color = IkoluColors.incident.withValues(alpha: 0.8)
          ..strokeWidth = 2,
      );
    }
    if (points.isEmpty) return;

    var lo = points.map((p) => p.v).reduce(math.min);
    var hi = points.map((p) => p.v).reduce(math.max);
    if (!level) lo = math.min(0, lo);
    if (hi - lo < 0.001) {
      hi += 1;
      lo -= level ? 1 : 0;
    }
    // El nivel es profundidad: más abajo en el gráfico es más profundo.
    double yOf(double v) {
      final n = (v - lo) / (hi - lo);
      return level ? plot.top + n * plot.height : plot.bottom - n * plot.height;
    }

    final limitX = plot.left + plot.width * reveal;
    final gapLimit = Duration(seconds: (a.interval.inSeconds * 2.5).round());
    final line = Path();
    final area = Path();
    var open = false;
    var areaStart = 0.0;
    var lastX = 0.0;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = xOf(p.at);
      if (x > limitX) break;
      final y = yOf(p.v);
      final broken = i > 0 && p.at.difference(points[i - 1].at) > gapLimit;
      if (!open || broken) {
        if (open) {
          area
            ..lineTo(lastX, plot.bottom)
            ..lineTo(areaStart, plot.bottom)
            ..close();
        }
        line.moveTo(x, y);
        area.moveTo(x, y);
        areaStart = x;
        open = true;
      } else {
        line.lineTo(x, y);
        area.lineTo(x, y);
      }
      lastX = x;
    }
    if (open) {
      area
        ..lineTo(lastX, plot.bottom)
        ..lineTo(areaStart, plot.bottom)
        ..close();
    }
    if (!level) {
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(plot),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in points.where((p) => p.error)) {
      final x = xOf(p.at);
      if (x > limitX) continue;
      canvas.drawCircle(
        Offset(x, yOf(p.v)),
        2.6,
        Paint()..color = IkoluColors.warning,
      );
    }

    _label(
      canvas,
      '${formatCl(level ? lo : hi, 2)} ${level ? 'm' : 'L/s'}',
      Offset(0, plot.top - 2),
      HydroTone.faint.withValues(alpha: 0.7),
      above: true,
    );
    _label(
      canvas,
      _day(a.start),
      Offset(0, size.height - bottom + 4),
      HydroTone.faint.withValues(alpha: 0.7),
    );
    _label(
      canvas,
      _day(a.end),
      Offset(size.width, size.height - bottom + 4),
      HydroTone.faint.withValues(alpha: 0.7),
      right: true,
    );

    if (cursor != null) {
      final target = t0 + (t1 - t0) * cursor!;
      var best = points.first;
      for (final p in points) {
        if ((p.at.millisecondsSinceEpoch - target).abs() <
            (best.at.millisecondsSinceEpoch - target).abs()) {
          best = p;
        }
      }
      final x = xOf(best.at);
      final y = yOf(best.v);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()..color = HydroTone.fog.withValues(alpha: 0.25),
      );
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
      canvas.drawCircle(
        Offset(x, y),
        7,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke,
      );
      final text =
          '${formatCl(best.v, 2)} ${level ? 'm' : 'L/s'} · ${_stamp(best.at)}';
      final tp = _painter(
        text,
        const TextStyle(
          color: Color(0xFF06222B),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      );
      final w = tp.width + 14;
      final left = (x - w / 2).clamp(0.0, math.max(0.0, size.width - w));
      final bubble = Rect.fromLTWH(left.toDouble(), 0, w, 20);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bubble, const Radius.circular(10)),
        Paint()..color = color,
      );
      tp.paint(canvas, Offset(bubble.left + 7, 10 - tp.height / 2));
    }
  }

  TextPainter _painter(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool right = false,
    bool above = false,
  }) {
    final p = _painter(
      text,
      TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
    );
    p.paint(
      canvas,
      Offset(right ? at.dx - p.width : at.dx, above ? at.dy - p.height : at.dy),
    );
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.reveal != reveal ||
      old.cursor != cursor ||
      old.level != level ||
      old.analysis != analysis;
}

/// Caudal promedio por hora del día: muestra cuándo se bombea. Al tocar
/// una barra se ve el detalle de esa hora.
class _HourlyProfile extends StatefulWidget {
  const _HourlyProfile({required this.analysis, super.key});

  final PointAnalysis analysis;

  @override
  State<_HourlyProfile> createState() => _HourlyProfileState();
}

class _HourlyProfileState extends State<_HourlyProfile> {
  late int _hour = _peak();

  int _peak() {
    final hourly = widget.analysis.hourlyFlow!;
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if ((hourly[h] ?? 0) > (hourly[best] ?? 0)) best = h;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    final hourly = a.hourlyFlow!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HourDetail(analysis: a, hour: _hour),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            void pick(Offset p) {
              final h = (p.dx / width * 24).floor().clamp(0, 23);
              if (h != _hour) setState(() => _hour = h);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => pick(d.localPosition),
              onHorizontalDragStart: (d) => pick(d.localPosition),
              onHorizontalDragUpdate: (d) => pick(d.localPosition),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  size: Size(width, 120),
                  painter: _HourlyPainter(
                    hourly: hourly,
                    grow: t,
                    selected: _hour,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HourDetail extends StatelessWidget {
  const _HourDetail({required this.analysis, required this.hour});

  final PointAnalysis analysis;
  final int hour;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final flow = a.hourlyFlow![hour];
    final on = a.hourlyOn?[hour];
    final count = a.hourlySamples?[hour] ?? 0;
    String hh(int h) => h.toString().padLeft(2, '0');
    final range = '${hh(hour)}:00 – ${hh((hour + 1) % 24)}:00';

    Widget stat(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: HydroTone.faint,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            color: HydroTone.fog,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Column(
        key: ValueKey(hour),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            range,
            style: const TextStyle(
              color: HydroTone.accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          if (count == 0)
            const Text(
              'Sin lecturas en esta hora',
              style: TextStyle(
                color: HydroTone.faint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Wrap(
              spacing: 22,
              runSpacing: 8,
              children: [
                stat('Caudal promedio', '${formatCl(flow ?? 0, 2)} L/s'),
                if (on != null)
                  stat('Bomba encendida', '${(on * 100).round()} % del tiempo'),
                stat('Lecturas', formatCl(count.toDouble(), 0)),
              ],
            ),
        ],
      ),
    );
  }
}

class _HourlyPainter extends CustomPainter {
  _HourlyPainter({
    required this.hourly,
    required this.grow,
    required this.selected,
    required this.textScaler,
  });

  final List<double?> hourly;
  final double grow;
  final int selected;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 16.0;
    final plotH = size.height - bottom;
    final max = math.max(
      0.0001,
      hourly.whereType<double>().fold(0.0, math.max),
    );
    final slot = size.width / 24;
    final barW = math.max(2.0, slot * 0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(slot * selected + 1, 0, slot - 2, plotH),
        const Radius.circular(6),
      ),
      Paint()..color = HydroTone.accent.withValues(alpha: 0.08),
    );
    for (var h = 0; h < 24; h++) {
      final v = hourly[h] ?? 0;
      final t = ((grow * 1.3) - h / 24 * 0.3).clamp(0.0, 1.0);
      final bh = math.max(1.5, v / max * (plotH - 6) * t);
      final x = slot * (h + 0.5) - barW / 2;
      final rect = Rect.fromLTWH(x, plotH - bh, barW, bh);
      final active = h == selected;
      final strong = v / max > 0.6;
      final top = active ? 1.0 : (strong ? 0.75 : 0.45);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(barW / 2),
          topRight: Radius.circular(barW / 2),
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              (active ? HydroTone.fog : HydroTone.accent).withValues(
                alpha: top,
              ),
              HydroTone.accent.withValues(alpha: top * 0.35),
            ],
          ).createShader(rect),
      );
      if (h % 6 == 0 || active) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${h.toString().padLeft(2, '0')} h',
            style: TextStyle(
              color: active
                  ? HydroTone.accent
                  : HydroTone.faint.withValues(alpha: 0.7),
              fontSize: 9.5,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout();
        final cx = slot * (h + 0.5) - tp.width / 2;
        if (!active && (h - selected).abs() < 3) continue;
        tp.paint(
          canvas,
          Offset(
            cx.clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble(),
            size.height - tp.height,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyPainter old) =>
      old.grow != grow || old.hourly != hourly || old.selected != selected;
}

// ------------------------------------------------------------ formato

String? _peakHours(List<double?> hourly) {
  final values = hourly.map((v) => v ?? 0).toList();
  final max = values.fold(0.0, math.max);
  if (max <= 0) return null;
  final ranges = <(int, int)>[];
  for (var h = 0; h < 24; h++) {
    if (values[h] / max <= 0.6) continue;
    if (ranges.isNotEmpty && ranges.last.$2 == h) {
      ranges[ranges.length - 1] = (ranges.last.$1, h + 1);
    } else {
      ranges.add((h, h + 1));
    }
  }
  if (ranges.isEmpty) return null;
  if (ranges.length == 1 && ranges.first == (0, 24)) {
    return 'Bombeo parejo todo el día';
  }
  if (ranges.length > 2) {
    final hours = ranges.fold(0, (sum, r) => sum + r.$2 - r.$1);
    return 'Bombeo fuerte en $hours horas repartidas';
  }
  String hh(int h) => h.toString().padLeft(2, '0');
  return 'Mayor bombeo '
      '${ranges.map((r) => '${hh(r.$1)}–${hh(r.$2)} h').join(' y ')}';
}

int _periodDays(PointAnalysis a) =>
    math.max(1, (a.end.difference(a.start).inHours / 24).ceil());

String _minutes(Duration d) => d.inMinutes >= 60
    ? '${formatCl(d.inMinutes / 60, 1)} h'
    : '${d.inMinutes} min';

String _day(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

String _stamp(DateTime t) =>
    '${_day(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

int? _toInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value');
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}
