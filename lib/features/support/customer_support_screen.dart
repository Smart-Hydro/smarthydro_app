import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/brand.dart';
import '../../shared/navigation/hydro_page_route.dart';
import '../../shared/ui/capture_point_picker.dart';
import '../../shared/ui/hydro_ui.dart';
import '../../shared/widgets/hydro_glass.dart';
import '../../shared/widgets/hydro_glyph.dart';

String supportStatusLabel(dynamic raw) {
  switch ('$raw'.trim().toUpperCase().replaceAll(' ', '_')) {
    case 'ABIERTO':
    case 'OPEN':
      return 'Abierta';
    case 'EN_PROCESO':
    case 'IN_PROGRESS':
      return 'En curso';
    case 'CERRADO':
    case 'CERRADA':
    case 'RESUELTO':
    case 'CLOSED':
      return 'Cerrada';
    default:
      final text = '$raw'.trim();
      if (text.isEmpty || text == 'null') return 'Pendiente';
      return text;
  }
}

String supportPriorityLabel(dynamic raw) {
  switch ('$raw'.trim().toUpperCase()) {
    case 'ALTA':
    case 'HIGH':
      return 'Alta';
    case 'BAJA':
    case 'LOW':
      return 'Baja';
    case 'MEDIA':
    case 'MEDIUM':
      return 'Media';
    default:
      final text = '$raw'.trim();
      if (text.isEmpty || text == 'null') return 'Media';
      return text;
  }
}

Color supportPriorityTone(dynamic raw) {
  switch ('$raw'.trim().toUpperCase()) {
    case 'ALTA':
    case 'HIGH':
      return IkoluColors.incident;
    case 'BAJA':
    case 'LOW':
      return IkoluColors.info;
    default:
      return IkoluColors.warning;
  }
}

Color supportStatusTone(dynamic raw) {
  switch (supportStatusLabel(raw)) {
    case 'Cerrada':
      return HydroTone.faint;
    case 'En curso':
      return IkoluColors.cyanSoft;
    default:
      return IkoluColors.connected;
  }
}

bool supportTicketIsOpen(Map<String, dynamic> ticket) {
  final status = '${ticket['status'] ?? ''}'.toUpperCase();
  return !status.contains('CERRAD') &&
      !status.contains('RESUELT') &&
      status != 'CLOSED';
}

