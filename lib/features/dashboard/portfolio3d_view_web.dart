import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const bool portfolio3dSupported = true;

const _viewType = 'portfolio3d';
web.HTMLIFrameElement? _frame;
Map<String, Object?>? _pending;
void Function(int?)? _onSelect;
void Function()? _onPage;
var _listening = false;
var _registered = false;

void _ensureListener() {
  if (_listening) return;
  _listening = true;
  web.window.addEventListener(
    'message',
    ((web.Event event) {
      final data = (event as web.MessageEvent).data.dartify();
      if (data is! Map) return;
      if (data['source'] != 'portfolio3d') return;
      if (data['type'] == 'page' && data['direction'] == 'down') {
        _onPage?.call();
        return;
      }
      if (data['type'] != 'select') return;
      final raw = data['index'];
      final index = raw is num ? raw.toInt() : null;
      _onSelect?.call(index);
    }).toJS,
  );
}

void _flush() {
  final window = _frame?.contentWindow;
  final pending = _pending;
  if (window == null || pending == null) return;
  window.postMessage(pending.jsify(), '*'.toJS);
}

void _post(Map<String, Object?> message) {
  _pending = message;
  _flush();
}

void _postFocus(int? index) {
  final window = _frame?.contentWindow;
  if (window == null) return;
  window.postMessage(
    <String, Object?>{
      'source': 'smarthydro',
      'type': 'focus',
      'index': index,
    }.jsify(),
    '*'.toJS,
  );
}

var _dim = 1.0;

void portfolio3dDim(double opacity) {
  _dim = opacity.clamp(0.0, 1.0).toDouble();
  final frame = _frame;
  if (frame == null) return;
  frame.style.opacity = '$_dim';
}

class PortfolioCityWeb extends StatefulWidget {
  const PortfolioCityWeb({
    required this.points,
    required this.onSelect,
    this.onPageDown,
    this.selected,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<int?> onSelect;
  final VoidCallback? onPageDown;
  final int? selected;

  @override
  State<PortfolioCityWeb> createState() => _PortfolioCityWebState();
}

class _PortfolioCityWebState extends State<PortfolioCityWeb> {
  String? _signature;

  @override
  void initState() {
    super.initState();
    _ensureListener();
    _onSelect = widget.onSelect;
    _onPage = widget.onPageDown;
    _ensureView();
    _sendIfNeeded();
    _postFocus(widget.selected);
  }

  @override
  void didUpdateWidget(covariant PortfolioCityWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _onSelect = widget.onSelect;
    _onPage = widget.onPageDown;
    _sendIfNeeded();
    if (widget.selected != oldWidget.selected) _postFocus(widget.selected);
  }

  @override
  void dispose() {
    if (identical(_onSelect, widget.onSelect)) _onSelect = null;
    if (identical(_onPage, widget.onPageDown)) _onPage = null;
    super.dispose();
  }

  void _sendIfNeeded() {
    final signature = [
      for (final point in widget.points) _pointPayload(point).toString(),
    ].join(';');
    if (signature == _signature) return;
    _signature = signature;
    _send();
  }

  void _send() {
    _post({
      'source': 'smarthydro',
      'type': 'portfolio',
      'points': [for (final point in widget.points) _pointPayload(point)],
    });
  }

  Map<String, Object?> _pointPayload(Map<String, dynamic> point) {
    final telemetry = _telemetry(point);
    final status = switch (_link(telemetry)) {
      'gap' => 'gap',
      'incident' => 'incident',
      _ => 'connected',
    };
    return {
      'title': _title(point),
      'surface': _surface(point),
      'status': status,
      'flow': _num(telemetry['flow']),
      'level': _num(telemetry['water_table'] ?? telemetry['nivel']),
      'total': _num(
        telemetry['total'] ??
            telemetry['total_raw'] ??
            telemetry['consumption'],
      ),
    };
  }

  void _ensureView() {
    if (_registered) return;
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final host = web.document.createElement('div') as web.HTMLDivElement
        ..style.backgroundColor = '#0B171B'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.margin = '0'
        ..style.overflow = 'hidden';
      final iframe =
          web.document.createElement('iframe') as web.HTMLIFrameElement
            ..src = 'portfolio3d.html'
            ..style.border = '0'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.display = 'block'
            ..style.background = '#0B171B'
            ..style.opacity = '$_dim';
      iframe.addEventListener('load', ((web.Event _) => _flush()).toJS);
      _frame = iframe;
      host.appendChild(iframe);
      return host;
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureView();
    return const ColoredBox(
      color: Color(0xFF0B171B),
      child: HtmlElementView(viewType: _viewType),
    );
  }
}

Map<String, dynamic> _telemetry(Map<String, dynamic> point) {
  final value = point['latest_telemetry'];
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const {};
}

String _title(Map<String, dynamic> point) {
  final text = point['title']?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return 'Punto';
  return text;
}

bool _surface(Map<String, dynamic> point) {
  final dga = point['dga'];
  if (dga is Map) {
    final type = '${dga['type_dga']}'.toUpperCase();
    if (type == 'SUPERFICIAL') return true;
  }
  return '${point['type_dga']}'.toUpperCase() == 'SUPERFICIAL';
}

String _link(Map<String, dynamic> telemetry) {
  if (telemetry['is_error'] == true) return 'incident';
  final stamp = telemetry['date_time_medition']?.toString();
  if (stamp == null || stamp.isEmpty || stamp == 'null') return 'gap';
  final raw = telemetry['days_not_connection'];
  final days = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (days != null && days > 0) return 'gap';
  return 'connected';
}

double? _num(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}
