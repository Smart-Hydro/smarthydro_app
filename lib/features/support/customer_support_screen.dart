import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../shared/navigation/hydro_page_route.dart';
import '../../shared/widgets/hydro_glass.dart';

Future<bool?> showSupportTicketSheet(
  BuildContext context, {
  required SmartHydroApi api,
  required String token,
  required List<Map<String, dynamic>> points,
  String? initialTitle,
  String? initialDescription,
  int? initialPointId,
  String? initialPriority,
  bool lockPoint = false,
}) async {
  var categories = const <Map<String, dynamic>>[];
  try {
    categories = (await api.ticketCategories(token))
        .where(
          (category) => const {
            'SOFTWARE',
            'HARDWARE',
            'COMPLIANCE',
          }.contains('${category['category_type']}'.toUpperCase()),
        )
        .toList(growable: false);
  } on SmartHydroApiException {
    categories = const [];
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NewTicketSheet(
      api: api,
      token: token,
      points: points,
      categories: categories,
      initialTitle: initialTitle,
      initialDescription: initialDescription,
      initialPointId: initialPointId,
      initialPriority: initialPriority,
      lockPoint: lockPoint,
    ),
  );
}

class CustomerSupportScreen extends StatefulWidget {
  const CustomerSupportScreen({
    required this.api,
    required this.token,
    required this.points,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final List<Map<String, dynamic>> points;

  @override
  State<CustomerSupportScreen> createState() => _CustomerSupportScreenState();
}

class _CustomerSupportScreenState extends State<CustomerSupportScreen> {
  List<Map<String, dynamic>> _tickets = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tickets = await widget.api.supportTickets(widget.token);
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _loading = false;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _createTicket() async {
    if (widget.points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Necesitas un punto asignado para crear una solicitud.',
          ),
        ),
      );
      return;
    }
    final result = await showSupportTicketSheet(
      context,
      api: widget.api,
      token: widget.token,
      points: widget.points,
    );
    if (result == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud creada correctamente.')),
      );
    }
  }

  void _openTicket(Map<String, dynamic> ticket) {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        _TicketDetailScreen(
          api: widget.api,
          token: widget.token,
          ticket: ticket,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Soporte'),
      actions: [
        IconButton(
          onPressed: _load,
          tooltip: 'Actualizar solicitudes',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _createTicket,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Nueva solicitud'),
    ),
    body: HydroFrame(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 92),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) _SupportError(message: _error!, onRetry: _load),
          if (!_loading && _error == null && _tickets.isEmpty)
            const _SupportEmpty(),
          for (final ticket in _tickets) ...[
            _TicketCard(ticket: ticket, onTap: () => _openTicket(ticket)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}

class _NewTicketSheet extends StatefulWidget {
  const _NewTicketSheet({
    required this.api,
    required this.token,
    required this.points,
    required this.categories,
    this.initialTitle,
    this.initialDescription,
    this.initialPointId,
    this.initialPriority,
    this.lockPoint = false,
  });

  final SmartHydroApi api;
  final String token;
  final List<Map<String, dynamic>> points;
  final List<Map<String, dynamic>> categories;
  final String? initialTitle;
  final String? initialDescription;
  final int? initialPointId;
  final String? initialPriority;
  final bool lockPoint;

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _pointId;
  int? _categoryId;
  String _priority = 'MEDIA';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.initialTitle ?? '';
    _descriptionController.text = widget.initialDescription ?? '';
    _priority = widget.initialPriority ?? 'MEDIA';
    final requested = widget.initialPointId;
    final known = widget.points.any(
      (point) => _asInt(point['id']) == requested,
    );
    _pointId = known
        ? requested
        : (widget.points.isEmpty ? null : _asInt(widget.points.first['id']));
    if (widget.categories.isNotEmpty) {
      _categoryId = _asInt(widget.categories.first['id']);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _pointId == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.api.createSupportTicket(
        widget.token,
        title: _titleController.text,
        description: _descriptionController.text,
        priority: _priority,
        pointIds: [_pointId!],
        categoryId: _categoryId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
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
          TextFormField(
            controller: _titleController,
            enabled: !_submitting,
            decoration: const InputDecoration(labelText: 'Asunto'),
            validator: (value) => (value?.trim().isNotEmpty ?? false)
                ? null
                : 'Ingresa un asunto.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            enabled: !_submitting,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Describe lo que ocurre',
            ),
            validator: (value) => (value?.trim().isNotEmpty ?? false)
                ? null
                : 'Describe brevemente el problema.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _pointId,
            decoration: const InputDecoration(labelText: 'Punto'),
            items: [
              for (final point in widget.points)
                DropdownMenuItem<int>(
                  value: _asInt(point['id']),
                  child: Text(point['title']?.toString() ?? 'Punto'),
                ),
            ],
            onChanged: _submitting || widget.lockPoint
                ? null
                : (value) => setState(() => _pointId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Sin categoría'),
              ),
              for (final category in widget.categories)
                DropdownMenuItem<int?>(
                  value: _asInt(category['id']),
                  child: Text(category['name']?.toString() ?? 'Categoría'),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() => _categoryId = value),
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
            onChanged: _submitting
                ? null
                : (value) => setState(() => _priority = value ?? 'MEDIA'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF847A))),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Enviar solicitud'),
          ),
        ],
      ),
    ),
  );
}

