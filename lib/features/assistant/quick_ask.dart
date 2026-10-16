import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/n1/n1_api.dart';
import '../../core/n1/n1_models.dart';
import '../../shared/widgets/hydro_glass.dart';

/// Pregunta corta a N1. En el inicio es una barra; en el resto, un robot que se asoma.
class QuickAsk extends StatefulWidget {
  const QuickAsk({
    required this.n1Api,
    required this.token,
    required this.email,
    required this.pointIds,
    this.peek = false,
    super.key,
  });

  final N1Api n1Api;
  final String token;
  final String email;
  final List<int> pointIds;

  /// Botón de robot que abre el campo. En el inicio va en falso y se ve la barra.
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
        _CoucouButton(
          open: _open,
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
              const CoucouMark(size: 26),
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
            Text(
              _answer!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _failed ? IkoluColors.incident : const Color(0xFFD5E4E2),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoucouButton extends StatelessWidget {
  const _CoucouButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: open ? 'Cerrar' : 'Pregunta rápida',
      child: Material(
        color: const Color(0xFF102328),
        elevation: 6,
        shadowColor: const Color(0x6600C8FF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: CoucouMark(size: open ? 26 : 30),
          ),
        ),
      ),
    );
  }
}

/// Cabeza del asistente: antena, ojos y una sonrisa corta.
class CoucouMark extends StatelessWidget {
  const CoucouMark({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _CoucouPainter()),
    );
  }
}

class _CoucouPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.045
      ..color = IkoluColors.cyan;
    final head = RRect.fromRectAndRadius(
      Rect.fromLTWH(width * 0.16, height * 0.3, width * 0.68, height * 0.56),
      Radius.circular(width * 0.22),
    );
    canvas.drawRRect(head, Paint()..color = const Color(0xFF12343C));
    canvas.drawRRect(head, stroke);
    final top = Offset(width * 0.5, height * 0.3);
    final tip = Offset(width * 0.5, height * 0.08);
    canvas.drawLine(
      top,
      tip,
      Paint()
        ..color = IkoluColors.cyanSoft
        ..strokeWidth = width * 0.045
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      tip,
      width * 0.07,
      Paint()..color = const Color(0xFFB8FFE8),
    );
    final eye = Paint()..color = const Color(0xFFE8F2F1);
    canvas.drawCircle(Offset(width * 0.38, height * 0.52), width * 0.055, eye);
    canvas.drawCircle(Offset(width * 0.62, height * 0.52), width * 0.055, eye);
    final smile = Path()
      ..moveTo(width * 0.38, height * 0.68)
      ..quadraticBezierTo(
        width * 0.5,
        height * 0.78,
        width * 0.62,
        height * 0.68,
      );
    canvas.drawPath(smile, stroke..strokeWidth = width * 0.04);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
