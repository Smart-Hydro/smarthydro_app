import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/n1/n1_api.dart';
import '../../core/n1/n1_models.dart';
import '../../shared/widgets/hydro_glass.dart';

enum _ChatRole { user, assistant, system }

class _ChatMessage {
  _ChatMessage({
    required this.role,
    required this.text,
    this.pending = false,
    this.errorCode,
    this.requeryOp,
    this.requeryPayload,
  });

  final _ChatRole role;
  String text;
  bool pending;
  List<String> links = const [];
  int? ticketId;
  String? errorCode;

  /// Para reconsultar jobs ⏳ (ask / report / list_files).
  final String? requeryOp;
  final Map<String, dynamic>? requeryPayload;
}

/// Pantalla Asistente N1 (chat) — ask, report, list_files, create_ticket.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    required this.n1Api,
    required this.session,
    required this.points,
    super.key,
  });

  final N1Api n1Api;
  final SmartHydroSession session;
  final List<Map<String, dynamic>> points;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[];
  late final String _sessionId;
  bool _busy = false;
  Timer? _pollTimer;

  String get _token => widget.session.token;
  String get _email => widget.session.email.trim().toLowerCase();
  List<int> get _pointIds => widget.points
      .map((p) => p['id'])
      .map((id) => id is int ? id : int.tryParse('$id'))
      .whereType<int>()
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _sessionId = 'sh-app-${DateTime.now().millisecondsSinceEpoch}';
    _messages.add(
      _ChatMessage(
        role: _ChatRole.system,
        text: widget.n1Api.isConfigured
            ? 'Soy SmartHydro N1. Pregúntame por el estado de un punto, pide un reporte, lista archivos o crea un ticket.'
            : 'N1 no está configurado. Compila con --dart-define=N1_WEB_APP_URL=<url /exec de la Web App>.',
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _sendAsk([String? forced]) async {
    final text = (forced ?? _controller.text).trim();
    if (text.isEmpty || _busy) return;
    if (!widget.n1Api.isConfigured) {
      _showConfigError();
      return;
    }
    if (_email.isEmpty) {
      _appendError('Tu sesión no tiene correo; N1 requiere requester.');
      return;
    }

    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(role: _ChatRole.user, text: text));
      _busy = true;
    });
    _scrollToEnd();

    final pendingBubble = _ChatMessage(
      role: _ChatRole.assistant,
      text: '…',
      pending: true,
      requeryOp: 'ask',
      requeryPayload: {'text': text},
    );
    setState(() => _messages.add(pendingBubble));
    _scrollToEnd();

    try {
      final result = await widget.n1Api.ask(
        token: _token,
        requester: _email,
        text: text,
        sessionId: _sessionId,
        pointsAllowed: _pointIds.isEmpty ? null : _pointIds,
      );
      _applyResult(pendingBubble, result);
    } on N1ApiException catch (error) {
      _failBubble(pendingBubble, error);
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  Future<void> _sendReport(String query) async {
    if (_busy || query.trim().isEmpty) return;
    if (!widget.n1Api.isConfigured) {
      _showConfigError();
      return;
    }
    setState(() {
      _messages.add(
        _ChatMessage(role: _ChatRole.user, text: 'Reporte: $query'),
      );
      _busy = true;
    });
    final bubble = _ChatMessage(
      role: _ChatRole.assistant,
      text: '⏳ preparando reporte…',
      pending: true,
      requeryOp: 'report',
      requeryPayload: {'query': query},
    );
    setState(() => _messages.add(bubble));
    _scrollToEnd();
    try {
      final result = await widget.n1Api.report(
        token: _token,
        requester: _email,
        query: query,
        pointsAllowed: _pointIds.isEmpty ? null : _pointIds,
      );
      _applyResult(bubble, result);
    } on N1ApiException catch (error) {
      _failBubble(bubble, error);
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  Future<void> _listFiles({String? client}) async {
    if (_busy) return;
    if (!widget.n1Api.isConfigured) {
      _showConfigError();
      return;
    }
    setState(() {
      _messages.add(
        _ChatMessage(
          role: _ChatRole.user,
          text: client == null || client.isEmpty
              ? 'Listar archivos recientes'
              : 'Listar archivos de $client',
        ),
      );
      _busy = true;
    });
    final bubble = _ChatMessage(
      role: _ChatRole.assistant,
      text: '…',
      pending: true,
      requeryOp: 'list_files',
      requeryPayload: {'client': client ?? ''},
    );
    setState(() => _messages.add(bubble));
    _scrollToEnd();
    try {
      final result = await widget.n1Api.listFiles(
        token: _token,
        requester: _email,
        client: client,
      );
      if (!mounted) return;
      if (result.files.isEmpty) {
        setState(() {
          bubble.pending = false;
          bubble.text = result.note?.isNotEmpty == true
              ? result.note!
              : 'No hay archivos recientes en la bitácora.';
        });
      } else {
        final links = result.files
            .where((f) => f.hasUrl)
            .map((f) => f.url)
            .toList(growable: false);
        final lines = result.files.map((f) {
          final label = [
            if (f.client.isNotEmpty) f.client,
            if (f.type.isNotEmpty) f.type,
            if (f.period.isNotEmpty) f.period,
          ].join(' · ');
          return '• ${label.isEmpty ? 'Archivo' : label}${f.hasUrl ? '' : ' (sin link)'}';
        });
        setState(() {
          bubble.pending = false;
          bubble.text =
              'Archivos (${result.files.length}):\n${lines.join('\n')}';
          bubble.links = links;
        });
      }
    } on N1ApiException catch (error) {
      _failBubble(bubble, error);
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  Future<void> _createTicketFlow() async {
    if (!widget.n1Api.isConfigured) {
      _showConfigError();
      return;
    }
    if (_pointIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Necesitas un punto asignado para crear un ticket.'),
        ),
      );
      return;
    }
    final draft = await showModalBottomSheet<_TicketDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF102328),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => _TicketDraftSheet(points: widget.points),
    );
    if (draft == null || !mounted) return;

    setState(() {
      _messages.add(
        _ChatMessage(
          role: _ChatRole.user,
          text: 'Crear ticket: ${draft.title}',
        ),
      );
      _busy = true;
    });
    final bubble = _ChatMessage(
      role: _ChatRole.assistant,
      text: 'Creando ticket…',
      pending: true,
    );
    setState(() => _messages.add(bubble));
    _scrollToEnd();

    try {
      final result = await widget.n1Api.createTicket(
        token: _token,
        requester: _email,
        title: draft.title,
        description: draft.description,
        points: [draft.pointId],
        priority: draft.priority,
        pointsAllowed: _pointIds,
      );
      if (!mounted) return;
      final id = result.ticketId;
      setState(() {
        bubble.pending = false;
        bubble.ticketId = id;
        bubble.text = id == null
            ? 'Ticket creado, pero la API no devolvió id.'
            : 'Ticket creado · id $id\n(El acuse y la asignación los gestiona la API; la app no los duplica.)';
      });
    } on N1ApiException catch (error) {
      _failBubble(bubble, error);
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  void _applyResult(_ChatMessage bubble, N1Response result) {
    if (!mounted) return;
    final urls = <String>{
      ...extractHttpUrls(result.text),
      ...result.files.where((f) => f.hasUrl).map((f) => f.url),
    }.toList(growable: false);
    setState(() {
      bubble.pending = result.isPending;
      bubble.text = result.text.trim().isEmpty
          ? (result.note ?? 'Sin texto de respuesta.')
          : result.text;
      bubble.links = urls;
      bubble.ticketId = result.ticketId;
    });
    if (result.isPending) {
      _scheduleRequery(bubble);
    } else {
      _pollTimer?.cancel();
    }
  }

  void _failBubble(_ChatMessage bubble, N1ApiException error) {
    if (!mounted) return;
    setState(() {
      bubble.pending = false;
      bubble.errorCode = error.code;
      bubble.text = error.code == null
          ? error.message
          : '${error.message} (${error.code})';
    });
  }

  void _appendError(String message) {
    setState(() {
      _messages.add(
        _ChatMessage(
          role: _ChatRole.assistant,
          text: message,
          errorCode: 'error',
        ),
      );
    });
    _scrollToEnd();
  }

  void _showConfigError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Configura N1_WEB_APP_URL con la URL /exec de la Web App N1.',
        ),
      ),
    );
  }

  void _scheduleRequery(_ChatMessage bubble) {
    _pollTimer?.cancel();
    _pollTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || bubble.requeryOp == null) return;
      _requery(bubble);
    });
  }

  Future<void> _requery(_ChatMessage bubble) async {
    if (_busy || bubble.requeryOp == null) return;
    setState(() => _busy = true);
    try {
      final op = bubble.requeryOp!;
      final payload = bubble.requeryPayload ?? const {};
      late final N1Response result;
      if (op == 'ask') {
        result = await widget.n1Api.ask(
          token: _token,
          requester: _email,
          text: '${payload['text'] ?? ''}',
          sessionId: _sessionId,
          pointsAllowed: _pointIds.isEmpty ? null : _pointIds,
        );
      } else if (op == 'report') {
        result = await widget.n1Api.report(
          token: _token,
          requester: _email,
          query: '${payload['query'] ?? ''}',
          pointsAllowed: _pointIds.isEmpty ? null : _pointIds,
        );
      } else if (op == 'list_files') {
        await _listFiles(client: '${payload['client'] ?? ''}');
        return;
      } else {
        return;
      }
      _applyResult(bubble, result);
      if (result.isPending) {
        // Tras un ⏳ de reporte, también consultar list_files por si ya hay link.
        if (op == 'report') {
          try {
            final files = await widget.n1Api.listFiles(
              token: _token,
              requester: _email,
            );
            final links = files.files
                .where((f) => f.hasUrl)
                .map((f) => f.url)
                .toList(growable: false);
            if (links.isNotEmpty && mounted) {
              setState(() {
                bubble.links = {...bubble.links, ...links}.toList();
                if (!result.isPending) bubble.pending = false;
              });
            }
          } on N1ApiException {
            // list_files opcional en el ciclo de reconsulta
          }
        }
        _scheduleRequery(bubble);
      }
    } on N1ApiException catch (error) {
      _failBubble(bubble, error);
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No pude abrir $url')));
    }
  }

  Future<void> _promptReport() async {
    final controller = TextEditingController(
      text: 'excel desconectados por acá',
    );
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pedir reporte'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Pedido en lenguaje natural',
            hintText: 'reporte mensual de … por acá',
          ),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query != null && query.isNotEmpty) await _sendReport(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Acciones N1',
            onSelected: (value) {
              switch (value) {
                case 'report':
                  _promptReport();
                case 'files':
                  _listFiles();
                case 'ticket':
                  _createTicketFlow();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'report', child: Text('Pedir reporte')),
              PopupMenuItem(value: 'files', child: Text('Listar archivos')),
              PopupMenuItem(value: 'ticket', child: Text('Crear ticket')),
            ],
          ),
        ],
      ),
      body: HydroFrame(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _ChatBubble(
                    message: msg,
                    onOpenUrl: _openUrl,
                    onRequery: msg.pending && msg.requeryOp != null
                        ? () => _requery(msg)
                        : null,
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_busy && widget.n1Api.isConfigured,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendAsk(),
                        decoration: const InputDecoration(
                          hintText: 'Pregunta a N1…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Enviar',
                      onPressed: _busy || !widget.n1Api.isConfigured
                          ? null
                          : () => _sendAsk(),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.onOpenUrl,
    this.onRequery,
  });

  final _ChatMessage message;
  final ValueChanged<String> onOpenUrl;
  final VoidCallback? onRequery;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _ChatRole.user;
    final isSystem = message.role == _ChatRole.system;
    final bg = isUser
        ? const Color(0xFF1A3A3E)
        : isSystem
        ? const Color(0xFF0F1C20)
        : const Color(0xFF12252A);
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: message.errorCode != null
                  ? const Color(0xFFFF847A).withValues(alpha: 0.45)
                  : message.pending
                  ? const Color(0xFFFFC46B).withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.pending)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '⏳ En curso…',
                        style: TextStyle(
                          color: Color(0xFFFFC46B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              SelectableText(
                message.text,
                style: TextStyle(
                  color: message.errorCode != null
                      ? const Color(0xFFFFA39B)
                      : const Color(0xFFE8F2F1),
                  height: 1.4,
                ),
              ),
              if (message.ticketId != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Chip(
                      label: Text('ticket_id ${message.ticketId}'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(
                        0xFF66E0C2,
                      ).withValues(alpha: 0.15),
                    ),
                    IconButton(
                      tooltip: 'Copiar id',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: '${message.ticketId}'),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ticket_id copiado')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ],
                ),
              ],
              if (message.links.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final url in message.links)
                      ActionChip(
                        avatar: const Icon(Icons.link_rounded, size: 16),
                        label: Text(
                          _shortUrl(url),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () => onOpenUrl(url),
                      ),
                  ],
                ),
              ],
              if (onRequery != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: onRequery,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reconsultar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _shortUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host;
    final path = uri.path;
    if (path.length <= 18) return '$host$path';
    return '$host…${path.substring(path.length - 12)}';
  }
}

