import 'package:flutter/material.dart';

import '../../../core/api/smarthydro_api.dart';
import '../point_meta.dart';

/// Ficha única para crear un punto de cero o editar el que está abierto.
class PointConfigCard extends StatefulWidget {
  const PointConfigCard({
    required this.onClose,
    this.point,
    this.token,
    this.userId,
    this.api,
    this.onSaved,
    this.initialPanel,
    this.knownPoints = const [],
    super.key,
  });

  /// Punto del esquema. Nulo cuando se crea uno nuevo.
  final Map<String, dynamic>? point;
  final String? token;
  final int? userId;
  final SmartHydroApi? api;
  final VoidCallback? onSaved;
  final VoidCallback onClose;

  /// Puntos de la cuenta ya cargados. El select de proyecto sale de aquí.
  final List<Map<String, dynamic>> knownPoints;

  /// point, telemetry, compliance, physical o scheme. Nulo abre Punto.
  final String? initialPanel;

  @override
  State<PointConfigCard> createState() => _PointConfigCardState();
}

class _PointConfigCardState extends State<PointConfigCard> {
  final _title = TextEditingController();
  final _frequency = TextEditingController(text: '60');
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  final _code = TextEditingController();
  final _flowGranted = TextEditingController();
  final _totalGranted = TextEditingController();
  final _shac = TextEditingController();
  final _region = TextEditingController();
  final _d1 = TextEditingController();
  final _d2 = TextEditingController();
  final _d3 = TextEditingController();
  final _d4 = TextEditingController();
  final _d5 = TextEditingController();
  final _d6 = TextEditingController();
  final _offset = TextEditingController();
  final _maxFlow = TextEditingController();
  final _maxDiff = TextEditingController();
  final _gapHours = TextEditingController();
  final _reconnect = TextEditingController();
  final _sendStart = TextEditingController();
  final _schemeName = TextEditingController();
  final _schemeDescription = TextEditingController();

  List<Map<String, dynamic>> _projects = const [];
  List<Map<String, dynamic>> _schemes = const [];
  final List<_VariableDraft> _rows = [];
  final List<int> _deletedVariableIds = [];
  int? _projectId;
  int? _savedPointId;
  int? _schemeId;
  int? _linkedSchemeId;
  var _sharedScheme = false;
  var _schemePick = false;
  int? _dgaId;
  var _provider = 'none';
  var _surface = false;
  var _telemetry = true;
  var _dga = false;
  var _standard = 'SIN_ESTANDAR';
  var _loading = false;
  var _saving = false;
  String? _error;
  var _panel = _ConfigPanel.point;

  bool get _creating => widget.point == null;

  String get _agency => _dga ? 'DGA' : 'SMA';

  @override
  void initState() {
    super.initState();
    _panel = switch (widget.initialPanel) {
      'telemetry' => _ConfigPanel.telemetry,
      'compliance' => _ConfigPanel.compliance,
      'physical' => _ConfigPanel.physical,
      'scheme' => _ConfigPanel.scheme,
      _ => _ConfigPanel.point,
    };
    final point = widget.point;
    if (point != null) _seedFromPoint(point);
    _projects = configProjectsOf(_knownScope);
    _projectId ??= configProjectId(
      _projects.isEmpty ? null : _projects.first['id'],
    );
    if (_rows.isEmpty) _rows.add(_VariableDraft());
    _load();
  }

  Iterable<Map<String, dynamic>> get _knownScope => [
    ...widget.knownPoints,
    if (widget.point != null) widget.point!,
  ];

