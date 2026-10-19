import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/brand.dart';
import '../../core/files/save_file.dart';
import '../../shared/ui/hydro_ui.dart';
import '../../shared/widgets/hydro_glass.dart';
import '../dashboard/capture_stage.dart' show formatCl;
import 'compliance_store.dart';
import 'dga_compliance.dart';

const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', //
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// Cumplimiento normativo DGA de un punto: reportes entregados con
/// comprobante, faltantes, límites autorizados, últimos envíos y descargas.
class PointComplianceScreen extends StatefulWidget {
  const PointComplianceScreen({
    required this.api,
    required this.token,
    required this.pointId,
    this.pointTitle,
    this.embedded = false,
    this.onBackToList,
    this.store,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final int pointId;
  final String? pointTitle;

  /// Dentro de Cumplimiento en escritorio: no abre otra ruta y el rail sigue.
  final bool embedded;

  /// Vuelve a la grilla sin un botón Volver en la cabecera.
  final VoidCallback? onBackToList;

  final ComplianceStore? store;

  @override
  State<PointComplianceScreen> createState() => _PointComplianceScreenState();
}

class _PointComplianceScreenState extends State<PointComplianceScreen> {
  late DateTime _month = _monthOf(DateTime.now());
  bool _loadingPoint = true;
  bool _loadingMonth = true;
  String? _error;
  String? _monthError;
  Map<String, dynamic> _dga = const {};
  Map<String, dynamic> _item = const {};
  List<DgaAttempt> _attempts = const [];
  String? _title;
  int _frequency = 60;
  Uint8List? _workbook;
  DgaCompliance? _compliance;
  DateTime? _selectedDay;
  bool _allAttempts = false;
  String? _busy;
  int _request = 0;

  ComplianceStore get _store => widget.store ?? ComplianceStore.instance;

  @override
  void initState() {
    super.initState();
    _title = widget.pointTitle;
    final cached = _store.detail(widget.token, widget.pointId);
    final listed = _store.pointOnList(widget.token, widget.pointId);
    if (cached != null) {
      _hydrateDetail(cached, listed ?? const {});
      final month = _store.month(widget.token, widget.pointId, _month);
      if (month != null) {
        _workbook = month.bytes;
        _compliance = month.compliance;
        _loadingMonth = false;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadPoint();
    });
  }

  DgaStandard get _standard => DgaStandard.parse(_dga['standard']);
  String? get _code => _str(_dga['code_dga']) ?? _str(_item['code']);
  bool get _active => _dga['send_dga'] == true;
  double? get _authorizedFlow =>
      _num(_dga['flow_granted_dga']) ?? _num(_item['authorized_flow']);
  double? get _authorizedTotal =>
      _num(_dga['total_granted_dga']) ?? _num(_item['authorized_total']);

  Future<void> _loadPoint() async {
    final cached = _store.detail(widget.token, widget.pointId);
    final listed = _store.pointOnList(widget.token, widget.pointId);
    if (cached != null && _store.detailIsFresh(widget.token, widget.pointId)) {
      await _loadMonth();
      return;
    }
    if (cached == null) {
      setState(() {
        _loadingPoint = true;
        _error = null;
      });
    }
    try {
      final detail = await widget.api.pointDgaDetail(
        widget.token,
        widget.pointId,
      );
      _store.putDetail(widget.token, widget.pointId, detail);
      Map<String, dynamic> item = listed ?? const {};
      if (item.isEmpty) {
        try {
          final list =
              _store.list(widget.token) ??
              await widget.api.compliancePoints(
                widget.token,
                pageSize: 200,
              );
          if (_store.list(widget.token) == null) {
            _store.putList(widget.token, list);
          }
          item = list.firstWhere(
            (p) => '${p['point_id']}' == '${widget.pointId}',
            orElse: () => const {},
          );
        } on SmartHydroApiException {
          // El resumen anual es complementario.
        }
      }
      if (!mounted) return;
      setState(() => _hydrateDetail(detail, item));
      await _loadMonth();
    } on SmartHydroApiException catch (e) {
      if (!mounted) return;
      if (cached != null) {
        await _loadMonth();
        return;
      }
      setState(() {
        _error = e.message;
        _loadingPoint = false;
      });
    }
  }

  void _hydrateDetail(Map<String, dynamic> detail, Map<String, dynamic> item) {
    final modules = detail['modules'];
    final m2 = modules is Map ? modules['m2'] : null;
    _dga = detail['dga'] is Map
        ? Map<String, dynamic>.from(detail['dga'] as Map)
        : const {};
    _item = item;
    _title = _str(detail['title']) ?? _title;
    _frequency = int.tryParse('${detail['frecuency'] ?? ''}') ?? 60;
    _attempts = [
      if (m2 is List)
        for (final r in m2)
          if (r is Map) DgaAttempt.fromJson(Map<String, dynamic>.from(r)),
    ]..sort((a, b) => b.at.compareTo(a.at));
    _loadingPoint = false;
  }

  Future<void> _loadMonth() async {
    final request = ++_request;
    final start = _month;
    final end = DateTime(start.year, start.month + 1);
    final cached = _store.month(widget.token, widget.pointId, start);
    if (cached != null &&
        _store.monthIsFresh(widget.token, widget.pointId, start)) {
      setState(() {
        _workbook = cached.bytes;
        _compliance = cached.compliance;
        _loadingMonth = false;
        _monthError = null;
        _selectedDay = null;
      });
      return;
    }
    setState(() {
      _loadingMonth = cached == null;
      _monthError = null;
      _selectedDay = null;
      if (cached != null) {
        _workbook = cached.bytes;
        _compliance = cached.compliance;
      }
    });
    try {
      final last = end.subtract(const Duration(days: 1));
      final bytes = await widget.api.dgaWorkbook(
        widget.token,
        widget.pointId,
        start: start,
        end: last.isAfter(DateTime.now()) ? DateTime.now() : last,
      );
      final rows = parseDgaWorkbook(bytes);
      final analyzed = analyzeDgaCompliance(
        rows,
        standard: _standard,
        frequencyMinutes: _frequency,
        start: start,
        end: end,
        authorizedFlow: _authorizedFlow,
      );
      _store.putMonth(
        widget.token,
        widget.pointId,
        start,
        ComplianceMonthSnap(bytes: bytes, compliance: analyzed),
      );
      if (!mounted || request != _request) return;
      setState(() {
        _workbook = bytes;
        _compliance = analyzed;
        _loadingMonth = false;
      });
    } on SmartHydroApiException catch (e) {
      if (!mounted || request != _request) return;
      if (cached != null) {
        setState(() => _loadingMonth = false);
        return;
      }
      setState(() {
        _monthError = e.message;
        _workbook = null;
        _compliance = null;
        _loadingMonth = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      if (cached != null) {
        setState(() => _loadingMonth = false);
        return;
      }
      setState(() {
        _monthError = 'No pudimos leer la planilla DGA del mes.';
        _loadingMonth = false;
      });
    }
  }

  Future<void> _downloadDga() async {
    final bytes = _workbook;
    if (bytes == null) return;
    final name =
        'Reporte_MEE_${safeFileName(_code ?? 'punto_${widget.pointId}')}_'
        '${_ym(_month)}.xlsx';
    await _save(() async => bytes, name, 'dga');
  }

  Future<void> _downloadRecords() async {
    final start = _month;
    final last = DateTime(start.year, start.month + 1, 0);
    final name =
        'Mediciones_${safeFileName(_title ?? 'punto_${widget.pointId}')}_'
        '${_ym(_month)}.xlsx';
    await _save(
      () => widget.api.recordsWorkbook(
        widget.token,
        widget.pointId,
        start: start,
        end: last.isAfter(DateTime.now()) ? DateTime.now() : last,
      ),
      name,
      'records',
    );
  }

  Future<void> _save(
    Future<Uint8List> Function() load,
    String name,
    String key,
  ) async {
    setState(() => _busy = key);
    try {
      await saveBytes(await load(), name, SmartHydroApi.xlsxMime);
      _toast('Descargado $name');
    } on SmartHydroApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo guardar el archivo.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final content = HydroSwap(
      state: _loadingPoint ? 'loading' : (_error == null ? 'ready' : 'error'),
      child: _body(),
    );
    if (widget.embedded) return content;
    return HydroPage(title: '', body: content);
  }

  Widget _body() {
    if (_loadingPoint) {
      return const HydroSkeleton(
        caption: 'Leyendo la ficha DGA…',
        tabs: true,
        kpis: 0,
        rows: 3,
      );
    }
    if (_error != null) {
      return HydroMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No pudimos cargar el cumplimiento',
        message: _error!,
        action: ('Reintentar', _loadPoint),
      );
    }
    final identity = _IdentityBand(
      title: _title ?? widget.pointTitle ?? 'Punto',
      code: _code,
      meta: _identityMeta(),
      status: _identityStatus(),
      facts: _identityFacts(),
      onBack: widget.onBackToList,
      onVerify: _code == null
          ? null
          : () => openExternal(
              'https://snia.mop.gob.cl/cExtracciones2/#/consultaQR/$_code',
            ),
    );
    if (_code == null) {
      return ListView(
        key: const Key('compliance-point-detail'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          identity,
          const SizedBox(height: 16),
          const HydroMessage(
            icon: Icons.policy_outlined,
            title: 'Este punto no tiene código de obra DGA',
            message:
                'Sin código de obra no hay reportes MEE que auditar. Si debería '
                'reportar, pide a soporte que configure su ficha DGA.',
          ),
        ],
      );
    }
    final c = _compliance;
    return ListView(
      key: const Key('compliance-point-detail'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        identity,
        const SizedBox(height: 18),
        _MonthTabs(
          selected: _month,
          onChanged: (m) {
            if (m == _month) return;
            setState(() => _month = m);
            _loadMonth();
          },
        ),
        const SizedBox(height: 18),
        if (_loadingMonth)
          const HydroSkeleton(
            caption: 'Leyendo la planilla DGA del mes…',
            inline: true,
            kpis: 0,
            rows: 3,
          )
        else if (_monthError != null)
          HydroMessage(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos leer la planilla del mes',
            message: _monthError!,
            action: ('Reintentar', _loadMonth),
          )
        else if (c != null) ...[
          _Hero(compliance: c, active: _active),
          const SizedBox(height: 26),
          const HydroSectionTitle(title: 'Hallazgos'),
          const SizedBox(height: 4),
          ..._findings(c).map((f) => _FindingRow(finding: f)),
          const SizedBox(height: 26),
          HydroSectionTitle(
            title: 'Reportes del mes',
            trailing: _standard.cadence,
          ),
          const SizedBox(height: 4),
          const HydroHint(
            'Cada día muestra la proporción de reportes con comprobante. '
            'Toca un día para ver qué horas faltaron.',
          ),
          const SizedBox(height: 12),
          _MonthCalendar(
            month: _month,
            compliance: c,
            selected: _selectedDay,
            onSelect: (d) =>
                setState(() => _selectedDay = _selectedDay == d ? null : d),
          ),
          _DayDetail(
            day: c.days.where((d) => d.date == _selectedDay).firstOrNull,
          ),
          const SizedBox(height: 26),
          const HydroSectionTitle(title: 'Límites autorizados'),
          const SizedBox(height: 12),
          _Limits(
            compliance: c,
            authorizedFlow: _authorizedFlow,
            authorizedTotal: _authorizedTotal,
            annual: _num(_item['annual_consumption']),
            pct: _num(_item['pct_consumed']),
          ),
        ],
        if (_attempts.isNotEmpty) ...[
          const SizedBox(height: 28),
          HydroSectionTitle(
            title: 'Últimos envíos a la DGA',
            trailing: '${_attempts.length} más recientes',
          ),
          const SizedBox(height: 4),
          const HydroHint(
            'Respuesta de la DGA a cada envío. Toca un comprobante para '
            'copiarlo.',
          ),
          const SizedBox(height: 6),
          for (final a in _allAttempts ? _attempts : _attempts.take(8))
            _AttemptRow(
              attempt: a,
              onCopy: (v) {
                Clipboard.setData(ClipboardData(text: v));
                _toast('Comprobante $v copiado');
              },
            ),
          if (_attempts.length > 8)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: HydroTone.accent),
                onPressed: () => setState(() => _allAttempts = !_allAttempts),
                child: Text(
                  _allAttempts ? 'Ver menos' : 'Ver los ${_attempts.length}',
                ),
              ),
            ),
        ],
        const SizedBox(height: 26),
        const HydroSectionTitle(title: 'Descargas'),
        const SizedBox(height: 10),
        _DownloadRow(
          icon: Icons.verified_outlined,
          title: 'Planilla DGA de ${_months[_month.month - 1]}',
          detail: 'Cada medición con su comprobante, formato MEE (XLSX).',
          busy: _busy == 'dga',
          onTap: _workbook == null || _busy != null ? null : _downloadDga,
        ),
        _DownloadRow(
          icon: Icons.table_chart_outlined,
          title: 'Mediciones de ${_months[_month.month - 1]}',
          detail: 'Todas las lecturas del punto (XLSX).',
          busy: _busy == 'records',
          onTap: _busy != null ? null : _downloadRecords,
        ),
      ],
    );
  }

