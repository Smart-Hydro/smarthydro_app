/// Clasificación de lecturas frente al caudal autorizado (L/s).
///
/// Sobre el límite: caudal estrictamente mayor al autorizado.
/// Cercano: desde el 90% inclusive hasta el autorizado inclusive.
enum FlowBand { within, near, over }

FlowBand? flowBand(num? flow, num? authorized) {
  if (flow == null || authorized == null || authorized <= 0) return null;
  if (flow > authorized) return FlowBand.over;
  if (flow >= authorized * 0.9) return FlowBand.near;
  return FlowBand.within;
}

List<Map<String, dynamic>> readingsInBand(
  List<Map<String, dynamic>> records,
  num? authorized,
  FlowBand band,
) {
  final matches = <Map<String, dynamic>>[];
  for (final record in records) {
    final flow = _asNum(record['flow']);
    if (flowBand(flow, authorized) == band) matches.add(record);
  }
  matches.sort((a, b) => _stamp(b).compareTo(_stamp(a)));
  return matches;
}

/// La consulta dedicada manda si trajo filas. Si vino vacía o falló, se usan
/// las mediciones del período que ya están en pantalla.
List<Map<String, dynamic>> visibleBandReadings({
  required List<Map<String, dynamic>> periodRecords,
  required List<Map<String, dynamic>> remoteRows,
  required num? authorized,
  required FlowBand band,
}) {
  if (remoteRows.isNotEmpty) {
    final copy = [...remoteRows];
    copy.sort((a, b) => _stamp(b).compareTo(_stamp(a)));
    return copy;
  }
  return readingsInBand(periodRecords, authorized, band);
}

num? _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse('${value ?? ''}');
}

String _stamp(Map<String, dynamic> record) =>
    record['date_time']?.toString() ??
    record['date_time_medition']?.toString() ??
    '';