  @override
  void dispose() {
    for (final field in [
      _title,
      _frequency,
      _lat,
      _lon,
      _code,
      _flowGranted,
      _totalGranted,
      _shac,
      _region,
      _d1,
      _d2,
      _d3,
      _d4,
      _d5,
      _d6,
      _offset,
      _maxFlow,
      _maxDiff,
      _gapHours,
      _reconnect,
      _sendStart,
      _schemeName,
      _schemeDescription,
    ]) {
      field.dispose();
    }
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _seedFromPoint(Map<String, dynamic> point) {
    _applyDetail(point);
    _applyConfig(configPayloadOf(point));
    final dga = dgaRowsOf(point);
    if (dga.isNotEmpty) _applyDga(dga);
    final variables = variableMapsOf(point);
    if (variables.isNotEmpty) _applyScheme(const [], variables);
  }

  Future<void> _load() async {
    final token = widget.token;
    final api = widget.api;
    if (token == null || token.isEmpty || api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final id = _pointId(widget.point);
    final knownIds = [
      for (final point in _knownScope)
        if (_pointId(point) != null) _pointId(point)!,
    ];
    final needCatalog =
        _hasUnresolvedProjectName(_knownScope) ||
        (_projects.isEmpty && _hasProjectHint(_knownScope));
    final needSchemeCatalog = knownIds.length > 1 || id == null;
    final projectsTask = needCatalog ? api.projects(token) : null;
    final detailTask = id == null ? null : api.catchmentPoint(token, id);
    final configTask = id == null ? null : api.pointConfig(token, id);
    final dgaTask = id == null ? null : api.pointDgaConfigs(token, id);
    final schemesTask = id == null ? null : api.schemesForPoint(token, id);
    final schemeCatalogTask = needSchemeCatalog && knownIds.isNotEmpty
        ? api.schemes(token)
        : null;
    String? loadError;
    Future<T?> guard<T>(Future<T>? task) async {
      if (task == null) return null;
      try {
        return await task;
      } on SmartHydroApiException catch (error) {
        loadError ??= error.message;
        return null;
      }
    }

    try {
      final catalog = await guard(projectsTask);
      final detail = await guard(detailTask);
      final config = await guard(configTask);
      final dga = await guard(dgaTask);
      final schemes =
          await guard(schemesTask) ?? const <Map<String, dynamic>>[];
      final schemeCatalog =
          await guard(schemeCatalogTask) ?? const <Map<String, dynamic>>[];
      var variables = const <Map<String, dynamic>>[];
      final schemeId = schemes.isEmpty
          ? null
          : configProjectId(schemes.first['id']);
      if (schemeId != null) {
        variables =
            await guard(api.schemeVariables(token, schemeId)) ?? const [];
      }
      if (!mounted) return;
      setState(() {
        if (catalog != null) {
          final scoped = configProjectsFromCatalog(catalog, _knownScope);
          if (scoped.isNotEmpty) _projects = scoped;
        }
        _schemes = _mergeSchemes(
          configSchemesOf(schemeCatalog, knownIds),
          schemes,
        );
        _applyDetail(detail);
        _adoptOpenProject();
        _applyConfig(config);
        if (dga != null && dga.isNotEmpty) _applyDga(dga);
        _applyScheme(schemes, variables);
        _matchProjectName(_projects);
        _projectId ??= configProjectId(
          _projects.isEmpty ? null : _projects.first['id'],
        );
        _error = loadError;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _adoptOpenProject() {
    final id = _projectId;
    if (id == null) return;
    if (_projects.any((project) => configProjectId(project['id']) == id)) {
      return;
    }
    final name = configProjectName(widget.point ?? const {});
    _projects = [
      ..._projects,
      {'id': id, 'name': name.isEmpty ? 'Proyecto $id' : name},
    ];
  }

  void _matchProjectName(List<Map<String, dynamic>> projects) {
    if (_projectId != null) return;
    final name = '${widget.point?['project_name'] ?? ''}'.trim();
    if (name.isEmpty) return;
    for (final project in projects) {
      if ('${project['name'] ?? ''}'.trim() == name) {
        _projectId = configProjectId(project['id']);
        return;
      }
    }
  }

  void _applyDetail(Map<String, dynamic>? detail) {
    if (detail == null) return;
    final title = '${detail['title'] ?? ''}'.trim();
    if (title.isNotEmpty) _title.text = title;
    final frequency = detail['frecuency'] ?? detail['frequency'];
    if (frequency != null &&
        '$frequency'.trim().isNotEmpty &&
        '$frequency' != 'null') {
      _frequency.text = '$frequency';
    }
    final lat = _text(detail['lat'] ?? detail['latitude']);
    if (lat.isNotEmpty) _lat.text = lat;
    final lon = _text(detail['lon'] ?? detail['lng'] ?? detail['longitude']);
    if (lon.isNotEmpty) _lon.text = lon;
    final projectId =
        configProjectId(detail['project']) ??
        configProjectId(detail['project_id']) ??
        configProjectId(detail['project_catchment']);
    if (projectId != null) _projectId = projectId;
    final kind = '${detail['type_dga'] ?? ''}'.toUpperCase();
    if (kind == 'SUPERFICIAL' || kind == 'SUBTERRANEO') {
      _surface = kind == 'SUPERFICIAL';
    }
    final provider = configProviderKey(detail);
    if (provider != 'none') _provider = provider;
  }

  void _applyConfig(Map<String, dynamic>? config) {
    if (config == null) return;
    const keys = [
      'd1',
      'd2',
      'd3',
      'd4',
      'd5',
      'd6',
      'nivel_offset',
      'max_flow_ls',
      'max_diff_m3_per_hour',
      'max_time_gap_hours',
      'reconnection_threshold_hours',
      'is_telemetry',
    ];
    if (!keys.any(config.containsKey)) return;
    _d1.text = _text(config['d1']);
    _d2.text = _text(config['d2']);
    _d3.text = _text(config['d3']);
    _d4.text = _text(config['d4']);
    _d5.text = _text(config['d5']);
    _d6.text = _text(config['d6']);
    _offset.text = _text(config['nivel_offset']);
    _maxFlow.text = _text(config['max_flow_ls']);
    _maxDiff.text = _text(config['max_diff_m3_per_hour']);
    _gapHours.text = _text(config['max_time_gap_hours']);
    _reconnect.text = _text(config['reconnection_threshold_hours']);
    if (config.containsKey('is_telemetry')) {
      _telemetry = config['is_telemetry'] != false;
    }
  }

  void _applyDga(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return;
    final row = rows.first;
    _dgaId = _intOf(row['id']);
    _dga = row['send_dga'] == true;
    final kind = '${row['type_dga'] ?? ''}'.toUpperCase();
    if (kind == 'SUPERFICIAL' || kind == 'SUBTERRANEO') {
      _surface = kind == 'SUPERFICIAL';
    }
    final standard = '${row['standard'] ?? ''}';
    if (standard.isNotEmpty && standard != 'null') _standard = standard;
    _code.text = _text(row['code_dga'] ?? row['code']);
    _flowGranted.text = _text(
      row['flow_granted_dga'] ?? row['authorized_flow'],
    );
    _totalGranted.text = _text(
      row['total_granted_dga'] ?? row['authorized_total'],
    );
    _shac.text = _text(row['shac']);
    _region.text = _text(row['region_dga'] ?? row['region']);
    _sendStart.text = _text(row['date_start_compliance']);
  }

  void _applyScheme(
    List<Map<String, dynamic>> schemes,
    List<Map<String, dynamic>> variables,
  ) {
    if (schemes.isEmpty && variables.isEmpty) return;
    final previous = List<_VariableDraft>.of(_rows);
    final scheme = schemes.isEmpty ? null : schemes.first;
    _schemeId = scheme == null ? null : _intOf(scheme['id']);
    _linkedSchemeId = _schemeId;
    _sharedScheme = configSchemePointIds(scheme ?? const {}).length > 1;
    _schemePick = _sharedScheme;
    if (scheme != null) {
      final name = _text(scheme['name']);
      final description = _text(scheme['description']);
      _schemeName.text = name;
      _schemeDescription.text = description == name ? '' : description;
    }
    final next = <_VariableDraft>[
      for (final variable in variables) _VariableDraft.fromMap(variable),
    ];
    if (next.isEmpty) {
      final keepSeed = previous.any(
        (row) =>
            row.id != null ||
            row.code.text.trim().isNotEmpty ||
            row.label.text.trim().isNotEmpty,
      );
      if (keepSeed) return;
      next.add(_VariableDraft());
    }
    _rows
      ..clear()
      ..addAll(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in previous) {
        row.dispose();
      }
    });
  }

  void _addVariable() {
    setState(() => _rows.add(_VariableDraft()));
  }

  void _removeVariable(_VariableDraft row) {
    setState(() {
      final id = row.id;
      if (id != null) _deletedVariableIds.add(id);
      _rows.remove(row);
      if (_rows.isEmpty) _rows.add(_VariableDraft());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  void _setSchemePick(bool pick) {
    setState(() {
      _schemePick = pick;
      if (pick) {
        final ids = [
          for (final scheme in _schemes)
            if (configProjectId(scheme['id']) != null)
              configProjectId(scheme['id'])!,
        ];
        if (_schemeId == null || !ids.contains(_schemeId)) {
          _schemeId = ids.isEmpty ? null : ids.first;
        }
        final selected = _schemeOf(_schemeId);
        _sharedScheme = configSchemePointIds(selected ?? const {}).length > 1;
        return;
      }
      if (_sharedScheme || _schemeId != _linkedSchemeId) {
        _schemeId = null;
        _sharedScheme = false;
        _deletedVariableIds.clear();
        for (final row in _rows) {
          row.id = null;
        }
      }
    });
  }

  Map<String, dynamic>? _schemeOf(int? id) {
    if (id == null) return null;
    for (final scheme in _schemes) {
      if (configProjectId(scheme['id']) == id) return scheme;
    }
    return null;
  }

  String? _schemeProblem() {
    if (_schemePick) {
      if (_schemes.isEmpty) {
        return 'Crea un esquema para este punto. No hay otros en tus puntos.';
      }
      if (_schemeId == null) return 'Elige un esquema existente.';
      return null;
    }
    var content = false;
    for (final row in _rows) {
      final label = row.label.text.trim();
      final code = row.code.text.trim();
      if (label.isEmpty && code.isEmpty) continue;
      if (label.isEmpty || code.isEmpty) {
        return 'Cada variable necesita etiqueta y código.';
      }
      content = true;
      if (_isTotalizer(row.type)) {
        final pulses = row.pulses.text.trim();
        if (pulses.isNotEmpty && int.tryParse(pulses) == null) {
          return 'El factor de pulsos tiene que ser un número entero.';
        }
      }
      if (row.type == 'NIVEL') {
        final base = row.nivel.text.trim();
        if (base.isNotEmpty && int.tryParse(base) == null) {
          return 'La base de nivel tiene que ser un número entero.';
        }
      }
      for (final pair in [(row.min, 'El mínimo'), (row.max, 'El máximo')]) {
        final raw = pair.$1.text.trim();
        if (raw.isEmpty) continue;
        if (double.tryParse(raw.replaceAll(',', '.')) == null) {
          return '${pair.$2} tiene que ser un número.';
        }
      }
    }
    final name = _schemeName.text.trim();
    final described = _schemeDescription.text.trim().isNotEmpty;
    final needed = content || name.isNotEmpty || described || _schemeId != null;
    if (needed && name.isEmpty) return 'El esquema necesita un nombre.';
    return null;
  }

  bool get _schemeNeeded {
    if (_schemePick) return _schemeId != null;
    if (_schemeId != null) return true;
    if (_schemeName.text.trim().isNotEmpty) return true;
    if (_schemeDescription.text.trim().isNotEmpty) return true;
    for (final row in _rows) {
      if (row.label.text.trim().isNotEmpty || row.code.text.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<void> _saveScheme(String token, SmartHydroApi api, int pointId) async {
    if (!_schemeNeeded) return;
    if (_schemePick) {
      await _linkPickedScheme(token, api, pointId);
      return;
    }
    final reuse =
        _schemeId != null && !_sharedScheme && _schemeId == _linkedSchemeId;
    if (!reuse) {
      _schemeId = null;
      _deletedVariableIds.clear();
      for (final row in _rows) {
        row.id = null;
      }
    }
    final name = _schemeName.text.trim();
    final written = _schemeDescription.text.trim();
    final description = written.isEmpty ? name : written;
    final body = <String, dynamic>{'name': name, 'description': description};
    final existing = _schemeId;
    if (existing == null) {
      body['points_catchment'] = [pointId];
      final created = await api.createScheme(token, body);
      final id = _intOf(created['id']);
      if (id == null) {
        throw const SmartHydroApiException('La API no devolvió el esquema.');
      }
      _schemeId = id;
    } else {
      await api.updateScheme(token, existing, body);
    }
    final schemeId = _schemeId;
    if (schemeId == null) return;
    if (_linkedSchemeId != null && _linkedSchemeId != schemeId) {
      await _unlinkScheme(token, api, _linkedSchemeId!, pointId);
    }
    _linkedSchemeId = schemeId;
    _sharedScheme = false;
    final pending = List<int>.of(_deletedVariableIds);
    for (final id in pending) {
      await api.deleteVariable(token, id);
      _deletedVariableIds.remove(id);
    }
    final service = _serviceOf(_provider);
    for (final row in _rows) {
      final label = row.label.text.trim();
      final code = row.code.text.trim();
      if (label.isEmpty && code.isEmpty) continue;
      final payload = row.toBody(schemeId, service);
      if (row.id == null) {
        final created = await api.createVariable(token, payload);
        row.id = _intOf(created['id']);
      } else {
        await api.updateVariable(token, row.id!, payload);
      }
    }
  }

  Future<void> _linkPickedScheme(
    String token,
    SmartHydroApi api,
    int pointId,
  ) async {
    final selected = _schemeId;
    if (selected == null) return;
    final scheme = _schemeOf(selected) ?? const <String, dynamic>{};
    final points = [
      ...configSchemePointIds(scheme),
      if (!configSchemePointIds(scheme).contains(pointId)) pointId,
    ];
    await api.updateScheme(token, selected, {'points_catchment': points});
    if (_linkedSchemeId != null && _linkedSchemeId != selected) {
      await _unlinkScheme(token, api, _linkedSchemeId!, pointId);
    }
    _linkedSchemeId = selected;
    _sharedScheme = points.length > 1;
  }

  Future<void> _unlinkScheme(
    String token,
    SmartHydroApi api,
    int schemeId,
    int pointId,
  ) async {
    final scheme = _schemeOf(schemeId) ?? const <String, dynamic>{};
    final next = [
      for (final id in configSchemePointIds(scheme))
        if (id != pointId) id,
    ];
    await api.updateScheme(token, schemeId, {'points_catchment': next});
  }

  Future<void> _save() async {
    final token = widget.token;
    final api = widget.api;
    final userId = widget.userId;
    if (token == null || api == null || userId == null) {
      setState(() => _error = 'La sesión no puede guardar este punto.');
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'El punto necesita un nombre.');
      return;
    }
    _projectId ??= _projects.isEmpty ? null : _intOf(_projects.first['id']);
    if (_projectId == null) {
      setState(() => _error = 'Elige un proyecto existente.');
      return;
    }
    final schemeProblem = _schemeProblem();
    if (schemeProblem != null) {
      setState(() => _error = schemeProblem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'title': _title.text.trim(),
        'project': _projectId,
        'owner_user': userId,
        'frecuency': _frequency.text.trim().isEmpty
            ? '60'
            : _frequency.text.trim(),
        'lat': _lat.text.trim(),
        'lon': _lon.text.trim(),
        'is_tdata': _provider == 'twin',
        'is_thethings': _provider == 'nettra',
        'is_novus': _provider == 'novus',
      };
      final existing = _savedPointId ?? _pointId(widget.point);
      final saved = existing == null
          ? await api.createCatchmentPoint(token, body)
          : await api.updateCatchmentPoint(token, existing, body);
      final id = _intOf(saved['id']) ?? existing;
      _savedPointId = id;
      if (id == null) {
        throw const SmartHydroApiException('La API no devolvió el punto.');
      }
      await api.patchPointConfig(token, id, {
        'd1': _num(_d1.text, '0'),
        'd2': _num(_d2.text, '0'),
        'd3': _num(_d3.text, '0'),
        'd4': _num(_d4.text, '0'),
        'd5': _num(_d5.text, '0'),
        'd6': int.tryParse(_d6.text.trim()) ?? 0,
        'is_telemetry': _telemetry,
        'nivel_offset': _num(_offset.text, '0'),
        'max_flow_ls': _num(_maxFlow.text, '150'),
        'max_diff_m3_per_hour': _num(_maxDiff.text, '500'),
        'max_time_gap_hours': _num(_gapHours.text, '2'),
        'reconnection_threshold_hours': _num(_reconnect.text, '2'),
      });
      final dgaBody = <String, dynamic>{
        'point_catchment': id,
        'send_dga': _dga,
        'type_dga': _surface ? 'SUPERFICIAL' : 'SUBTERRANEO',
        'standard': _standard,
        'code_dga': _code.text.trim(),
        'flow_granted_dga': _num(_flowGranted.text, '0'),
        'total_granted_dga': int.tryParse(_totalGranted.text.trim()) ?? 0,
        'shac': _shac.text.trim(),
        'region_dga': _region.text.trim(),
        if (_sendStart.text.trim().isNotEmpty)
          'date_start_compliance': _sendStart.text.trim(),
      };
      if (_dgaId == null) {
        if (_dga) await api.createDgaConfig(token, dgaBody);
      } else {
        await api.updateDgaConfig(token, _dgaId!, dgaBody);
      }
      await _saveScheme(token, api, id);
      widget.onSaved?.call();
      widget.onClose();
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4E756E)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF21A3036), Color(0xF20A1418)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        key: const ValueKey('capture-config-card'),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _creating ? 'Nuevo punto' : 'Configurar punto',
                      style: const TextStyle(
                        color: Color(0xFFF4FBFA),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('capture-config-close'),
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: const Color(0xFFD5E4E2),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: Color(0xFF7EE0D0),
                    backgroundColor: Color(0xFF1A3036),
                  ),
                ),
              const SizedBox(height: 2),
              _sectionChips(),
              const SizedBox(height: 8),
              Text(_panelLead, style: _configHelp),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 460;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _panelBody(narrow),
                    );
                  },
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF847A),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('capture-config-save'),
                onPressed: (_saving || _loading) ? null : _save,
                child: Text(_saving ? 'Guardando' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _panelLead {
    switch (_panel) {
      case _ConfigPanel.point:
        return 'Nombre, proyecto, tipo de captación y ubicación en el mapa.';
      case _ConfigPanel.telemetry:
        return 'De qué equipo llegan las lecturas y si se procesan.';
      case _ConfigPanel.compliance:
        return _dga
            ? 'Lo que se informa a la DGA. El detalle aparece al activarlo.'
            : 'Si no es DGA, el punto es SMA. Activa el envío solo si debe informar a la DGA.';
      case _ConfigPanel.physical:
        return 'Medidas de terreno y límites para aceptar una lectura.';
      case _ConfigPanel.scheme:
        return 'Elige un esquema existente o crea uno solo para este punto. Compartir variables es riesgoso.';
    }
  }

  Widget _sectionChips() {
    const panels = <({_ConfigPanel panel, String label})>[
      (panel: _ConfigPanel.point, label: 'Punto'),
      (panel: _ConfigPanel.telemetry, label: 'Telemetría'),
      (panel: _ConfigPanel.compliance, label: 'Cumplimiento'),
      (panel: _ConfigPanel.physical, label: 'Física'),
      (panel: _ConfigPanel.scheme, label: 'Esquema'),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final item in panels) _panelChip(item.label, item.panel)],
    );
  }

  Widget _panelChip(String label, _ConfigPanel panel) {
    final selected = _panel == panel;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? const Color(0xFF1C4A46) : const Color(0xFF102226),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () => setState(() => _panel = panel),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? const Color(0xFF7EE0D0)
                    : const Color(0xFF2C4744),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFFF4FBFA)
                    : const Color(0xFFB7C8C6),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelBody(bool narrow) {
    switch (_panel) {
      case _ConfigPanel.point:
        return _pointPanel(narrow);
      case _ConfigPanel.telemetry:
        return _telemetryPanel();
      case _ConfigPanel.compliance:
        return _compliancePanel(narrow);
      case _ConfigPanel.physical:
        return _physicalPanel(narrow);
      case _ConfigPanel.scheme:
        return _schemeSection(narrow);
    }
  }

  Widget _pointPanel(bool narrow) {
    return _stack([
      _field(
        'Nombre',
        _title,
        help: 'Así aparece en la red y en el resto de la app.',
      ),
      _noted(
        _projectField(),
        'Solo los proyectos donde ya tienes puntos. Ahí puedes crear más.',
      ),
      _noted(
        _choice(
          'Tipo',
          _surface,
          'Pozo',
          'Superficial',
          (value) => setState(() => _surface = value),
        ),
        'Pozo es subterráneo. Superficial es canal o río. Cambia la miniatura.',
      ),
      _field(
        'Frecuencia (min)',
        _frequency,
        help: 'Minutos entre una lectura y la siguiente.',
      ),
      _pair(
        _field(
          'Latitud',
          _lat,
          help: 'Opcional. Norte-sur del punto en el mapa.',
        ),
        _field(
          'Longitud',
          _lon,
          help: 'Opcional. Este-oeste del punto en el mapa.',
        ),
        narrow,
      ),
    ]);
  }

  Widget _telemetryPanel() {
    return _stack([
      _noted(
        _providerField(),
        'Equipo que envía las lecturas: Twin, Nettra, Novus o ninguno.',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Telemetría activa', style: _configLabel),
        subtitle: const Text(
          'Si la apagas, las lecturas de este punto no se procesan.',
          style: _configHelp,
        ),
        value: _telemetry,
        onChanged: (value) => setState(() => _telemetry = value),
      ),
    ]);
  }

  Widget _compliancePanel(bool narrow) {
    return _stack([
      SwitchListTile(
        key: const ValueKey('capture-config-dga'),
        contentPadding: EdgeInsets.zero,
        title: Text('Cumplimiento $_agency', style: _configLabel),
        subtitle: Text(
          _dga
              ? 'Activo: este punto informa a la Dirección General de Aguas.'
              : 'Sin envío DGA. El punto queda como SMA.',
          style: _configHelp,
        ),
        value: _dga,
        onChanged: (value) => setState(() => _dga = value),
      ),
      if (_dga) ...[
        _noted(
          _standardField(),
          'Régimen de reporte que corresponde al derecho.',
        ),
        _field(
          'Código de obra',
          _code,
          key: const ValueKey('capture-config-code'),
          help: 'Identificador de la obra ante la DGA.',
        ),
        _pair(
          _field(
            'Caudal otorgado (L/s)',
            _flowGranted,
            help: 'Caudal autorizado del derecho, en litros por segundo.',
          ),
          _field(
            'Total otorgado (m³)',
            _totalGranted,
            help: 'Volumen total autorizado, en metros cúbicos.',
          ),
          narrow,
        ),
        _pair(
          _field(
            'SHAC',
            _shac,
            help: 'Sector hidrogeológico de aprovechamiento común.',
          ),
          _field(
            'Región DGA',
            _region,
            help: 'Región con la que se informa el punto.',
          ),
          narrow,
        ),
        _field(
          'Inicio de envío',
          _sendStart,
          help: 'Desde cuándo se reporta. Fecha en formato AAAA-MM-DD.',
        ),
      ],
    ]);
  }

  Widget _physicalPanel(bool narrow) {
    return _stack([
      _caption('Terreno'),
      _pair(
        _field(
          'Profundidad (m)',
          _d1,
          help: 'Profundidad total del pozo, medida desde la superficie.',
        ),
        _field(
          'Bomba (m)',
          _d2,
          help: 'Profundidad a la que está instalada la bomba.',
        ),
        narrow,
      ),
      _pair(
        _field(
          'Sensor de nivel (m)',
          _d3,
          help: 'Profundidad a la que está el sensor de nivel.',
        ),
        _field(
          'Ducto de salida (pulg)',
          _d4,
          help: 'Diámetro del ducto de salida de la bomba, en pulgadas.',
        ),
        narrow,
      ),
      _pair(
        _field(
          'Flujómetro (pulg)',
          _d5,
          help: 'Diámetro del medidor de caudal, en pulgadas.',
        ),
        _field(
          'Caudalímetro inicial',
          _d6,
          help: 'Lectura inicial del medidor. Se suma al total que se muestra.',
        ),
        narrow,
      ),
      _caption('Procesamiento'),
      _field(
        'Offset de nivel (m)',
        _offset,
        help: 'Desfase que se aplica al nivel antes de calcularlo.',
      ),
      _pair(
        _field(
          'Caudal máximo (L/s)',
          _maxFlow,
          help: 'Si una lectura lo supera, se descarta y el caudal queda en 0.',
        ),
        _field(
          'Salto máximo (m³/h)',
          _maxDiff,
          help:
              'Si el volumen salta más que esto en una hora, se ignora como error.',
        ),
        narrow,
      ),
      _pair(
        _field(
          'Horas sin datos',
          _gapHours,
          help:
              'Pasado este lapso sin lecturas no se calcula el caudal promedio.',
        ),
        _field(
          'Reconexión (horas)',
          _reconnect,
          help:
              'Si pasa más tiempo entre lecturas, el salto se acepta como reconexión.',
        ),
        narrow,
      ),
    ]);
  }

  Widget _schemeSection(bool narrow) {
    return _stack([
      _noted(
        _choice(
          'Esquema',
          _schemePick,
          'Nuevo para este punto',
          'Elegir existente',
          _setSchemePick,
        ),
        'Un esquema compartido cambia las variables de todos los puntos que lo usan.',
      ),
      if (_schemePick) _schemePicker() else ..._ownSchemeFields(narrow),
    ]);
  }

  Widget _schemePicker() {
    final ids = [
      for (final scheme in _schemes)
        if (_intOf(scheme['id']) != null) _intOf(scheme['id'])!,
    ];
    if (ids.isEmpty) {
      return const Text(
        'No hay esquemas en tus puntos. Crea uno para este punto.',
        style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey('capture-config-scheme-pick-$_schemeId'),
          initialValue: ids.contains(_schemeId) ? _schemeId : ids.first,
          dropdownColor: const Color(0xFF102226),
          style: const TextStyle(color: Color(0xFFF4FBFA), fontSize: 13),
          decoration: _decoration('Esquema existente'),
          items: [
            for (final scheme in _schemes)
              if (_intOf(scheme['id']) != null)
                DropdownMenuItem(
                  value: _intOf(scheme['id']),
                  child: Text('${scheme['name'] ?? 'Esquema'}'),
                ),
          ],
          onChanged: (value) => setState(() {
            _schemeId = value ?? ids.first;
            final selected = _schemeOf(_schemeId);
            _sharedScheme =
                configSchemePointIds(selected ?? const {}).length > 1;
          }),
        ),
        const SizedBox(height: 8),
        Text(
          _sharedScheme
              ? 'Este esquema también está en otros puntos. Al elegirlo no se editan las variables.'
              : 'Este esquema queda ligado a este punto. Las variables no se editan aquí.',
          style: TextStyle(
            color: _sharedScheme
                ? const Color(0xFFFFC46B)
                : const Color(0xFF9AB0B1),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  List<Widget> _ownSchemeFields(bool narrow) {
    return [
      if (_sharedScheme)
        const Text(
          'Este esquema también está en otros puntos. Al guardar se crea uno nuevo para este punto.',
          style: TextStyle(
            color: Color(0xFFFFC46B),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      _field(
        'Nombre del esquema',
        _schemeName,
        key: const ValueKey('capture-config-scheme'),
        help: 'Nombre del grupo de variables de este punto.',
      ),
      _field(
        'Descripción',
        _schemeDescription,
        help: 'Texto libre. Si lo dejas vacío, se usa el nombre.',
      ),
      for (final row in _rows) _variableRow(row, narrow),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('capture-config-add-variable'),
          onPressed: _addVariable,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF9CC8C2),
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Agregar variable'),
        ),
      ),
    ];
  }

  Widget _caption(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF9CC8C2),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _stack(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: 14),
          children[index],
        ],
      ],
    );
  }

  Widget _pair(Widget left, Widget right, bool narrow) {
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, const SizedBox(height: 14), right],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _noted(Widget child, String help) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: 4),
        Text(help, style: _configHelp),
      ],
    );
  }

  Widget _variableRow(_VariableDraft row, bool narrow) {
    final types = <String>[
      ..._variableTypes,
      if (!_variableTypes.contains(row.type)) row.type,
    ];
    final label = _field(
      'Etiqueta',
      row.label,
      help: 'Nombre con el que verás esta medición.',
    );
    final code = _field(
      'Código',
      row.code,
      help: 'Código del logger, tal como llega del equipo.',
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2C4744)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Variable',
                    style: TextStyle(
                      color: Color(0xFF9CC8C2),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeVariable(row),
                  tooltip: 'Quitar variable',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: const Color(0xFFD5E4E2),
                ),
              ],
            ),
            if (narrow)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [label, const SizedBox(height: 12), code],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 12),
                  Expanded(child: code),
                ],
              ),
            const SizedBox(height: 12),
            _noted(
              DropdownButtonFormField<String>(
                key: ObjectKey(row),
                initialValue: types.contains(row.type) ? row.type : types.first,
                dropdownColor: const Color(0xFF102226),
                style: const TextStyle(color: Color(0xFFF4FBFA), fontSize: 13),
                decoration: _decoration('Tipo de variable'),
                items: [
                  for (final type in types)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_variableTypeLabel(type)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => row.type = value);
                },
              ),
              'Qué mide esta fila: caudal, nivel, totalizado u otra señal.',
            ),
            if (_isTotalizer(row.type)) ...[
              const SizedBox(height: 12),
              _field(
                'Factor de pulsos',
                row.pulses,
                help: 'El volumen guardado es (pulsos × factor) / 1000.',
              ),
            ],
            if (row.type == 'CAUDAL')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Pasar caudal de m³ a litros',
                  style: _configLabel,
                ),
                subtitle: const Text(
                  'Convierte la lectura de metros cúbicos a litros.',
                  style: _configHelp,
                ),
                value: row.convertToLt,
                onChanged: (value) => setState(() => row.convertToLt = value),
              ),
            if (row.type == 'NIVEL') ...[
              const SizedBox(height: 12),
              _field(
                'Base de cálculo del nivel',
                row.nivel,
                help: 'Número base con el que se calcula el nivel.',
              ),
            ],
            if (row.type == 'CAUDAL_PROMEDIO')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Guardar caudal promedio',
                  style: _configLabel,
                ),
                subtitle: const Text(
                  'Si está activo, se guarda la serie de caudal promedio.',
                  style: _configHelp,
                ),
                value: row.storeAverage,
                onChanged: (value) => setState(() => row.storeAverage = value),
              ),
            const SizedBox(height: 12),
            _pair(
              _field(
                'Mínimo',
                row.min,
                help: 'Tope inferior. Vacío no limita.',
              ),
              _field(
                'Máximo',
                row.max,
                help: 'Tope superior. Vacío no limita.',
              ),
              narrow,
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectField() {
    final ids = [
      for (final project in _projects)
        if (_intOf(project['id']) != null) _intOf(project['id'])!,
    ];
    if (ids.isEmpty) {
      return const Text(
        'No hay proyectos en tus puntos.',
        style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
      );
    }
    return DropdownButtonFormField<int>(
      key: ValueKey('config-project-$_projectId'),
      initialValue: ids.contains(_projectId) ? _projectId : ids.first,
      dropdownColor: const Color(0xFF102226),
      style: const TextStyle(color: Color(0xFFF4FBFA), fontSize: 13),
      decoration: _decoration('Proyecto'),
      items: [
        for (final project in _projects)
          if (_intOf(project['id']) != null)
            DropdownMenuItem(
              value: _intOf(project['id']),
              child: Text('${project['name'] ?? 'Proyecto'}'),
            ),
      ],
      onChanged: (value) => setState(() => _projectId = value),
    );
  }

  Widget _providerField() {
    return DropdownButtonFormField<String>(
      key: ValueKey('config-provider-$_provider'),
      initialValue: _provider,
      dropdownColor: const Color(0xFF102226),
      style: const TextStyle(color: Color(0xFFF4FBFA), fontSize: 13),
      decoration: _decoration('Proveedor'),
      items: const [
        DropdownMenuItem(value: 'none', child: Text('Ninguno')),
        DropdownMenuItem(value: 'twin', child: Text('Twin')),
        DropdownMenuItem(value: 'nettra', child: Text('Nettra')),
        DropdownMenuItem(value: 'novus', child: Text('Novus')),
      ],
      onChanged: (value) => setState(() => _provider = value ?? 'none'),
    );
  }

  Widget _standardField() {
    return DropdownButtonFormField<String>(
      key: ValueKey('config-standard-$_standard'),
      initialValue: _standard,
      dropdownColor: const Color(0xFF102226),
      style: const TextStyle(color: Color(0xFFF4FBFA), fontSize: 13),
      decoration: _decoration('Estándar DGA'),
      items: const [
        DropdownMenuItem(value: 'SIN_ESTANDAR', child: Text('Sin estándar')),
        DropdownMenuItem(value: 'MAYOR', child: Text('Mayor')),
        DropdownMenuItem(value: 'MEDIO', child: Text('Medio')),
        DropdownMenuItem(value: 'MENOR', child: Text('Menor')),
        DropdownMenuItem(
          value: 'CAUDALES_MUY_PEQUENOS',
          child: Text('Caudales muy pequeños'),
        ),
      ],
      onChanged: (value) => setState(() => _standard = value ?? 'SIN_ESTANDAR'),
    );
  }

  Widget _choice(
    String label,
    bool second,
    String firstLabel,
    String secondLabel,
    ValueChanged<bool> onChanged,
  ) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9CC8C2), fontSize: 12),
        ),
        ChoiceChip(
          label: Text(firstLabel),
          selected: !second,
          onSelected: (_) => onChanged(false),
          selectedColor: const Color(0xFF1C4A46),
          backgroundColor: const Color(0xFF102226),
          labelStyle: TextStyle(
            color: !second ? const Color(0xFFF4FBFA) : const Color(0xFF9AB0B1),
            fontSize: 13,
          ),
          side: BorderSide(
            color: !second ? const Color(0xFF7EE0D0) : const Color(0xFF2C4744),
          ),
        ),
        ChoiceChip(
          label: Text(secondLabel),
          selected: second,
          onSelected: (_) => onChanged(true),
          selectedColor: const Color(0xFF1C4A46),
          backgroundColor: const Color(0xFF102226),
          labelStyle: TextStyle(
            color: second ? const Color(0xFFF4FBFA) : const Color(0xFF9AB0B1),
            fontSize: 13,
          ),
          side: BorderSide(
            color: second ? const Color(0xFF7EE0D0) : const Color(0xFF2C4744),
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration(String label) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Color(0xFF2C4744)),
    );
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF102226),
      labelStyle: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
      contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFF7EE0D0)),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    Key? key,
    String? help,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: key,
          controller: controller,
          style: const TextStyle(color: Color(0xFFF4FBFA), fontSize: 13),
          decoration: _decoration(label),
        ),
        if (help != null) ...[
          const SizedBox(height: 4),
          Text(help, style: _configHelp),
        ],
      ],
    );
  }
}

