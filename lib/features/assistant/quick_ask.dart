import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/n1/n1_api.dart';
import '../../core/n1/n1_memory.dart';
import '../../core/n1/n1_models.dart';
import '../../core/n1/n1_present.dart';
import 'n1_buddy.dart';
import 'n1_message_body.dart';

class _Line {
  _Line({required this.mine, required this.text, this.pending = false});

  final bool mine;
  String text;
  bool pending;
}

/// Chat flotante de N1. El buddy abre una caja de conversación, no un campo.
class QuickAsk extends StatefulWidget {
  const QuickAsk({
    required this.n1Api,
    required this.token,
    required this.email,
    required this.pointIds,
    this.name = '',
    this.clients = const [],
    this.pointNames = const [],
    this.peek = false,
    this.userId,
    super.key,
  });

  final N1Api n1Api;
  final String token;
  final String email;
  final List<int> pointIds;
  final String name;
  final List<String> clients;
  final List<String> pointNames;
  final int? userId;

  /// Buddy que abre la caja. Sin peek la caja queda siempre visible (tests).
  final bool peek;

  @override
  State<QuickAsk> createState() => _QuickAskState();
}

class _QuickAskState extends State<QuickAsk> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final String _sessionId;
  var _open = false;
  var _busy = false;
  var _failed = false;
  final _turns = <_Line>[];

  static const _panelW = 380.0;
  static const _panelH = 440.0;

  @override
  void initState() {
    super.initState();
    _sessionId = N1Memory.sessionId(
      userId: widget.userId,
      email: widget.email,
    );
    unawaited(_restore());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final saved = await N1Memory.load(widget.userId);
    if (!mounted || saved.isEmpty) return;
    setState(() {
      _turns
        ..clear()
        ..addAll([
          for (final turn in saved)
            if (turn.role == 'user' || turn.role == 'assistant')
              _Line(mine: turn.role == 'user', text: turn.text),
        ]);
    });
    _scrollToEnd();
  }

  N1BuddyMood get _mood {
    if (_busy) return N1BuddyMood.thinking;
    if (_failed) return N1BuddyMood.error;
    if (_turns.any((t) => !t.mine)) return N1BuddyMood.proud;
    return N1BuddyMood.idle;
  }

  String get _subtitle {
    final n = widget.pointNames.length;
    if (n == 1) return 'Veo 1 punto';
    if (n > 1) return 'Veo $n puntos';
    return 'Conversación continua';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 64,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    final email = widget.email.trim().toLowerCase();
    if (!widget.n1Api.isConfigured) {
      setState(() {
        _failed = true;
        _turns.add(
          _Line(
            mine: false,
            text: 'El asistente no está disponible en esta compilación.',
          ),
        );
      });
      return;
    }
    if (email.isEmpty) {
      setState(() {
        _failed = true;
        _turns.add(
          _Line(mine: false, text: 'Tu sesión no tiene correo para preguntar.'),
        );
      });
      return;
    }
    final pending = _Line(
      mine: false,
      text: 'Consultando tus puntos…',
      pending: true,
    );
    setState(() {
      _busy = true;
      _failed = false;
      _turns.add(_Line(mine: true, text: text));
      _turns.add(pending);
      _controller.clear();
    });
    _scrollToEnd();
    try {
      final result = await widget.n1Api.ask(
        token: widget.token,
        requester: email,
        text: text,
        sessionId: _sessionId,
        pointsAllowed: widget.pointIds.isEmpty ? null : widget.pointIds,
        name: widget.name,
        clients: widget.clients,
        pointNames: widget.pointNames.isEmpty ? null : widget.pointNames,
      );
      if (!mounted) return;
      final reply = result.text.trim();
      final shown = n1PresentText(reply);
      final answer = result.isPending && (reply.isEmpty || reply.startsWith('⏳'))
          ? 'Consultando tus puntos…'
          : (shown.isNotEmpty ? shown : (result.error ?? 'Sin respuesta.'));
      setState(() {
        _failed = !result.ok;
        pending.pending = result.isPending;
        pending.text = answer;
      });
      await N1Memory.append(widget.userId, N1ChatTurn(role: 'user', text: text));
      await N1Memory.append(
        widget.userId,
        N1ChatTurn(role: 'assistant', text: answer),
      );
    } on N1ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        pending.pending = false;
        pending.text = error.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.peek) return _panel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_open) ...[
          _panel(),
          const SizedBox(height: 8),
        ],
        _BuddyPeek(open: _open, mood: _mood, onTap: _toggle),
      ],
    );
  }

  Widget _panel() {
    final media = MediaQuery.sizeOf(context);
    final width = math.min(_panelW, math.max(300.0, media.width - 24));
    final height = math.min(_panelH, math.max(320.0, media.height * 0.58));
    return Material(
      key: const ValueKey('n1-quick-panel'),
      color: const Color(0xF20A1418),
      elevation: 18,
      shadowColor: const Color(0xA0000000),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            Expanded(child: _thread()),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          N1Buddy(size: 36, mood: _mood),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'N1 · SmartHydro',
                  style: TextStyle(
                    color: Color(0xFFF4FEFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  style: const TextStyle(
                    color: Color(0xFF9AB0B1),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (widget.peek)
            IconButton(
              tooltip: 'Cerrar',
              onPressed: _toggle,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _thread() {
    if (_turns.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Text(
          'Pregúntame por el estado de tus puntos. Este hilo queda aquí y sigue en Asistente.',
          style: TextStyle(
            color: Color(0xFF9AB0B1),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      itemCount: _turns.length,
      itemBuilder: (context, index) {
        final line = _turns[index];
        return Align(
          alignment: line.mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: line.mine
                    ? const Color(0xFF164A52)
                    : const Color(0xFF12252A),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(line.mine ? 14 : 4),
                  bottomRight: Radius.circular(line.mine ? 4 : 14),
                ),
                border: Border.all(
                  color: line.pending
                      ? const Color(0xFFFFC46B).withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: line.mine
                  ? Text(
                      line.text,
                      style: const TextStyle(
                        color: Color(0xFFE8F2F1),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    )
                  : N1MessageBody(
                      text: line.text,
                      error:
                          _failed &&
                          !line.mine &&
                          index == _turns.length - 1,
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC0E1A1E),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(
                    color: Color(0xFFF4FEFF),
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Pregunta a N1…',
                    hintStyle: TextStyle(
                      color: Color(0xFF8FA3A4),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Enviar',
                onPressed: _busy ? null : _send,
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: IkoluColors.cyan,
                  foregroundColor: const Color(0xFF062028),
                  disabledBackgroundColor: const Color(0xFF1A3338),
                ),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: Color(0xFF062028),
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buddy flotante N1: chico en reposo, crece al acercar el cursor.
class _BuddyPeek extends StatefulWidget {
  const _BuddyPeek({
    required this.open,
    required this.mood,
    required this.onTap,
  });

  final bool open;
  final N1BuddyMood mood;
  final VoidCallback onTap;

  @override
  State<_BuddyPeek> createState() => _BuddyPeekState();
}

class _BuddyPeekState extends State<_BuddyPeek> {
  var _hover = false;

  static const _idle = 34.0;
  static const _hot = 46.0;

  double get _size {
    if (widget.open || _hover) return _hot;
    return _idle;
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.open ? 'Cerrar' : 'Asistente N1',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              alignment: Alignment.center,
              child: N1Buddy(
                key: const ValueKey('n1-quick-buddy'),
                size: size,
                mood: widget.mood,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
