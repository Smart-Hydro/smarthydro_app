/// Identidad del usuario logueado para que N1 no pregunte quién es.

List<String> n1ClientNamesOf(Iterable<Map<String, dynamic>> points) {
  final seen = <String>{};
  final names = <String>[];
  for (final point in points) {
    final raw =
        '${point['client_name'] ?? point['client'] ?? point['cliente'] ?? ''}'
            .trim();
    if (raw.isEmpty) continue;
    final key = raw.toLowerCase();
    if (seen.add(key)) names.add(raw);
  }
  return names;
}

/// Nombres de los puntos del usuario activo, sin repetir.
List<String> n1PointNamesOf(Iterable<Map<String, dynamic>> points) {
  final seen = <String>{};
  final names = <String>[];
  for (final point in points) {
    final raw = '${point['title'] ?? point['name'] ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') continue;
    final key = raw.toLowerCase();
    if (seen.add(key)) names.add(raw);
  }
  return names;
}

/// Completa la pregunta con cliente y nombre si el texto aún no los trae.
///
/// N1 trata `text` como lookup de un punto: pegar títulos ahí hace que busque
/// el bloque entero («riego chile soy … y 1 más») y responda «No ubiqué …».
/// El alcance de captaciones va en `points_allowed`, no en el texto.
String n1DecorateAskText(
  String text, {
  String? name,
  List<String> clients = const [],
  List<String> points = const [],
}) {
  // Firma estable: callers siguen pasando `points`; no se inyectan en `text`.
  points;
  final ask = text.trim();
  if (ask.isEmpty) return ask;
  final lower = ask.toLowerCase();
  final known = <String>[];
  final seen = <String>{};
  for (final client in clients) {
    final c = client.trim();
    if (c.isEmpty) continue;
    if (seen.add(c.toLowerCase())) known.add(c);
  }
  final namedClient = known.any((c) => lower.contains(c.toLowerCase()));
  final who = (name ?? '').trim();
  final namedWho =
      who.isNotEmpty &&
      lower.contains(who.split(RegExp(r'\s+')).first.toLowerCase());
  final whoIsClient = known.any((c) => c.toLowerCase() == who.toLowerCase());

  final bits = <String>[];
  if (!namedClient && known.isNotEmpty) {
    bits.add(
      known.length == 1
          ? 'cliente ${known.first}'
          : 'clientes ${known.join(', ')}',
    );
  }
  if (!namedWho && who.isNotEmpty && !whoIsClient) bits.add('soy $who');
  if (bits.isEmpty) return ask;
  return '$ask (${bits.join('; ')})';
}