const _configHelp = TextStyle(
  color: Color(0xFF8FA3A4),
  fontSize: 12,
  height: 1.35,
);

const _configLabel = TextStyle(
  color: Color(0xFFD5E4E2),
  fontSize: 14,
  fontWeight: FontWeight.w600,
  height: 1.25,
);

enum _ConfigPanel { point, telemetry, compliance, physical, scheme }

int? _pointId(Map<String, dynamic>? point) {
  if (point == null) return null;
  final raw = point['id'];
  final id = raw is int ? raw : int.tryParse('$raw');
  if (id == null || id <= 0) return null;
  return id;
}

int? _intOf(dynamic raw) => configProjectId(raw);

/// Handler del dropdown: twin / nettra / novus. `tago` es Novus.
@visibleForTesting
String configProviderKey(Map<String, dynamic> data) {
  switch (loggerModelOf(data)) {
    case 'Twin':
      return 'twin';
    case 'Nettra':
      return 'nettra';
    case 'Novus':
      return 'novus';
    default:
      return 'none';
  }
}

/// Id de proyecto aunque venga anidado `{id: 3}` o como `project_id`.
@visibleForTesting
int? configProjectId(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw > 0 ? raw : null;
  if (raw is num) {
    final id = raw.toInt();
    return id > 0 ? id : null;
  }
  if (raw is Map) {
    return configProjectId(raw['id'] ?? raw['pk'] ?? raw['project']);
  }
  return int.tryParse('$raw'.trim());
}

