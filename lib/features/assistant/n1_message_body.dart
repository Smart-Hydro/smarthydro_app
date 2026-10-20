import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/n1/n1_present.dart';

/// Respuesta de N1 con jerarquía visual: títulos, puntos y datos, sin markdown.
class N1MessageBody extends StatelessWidget {
  const N1MessageBody({
    required this.text,
    this.error = false,
    super.key,
  });

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final blocks = n1PresentBlocks(text);
    if (blocks.isEmpty) {
      return SelectableText(
        text,
        style: TextStyle(
          color: error ? const Color(0xFFFFA39B) : const Color(0xFFE8F2F1),
          height: 1.45,
          fontSize: 14,
        ),
      );
    }
    return Column(
      key: const ValueKey('n1-msg-body'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: _gapBefore(blocks[i], blocks[i - 1])),
          _block(blocks[i]),
        ],
      ],
    );
  }

  double _gapBefore(N1PresentBlock block, N1PresentBlock prev) {
    if (prev.kind == N1BlockKind.point && block.kind == N1BlockKind.point) {
      return 10;
    }
    if (prev.kind == N1BlockKind.stat && block.kind == N1BlockKind.stat) {
      return 8;
    }
    if (block.kind == N1BlockKind.suggest) return 16;
    if (block.kind == N1BlockKind.section) return 14;
    return 12;
  }

  Widget _block(N1PresentBlock block) {
    final ink = error ? const Color(0xFFFFA39B) : const Color(0xFFE8F2F1);
    switch (block.kind) {
      case N1BlockKind.heading:
        return SelectableText(
          block.text,
          style: TextStyle(
            color: ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        );
      case N1BlockKind.section:
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            block.text,
            style: const TextStyle(
              color: Color(0xFF9AB0B1),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        );
      case N1BlockKind.point:
        return _point(block, ink);
      case N1BlockKind.stat:
        return _stat(block, ink);
      case N1BlockKind.suggest:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sugerencia',
              style: TextStyle(
                color: Color(0xFF9AB0B1),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              block.text,
              style: TextStyle(color: ink, fontSize: 13.5, height: 1.45),
            ),
          ],
        );
      case N1BlockKind.body:
        return SelectableText(
          block.text,
          style: TextStyle(color: ink, fontSize: 13.5, height: 1.45),
        );
    }
  }

  Widget _point(N1PresentBlock block, Color ink) {
    return Container(
      key: ValueKey('n1-msg-point-${block.text}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0x3310181C),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            block.text,
            style: TextStyle(
              color: ink,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (block.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final tag in block.tags) _tag(tag)],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(N1PresentBlock block, Color ink) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(
            block.text,
            style: const TextStyle(
              color: Color(0xFF9AB0B1),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            block.detail ?? '',
            style: TextStyle(
              color: ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tag(String label) {
    final tone = _tagColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }

  Color _tagColor(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('activo') || lower.contains('cumple')) {
      return IkoluColors.connected;
    }
    if (lower.contains('sin datos') ||
        lower.contains('sin ticket') ||
        lower.contains('riesgo')) {
      return IkoluColors.warning;
    }
    if (lower.contains('dga') || lower.contains('reporte')) {
      return IkoluColors.cyanSoft;
    }
    return const Color(0xFFB7C9C8);
  }
}
