/// Bloques limpios para pintar la respuesta de N1 (sin markdown).
enum N1BlockKind { heading, section, point, stat, suggest, body }

class N1PresentBlock {
  const N1PresentBlock({
    required this.kind,
    required this.text,
    this.detail,
    this.tags = const [],
  });

  final N1BlockKind kind;
  final String text;
  final String? detail;
  final List<String> tags;
}

/// Texto plano para memoria / fallback. Secciones con línea en blanco.
String n1PresentText(String raw) {
  final blocks = n1PresentBlocks(raw);
  if (blocks.isEmpty) return '';
  final out = <String>[];
  N1BlockKind? prev;
  for (final block in blocks) {
    final chunk = _blockAsText(block);
    if (chunk.isEmpty) continue;
    if (out.isNotEmpty) {
      final tight =
          prev == N1BlockKind.point && block.kind == N1BlockKind.point ||
          prev == N1BlockKind.stat && block.kind == N1BlockKind.stat;
      out.add(tight ? '\n' : '\n\n');
    }
    out.add(chunk);
    prev = block.kind;
  }
  return out.join().trim();
}

List<N1PresentBlock> n1PresentBlocks(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  final blocks = <N1PresentBlock>[];
  for (final line in lines) {
    var text = line.trim();
    if (text.isEmpty) continue;
    if (text.startsWith('ℹ️')) continue;
    if (text.startsWith('_Panel:')) continue;
    if (text.startsWith('_Detalle')) continue;
    if (text.toLowerCase().contains('usa los botones de abajo')) {
      text = text
          .replaceAll(RegExp(r'usa los botones.*', caseSensitive: false), '')
          .replaceAll(RegExp(r'·\s*$'), '')
          .trim();
      if (text.isEmpty) continue;
    }
    text = _stripMarks(text);
    if (text.isEmpty) continue;

    final lower = text.toLowerCase();
    if (RegExp(r'^por punto:?$', caseSensitive: false).hasMatch(text)) {
      blocks.add(const N1PresentBlock(kind: N1BlockKind.section, text: 'Por punto'));
      continue;
    }
    if (lower.startsWith('te sugiero')) {
      final body = text
          .replaceFirst(RegExp(r'^te sugiero:?\s*', caseSensitive: false), '')
          .trim();
      blocks.add(
        N1PresentBlock(
          kind: N1BlockKind.suggest,
          text: body.isEmpty ? text : body,
        ),
      );
      continue;
    }
    if (lower == 'sugerencia') {
      blocks.add(
        const N1PresentBlock(kind: N1BlockKind.section, text: 'Sugerencia'),
      );
      continue;
    }

    final stat = _statBlock(text);
    if (stat != null) {
      blocks.add(stat);
      continue;
    }

    if (text.startsWith('•') || text.startsWith('-')) {
      text = text.replaceFirst(RegExp(r'^[•\-]\s*'), '');
    }
    if (_looksLikePoint(text)) {
      blocks.add(_pointBlock(text));
      continue;
    }
    if (_looksLikeHeading(text, blocks)) {
      blocks.add(N1PresentBlock(kind: N1BlockKind.heading, text: _tidy(text)));
      continue;
    }
    blocks.add(N1PresentBlock(kind: N1BlockKind.body, text: _tidy(text)));
  }
  return blocks;
}

String _blockAsText(N1PresentBlock block) {
  switch (block.kind) {
    case N1BlockKind.heading:
    case N1BlockKind.section:
    case N1BlockKind.body:
      return block.text;
    case N1BlockKind.suggest:
      return 'Sugerencia\n${block.text}';
    case N1BlockKind.stat:
      final value = block.detail;
      if (value == null || value.isEmpty) return block.text;
      return '${block.text}: $value';
    case N1BlockKind.point:
      if (block.tags.isEmpty) return block.text;
      return '${block.text} · ${block.tags.join(' · ')}';
  }
}

bool _looksLikeHeading(String text, List<N1PresentBlock> soFar) {
  if (RegExp(r'\d+\s*puntos?', caseSensitive: false).hasMatch(text)) {
    return true;
  }
  return soFar.isEmpty && !text.contains(' · ');
}

bool _looksLikePoint(String text) {
  final lower = text.toLowerCase();
  const hints = [
    'activo',
    'sin datos',
    'sin ticket',
    'últ.',
    'ult.',
    'dga',
    'desconect',
  ];
  if (!hints.any(lower.contains)) return false;
  return text.contains(' · ') || text.contains(' – ');
}

N1PresentBlock _pointBlock(String line) {
  final tidy = _tidy(line);
  final parts = tidy.split(' · ').where((p) => p.trim().isNotEmpty).toList();
  if (parts.isEmpty) {
    return N1PresentBlock(kind: N1BlockKind.point, text: tidy);
  }
  final name = parts.first.split(' – ').last.trim();
  return N1PresentBlock(
    kind: N1BlockKind.point,
    text: name,
    tags: [for (final tag in parts.skip(1)) _tidy(tag)],
  );
}

N1PresentBlock? _statBlock(String text) {
  final match = RegExp(
    r'^(Desconectados|Tickets abiertos|Cumplimiento DGA)\s*:?\s*(.*)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final label = _statLabel(match.group(1)!);
  var value = _tidy(match.group(2) ?? '');
  value = value.replaceAll(RegExp(r'^·\s*'), '');
  return N1PresentBlock(kind: N1BlockKind.stat, text: label, detail: value);
}

String _statLabel(String raw) {
  final lower = raw.toLowerCase();
  if (lower.startsWith('desconect')) return 'Desconectados';
  if (lower.startsWith('ticket')) return 'Tickets abiertos';
  return 'Cumplimiento DGA';
}

String _stripMarks(String text) {
  var t = text.trim();
  t = t.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
  t = t.replaceAll('*', '');
  t = t.replaceAll('ℹ️', '');
  return t.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
}

String _tidy(String text) => text
    .replaceAll('sin ticket SLA', 'sin ticket')
    .replaceAll('DGA no reporta DGA', 'sin reporte DGA')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