@visibleForTesting
String configProjectName(Map<String, dynamic> point) {
  final nested = point['project'];
  if (nested is Map) {
    final name = '${nested['name'] ?? nested['title'] ?? ''}'.trim();
    if (name.isNotEmpty && name != 'null') return name;
  }
  for (final key in ['project_name', 'project_title']) {
    final name = '${point[key] ?? ''}'.trim();
    if (name.isNotEmpty && name != 'null') return name;
  }
  return '';
}

/// Proyectos únicos de los puntos de la cuenta. Sin el catálogo global.
@visibleForTesting
List<Map<String, dynamic>> configProjectsOf(
  Iterable<Map<String, dynamic>> points,
) {
  final byId = <int, Map<String, dynamic>>{};
  for (final point in points) {
    final id =
        configProjectId(point['project']) ??
        configProjectId(point['project_id']) ??
        configProjectId(point['project_catchment']);
    if (id == null) continue;
    final name = configProjectName(point);
    final previous = byId[id];
    if (previous != null && '${previous['name']}'.trim().isNotEmpty) continue;
    byId[id] = {'id': id, 'name': name.isEmpty ? 'Proyecto $id' : name};
  }
  final list = byId.values.toList();
  list.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  return list;
}

/// Si el summary no trae id, se cruza el catálogo solo con los nombres
/// de los puntos de esta cuenta.
@visibleForTesting
List<Map<String, dynamic>> configProjectsFromCatalog(
  List<Map<String, dynamic>> catalog,
  Iterable<Map<String, dynamic>> points,
) {
  final allowedIds = <int>{};
  final allowedNames = <String>{};
  for (final point in points) {
    final id =
        configProjectId(point['project']) ??
        configProjectId(point['project_id']) ??
        configProjectId(point['project_catchment']);
    if (id != null) allowedIds.add(id);
    final name = configProjectName(point).toLowerCase();
    if (name.isNotEmpty) allowedNames.add(name);
  }
  if (allowedIds.isEmpty && allowedNames.isEmpty) return const [];
  final seen = <int>{};
  final list = <Map<String, dynamic>>[];
  for (final project in catalog) {
    final id = configProjectId(project['id']);
    if (id == null || seen.contains(id)) continue;
    final name = '${project['name'] ?? ''}'.trim().toLowerCase();
    if (!allowedIds.contains(id) && !allowedNames.contains(name)) continue;
    seen.add(id);
    list.add({'id': id, 'name': '${project['name'] ?? 'Proyecto $id'}'.trim()});
  }
  list.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  return list;
}

