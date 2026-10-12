/// Metadatos del punto: variables del esquema del logger, ficha del equipo y DGA.
///
/// Fuente: `/api/ik/point/{id}/variables/` (`str_variable` = nombre en el
/// esquema del logger, `type_variable` / `label` / `display_key` = a qué
/// corresponde en SmartHydro), `/config/` (`token_service`) y el bloque `dga`
/// del summary. Solo se muestra lo que el punto tiene activo.
library;

class PointVariable {
  const PointVariable({
    required this.type,
    this.strVariable,
    this.label,
    this.displayKey,
    this.token,
  });

  factory PointVariable.fromJson(Map<String, dynamic> json) => PointVariable(
    type: _normalizeType(json['type_variable'] ?? json['type']),
    // Nombre en el esquema del logger (ej. ai1ActualValue).
    strVariable: _str(json['str_variable']),
    label: _str(json['label']),
    displayKey: _str(json['display_key']),
    token: _str(json['token_service']),
  );

  /// `CAUDAL`, `NIVEL`, `TOTALIZADO`, `CAUDAL_PROMEDIO`, …
  final String type;

  /// Texto de la variable en el esquema del punto / logger.
  final String? strVariable;

  /// Etiqueta legible (ej. "Caudal").
  final String? label;

  /// Clave de visualización en la app (caudal, nivel, total…).
  final String? displayKey;

  final String? token;

  bool get isFlow => type == 'CAUDAL' || type == 'CAUDAL_PROMEDIO';
  bool get isLevel => type == 'NIVEL';
  bool get isTotal => type == 'TOTALIZADO';

  /// A qué corresponde esta variable del esquema.
  String get meaning {
    if (label != null && label!.isNotEmpty) return label!;
    if (displayKey != null && displayKey!.isNotEmpty) {
      return displayKey!.replaceAll('_', ' ');
    }
    if (type.isNotEmpty && type != 'NULL') {
      return type.replaceAll('_', ' ').toLowerCase();
    }
    return 'sin mapear';
  }

  /// Nombre que se muestra a la izquierda: el del esquema del logger.
  String get schemaName => strVariable ?? label ?? type;

  static String _normalizeType(dynamic raw) {
    final t = '$raw'.trim().toUpperCase().replaceAll(' ', '_');
    if (t == 'CAUDAL_PROMEDIO' || t == 'CAUDALPROMEDIO') {
      return 'CAUDAL_PROMEDIO';
    }
    return t;
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }
}

/// Catálogo de variables del punto. Si la API falla, [unknown] queda en true
/// y la UI cae al criterio de “hay valor en telemetría”.
class PointVariables {
  const PointVariables({this.items = const [], this.unknown = false});

  factory PointVariables.fromJson(List<Map<String, dynamic>> list) =>
      PointVariables(
        items: list.map(PointVariable.fromJson).toList(growable: false),
      );

  static const unknownCatalog = PointVariables(unknown: true);

  final List<PointVariable> items;
  final bool unknown;

  bool get hasFlow => unknown || items.any((v) => v.isFlow);
  bool get hasLevel => unknown || items.any((v) => v.isLevel);
  bool get hasTotal => unknown || items.any((v) => v.isTotal);

  List<PointVariable> get flows =>
      items.where((v) => v.isFlow).toList(growable: false);
  List<PointVariable> get levels =>
      items.where((v) => v.isLevel).toList(growable: false);
  List<PointVariable> get totals =>
      items.where((v) => v.isTotal).toList(growable: false);
}

/// Modelo / proveedor del datalogger (Twin, Nettra, Novus…).
String? loggerModelOf(Map<String, dynamic> data) {
  final provider =
      '${data['provider'] ?? data['telemetry_provider_name'] ?? ''}'
          .trim()
          .toLowerCase();
  if (provider.contains('twin') ||
      provider.contains('tdata') ||
      data['is_tdata'] == true) {
    return 'Twin';
  }
  if (provider.contains('nettra') ||
      provider.contains('thethings') ||
      provider.contains('tago') ||
      data['is_thethings'] == true) {
    return 'Nettra';
  }
  if (provider.contains('novus') || data['is_novus'] == true) {
    return 'Novus';
  }
  if (provider.isNotEmpty && provider != 'null' && provider != 'none') {
    return provider[0].toUpperCase() + provider.substring(1);
  }
  return null;
}

/// Ficha DGA del punto. Solo se arma si el cumplimiento está activo.
class DgaInfo {
  const DgaInfo({
    this.type,
    this.code,
    this.standard,
    this.flowGranted,
    this.totalGranted,
    this.shac,
    this.region,
  });

  static DgaInfo? tryParse(Map<String, dynamic> dga) {
    if (dga.isEmpty) return null;
    final send = dga['send_dga'] == true;
    final code = _str(dga['code_dga'] ?? dga['code']);
    if (!send && code == null) return null;
    return DgaInfo(
      type: _str(dga['type_dga']),
      code: code,
      standard: _str(dga['standard']),
      flowGranted: _num(dga['flow_granted_dga'] ?? dga['authorized_flow']),
      totalGranted: _num(dga['total_granted_dga'] ?? dga['authorized_total']),
      shac: _str(dga['shac']),
      region: _str(dga['region_dga'] ?? dga['region']),
    );
  }

  final String? type;
  final String? code;
  final String? standard;
  final double? flowGranted;
  final double? totalGranted;
  final String? shac;
  final String? region;

  List<({String label, String value})> get fields => [
    if (type != null) (label: 'Tipo', value: type!),
    if (code != null) (label: 'Código de obra', value: code!),
    if (standard != null) (label: 'Estándar', value: standard!),
    if (flowGranted != null)
      (label: 'Caudal otorgado', value: '${_fmt(flowGranted!)} L/s'),
    if (totalGranted != null)
      (label: 'Total otorgado', value: '${_fmt(totalGranted!)} m³'),
    if (shac != null) (label: 'SHAC', value: shac!),
    if (region != null) (label: 'Región', value: region!),
  ];

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  static String _fmt(double v) =>
      v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// Todo lo que el tablero muestra al tocar el datalogger.
class LoggerInfo {
  const LoggerInfo({
    this.token,
    this.model,
    this.frequency,
    this.telemetry = false,
    this.variables = const [],
    this.dga,
  });

  final String? token;
  final String? model;
  final String? frequency;
  final bool telemetry;
  final List<PointVariable> variables;
  final DgaInfo? dga;

  /// Datos del equipo (sin el listado del esquema).
  List<({String label, String value})> get fields => [
    if (model != null) (label: 'Modelo', value: model!),
    if (token != null) (label: 'Token', value: token!),
    if (frequency != null) (label: 'Frecuencia', value: '$frequency min'),
    (label: 'Telemetría', value: telemetry ? 'Activa' : 'Inactiva'),
  ];

  /// Variables del esquema del logger → a qué corresponden en SmartHydro.
  /// Izquierda: `str_variable`; derecha: etiqueta / tipo.
  List<({String label, String value})> get schemeFields => [
    for (final v in variables)
      (
        label: v.schemaName,
        value: v.type.isEmpty || v.type == 'NULL'
            ? v.meaning
            : '${v.meaning} · ${v.type.replaceAll('_', ' ')}',
      ),
  ];
}
