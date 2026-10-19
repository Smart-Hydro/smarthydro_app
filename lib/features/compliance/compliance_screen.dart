import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../shared/navigation/hydro_page_route.dart';
import '../../shared/ui/hydro_ui.dart';
import '../../shared/widgets/hydro_glass.dart';
import 'compliance_store.dart';
import 'point_compliance_screen.dart';

/// Azul, azul claro y rojo del Kit Digital de Gobierno de Chile
/// (Pantone 293 C, 544 C y 185 C). El indicador de cumplimiento no usa otra paleta.
abstract final class _Gobierno {
  static const azul = Color(0xFF0F69B4);
  static const azulClaro = Color(0xFFC3DFF4);
  static const rojo = Color(0xFFEB3C46);
}

class ComplianceScreen extends StatefulWidget {
  const ComplianceScreen({
    required this.api,
    required this.token,
    this.showBack = true,
    this.seed,
    this.store,
    super.key,
  });

  final SmartHydroApi api;
  final String token;

  /// En el shell de escritorio el rail reemplaza a Volver.
  final bool showBack;

  /// Listado que el dashboard ya trajo. Evita el skeleton de entrada.
  final List<Map<String, dynamic>>? seed;

  final ComplianceStore? store;

  @override
  State<ComplianceScreen> createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> {
  List<Map<String, dynamic>> _points = const [];
  bool _loading = true;
  bool _refreshing = false;
  bool _activeOnly = false;
  String _typeFilter = 'ALL';
  String? _error;
  Map<String, dynamic>? _selected;
  bool _wide = false;

  ComplianceStore get _store => widget.store ?? ComplianceStore.instance;

  @override
  void initState() {
    super.initState();
    final cached = _store.list(widget.token);
    final seed = widget.seed;
    if (cached != null) {
      _points = cached;
      _loading = false;
    } else if (seed != null && seed.isNotEmpty) {
      _points = seed;
      _loading = false;
      _store.putList(widget.token, seed);
    }
    if (!_store.listIsFresh(widget.token)) {
      _load(silent: _points.isNotEmpty);
    }
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (force) _store.invalidate(widget.token);
    if (!silent) {
      setState(() {
        _loading = _points.isEmpty;
        _refreshing = _points.isNotEmpty;
        _error = null;
      });
    } else if (mounted) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }
    try {
      final points = await widget.api.compliancePoints(
        widget.token,
        pageSize: 200,
      );
      _store.putList(widget.token, points);
      if (!mounted) return;
      setState(() {
        _points = points;
        _loading = false;
        _refreshing = false;
        if (_typeFilter != 'ALL' && !_availableTypes.contains(_typeFilter)) {
          _typeFilter = 'ALL';
        }
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (_points.isEmpty) _error = error.message;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Set<String> get _availableTypes {
    final types = <String>{};
    for (final point in _points) {
      final raw = point['compliance_type'];
      if (raw is List) {
        for (final type in raw) {
          types.add('$type');
        }
      }
    }
    return types;
  }

  List<Map<String, dynamic>> get _visiblePoints {
    final source = _activeOnly
        ? _points
              .where((point) => point['compliance_active'] == true)
              .toList()
        : [..._points];
    final visible = _typeFilter == 'ALL'
        ? source
        : source.where((point) {
            final raw = point['compliance_type'];
            return raw is List &&
                raw.map((type) => '$type').contains(_typeFilter);
          }).toList();
    visible.sort(_exceedsFirst);
    return visible;
  }

  void _openPoint(Map<String, dynamic> point) {
    if (_wide) {
      setState(() => _selected = point);
      return;
    }
    Navigator.of(context).push<void>(
      hydroPageRoute(
        PointComplianceScreen(
          api: widget.api,
          token: widget.token,
          pointId: _toInt(point['point_id']),
          pointTitle: point['point_name']?.toString(),
          store: _store,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final types = _availableTypes;
    final points = _visiblePoints;
    return HydroPage(
      title: '',
      showBack: widget.showBack,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          _wide = wide;
          final selected = _selected;
          final pane = selected != null
              ? PointComplianceScreen(
                  key: ValueKey(
                    'compliance-open-${_toInt(selected['point_id'])}',
                  ),
                  api: widget.api,
                  token: widget.token,
                  pointId: _toInt(selected['point_id']),
                  pointTitle: selected['point_name']?.toString(),
                  embedded: true,
                  store: _store,
                  onBackToList: () => setState(() => _selected = null),
                )
              : ListView(
                  key: Key(
                    wide
                        ? 'compliance-layout-wide'
                        : 'compliance-layout-narrow',
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
              _FilterBar(
                activeOnly: _activeOnly,
                types: types,
                selected: _typeFilter,
                refreshing: _refreshing,
                onActive: (value) => setState(() => _activeOnly = value),
                onType: (type) => setState(() => _typeFilter = type),
                onRefresh: () => _load(force: true),
              ),
              const SizedBox(height: 12),
              if (_loading && _points.isEmpty)
                const HydroSkeletonCards(height: 88)
              else if (_loading)
                const HydroLinearBar(),
              if (_error != null)
                _ErrorCard(
                  message: _error!,
                  onRetry: () => _load(force: true),
                ),
              if (!_loading && _error == null && _points.isEmpty)
                const _EmptyCompliance(),
              if (points.isNotEmpty) ...[
                _StatusStrip(points: points),
                const SizedBox(height: 12),
                _PointGrid(wide: wide, points: points, onOpen: _openPoint),
              ],
            ],
          );
          return AnimatedSwitcher(
            duration: HydroMotion.of(
              context,
              const Duration(milliseconds: 440),
            ),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, animation) {
              final id = child.key is ValueKey
                  ? '${(child.key as ValueKey).value}'
                  : '';
              final fromRight = id.startsWith('compliance-open');
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: Offset(fromRight ? 0.07 : -0.04, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                ),
              );
            },
            child: pane,
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.activeOnly,
    required this.types,
    required this.selected,
    required this.refreshing,
    required this.onActive,
    required this.onType,
    required this.onRefresh,
  });

  final bool activeOnly;
  final Set<String> types;
  final String selected;
  final bool refreshing;
  final ValueChanged<bool> onActive;
  final ValueChanged<String> onType;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Solo activos', style: HydroText.subtitle),
        Switch.adaptive(
          value: activeOnly,
          activeTrackColor: _Gobierno.azul,
          activeThumbColor: _Gobierno.azulClaro,
          onChanged: onActive,
        ),
        if (types.length > 1) ...[
          _TypeChip(
            label: 'Todos',
            selected: selected == 'ALL',
            onTap: () => onType('ALL'),
          ),
          for (final type in ['DGA', 'SMA'])
            if (types.contains(type))
              _TypeChip(
                label: type,
                selected: selected == type,
                onTap: () => onType(type),
              ),
        ],
        _RefreshChip(busy: refreshing, onTap: refreshing ? null : onRefresh),
      ],
    );
  }
}

class _RefreshChip extends StatelessWidget {
  const _RefreshChip({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = busy
        ? _Gobierno.azulClaro.withValues(alpha: 0.55)
        : _Gobierno.azulClaro;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const Key('compliance-refresh'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: busy ? 0.7 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _Gobierno.azul.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: _Gobierno.azulClaro,
                    ),
                  )
                else
                  Icon(Icons.refresh_rounded, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  busy ? 'Actualizando' : 'Actualizar',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.points});

  final List<Map<String, dynamic>> points;

  @override
  Widget build(BuildContext context) {
    var dentro = 0;
    var cerca = 0;
    var excede = 0;
    for (final point in points) {
      switch (_warningLevel(point)) {
        case 'critical':
          excede++;
        case 'warning':
          cerca++;
        case 'safe':
          dentro++;
      }
    }
    return Row(
      children: [
        Expanded(
          child: _CountPill(
            label: 'Dentro',
            count: dentro,
            color: _Gobierno.azulClaro,
            dot: _Gobierno.azul,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountPill(
            label: 'Cerca',
            count: cerca,
            color: _Gobierno.azulClaro,
            dot: _Gobierno.rojo,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountPill(
            label: 'Excede',
            count: excede,
            color: _Gobierno.rojo,
          ),
        ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.count,
    required this.color,
    Color? dot,
  }) : dot = dot ?? color;

  final String label;
  final int count;
  final Color color;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return HydroGlassLight(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      radius: 16,
      strength: 0.7,
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HydroTone.faint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PointGrid extends StatelessWidget {
  const _PointGrid({
    required this.wide,
    required this.points,
    required this.onOpen,
  });

  final bool wide;
  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    Widget card(Map<String, dynamic> point) =>
        _CompliancePointCard(point: point, onTap: () => onOpen(point));
    if (!wide) {
      return Column(
        children: [
          for (var i = 0; i < points.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            card(points[i]),
          ],
        ],
      );
    }
    const columns = 3;
    final rows = <Widget>[];
    for (var i = 0; i < points.length; i += columns) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 12),
                Expanded(
                  child: i + column < points.length
                      ? card(points[i + column])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: HydroMotion.of(context, HydroMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? _Gobierno.azul.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _Gobierno.azulClaro : HydroTone.faint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompliancePointCard extends StatelessWidget {
  const _CompliancePointCard({required this.point, required this.onTap});

  final Map<String, dynamic> point;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final warning = _warningLevel(point);
    final authFlow = _numOrNull(point['authorized_flow']);
    final currentFlow = _numOrNull(point['flow']) ?? 0;
    final flowRatio = authFlow != null && authFlow > 0
        ? currentFlow / authFlow
        : null;
    final pctTotal = _numOrNull(point['pct_consumed']);
    final volumeRatio = pctTotal == null ? null : pctTotal / 100;
    final mark = _worstRatio(flowRatio, volumeRatio);
    final (status, statusColor) = _statusOf(warning);
    final types = point['compliance_type'];
    final agency = types is List && types.isNotEmpty
        ? types.map((type) => '$type').join(' · ')
        : 'DGA';
    final meta = [
      agency,
      if (point['code'] != null) '${point['code']}',
      '${point['client_name'] ?? 'Cliente'}',
    ].join(' · ');
    final level = _numOrNull(point['water_table'] ?? point['nivel']);
    final surface = _isSurface(point);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: HydroGlassLight(
          radius: 18,
          strength: 0.85,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _WaterMark(ratio: mark, level: warning, surface: surface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                point['point_name']?.toString() ?? 'Punto',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: HydroTone.fog,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HydroTone.faint,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Última medición',
                style: TextStyle(
                  color: HydroTone.faint,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              _LastReading(
                flow: currentFlow,
                authorizedFlow: authFlow,
                flowRatio: flowRatio,
                pct: pctTotal,
                volumeRatio: volumeRatio,
                annual: point['annual_consumption'],
                waterTable: level,
                surface: surface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaterMark extends StatelessWidget {
  const _WaterMark({
    required this.ratio,
    required this.level,
    required this.surface,
  });

  final double? ratio;
  final String level;
  final bool surface;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      'critical' => _Gobierno.rojo,
      'warning' || 'safe' => _Gobierno.azul,
      _ => _Gobierno.azulClaro.withValues(alpha: 0.35),
    };
    return Semantics(
      label: surface
          ? 'Canal. ${_statusOf(level).$1}'
          : 'Columna de agua. ${_statusOf(level).$1}',
      child: SizedBox(
        width: 22,
        height: 36,
        child: CustomPaint(
          painter: _WaterPainter(
            ratio: ratio,
            color: color,
            level: level,
            surface: surface,
          ),
        ),
      ),
    );
  }
}

class _WaterPainter extends CustomPainter {
  const _WaterPainter({
    required this.ratio,
    required this.color,
    required this.level,
    required this.surface,
  });

  final double? ratio;
  final Color color;
  final String level;
  final bool surface;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = (ratio ?? 0).clamp(0.0, 1.0);
    if (surface) {
      _paintChannel(canvas, size, fill);
    } else {
      _paintWell(canvas, size, fill);
    }
  }

  void _paintWell(Canvas canvas, Size size, double fill) {
    final tubeW = 10.0;
    final left = (size.width - tubeW) / 2;
    final casing = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, 0, tubeW, size.height),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      casing,
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );
    canvas.drawRRect(
      casing,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.save();
    canvas.clipRRect(casing);
    if (fill > 0) {
      final height = size.height * fill;
      final water = Rect.fromLTWH(0, size.height - height, size.width, height);
      canvas.drawRect(
        water,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.75),
              color,
            ],
          ).createShader(water),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - height, size.width, 1.4),
        Paint()..color = _Gobierno.azulClaro.withValues(alpha: 0.95),
      );
      canvas.drawRect(
        Rect.fromLTWH(2, size.height - height + 2, 2, (height - 4).clamp(0, 8)),
        Paint()..color = Colors.white.withValues(alpha: 0.28),
      );
    }
    canvas.restore();
    final cap = switch (level) {
      'warning' || 'critical' => _Gobierno.rojo,
      _ => Colors.white.withValues(alpha: 0.34),
    };
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, 3),
        const Radius.circular(1.5),
      ),
      Paint()..color = cap,
    );
  }

  void _paintChannel(Canvas canvas, Size size, double fill) {
    final bed = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height * 0.28, size.width, size.height * 0.72),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      bed,
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );
    canvas.drawRRect(
      bed,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.save();
    canvas.clipRRect(bed);
    if (fill > 0) {
      final width = size.width * fill;
      final water = Rect.fromLTWH(
        0,
        size.height * 0.28,
        width,
        size.height * 0.72,
      );
      canvas.drawRect(
        water,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              color.withValues(alpha: 0.55),
              color,
            ],
          ).createShader(water),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * 0.28, width, 1.4),
        Paint()..color = _Gobierno.azulClaro.withValues(alpha: 0.95),
      );
    }
    canvas.restore();
    final lip = switch (level) {
      'warning' || 'critical' => _Gobierno.rojo,
      _ => Colors.white.withValues(alpha: 0.34),
    };
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.22, size.width, 2.2),
        const Radius.circular(1),
      ),
      Paint()..color = lip,
    );
  }

  @override
  bool shouldRepaint(covariant _WaterPainter old) =>
      old.ratio != ratio ||
      old.color != color ||
      old.level != level ||
      old.surface != surface;
}

