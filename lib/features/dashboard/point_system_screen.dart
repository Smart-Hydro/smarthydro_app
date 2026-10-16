import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../shared/ui/hydro_ui.dart';
import 'avisos_inbox.dart';
import 'point_system.dart';

/// Consola de registros del punto: críticas, atención e historial.
class PointSystemScreen extends StatefulWidget {
  const PointSystemScreen({
    required this.api,
    required this.token,
    required this.pointId,
    required this.pointTitle,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final int pointId;
  final String pointTitle;

  @override
  State<PointSystemScreen> createState() => _PointSystemScreenState();
}

class _PointSystemScreenState extends State<PointSystemScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _events = const [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    final blank = _events.isEmpty;
    setState(() {
      if (blank) _loading = true;
      _error = null;
    });
    try {
      final events = await _eventsOfPoint();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (_events.isEmpty) {
        setState(() => _error = error.message);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      _busy = false;
    }
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

  @override
  Widget build(BuildContext context) {
    return HydroPage(
      title: 'Sistema',
      subtitle: Text(
        widget.pointTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HydroText.subtitle,
      ),
      body: HydroSwap(
        state: _loading ? 'loading' : (_error == null ? 'ready' : 'error'),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const HydroSkeleton(
        caption: 'Leyendo los registros de este punto…',
        hero: false,
        kpis: 3,
        chart: false,
        rows: 5,
      );
    }
    if (_error != null) {
      return HydroMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No pudimos cargar los registros',
        message: _error!,
        action: ('Reintentar', _load),
      );
    }
    return AvisosInbox(
      summary: const {'period_days': 7},
      events: _events,
      loading: false,
      onRefresh: _load,
      showHeading: false,
      lockedPointId: widget.pointId,
    );
  }
}
