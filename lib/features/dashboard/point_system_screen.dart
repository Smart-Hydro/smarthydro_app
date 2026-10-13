import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/brand.dart';
import '../../shared/ui/hydro_ui.dart';
import '../support/customer_support_screen.dart';
import 'point_system.dart';

/// Lo que muestra Avisos, acotado al punto que se está viendo.
class PointSystemScreen extends StatefulWidget {
  const PointSystemScreen({
    required this.api,
    required this.token,
    required this.pointId,
    required this.pointTitle,
    required this.points,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final int pointId;
  final String pointTitle;
  final List<Map<String, dynamic>> points;

  @override
  State<PointSystemScreen> createState() => _PointSystemScreenState();
}

class _PointSystemScreenState extends State<PointSystemScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _notices = const [];
  List<Map<String, dynamic>> _events = const [];

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
      final notices = await _noticesOfPoint();
      final events = await _eventsOfPoint();
      if (!mounted) return;
      setState(() {
        _notices = notices;
        _events = events;
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

  Future<List<Map<String, dynamic>>> _noticesOfPoint() async {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (var page = 1; page <= 3; page++) {
      final data = await widget.api.ticketNotifications(
        widget.token,
        page: page,
      );
      final results = data['results'];
      final batch = results is List
          ? results.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : const <Map<String, dynamic>>[];
      if (batch.isEmpty) break;
      var fresh = false;
      for (final item in batch) {
        if (!seen.add('${item['id']}')) continue;
        fresh = true;
        if (systemItemMatchesPoint(item, widget.pointId)) out.add(item);
      }
      if (!fresh || data['next'] == null && batch.length < 10) break;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _eventsOfPoint() async {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (var page = 1; page <= 4; page++) {
      final batch = await widget.api.systemEvents(
        widget.token,
        page: page,
        pageSize: 50,
      );
      if (batch.isEmpty) break;
      var fresh = false;
      for (final item in batch) {
        if (!seen.add('${item['id']}')) continue;
        fresh = true;
        if (systemItemMatchesPoint(item, widget.pointId)) out.add(item);
      }
      if (!fresh || batch.length < 10) break;
    }
    return out;
  }

  Future<void> _markRead(Map<String, dynamic> notice) async {
    final id = notice['id'];
    final numeric = id is int ? id : int.tryParse('$id');
    if (numeric == null || notice['is_read'] == true) return;
    try {
      await widget.api.markTicketNotificationsRead(widget.token, [numeric]);
      if (!mounted) return;
      setState(() {
        _notices = [
          for (final item in _notices)
            item['id'] == id ? {...item, 'is_read': true} : item,
        ];
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openEvent(Map<String, dynamic> event) async {
    final label = _eventTypeLabel(event['event_type']?.toString());
    final severity = (event['severity'] as String? ?? 'INFO').toUpperCase();
    final title = event['title']?.toString().trim();
    final message = event['message']?.toString() ?? '';
    final when = _stamp(event['created'] ?? event['created_at']);
    final subject = (title == null || title.isEmpty) ? label : title;
    final create = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF102328),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                subject,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$label · ${widget.pointTitle} · $when',
                style: const TextStyle(color: HydroTone.faint, fontSize: 12),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(message, style: const TextStyle(height: 1.4)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Crear solicitud'),
              ),
            ],
          ),
        ),
      ),
    );
    if (create != true || !mounted) return;
    final priority = switch (severity) {
      'CRITICAL' || 'ALERT' => 'ALTA',
      'WARNING' => 'MEDIA',
      _ => 'BAJA',
    };
    await showSupportTicketSheet(
      context,
      api: widget.api,
      token: widget.token,
      points: widget.points,
      initialTitle: subject,
      initialDescription: [
        'Evento #${event['id'] ?? '—'}',
        'Tipo: $label',
        'Severidad: $severity',
        'Fecha: $when',
        'Punto: ${widget.pointTitle}',
        if (message.isNotEmpty) '',
        if (message.isNotEmpty) message,
      ].join('\n'),
      initialPointId: widget.pointId,
      initialPriority: priority,
      lockPoint: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notices.where((n) => n['is_read'] != true).length;
    return HydroPage(
      title: 'Sistema',
      subtitle: Text(
        widget.pointTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HydroText.subtitle,
      ),
      trailing: IconButton(
        tooltip: 'Actualizar',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh_rounded, color: HydroTone.faint),
      ),
      body: HydroSwap(
        state: _loading ? 'loading' : (_error == null ? 'ready' : 'error'),
        child: _body(unread),
      ),
    );
  }

  Widget _body(int unread) {
    if (_loading) {
      return const HydroSkeleton(
        caption: 'Leyendo los avisos de este punto…',
        hero: false,
        kpis: 3,
        chart: false,
        rows: 5,
      );
    }
    if (_error != null) {
      return HydroMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No pudimos cargar el sistema',
        message: _error!,
        action: ('Reintentar', _load),
      );
    }
    final critical = _events
        .where((e) => _severity(e) == 'CRITICAL' || _severity(e) == 'ALERT')
        .length;
    final warnings = _events.where((e) => _severity(e) == 'WARNING').length;
    final info = _events.length - critical - warnings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          '${_events.length} eventos recientes · $unread '
          '${unread == 1 ? 'aviso' : 'avisos'} de soporte sin leer',
          style: HydroText.subtitle,
        ),
        const SizedBox(height: 14),
        HydroGlassLight(
          child: Row(
            children: [
              _Count(label: 'Críticas', value: critical),
              _Count(label: 'Avisos', value: warnings),
              _Count(label: 'Info', value: info < 0 ? 0 : info),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const HydroSectionTitle(title: 'Soporte y tickets'),
        const SizedBox(height: 8),
        if (_notices.isEmpty)
          const HydroMessage(
            icon: Icons.mark_email_read_outlined,
            title: 'Sin avisos de soporte de este punto',
            message:
                'Los comentarios y cambios en las solicitudes de este punto aparecerán aquí.',
          )
        else
          for (final notice in _notices) ...[
            _NoticeRow(notice: notice, onMarkRead: () => _markRead(notice)),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 16),
        const HydroSectionTitle(title: 'Eventos de sistema'),
        const SizedBox(height: 8),
        if (_events.isEmpty)
          const HydroMessage(
            icon: Icons.sensors_outlined,
            title: 'Sin eventos recientes de este punto',
            message:
                'Las desconexiones, errores de medición y saltos de este punto aparecerán aquí.',
          )
        else
          for (final event in _events) ...[
            _EventRow(event: event, onTap: () => _openEvent(event)),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: HydroTone.fog,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: HydroText.subtitle),
      ],
    ),
  );
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.notice, required this.onMarkRead});