class _LastReading extends StatelessWidget {
  const _LastReading({
    required this.flow,
    required this.authorizedFlow,
    required this.flowRatio,
    required this.pct,
    required this.volumeRatio,
    required this.annual,
    required this.waterTable,
    required this.surface,
  });

  final double flow;
  final double? authorizedFlow;
  final double? flowRatio;
  final double? pct;
  final double? volumeRatio;
  final dynamic annual;
  final double? waterTable;
  final bool surface;

  @override
  Widget build(BuildContext context) {
    final flowBreach = flowRatio != null && flowRatio! >= 1;
    final volumeBreach =
        (volumeRatio != null && volumeRatio! >= 1) ||
        (pct != null && pct! >= 100);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ReadingCell(
            label: 'Caudal',
            value: _fmt(flow),
            unit: authorizedFlow == null
                ? 'L/s'
                : '/ ${_fmt(authorizedFlow)} L/s',
            color: flowBreach ? _Gobierno.rojo : _Gobierno.azulClaro,
          ),
        ),
        const _ReadingSplit(),
        Expanded(
          child: _ReadingCell(
            label: 'Volumen',
            value: pct == null ? _fmt(annual) : '${pct!.toStringAsFixed(0)}%',
            unit: '${_fmt(annual)} m³',
            color: volumeBreach ? _Gobierno.rojo : _Gobierno.azulClaro,
          ),
        ),
        const _ReadingSplit(),
        Expanded(
          child: _ReadingCell(
            label: 'Nivel',
            value: waterTable == null ? '—' : _fmt(waterTable),
            unit: surface ? 'm' : 'm freático',
            color: waterTable == null ? HydroTone.faint : _Gobierno.azulClaro,
          ),
        ),
      ],
    );
  }
}