String supportTicketPointLabel(Map<String, dynamic> ticket) {
  final points = ticket['points'];
  if (points is List && points.isNotEmpty) {
    final first = _asMap(points.first);
    final title = first['title']?.toString().trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  return 'Sin punto';
}

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
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0E1C20),
    barrierColor: Colors.black.withValues(alpha: 0.54),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => SupportTicketSheet(
      api: api,
      token: token,
      points: points,
      categories: const [],
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
    this.showBack = true,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final List<Map<String, dynamic>> points;

  /// En el shell de escritorio el rail reemplaza a Volver.
  final bool showBack;

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
  Widget build(BuildContext context) {
    final open = _tickets.where(supportTicketIsOpen).length;
    final high = _tickets
        .where((t) => supportPriorityLabel(t['priority']) == 'Alta')
        .length;
    return HydroPage(
      title: 'Soporte',
      showBack: widget.showBack,
      subtitle: const Text(
        'Tickets de tus puntos · seguimiento SLA',
        style: HydroText.subtitle,
      ),
      titleLeading: const HydroGlyph(
        kind: HydroGlyphKind.soporte,
        color: IkoluColors.warning,
        size: 40,
        keyPrefix: 'support-glyph',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _load,
            tooltip: 'Actualizar solicitudes',
            icon: const Icon(Icons.refresh_rounded, color: HydroTone.faint),
          ),
          _SupportTextButton(
            label: MediaQuery.sizeOf(context).width < 720
                ? 'Nueva'
                : 'Nueva solicitud',
            onPressed: _createTicket,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (!_loading && _error == null && _tickets.isNotEmpty) ...[
            _SupportPulse(open: open, high: high, total: _tickets.length),
            const SizedBox(height: 14),
          ],
          if (_loading && _tickets.isEmpty)
            const HydroSkeletonCards(height: 88)
          else if (_loading)
            HydroLinearBar(),
          if (_error != null) _SupportError(message: _error!, onRetry: _load),
          if (!_loading && _error == null && _tickets.isEmpty)
            _SupportEmpty(onCreate: _createTicket),
          for (final ticket in _tickets) ...[
            _TicketCard(ticket: ticket, onTap: () => _openTicket(ticket)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class SupportTicketSheet extends StatefulWidget {
  const SupportTicketSheet({
    required this.api,
    required this.token,
    required this.points,
    this.categories = const [],
    this.initialTitle,
    this.initialDescription,
    this.initialPointId,
    this.initialPriority,
    this.lockPoint = false,
    this.onResult,
    super.key,
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
  final ValueChanged<bool>? onResult;

  @override
  State<SupportTicketSheet> createState() => _SupportTicketSheetState();
}

class _SupportTicketSheetState extends State<SupportTicketSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _pointId;
  int? _categoryId;
  String _priority = 'MEDIA';
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _categories = const [];

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
    _categories = widget.categories;
    if (_categories.isNotEmpty) {
      _categoryId = _asInt(_categories.first['id']);
    } else {
      _loadCategories();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = (await widget.api.ticketCategories(widget.token))
          .where(
            (category) => const {
              'SOFTWARE',
              'HARDWARE',
              'COMPLIANCE',
            }.contains('${category['category_type']}'.toUpperCase()),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (_categoryId == null && categories.isNotEmpty) {
          _categoryId = _asInt(categories.first['id']);
        }
      });
    } on SmartHydroApiException {
      // El formulario sigue sin categorías.
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
      if (!mounted) return;
      if (widget.onResult != null) {
        widget.onResult!(true);
      } else {
        Navigator.of(context).pop(true);
      }
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
      16,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 22,
    ),
    child: Form(
      key: _formKey,
      child: ListView(
        shrinkWrap: true,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Nueva solicitud', style: HydroText.title),
          const SizedBox(height: 4),
          const HydroHint(
            'Queda ligada al punto. Cuéntanos qué ves en el logger o en la red.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _titleController,
            enabled: !_submitting,
            style: const TextStyle(color: HydroTone.fog),
            decoration: _supportField('Asunto'),
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
            style: const TextStyle(color: HydroTone.fog),
            decoration: _supportField('Describe lo que ocurre'),
            validator: (value) => (value?.trim().isNotEmpty ?? false)
                ? null
                : 'Describe brevemente el problema.',
          ),
          const SizedBox(height: 16),
          const Text('Punto', style: HydroText.sectionTrailing),
          const SizedBox(height: 8),
          IgnorePointer(
            ignoring: _submitting || widget.lockPoint,
            child: Opacity(
              opacity: widget.lockPoint ? 0.72 : 1,
              child: CapturePointFilter(
                points: widget.points,
                selectedId: _pointId,
                onChanged: (id) => setState(() => _pointId = id),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Prioridad', style: HydroText.sectionTrailing),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in const [
                ('BAJA', 'Baja'),
                ('MEDIA', 'Media'),
                ('ALTA', 'Alta'),
              ])
                _ChoicePill(
                  label: item.$2,
                  selected: _priority == item.$1,
                  tone: supportPriorityTone(item.$1),
                  onTap: _submitting
                      ? null
                      : () => setState(() => _priority = item.$1),
                ),
            ],
          ),
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Categoría', style: HydroText.sectionTrailing),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in _categories)
                  _ChoicePill(
                    label: category['name']?.toString() ?? 'Categoría',
                    selected: _categoryId == _asInt(category['id']),
                    tone: IkoluColors.cyanSoft,
                    onTap: _submitting
                        ? null
                        : () => setState(
                            () => _categoryId = _asInt(category['id']),
                          ),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: IkoluColors.incident)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: IkoluColors.cyan,
              foregroundColor: const Color(0xFF041014),
              minimumSize: const Size.fromHeight(46),
              shape: const StadiumBorder(),
            ),
            child: _submitting
                ? HydroSpinner(size: 18)
                : const Text('Enviar solicitud'),
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
    final pointLabel = supportTicketPointLabel(ticket);
    return HydroPage(
      title: 'Solicitud #${widget.ticket['id']}',
      subtitle: Text(
        pointLabel,
        style: HydroText.subtitle,
      ),
      body: Column(
        children: [
          if (_loading && _comments.isNotEmpty) HydroLinearBar(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: IkoluColors.incident),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              children: [
                Text(
                  ticket['title']?.toString() ?? 'Solicitud',
                  style: HydroText.title,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ToneChip(
                      label: supportStatusLabel(ticket['status']),
                      tone: supportStatusTone(ticket['status']),
                    ),
                    _ToneChip(
                      label: supportPriorityLabel(ticket['priority']),
                      tone: supportPriorityTone(ticket['priority']),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                HydroGlassLight(
                  radius: 16,
                  child: Text(
                    ticket['description']?.toString() ?? '',
                    style: const TextStyle(
                      color: HydroTone.fog,
                      height: 1.4,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const HydroSectionTitle(title: 'Conversación'),
                const SizedBox(height: 10),
                if (_comments.isEmpty && _loading)
                  const HydroShimmer(
                    child: Column(
                      children: [HydroBoneRow(seed: 0), HydroBoneRow(seed: 1)],
                    ),
                  )
                else if (_comments.isEmpty)
                  const HydroHint('Todavía no hay respuestas.'),
                for (final comment in _comments)
                  _SupportComment(comment: comment),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: HydroTone.fog),
                      decoration: _supportField('Escribe un mensaje…').copyWith(
                        labelText: null,
                        hintText: 'Escribe un mensaje…',
                        hintStyle: HydroText.hint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SupportTextButton(
                    label: _sending ? '…' : 'Enviar',
                    onPressed: _sending ? null : _sendComment,
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
  Widget build(BuildContext context) {
    final priority = ticket['priority'];
    final status = ticket['status'];
    final tone = supportPriorityTone(priority);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: HydroGlassLight(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 36,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket['title']?.toString() ?? 'Solicitud',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HydroTone.fog,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      supportTicketPointLabel(ticket),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tone,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _ToneChip(
                          label: supportStatusLabel(status),
                          tone: supportStatusTone(status),
                        ),
                        _ToneChip(
                          label: supportPriorityLabel(priority),
                          tone: tone,
                        ),
                        _ToneChip(
                          label: 'N° ${ticket['id']}',
                          tone: HydroTone.faint,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportPulse extends StatelessWidget {
  const _SupportPulse({
    required this.open,
    required this.high,
    required this.total,
  });

  final int open;
  final int high;
  final int total;

  @override
  Widget build(BuildContext context) {
    return HydroGlassLight(
      key: const ValueKey('support-pulse'),
      radius: 16,
      strength: 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _PulseStat(label: 'Abiertas', value: '$open', tone: IkoluColors.connected),
          _pulseDivider(),
          _PulseStat(label: 'Alta', value: '$high', tone: IkoluColors.incident),
          _pulseDivider(),
          _PulseStat(label: 'Total', value: '$total', tone: IkoluColors.cyan),
        ],
      ),
    );
  }

  Widget _pulseDivider() => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: Colors.white.withValues(alpha: 0.08),
  );
}

class _PulseStat extends StatelessWidget {
  const _PulseStat({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: tone,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: HydroTone.faint,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportComment extends StatelessWidget {
  const _SupportComment({required this.comment});

  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: HydroGlassLight(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            comment['author_name']?.toString() ?? 'Equipo SmartHydro',
            style: const TextStyle(
              color: HydroTone.fog,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            comment['content']?.toString() ??
                comment['message']?.toString() ??
                '',
            style: const TextStyle(
              color: Color(0xFFD5E6E4),
              height: 1.4,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _supportDate(comment['created']),
            style: const TextStyle(color: Color(0xFF81999A), fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class _SupportEmpty extends StatelessWidget {
  const _SupportEmpty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return HydroGlassLight(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          const HydroGlyph(
            kind: HydroGlyphKind.soporte,
            color: IkoluColors.warning,
            size: 56,
            keyPrefix: 'support-empty',
          ),
          const SizedBox(height: 14),
          const Text(
            'Sin solicitudes',
            style: HydroText.section,
          ),
          const SizedBox(height: 6),
          const HydroHint(
            'Cuando un logger o la red pida una mano, crea una solicitud. Queda ligada al punto.',
          ),
          const SizedBox(height: 16),
          _SupportTextButton(label: 'Nueva solicitud', onPressed: onCreate),
        ],
      ),
    );
  }
}

class _SupportError extends StatelessWidget {
  const _SupportError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => HydroGlassLight(
    child: Row(
      children: [
        Expanded(
          child: Text(message, style: const TextStyle(color: HydroTone.fog)),
        ),
        _SupportTextButton(label: 'Reintentar', onPressed: onRetry),
      ],
    ),
  );
}

class _ToneChip extends StatelessWidget {
  const _ToneChip({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.tone,
    this.onTap,
  });

  final String label;
  final bool selected;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: HydroMotion.of(context, HydroMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: selected ? 0.22 : 0.08),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: tone.withValues(alpha: selected ? 0.7 : 0.22),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? tone : HydroTone.fog,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportTextButton extends StatelessWidget {
  const _SupportTextButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: HydroTone.fog,
        backgroundColor: IkoluColors.cyan.withValues(alpha: 0.14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

InputDecoration _supportField(String label) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
  );
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.04),
    labelStyle: const TextStyle(color: HydroTone.faint, fontSize: 13),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: IkoluColors.cyanSoft),
    ),
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