  final Map<String, dynamic> notice;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final read = notice['is_read'] == true;
    return HydroGlassLight(
      strength: 0.7,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            read
                ? Icons.mark_email_read_outlined
                : Icons.mark_email_unread_outlined,
            color: read ? HydroTone.faint : HydroTone.fog,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice['ticket_title']?.toString() ??
                      'Actualización de soporte',
                  style: const TextStyle(
                    color: HydroTone.fog,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notice['message']?.toString() ?? '',
                  style: TextStyle(
                    color: HydroTone.fog.withValues(alpha: 0.78),
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_stamp(notice['created']), style: HydroText.hint),
              ],
            ),
          ),
          if (!read)
            IconButton(
              tooltip: 'Marcar como leída',
              onPressed: onMarkRead,
              icon: const Icon(Icons.done_rounded, color: HydroTone.faint),
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});

  final Map<String, dynamic> event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final severity = _severity(event);
    final (icon, color) = switch (severity) {
      'CRITICAL' ||
      'ALERT' => (Icons.error_outline_rounded, IkoluColors.incident),
      'WARNING' => (Icons.warning_amber_rounded, IkoluColors.warning),
      _ => (Icons.info_outline_rounded, HydroTone.faint),
    };
    return HydroGlassLight(
      strength: 0.7,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _eventTypeLabel(event['event_type']?.toString()),
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event['title']?.toString() ?? 'Evento de sistema',
                    style: const TextStyle(
                      color: HydroTone.fog,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((event['message']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event['message'].toString(),
                      style: TextStyle(
                        color: HydroTone.fog.withValues(alpha: 0.78),
                        height: 1.35,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _stamp(event['created'] ?? event['created_at']),
                    style: HydroText.hint,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: HydroTone.faint),
          ],
        ),
      ),
    );
  }
}

String _severity(Map<String, dynamic> event) =>
    (event['severity'] as String? ?? '').toUpperCase();

String _eventTypeLabel(String? type) => switch (type) {
  'DISCONNECTION' => 'Desconexión',
  'RECONNECTION' => 'Reconexión',
  'MEASUREMENT_ERROR' => 'Error de medición',
  'COUNTER_RESET' => 'Reinicio de contador',
  'MASSIVE_JUMP_BLOCKED' => 'Salto bloqueado',
  'TOKEN_REFRESH' => 'Token',
  'API_ERROR' => 'Error de API',
  _ => 'Evento',
};

String _stamp(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (parsed == null) return 'Sin fecha';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(parsed.day)}/${two(parsed.month)} ${two(parsed.hour)}:${two(parsed.minute)}';
}