class _ReadingSplit extends StatelessWidget {
  const _ReadingSplit();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 36,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Colors.white.withValues(alpha: 0.1),
  );
}

class _ReadingCell extends StatelessWidget {
  const _ReadingCell({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        Text(
          unit,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: HydroTone.faint,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EmptyCompliance extends StatelessWidget {
  const _EmptyCompliance();

  @override
  Widget build(BuildContext context) => const HydroMessage(
    icon: Icons.water_drop_outlined,
    title: 'Sin captaciones DGA',
    message: 'No hay puntos con ficha de cumplimiento para mostrar.',
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return HydroGlassLight(
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _Gobierno.rojo),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: HydroTone.fog, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: onRetry,
            tooltip: 'Reintentar',
            icon: const Icon(Icons.refresh_rounded, color: _Gobierno.azulClaro),
          ),
        ],
      ),
    );
  }
}

(String, Color) _statusOf(String level) => switch (level) {
  'critical' => ('Excede', _Gobierno.rojo),
  'warning' => ('Cerca', _Gobierno.azulClaro),
  'safe' => ('Dentro', _Gobierno.azulClaro),
  _ => ('Sin límite', HydroTone.faint),
};

double? _worstRatio(double? flow, double? volume) {
  if (flow == null) return volume;
  if (volume == null) return flow;
  return flow > volume ? flow : volume;
}

