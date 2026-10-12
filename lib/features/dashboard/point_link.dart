/// Estado de enlace de un punto a partir de su última telemetría.
///
/// Una regla de alerta configurada no es una incidencia. El rojo solo aparece
/// cuando la última lectura llegó marcada como error.
enum PointLink { connected, gap, incident }

PointLink pointLinkOf(Map<String, dynamic> point) {
  final telemetry = _telemetry(point);
  if (telemetry['is_error'] == true) return PointLink.incident;

  final stamp = telemetry['date_time_medition']?.toString();
  if (stamp == null || stamp.isEmpty || stamp == 'null') {
    return PointLink.gap;
  }

  final rawDays = telemetry['days_not_connection'];
  final days = rawDays is num
      ? rawDays.toDouble()
      : double.tryParse('$rawDays');
  if (days != null && days > 0) return PointLink.gap;
  return PointLink.connected;
}

String pointLinkLabel(PointLink link) => switch (link) {
  PointLink.connected => 'Conectado',
  PointLink.gap => 'Advertencia',
  PointLink.incident => 'Incidencia',
};

Map<String, dynamic> _telemetry(Map<String, dynamic> point) {
  final value = point['latest_telemetry'];
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const {};
}