bool _hasProjectHint(Iterable<Map<String, dynamic>> points) {
  for (final point in points) {
    if (configProjectId(point['project']) != null) return true;
    if (configProjectId(point['project_id']) != null) return true;
    if (configProjectId(point['project_catchment']) != null) return true;
    if (configProjectName(point).isNotEmpty) return true;
  }
  return false;
}

bool _hasUnresolvedProjectName(Iterable<Map<String, dynamic>> points) {
  for (final point in points) {
    final id =
        configProjectId(point['project']) ??
        configProjectId(point['project_id']) ??
        configProjectId(point['project_catchment']);
    if (id != null) continue;
    if (configProjectName(point).isNotEmpty) return true;
  }
  return false;
}

@visibleForTesting
Map<String, dynamic>? configPayloadOf(Map<String, dynamic> point) {
  final nested =
      point['config_data'] ?? point['config'] ?? point['physical_config'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  if (point.containsKey('d1') || point.containsKey('nivel_offset')) {
    return point;
  }
  return null;
}

@visibleForTesting
List<Map<String, dynamic>> dgaRowsOf(Map<String, dynamic> point) {
  final nested = point['dga'] ?? point['dga_config'];
  final top = <String, dynamic>{
    if (point['send_dga'] != null) 'send_dga': point['send_dga'],
    if (point['code_dga'] != null) 'code_dga': point['code_dga'],
    if (point['type_dga'] != null) 'type_dga': point['type_dga'],
    if (point['standard'] != null) 'standard': point['standard'],
    if (point['flow_granted_dga'] != null)
      'flow_granted_dga': point['flow_granted_dga'],
    if (point['authorized_flow'] != null)
      'authorized_flow': point['authorized_flow'],
    if (point['total_granted_dga'] != null)
      'total_granted_dga': point['total_granted_dga'],
    if (point['authorized_total'] != null)
      'authorized_total': point['authorized_total'],
    if (point['shac'] != null) 'shac': point['shac'],
    if (point['region_dga'] != null) 'region_dga': point['region_dga'],
    if (point['date_start_compliance'] != null)
      'date_start_compliance': point['date_start_compliance'],
  };
  if (nested is Map) {
    return [
      {...top, ...Map<String, dynamic>.from(nested)},
    ];
  }
  if (nested is List) {
    return [
      for (final item in nested)
        if (item is Map) {...top, ...Map<String, dynamic>.from(item)},
    ];
  }
  if (point['send_dga'] == true ||
      point['code_dga'] != null ||
      point['flow_granted_dga'] != null ||
      point['authorized_flow'] != null) {
    return [point];
  }
  return const [];
}

@visibleForTesting
List<Map<String, dynamic>> variableMapsOf(Map<String, dynamic> point) {
  final raw = point['variables'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

String _text(dynamic raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return '';
  return text;
}

String _num(String raw, String fallback) {
  final text = raw.trim();
  if (text.isEmpty) return fallback;
  return text.replaceAll(',', '.');
}

List<Map<String, dynamic>> _mergeSchemes(
  List<Map<String, dynamic>> catalog,
  List<Map<String, dynamic>> extra,
) {
  final byId = <int, Map<String, dynamic>>{};
  for (final scheme in [...catalog, ...extra]) {
    final id = configProjectId(scheme['id']);
    if (id == null) continue;
    final name = '${scheme['name'] ?? ''}'.trim();
    byId[id] = {
      'id': id,
      'name': name.isEmpty ? 'Esquema $id' : name,
      'description': scheme['description'],
      'points_catchment': configSchemePointIds(scheme),
    };
  }
  final list = byId.values.toList();
  list.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  return list;
}

/// Ids de puntos ligados al esquema (`points_catchment`).
@visibleForTesting
List<int> configSchemePointIds(Map<String, dynamic> scheme) {
  final raw = scheme['points_catchment'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (configProjectId(item) != null) configProjectId(item)!,
  ];
}

/// Esquemas de los puntos de la cuenta. Sin el catálogo global.
@visibleForTesting
List<Map<String, dynamic>> configSchemesOf(
  List<Map<String, dynamic>> catalog,
  Iterable<int> pointIds,
) {
  final allowed = pointIds.toSet();
  if (allowed.isEmpty) return const [];
  final seen = <int>{};
  final list = <Map<String, dynamic>>[];
  for (final scheme in catalog) {
    final id = configProjectId(scheme['id']);
    if (id == null || seen.contains(id)) continue;
    final points = configSchemePointIds(scheme);
    if (points.isEmpty || !points.any(allowed.contains)) continue;
    seen.add(id);
    final name = '${scheme['name'] ?? ''}'.trim();
    list.add({
      'id': id,
      'name': name.isEmpty ? 'Esquema $id' : name,
      'description': scheme['description'],
      'points_catchment': points,
    });
  }
  list.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  return list;
}

const _variableTypes = [
  'CAUDAL',
  'NIVEL',
  'TOTALIZADO',
  'CAUDAL_PROMEDIO',
  'TOTALIZADO_MODBUS',
  'TOTALIZADO_MODBUS_LO',
  'TOTALIZADO_MODBUS_HI',
];

const _variableTypeLabels = {
  'CAUDAL': 'Caudal',
  'NIVEL': 'Nivel',
  'TOTALIZADO': 'Totalizado',
  'CAUDAL_PROMEDIO': 'Caudal promedio',
  'TOTALIZADO_MODBUS': 'Totalizado Modbus',
  'TOTALIZADO_MODBUS_LO': 'Totalizado Modbus bajo',
  'TOTALIZADO_MODBUS_HI': 'Totalizado Modbus alto',
};

String _variableTypeLabel(String type) => _variableTypeLabels[type] ?? type;

bool _isTotalizer(String type) => type.startsWith('TOTALIZADO');

String? _serviceOf(String provider) {
  switch (provider) {
    case 'twin':
      return 'TWIN';
    case 'nettra':
      return 'NETTRA';
    case 'novus':
      return 'NOVUS';
    default:
      return null;
  }
}

String? _optionalDecimal(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  return text.replaceAll(',', '.');
}

class _VariableDraft {
  _VariableDraft();

  int? id;
  final label = TextEditingController();
  final code = TextEditingController();
  var type = 'CAUDAL';
  final pulses = TextEditingController(text: '1000');
  var convertToLt = false;
  final nivel = TextEditingController();
  var storeAverage = true;
  final min = TextEditingController();
  final max = TextEditingController();
  String? displayKey;
  var _disposed = false;

  factory _VariableDraft.fromMap(Map<String, dynamic> raw) {
    final draft = _VariableDraft();
    draft.id = _intOf(raw['id']);
    draft.label.text = _text(raw['label']);
    draft.code.text = _text(raw['str_variable']);
    final type = _text(raw['type_variable']);
    if (type.isNotEmpty) draft.type = type;
    final pulses = raw['pulses_factor'];
    draft.pulses.text = pulses == null || '$pulses' == 'null'
        ? '1000'
        : '$pulses';
    draft.convertToLt = raw['convert_to_lt'] == true;
    final nivel = raw['calculate_nivel'];
    draft.nivel.text = nivel == null || '$nivel' == 'null' ? '' : '$nivel';
    draft.storeAverage = raw['store_average_flow'] != false;
    draft.min.text = _text(raw['min_value']);
    draft.max.text = _text(raw['max_value']);
    final display = _text(raw['display_key']);
    draft.displayKey = display.isEmpty ? null : display;
    return draft;
  }

  Map<String, dynamic> toBody(int schemeId, String? service) {
    final body = <String, dynamic>{
      'scheme_catchment': schemeId,
      'str_variable': code.text.trim(),
      'label': label.text.trim(),
      'type_variable': type,
      'service': service,
      'pulses_factor': _isTotalizer(type)
          ? (int.tryParse(pulses.text.trim()) ?? 1000)
          : 1000,
      'convert_to_lt': type == 'CAUDAL' && convertToLt,
      'calculate_nivel': type == 'NIVEL'
          ? int.tryParse(nivel.text.trim())
          : null,
      'store_average_flow': type == 'CAUDAL_PROMEDIO' && storeAverage,
      'min_value': _optionalDecimal(min.text),
      'max_value': _optionalDecimal(max.text),
    };
    final shown = displayKey;
    if (shown != null && shown.isNotEmpty) body['display_key'] = shown;
    return body;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    label.dispose();
    code.dispose();
    pulses.dispose();
    nivel.dispose();
    min.dispose();
    max.dispose();
  }
}