class _TicketDraft {
  const _TicketDraft({
    required this.title,
    required this.description,
    required this.pointId,
    required this.priority,
  });

  final String title;
  final String description;
  final int pointId;
  final String priority;
}

class _TicketDraftSheet extends StatefulWidget {
  const _TicketDraftSheet({required this.points});

  final List<Map<String, dynamic>> points;

  @override
  State<_TicketDraftSheet> createState() => _TicketDraftSheetState();
}

class _TicketDraftSheetState extends State<_TicketDraftSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  late int _pointId;
  String _priority = 'MEDIA';

  @override
  void initState() {
    super.initState();
    final first = widget.points.first['id'];
    _pointId = first is int ? first : int.tryParse('$first') ?? 0;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 22,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Nuevo ticket vía N1',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Solo se muestra el ticket_id. Correo y asignación los maneja la API.',
              style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Asunto'),
              validator: (v) =>
                  (v?.trim().isNotEmpty ?? false) ? null : 'Ingresa un asunto.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Descripción'),
              validator: (v) => (v?.trim().isNotEmpty ?? false)
                  ? null
                  : 'Describe el problema.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _pointId,
              decoration: const InputDecoration(labelText: 'Punto'),
              items: [
                for (final point in widget.points)
                  DropdownMenuItem(
                    value: point['id'] is int
                        ? point['id'] as int
                        : int.tryParse('${point['id']}') ?? 0,
                    child: Text(point['title']?.toString() ?? 'Punto'),
                  ),
              ],
              onChanged: (v) => setState(() => _pointId = v ?? _pointId),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Prioridad'),
              items: const [
                DropdownMenuItem(value: 'BAJA', child: Text('Baja')),
                DropdownMenuItem(value: 'MEDIA', child: Text('Media')),
                DropdownMenuItem(value: 'ALTA', child: Text('Alta')),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'MEDIA'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(
                  context,
                  _TicketDraft(
                    title: _title.text.trim(),
                    description: _description.text.trim(),
                    pointId: _pointId,
                    priority: _priority,
                  ),
                );
              },
              icon: const Icon(Icons.confirmation_number_outlined),
              label: const Text('Crear ticket'),
            ),
          ],
        ),
      ),
    );
  }
}
