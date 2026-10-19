import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/n1/n1_api.dart';
import '../../core/n1/n1_models.dart';
import '../../shared/widgets/hydro_glass.dart';
import 'n1_buddy.dart';

/// Pregunta corta a N1. En el inicio es una barra; en el resto, un buddy que se asoma.
class QuickAsk extends StatefulWidget {
  const QuickAsk({
    required this.n1Api,
    required this.token,
    required this.email,
    required this.pointIds,
    this.name = '',
    this.clients = const [],
    this.peek = false,
    super.key,
  });

  final N1Api n1Api;
  final String token;
  final String email;
  final List<int> pointIds;
  final String name;
  final List<String> clients;

  /// Botón del buddy que abre el campo. En el inicio va en falso y se ve la barra.
  final bool peek;

  @override
  State<QuickAsk> createState() => _QuickAskState();
}

class _QuickAskState extends State<QuickAsk> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final String _sessionId;
  var _open = false;
  var _busy = false;
  String? _answer;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _sessionId = 'sh-quick-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  N1BuddyMood get _mood {
    if (_busy) return N1BuddyMood.thinking;
    if (_failed) return N1BuddyMood.error;
    if (_answer != null) return N1BuddyMood.proud;
    return N1BuddyMood.idle;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    final email = widget.email.trim().toLowerCase();
    if (!widget.n1Api.isConfigured) {
      setState(() {
        _failed = true;
        _answer = 'El asistente no está disponible en esta compilación.';
      });
      return;
    }
    if (email.isEmpty) {
      setState(() {
        _failed = true;
        _answer = 'Tu sesión no tiene correo para preguntar.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _answer = null;
    });
    try {
      final result = await widget.n1Api.ask(
        token: widget.token,
        requester: email,
        text: text,
        sessionId: _sessionId,
        pointsAllowed: widget.pointIds.isEmpty ? null : widget.pointIds,
        name: widget.name,
        clients: widget.clients,
      );
      if (!mounted) return;
      final reply = result.text.trim();
      setState(() {
        _failed = !result.ok;
        _answer = reply.isNotEmpty ? reply : (result.error ?? 'Sin respuesta.');
        _controller.clear();
      });
    } on N1ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _answer = error.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.peek) return _bar();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_open) ...[
          SizedBox(width: 300, child: _bar()),
          const SizedBox(height: 8),
        ],
        _BuddyPeek(
          open: _open,
          mood: _mood,
          onTap: () {
            setState(() => _open = !_open);
            if (_open) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focus.requestFocus();
              });
            }
          },
        ),
      ],
    );
  }

  Widget _bar() {
    return HydroGlass(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              N1Buddy(size: 28, mood: _mood),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 2,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Pregunta rápida',
                    hintStyle: TextStyle(
                      color: Color(0xFF8FA3A4),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Preguntar',
                onPressed: _busy ? null : _send,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    : const Icon(Icons.arrow_upward_rounded, size: 18),
              ),
            ],
          ),
          if (_answer != null) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(
                  _answer!,
                  style: TextStyle(
                    color: _failed
                        ? IkoluColors.incident
                        : const Color(0xFFD5E4E2),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Buddy flotante N1: se asoma abajo a la derecha.
class _BuddyPeek extends StatelessWidget {
  const _BuddyPeek({
    required this.open,
    required this.mood,
    required this.onTap,
  });

  final bool open;
  final N1BuddyMood mood;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = open ? 52.0 : 60.0;
    return Tooltip(
      message: open ? 'Cerrar' : 'Pregunta rápida',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            alignment: Alignment.center,
            child: N1Buddy(
              key: const ValueKey('n1-quick-buddy'),
              size: size,
              mood: mood,
            ),
          ),
        ),
      ),
    );
  }
}
