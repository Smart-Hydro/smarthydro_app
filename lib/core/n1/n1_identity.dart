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

/// Completa la pregunta con cliente y nombre si el texto aún no los trae.
/// N1 (AppApi cliente) pide «qué cliente o punto» cuando el alcance viene vacío.
String n1DecorateAskText(
  String text, {
  String? name,
  List<String> clients = const [],
}) {
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

  final bits = <String>[];
  if (!namedClient && known.isNotEmpty) {
    bits.add(
      known.length == 1
          ? 'cliente ${known.first}'
          : 'clientes ${known.join(', ')}',
    );
  }
  if (!namedWho && who.isNotEmpty) bits.add('soy $who');
  if (bits.isEmpty) return ask;
  return '$ask (${bits.join('; ')})';
}