  String _identityMeta() {
    final client = _str(_item['client_name']);
    final type = _str(_dga['type_dga']);
    return [
      ?client,
      _standard.label,
      if (type != null) _capitalize(type.toLowerCase()),
    ].join(' · ');
  }

  (String, Color)? _identityStatus() {
    final warning = _item['compliance_warning'];
    final level = warning is Map ? warning['level'] : null;
    return switch (level) {
      'critical' => ('Excede', _Gob.rojo),
      'warning' => ('Cerca', _Gob.azulClaro),
      'safe' => ('Dentro', _Gob.azulClaro),
      _ => null,
    };
  }

  List<(String, String)> _identityFacts() {
    final type = _str(_dga['type_dga']);
    return [
      ('Estándar MEE', _standard.label),
      ('Reporte', _capitalize(_standard.cadence)),
      if (type != null) ('Tipo de captación', _capitalize(type.toLowerCase())),
      if (_authorizedFlow != null)
        ('Caudal autorizado', '${formatCl(_authorizedFlow!, 2)} L/s'),
      if (_authorizedTotal != null)
        ('Volumen anual', '${formatCl(_authorizedTotal!, 0)} m³'),
      if (_str(_dga['shac']) != null) ('SHAC', _str(_dga['shac'])!),
      if (_str(_dga['region_dga'] ?? _dga['region']) != null)
        ('Región', _str(_dga['region_dga'] ?? _dga['region'])!),
      if (parseWallClock(_dga['date_start_compliance']) != null)
        (
          'Cumplimiento desde',
          _date(parseWallClock(_dga['date_start_compliance'])!),
        ),
      ('Envío a la DGA', _dga['send_dga'] == true ? 'Activado' : 'Desactivado'),
    ];
  }