class _TicketDetailScreen extends StatefulWidget {
  const _TicketDetailScreen({
    required this.api,
    required this.token,
    required this.ticket,
  });

  final SmartHydroApi api;
  final String token;
  final Map<String, dynamic> ticket;

  @override
  State<_TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<_TicketDetailScreen> {
  final _commentController = TextEditingController();
  Map<String, dynamic> _detail = const {};
  List<Map<String, dynamic>> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = _asInt(widget.ticket['id']);
      final results = await Future.wait<dynamic>([
        widget.api.supportTicket(widget.token, id),
        widget.api.ticketComments(widget.token, id),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = results[0] as Map<String, dynamic>;
        _comments = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.api.addTicketComment(
        widget.token,
        _asInt(widget.ticket['id']),
        text,
      );
      _commentController.clear();
      await _load();
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _detail.isEmpty ? widget.ticket : _detail;
    final points = ticket['points'];
    final pointLabel = points is List && points.isNotEmpty
        ? _asMap(points.first)['title']?.toString() ?? 'Punto asociado'
        : 'Solicitud general';
    return Scaffold(
      appBar: AppBar(title: Text('Solicitud #${widget.ticket['id']}')),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFF847A)),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  ticket['title']?.toString() ?? 'Solicitud',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '$pointLabel · ${ticket['status'] ?? 'Estado pendiente'} · ${ticket['priority'] ?? 'Prioridad'}',
                  style: const TextStyle(
                    color: Color(0xFF9AB0B1),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                _SupportCard(
                  child: Text(ticket['description']?.toString() ?? ''),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Conversación',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                if (_comments.isEmpty && !_loading)
                  const Text(
                    'Todavía no hay respuestas.',
                    style: TextStyle(color: Color(0xFF9AB0B1)),
                  ),
                for (final comment in _comments)
                  _SupportComment(comment: comment),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Enviar respuesta',
                    onPressed: _sending ? null : _sendComment,
                    icon: _sending
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
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});

  final Map<String, dynamic> ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF112328),
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            const Icon(Icons.support_agent_rounded, color: Color(0xFFFFC46B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket['title']?.toString() ?? 'Solicitud',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'N° ${ticket['id']} · ${ticket['status'] ?? ''} · ${ticket['priority'] ?? ''}',
                    style: const TextStyle(
                      color: Color(0xFF9AB0B1),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF91A8AA)),
          ],
        ),
      ),
    ),
  );
}

class _SupportComment extends StatelessWidget {
  const _SupportComment({required this.comment});

  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: _SupportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            comment['author_name']?.toString() ?? 'Equipo SmartHydro',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          ),
          const SizedBox(height: 5),
          Text(
            comment['content']?.toString() ??
                comment['message']?.toString() ??
                '',
          ),
          const SizedBox(height: 5),
          Text(
            _supportDate(comment['created']),
            style: const TextStyle(color: Color(0xFF81999A), fontSize: 9),
          ),
        ],
      ),
    ),
  );
}

class _SupportEmpty extends StatelessWidget {
  const _SupportEmpty();

  @override
  Widget build(BuildContext context) => const _SupportCard(
    child: Column(
      children: [
        Icon(Icons.inbox_outlined, color: Color(0xFF66E0C2), size: 30),
        SizedBox(height: 9),
        Text('No tienes solicitudes de soporte activas.'),
      ],
    ),
  );
}

class _SupportError extends StatelessWidget {
  const _SupportError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _SupportCard(
    child: Row(
      children: [
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFF112328),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: child,
  );
}

int _asInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  return const {};
}

String _supportDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
