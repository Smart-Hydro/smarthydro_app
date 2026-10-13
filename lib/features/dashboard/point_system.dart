/// El aviso o el evento pertenece a este punto de captación.
bool systemItemMatchesPoint(Map<String, dynamic> item, int pointId) {
  if (pointId <= 0) return false;

  bool same(dynamic value) {
    if (value is int) return value == pointId;
    if (value is num) return value.toInt() == pointId;
    final parsed = int.tryParse('$value');
    return parsed == pointId && value != null && '$value' != 'null';
  }

  bool inMap(Map<dynamic, dynamic> map) {
    if (same(map['point_id']) || same(map['catchment_point_id'])) return true;
    for (final key in ['point', 'catchment_point']) {
      final value = map[key];
      if (same(value)) return true;
      if (value is Map && (same(value['id']) || same(value['point_id']))) {
        return true;
      }
    }
    final points = map['points'];
    if (points is List) {
      for (final point in points) {
        if (same(point)) return true;
        if (point is Map && (same(point['id']) || same(point['point_id']))) {
          return true;
        }
      }
    }
    final ticket = map['ticket'];
    if (ticket is Map && inMap(ticket)) return true;
    return false;
  }

  return inMap(item);
}