  List<_Finding> _findings(DgaCompliance c) {
    final out = <_Finding>[];
    if (!_active) {
      out.add(
        const _Finding(
          _Level.warning,
          'El envío a la DGA está desactivado',
          'Las mediciones no se están reportando. Si el punto debe cumplir, '
              'activa el envío o contacta a soporte.',
        ),
      );
    }
    final noData = c.gaps.where((g) => g.kind == DgaSlotState.noData).toList();
    final noVoucher = c.gaps
        .where((g) => g.kind == DgaSlotState.noVoucher)
        .toList();
    String ranges(List<DgaGap> gaps) {
      final top = [...gaps]..sort((a, b) => b.count.compareTo(a.count));
      final shown = top.take(3).map(_gapText).join('; ');
      return gaps.length > 3 ? '$shown y ${gaps.length - 3} tramos más' : shown;
    }

    if (noData.isNotEmpty) {
      final n = noData.fold(0, (s, g) => s + g.count);
      out.add(
        _Finding(
          _Level.critical,
          '$n ${n == 1 ? 'reporte' : 'reportes'} sin medición',
          'No hubo dato que enviar: ${ranges(noData)}.',
          'Sin medición no hay reporte. Revisa la transmisión del datalogger '
              'en esas horas.',
        ),
      );
    }
    if (noVoucher.isNotEmpty) {
      final n = noVoucher.fold(0, (s, g) => s + g.count);
      out.add(
        _Finding(
          _Level.warning,
          '$n ${n == 1 ? 'reporte' : 'reportes'} sin comprobante',
          'Hubo medición, pero la DGA no devolvió comprobante: '
              '${ranges(noVoucher)}.',
          'Revisa la respuesta en "Últimos envíos". Si persiste, avisa a '
              'soporte para reenviar.',
        ),
      );
    }
    final af = _authorizedFlow;
    if (c.exceedances > 0 && af != null) {
      out.add(
        _Finding(
          _Level.critical,
          'Caudal sobre lo autorizado',
          '${c.exceedances} mediciones superaron los ${formatCl(af, 2)} L/s '
              'autorizados; la máxima fue ${formatCl(c.maxFlow ?? 0, 2)} L/s.',
          'Superar el caudal autorizado puede ser fiscalizado por la DGA.',
        ),
      );
    } else if (c.nearLimit > 0 && af != null) {
      out.add(
        _Finding(
          _Level.info,
          'Caudal cerca del límite',
          '${c.nearLimit} mediciones estuvieron entre el 90 % y el 100 % de '
              'los ${formatCl(af, 2)} L/s autorizados.',
        ),
      );
    }
    final pct = _num(_item['pct_consumed']);
    if (pct != null && pct >= 85) {
      out.add(
        _Finding(
          pct >= 100 ? _Level.critical : _Level.warning,
          pct >= 100
              ? 'Volumen anual autorizado superado'
              : 'Volumen anual cerca del límite',
          'Lleva el ${formatCl(pct, 1)} % del volumen anual autorizado.',
        ),
      );
    }
    final last = c.lastVoucher;
    final isCurrent = _month == _monthOf(DateTime.now());
    if (isCurrent &&
        _active &&
        (_standard == DgaStandard.mayor ||
            _standard == DgaStandard.sinEstandar) &&
        (last == null ||
            DateTime.now().difference(last.at) > const Duration(hours: 3))) {
      out.add(
        _Finding(
          _Level.warning,
          'Sin comprobantes recientes',
          last == null
              ? 'Este mes no hay reportes con comprobante.'
              : 'El último comprobante es del ${_stamp(last.at)}.',
          'Con estándar Mayor debería llegar un comprobante cada hora.',
        ),
      );
    }
    if (out.isEmpty) {
      out.add(
        _Finding(
          _Level.ok,
          'Todos los reportes del mes tienen comprobante',
          c.expected == 0
              ? 'En este período no correspondía reportar.'
              : '${c.delivered} de ${c.expected} reportes entregados a la DGA.',
        ),
      );
    }
    return out;
  }
}