String _warningLevel(Map<String, dynamic> point) {
  final warning = point['compliance_warning'];
  if (warning is Map && warning['level'] is String) {
    return warning['level'] as String;
  }
  return 'unknown';
}

int _exceedsFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
  final rank = _exceedRank(a).compareTo(_exceedRank(b));
  if (rank != 0) return rank;
  final pressure = _pressure(b).compareTo(_pressure(a));
  if (pressure != 0) return pressure;
  return '${a['point_name'] ?? ''}'.compareTo('${b['point_name'] ?? ''}');
}

/// Quien se pasa de caudal o de volumen va primero. Después, quien está cerca.
int _exceedRank(Map<String, dynamic> point) {
  final level = _warningLevel(point);
  final auth = _numOrNull(point['authorized_flow']);
  final flow = _numOrNull(point['flow']);
  final pct = _numOrNull(point['pct_consumed']);
  final overFlow = auth != null && auth > 0 && flow != null && flow > auth;
  final overVolume = pct != null && pct >= 100;
  if (level == 'critical' || overFlow || overVolume) return 0;
  final nearFlow =
      auth != null && auth > 0 && flow != null && flow / auth >= 0.9;
  final nearVolume = pct != null && pct >= 80;
  if (level == 'warning' || nearFlow || nearVolume) return 1;
  if (level == 'safe') return 2;
  return 3;
}

double _pressure(Map<String, dynamic> point) {
  final auth = _numOrNull(point['authorized_flow']);
  final flow = _numOrNull(point['flow']);
  final flowRatio = auth != null && auth > 0 && flow != null
      ? flow / auth
      : 0.0;
  final pct = _numOrNull(point['pct_consumed']);
  final volumeRatio = pct == null ? 0.0 : pct / 100;
  return flowRatio > volumeRatio ? flowRatio : volumeRatio;
}

int _toInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

bool _isSurface(Map<String, dynamic> point) =>
    '${point['type_dga']}'.toUpperCase() == 'SUPERFICIAL';

double? _numOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

String _fmt(dynamic value) {
  final number = _numOrNull(value);
  if (number == null) return '—';
  return number == number.roundToDouble()
      ? number.toStringAsFixed(0)
      : number.toStringAsFixed(2);
}
