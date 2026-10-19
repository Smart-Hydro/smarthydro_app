import 'dart:typed_data';

import 'dga_compliance.dart';

/// Cache en memoria del listado DGA, la ficha del punto y la planilla del mes.
///
/// Vive en el proceso: salir y volver a Cumplimiento no vuelve a cargar de
/// cero. [invalidate] (Actualizar) tira las entradas de ese token.
class ComplianceStore {
  ComplianceStore({
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  static ComplianceStore instance = ComplianceStore();

  final Duration ttl;
  final DateTime Function() clock;

  final Map<String, _Stamp<List<Map<String, dynamic>>>> _lists = {};
  final Map<String, _Stamp<Map<String, dynamic>>> _details = {};
  final Map<String, _Stamp<ComplianceMonthSnap>> _months = {};

  static String _listKey(String token) => 'list|$token';
  static String _detailKey(String token, int pointId) =>
      'detail|$token|$pointId';
  static String _monthKey(String token, int pointId, DateTime month) =>
      'month|$token|$pointId|${month.year}-${month.month}';

  bool _fresh(_Stamp<dynamic>? stamp) {
    if (stamp == null) return false;
    return clock().difference(stamp.at) <= ttl;
  }

  List<Map<String, dynamic>>? list(String token) => _lists[_listKey(token)]?.value;

  bool listIsFresh(String token) => _fresh(_lists[_listKey(token)]);

  void putList(String token, List<Map<String, dynamic>> points) {
    _lists[_listKey(token)] = _Stamp(
      [
        for (final point in points) Map<String, dynamic>.from(point),
      ],
      clock(),
    );
  }

  Map<String, dynamic>? pointOnList(String token, int pointId) {
    final points = list(token);
    if (points == null) return null;
    for (final point in points) {
      if ('${point['point_id']}' == '$pointId') return point;
    }
    return null;
  }

  Map<String, dynamic>? detail(String token, int pointId) =>
      _details[_detailKey(token, pointId)]?.value;

  bool detailIsFresh(String token, int pointId) =>
      _fresh(_details[_detailKey(token, pointId)]);

  void putDetail(String token, int pointId, Map<String, dynamic> detail) {
    _details[_detailKey(token, pointId)] = _Stamp(
      Map<String, dynamic>.from(detail),
      clock(),
    );
  }

  ComplianceMonthSnap? month(String token, int pointId, DateTime month) =>
      _months[_monthKey(token, pointId, month)]?.value;

  bool monthIsFresh(String token, int pointId, DateTime month) =>
      _fresh(_months[_monthKey(token, pointId, month)]);

  void putMonth(
    String token,
    int pointId,
    DateTime month,
    ComplianceMonthSnap snap,
  ) {
    _months[_monthKey(token, pointId, month)] = _Stamp(snap, clock());
  }

  void invalidate(String token) {
    final prefix = '|$token';
    _lists.removeWhere((key, _) => key.contains(prefix));
    _details.removeWhere((key, _) => key.contains(prefix));
    _months.removeWhere((key, _) => key.contains(prefix));
  }

  void clear() {
    _lists.clear();
    _details.clear();
    _months.clear();
  }
}

class ComplianceMonthSnap {
  const ComplianceMonthSnap({
    required this.bytes,
    required this.compliance,
  });

  final Uint8List bytes;
  final DgaCompliance compliance;
}

class _Stamp<T> {
  const _Stamp(this.value, this.at);

  final T value;
  final DateTime at;
}