// ------------------------------------------------------------- piezas

class _MonthTabs extends StatelessWidget {
  const _MonthTabs({required this.selected, required this.onChanged});

  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = _monthOf(DateTime.now());
    final months = [
      for (var i = 0; i < 6; i++) DateTime(now.year, now.month - i),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final m in months)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onChanged(m),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    Text(
                      m.year == now.year
                          ? _capitalize(_months[m.month - 1].substring(0, 3))
                          : '${_capitalize(_months[m.month - 1].substring(0, 3))} '
                                '${m.year % 100}',
                      style: TextStyle(
                        color: m == selected ? HydroTone.fog : HydroTone.faint,
                        fontSize: 13,
                        fontWeight: m == selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      width: m == selected ? 18 : 0,
                      height: 2,
                      decoration: BoxDecoration(
                        color: HydroTone.accent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.compliance, required this.active});

  final DgaCompliance compliance;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = compliance;
    final rate = c.rate;
    final (label, color) = rate == null
        ? ('Sin reportes exigidos', HydroTone.faint)
        : rate >= 0.98
        ? ('Al día con la DGA', IkoluColors.connected)
        : rate >= 0.9
        ? ('Cumplimiento parcial', IkoluColors.warning)
        : ('Incumplimiento', IkoluColors.incident);
    final pending = c.count(DgaSlotState.inProgress);
    return Row(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: rate ?? 0),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => SizedBox.square(
            dimension: 96,
            child: CustomPaint(
              painter: _RingPainter(progress: t, color: color),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      rate == null ? '—' : '${(t * 100).floor()} %',
                      style: const TextStyle(
                        color: HydroTone.fog,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'entregado',
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
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${formatCl(c.delivered.toDouble(), 0)} de '
                '${formatCl(c.expected.toDouble(), 0)} reportes con comprobante',
                style: const TextStyle(
                  color: HydroTone.fog,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Estándar ${c.standard.label}: ${c.standard.cadence}'
                '${pending > 0 ? ' · $pending en proceso' : ''}'
                '${active ? '' : ' · envío desactivado'}',
                style: const TextStyle(
                  color: HydroTone.faint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
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
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

enum _Level { critical, warning, info, ok }

class _Finding {
  const _Finding(this.level, this.title, this.detail, [this.action]);

  final _Level level;
  final String title;
  final String detail;
  final String? action;
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final _Finding finding;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (finding.level) {
      _Level.critical => (IkoluColors.incident, Icons.error_outline_rounded),
      _Level.warning => (IkoluColors.warning, Icons.warning_amber_rounded),
      _Level.info => (IkoluColors.info, Icons.info_outline_rounded),
      _Level.ok => (IkoluColors.connected, Icons.verified_outlined),
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
                      color: color,
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

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.compliance,
    required this.selected,
    required this.onSelect,
  });

  final DateTime month;
  final DgaCompliance compliance;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final byDate = {for (final d in compliance.days) d.date: d};
    final offset = month.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = offset + daysInMonth;
    const weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return Column(
      children: [
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(
                      color: HydroTone.faint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row * 7 < cells; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: () {
                        final n = row * 7 + col - offset + 1;
                        if (n < 1 || n > daysInMonth) {
                          return const SizedBox(height: 40);
                        }
                        final date = DateTime(month.year, month.month, n);
                        return _DayCell(
                          day: n,
                          data: byDate[date],
                          selected: selected == date,
                          onTap: byDate[date] == null
                              ? null
                              : () => onSelect(date),
                        );
                      }(),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final DgaDay? data;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = data?.ratio;
    final color = ratio == null
        ? null
        : ratio >= 0.999
        ? IkoluColors.connected
        : ratio >= 0.9
        ? IkoluColors.warning
        : IkoluColors.incident;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: ratio == null
          ? 'Día $day sin reportes exigidos'
          : 'Día $day, ${(ratio * 100).round()} por ciento entregado',
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 40,
          decoration: BoxDecoration(
            color: color == null
                ? Colors.white.withValues(alpha: data == null ? 0.015 : 0.04)
                : color.withValues(alpha: 0.10 + 0.14 * (1 - (ratio ?? 1))),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? HydroTone.fog.withValues(alpha: 0.8)
                  : (color ?? Colors.white).withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  color: data == null
                      ? HydroTone.faint.withValues(alpha: 0.5)
                      : HydroTone.fog,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (color != null)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayDetail extends StatelessWidget {
  const _DayDetail({required this.day});

  final DgaDay? day;

  @override
  Widget build(BuildContext context) {
    final d = day;
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: d == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HydroTone.hair),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.date.day} de ${_months[d.date.month - 1]} · '
                    '${d.count(DgaSlotState.delivered)} de ${d.expected} '
                    'reportes con comprobante',
                    style: const TextStyle(
                      color: HydroTone.fog,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (d.slots.every(
                    (s) =>
                        s.$2 == DgaSlotState.delivered ||
                        s.$2 == DgaSlotState.inProgress,
                  ))
                    const Text(
                      'Todos los reportes del día llegaron a la DGA.',
                      style: TextStyle(color: HydroTone.faint, fontSize: 12),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (hour, state) in d.slots)
                          if (state == DgaSlotState.noData ||
                              state == DgaSlotState.noVoucher)
                            _HourChip(hour: hour, state: state),
                      ],
                    ),
                  const SizedBox(height: 8),
                  const Wrap(
                    spacing: 14,
                    children: [
                      _Legend(
                        color: IkoluColors.incident,
                        text: 'sin medición',
                      ),
                      _Legend(
                        color: IkoluColors.warning,
                        text: 'sin comprobante',
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _HourChip extends StatelessWidget {
  const _HourChip({required this.hour, required this.state});

  final DateTime hour;
  final DgaSlotState state;

  @override
  Widget build(BuildContext context) {
    final color = state == DgaSlotState.noData
        ? IkoluColors.incident
        : IkoluColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${_two(hour.hour)}:00',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        text,
        style: const TextStyle(color: HydroTone.faint, fontSize: 10.5),
      ),
    ],
  );
}

class _Limits extends StatelessWidget {
  const _Limits({
    required this.compliance,
    required this.authorizedFlow,
    required this.authorizedTotal,
    required this.annual,
    required this.pct,
  });

  final DgaCompliance compliance;
  final double? authorizedFlow;
  final double? authorizedTotal;
  final double? annual;
  final double? pct;

  @override
  Widget build(BuildContext context) {
    final c = compliance;
    final af = authorizedFlow;
    final flowRatio = af == null || af <= 0 || c.maxFlow == null
        ? null
        : c.maxFlow! / af;
    final annualRatio = pct != null
        ? pct! / 100
        : annual != null && authorizedTotal != null && authorizedTotal! > 0
        ? annual! / authorizedTotal!
        : null;
    return Column(
      children: [
        _LimitBar(
          label: 'Caudal máximo del mes',
          value: c.maxFlow == null ? '—' : '${formatCl(c.maxFlow!, 2)} L/s',
          limit: af == null
              ? 'sin caudal autorizado'
              : 'de ${formatCl(af, 2)} L/s',
          ratio: flowRatio,
          note: c.exceedances > 0
              ? '${c.exceedances} mediciones sobre el límite'
              : c.nearLimit > 0
              ? '${c.nearLimit} mediciones sobre el 90 %'
              : af == null
              ? null
              : 'Siempre bajo el límite',
        ),
        const SizedBox(height: 16),
        _LimitBar(
          label: 'Volumen del año',
          value: annual == null ? '—' : '${formatCl(annual!, 0)} m³',
          limit: authorizedTotal == null
              ? 'sin volumen anual autorizado'
              : 'de ${formatCl(authorizedTotal!, 0)} m³',
          ratio: annualRatio,
          note: c.volume == null
              ? null
              : 'Este mes: ${formatCl(c.volume!, 1)} m³',
        ),
      ],
    );
  }
}

class _LimitBar extends StatelessWidget {
  const _LimitBar({
    required this.label,
    required this.value,
    required this.limit,
    required this.ratio,
    this.note,
  });

  final String label;
  final String value;
  final String limit;
  final double? ratio;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final r = ratio;
    final color = r == null
        ? HydroTone.faint
        : r > 1
        ? IkoluColors.incident
        : r >= 0.9
        ? IkoluColors.warning
        : IkoluColors.connected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: HydroTone.faint,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 6,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: HydroTone.fog,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                limit,
                style: const TextStyle(
                  color: HydroTone.faint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (r ?? 0).clamp(0.0, 1.2)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => SizedBox(
            height: 7,
            width: double.infinity,
            child: CustomPaint(
              painter: _LimitFillPainter(ratio: t, color: color),
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 5),
          Text(
            note!,
            style: TextStyle(
              color: r != null && r > 1 ? color : HydroTone.faint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _LimitFillPainter extends CustomPainter {
  const _LimitFillPainter({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(
      track,
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );
    final t = ratio.clamp(0.0, 1.0);
    if (t > 0) {
      canvas.save();
      canvas.clipRRect(track);
      final water = Rect.fromLTWH(0, 0, size.width * t, size.height);
      canvas.drawRect(
        water,
        Paint()
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: 0.72), color],
          ).createShader(water),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * t, 1.2),
        Paint()..color = Colors.white.withValues(alpha: 0.45),
      );
      canvas.restore();
    }
    if (ratio > 1) {
      canvas.drawRRect(
        track,
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LimitFillPainter old) =>
      old.ratio != ratio || old.color != color;
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.attempt, required this.onCopy});

  final DgaAttempt attempt;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final a = attempt;
    final (label, color) = switch (a.status) {
      DgaAttemptStatus.sent => ('Enviado', IkoluColors.connected),
      DgaAttemptStatus.queued => ('En cola', HydroTone.accent),
      DgaAttemptStatus.error => ('Rechazado', IkoluColors.incident),
    };
    final values = [
      if (a.flow != null) '${formatCl(a.flow!, 2)} L/s',
      if (a.total != null) '${formatCl(a.total!, 0)} m³',
      if (a.waterTable != null) 'nivel ${formatCl(a.waterTable!, 2)} m',
    ].join(' · ');
    final voucher = isValidVoucher(a.voucher) ? a.voucher!.trim() : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HydroTone.hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _stamp(a.at),
                        style: const TextStyle(
                          color: HydroTone.fog,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (values.isNotEmpty)
                  Text(
                    values,
                    style: const TextStyle(
                      color: HydroTone.faint,
                      fontSize: 11.5,
                    ),
                  ),
                if (voucher != null)
                  InkWell(
                    onTap: () => onCopy(voucher),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Comprobante $voucher',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: HydroTone.accent,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.copy_rounded,
                            size: 12,
                            color: HydroTone.accent,
                          ),
                        ],
                      ),
                    ),
                  )
                else if ((a.response ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Respuesta DGA: ${a.response!.trim()}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.9),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: HydroTone.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: HydroTone.accent, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: HydroTone.fog,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: HydroTone.faint,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          busy
              ? const HydroSpinner(size: 18, strokeWidth: 2)
              : Icon(
                  Icons.download_rounded,
                  color: onTap == null
                      ? HydroTone.faint.withValues(alpha: 0.4)
                      : HydroTone.accent,
                ),
        ],
      ),
    ),
  );
}

abstract final class _Gob {
  static const azulClaro = Color(0xFFC3DFF4);
  static const rojo = Color(0xFFEB3C46);
}

class _IdentityBand extends StatelessWidget {
  const _IdentityBand({
    required this.title,
    required this.code,
    required this.meta,
    required this.status,
    required this.facts,
    required this.onBack,
    required this.onVerify,
  });

  final String title;
  final String? code;
  final String meta;
  final (String, Color)? status;
  final List<(String, String)> facts;
  final VoidCallback? onBack;
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final state = status;
    return HydroGlassLight(
      radius: 18,
      strength: 0.85,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (onBack != null) ...[
                InkWell(
                  key: const Key('compliance-back-to-list'),
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(0, 4, 10, 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_back_rounded,
                          size: 18,
                          color: _Gob.azulClaro,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Volver',
                          style: TextStyle(
                            color: _Gob.azulClaro,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: HydroTone.fog,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (state != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 8),
                  child: Text(
                    state.$1,
                    style: TextStyle(
                      color: state.$2,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            code ?? 'Sin código de obra',
            style: TextStyle(
              color: code == null ? HydroTone.faint : _Gob.azulClaro,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              meta,
              style: const TextStyle(
                color: HydroTone.faint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                for (final (label, value) in facts)
                  SizedBox(
                    width: 148,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HydroTone.faint,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HydroTone.fog,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (onVerify != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onVerify,
              style: TextButton.styleFrom(
                foregroundColor: _Gob.azulClaro,
                backgroundColor: _Gob.azulClaro.withValues(alpha: 0.08),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Ver la obra en el portal de la DGA'),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ formato

DateTime _monthOf(DateTime t) => DateTime(t.year, t.month);

String _gapText(DgaGap g) {
  final day = '${g.start.day}/${_two(g.start.month)}';
  final range = g.count == 1
      ? '${_two(g.start.hour)}:00'
      : '${_two(g.start.hour)}:00–${_two(g.end.hour)}:00';
  return g.start.day == g.end.day
      ? '$day $range'
      : '${_stamp(g.start)} a ${_stamp(g.end)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

String _ym(DateTime t) => '${t.year}-${_two(t.month)}';

String _date(DateTime t) => '${_two(t.day)}/${_two(t.month)}/${t.year}';

String _stamp(DateTime t) =>
    '${_two(t.day)}/${_two(t.month)} ${_two(t.hour)}:${_two(t.minute)}';

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String? _str(dynamic v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}
