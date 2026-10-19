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

  /// Tipo corto para la ficha del logger: Nivel, Caudal o Acumulado.
  String get simpleType {
    if (isLevel) return 'Nivel';
    if (isFlow) return 'Caudal';
    if (isTotal) return 'Acumulado';
    return meaning;
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

const _twinNames = {'twin', 'tdata'};

/// `tago` es el handler de Novus en la API. No es Nettra.
const _novusNames = {'novus', 'tago'};
const _nettraNames = {'nettra', 'thethings'};

/// Modelo del datalogger. La API manda `provider` como handler
/// (`tdata`, `thethings`, `tago`) o, si no hay proveedor nuevo, no manda
/// nombre y el cliente usa los booleanos viejos en ese mismo orden.
String? loggerModelOf(Map<String, dynamic> data) {
  final provider =
      '${data['provider'] ?? data['telemetry_provider_name'] ?? ''}'
          .trim()
          .toLowerCase();
  if (provider.isNotEmpty && provider != 'null' && provider != 'none') {
    if (_names(provider, _twinNames)) return 'Twin';
    if (_names(provider, _novusNames)) return 'Novus';
    if (_names(provider, _nettraNames)) return 'Nettra';
    return provider[0].toUpperCase() + provider.substring(1);
  }
  if (data['is_tdata'] == true) return 'Twin';
  if (data['is_thethings'] == true) return 'Nettra';
  if (data['is_novus'] == true) return 'Novus';
  return null;
}

bool _names(String provider, Set<String> names) {
  if (names.contains(provider)) return true;
  for (final token in provider.split(RegExp(r'[^a-z0-9]+'))) {
    if (names.contains(token)) return true;
  }
  return false;
}

/// Ficha de cumplimiento del punto, DGA o SMA. Nula si el punto no tiene
/// cumplimiento según la regla del API.
class DgaInfo {
  const DgaInfo({
    this.agency = 'DGA',
    this.type,
    this.code,
    this.standard,
    this.flowGranted,
    this.totalGranted,
    this.shac,
    this.region,
    this.smaDevice,
  });

  static DgaInfo? tryParse(Map<String, dynamic> dga) {
    if (dga.isEmpty) return null;
    final code = _str(dga['code_dga'] ?? dga['code']);
    final agency = complianceAgencyForConfig({
      'code_dga': code,
      'sma_device_id': dga['sma_device_id'],
    });
    if (agency == null) return null;
    return DgaInfo(
      agency: agency,
      type: _str(dga['type_dga']),
      code: code,
      standard: _str(dga['standard']),
      flowGranted: _num(dga['flow_granted_dga'] ?? dga['authorized_flow']),
      totalGranted: _num(dga['total_granted_dga'] ?? dga['authorized_total']),
      shac: _str(dga['shac']),
      region: _str(dga['region_dga'] ?? dga['region']),
      smaDevice: _str(dga['sma_device_id']),
    );
  }

  /// `DGA` o `SMA`.
  final String agency;
  final String? type;
  final String? code;
  final String? standard;
  final double? flowGranted;

  /// En DGA es el volumen anual otorgado. En SMA el API lo usa como ID del
  /// proceso, no como volumen.
  final double? totalGranted;
  final String? shac;
  final String? region;
  final String? smaDevice;

  bool get isSma => agency == 'SMA';

  List<({String label, String value})> get fields => isSma
      ? [
          if (code != null) (label: 'Código UF', value: code!),
          if (smaDevice != null) (label: 'Dispositivo SMA', value: smaDevice!),
          if (totalGranted != null)
            (label: 'Proceso SMA', value: totalGranted!.toStringAsFixed(0)),
          if (flowGranted != null)
            (label: 'Caudal otorgado', value: '${_fmt(flowGranted!)} L/s'),
        ]
      : [
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

/// `DGA`, `SMA` o nulo si el punto no tiene cumplimiento.
///
/// Usa `compliance_type` cuando la API lo manda; si no, la misma regla que
/// `compliance_type_for_config` del API sobre la config del punto.
String? complianceAgencyOf(
  Map<String, dynamic> point, {
  Map<String, dynamic>? compliance,
}) {
  final types = <String>{
    ..._agencyTokens(point['compliance_type']),
    ..._agencyTokens(compliance?['compliance_type']),
  };
  if (types.contains('DGA')) return 'DGA';
  if (types.contains('SMA')) return 'SMA';
  final nested = point['dga'];
  if (nested is Map) {
    final agency = complianceAgencyForConfig(Map<String, dynamic>.from(nested));
    if (agency != null) return agency;
  }
  return complianceAgencyForConfig(point);
}

/// Regla del API: código de obra que empieza con OB es DGA; otro código o un
/// dispositivo SMA es SMA. Sin código ni dispositivo no hay cumplimiento,
/// aunque `send_dga` esté encendido.
String? complianceAgencyForConfig(Map<String, dynamic> config) {
  final code = '${config['code_dga'] ?? ''}'.trim();
  if (code.isNotEmpty && code != 'null') {
    return code.toUpperCase().startsWith('OB') ? 'DGA' : 'SMA';
  }
  final device = '${config['sma_device_id'] ?? ''}'.trim();
  if (device.isNotEmpty && device != 'null') return 'SMA';
  return null;
}

Set<String> _agencyTokens(dynamic raw) {
  if (raw is List) {
    return {
      for (final item in raw)
        if ('$item'.trim().isNotEmpty && '$item'.trim() != 'null')
          '$item'.trim().toUpperCase(),
    };
  }
  final text = '$raw'.trim().toUpperCase();
  if (text.isEmpty || text == 'NULL') return const {};
  return {text};
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

  /// Variables del esquema: el texto del logger y el tipo simple.
  List<({String label, String value})> get schemeFields => [
    for (final v in variables) (label: v.schemaName, value: v.simpleType),
  ];
}
