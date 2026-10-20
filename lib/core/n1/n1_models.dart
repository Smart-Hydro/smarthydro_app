// Modelos del contrato N1 App API (docs/INTEGRATION_FLUTTER.md / AppApi.gs).

class N1ApiException implements Exception {
  const N1ApiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class N1Health {
  const N1Health({
    required this.ok,
    this.servicio,
    this.version,
    this.ops = const [],
    this.docs,
  });

  final bool ok;
  final String? servicio;
  final String? version;
  final List<String> ops;
  final String? docs;

  factory N1Health.fromJson(Map<String, dynamic> json) {
    final ops = json['ops'];
    return N1Health(
      ok: json['ok'] == true,
      servicio: json['servicio']?.toString(),
      version: json['version']?.toString(),
      ops: ops is List
          ? ops.map((e) => '$e').toList(growable: false)
          : const [],
      docs: json['docs']?.toString(),
    );
  }
}

class N1Response {
  const N1Response({
    required this.ok,
    this.text = '',
    this.async = false,
    this.pending = false,
    this.version,
    this.via,
    this.intent,
    this.entity,
    this.scope,
    this.note,
    this.code,
    this.error,
    this.ticketId,
    this.ticket,
    this.dryRun = false,
    this.files = const [],
    this.sheetUrl,
    this.report,
    this.raw = const {},
  });

  final bool ok;
  final String text;
  final bool async;
  final bool pending;
  final String? version;
  final String? via;
  final String? intent;
  final String? entity;
  final String? scope;
  final String? note;
  final String? code;
  final String? error;
  final int? ticketId;
  final Map<String, dynamic>? ticket;
  final bool dryRun;
  final List<N1FileItem> files;
  final String? sheetUrl;
  final Map<String, dynamic>? report;
  final Map<String, dynamic> raw;

  /// Job aún en curso (⏳): la app debe reconsultar.
  /// Si ya vino un texto útil, no seguimos esperando aunque N1 marque async.
  bool get isPending {
    final t = text.trim();
    final hourglass = t.startsWith('⏳');
    if (!pending && !async && !hourglass) return false;
    if (t.length >= 40 && !hourglass) return false;
    return pending || async || hourglass;
  }

  factory N1Response.fromJson(Map<String, dynamic> json) {
    final filesRaw = json['files'];
    final ticketRaw = json['ticket'];
    final reportRaw = json['report'];
    final ticketId =
        _asInt(json['ticket_id']) ?? _asInt(_asMap(ticketRaw)['id']);
    return N1Response(
      ok: json['ok'] == true,
      text: json['text']?.toString() ?? '',
      async: json['async'] == true,
      pending: json['pending'] == true,
      version: json['version']?.toString(),
      via: json['via']?.toString(),
      intent: json['intent']?.toString(),
      entity: json['entity']?.toString(),
      scope: json['scope']?.toString(),
      note: json['note']?.toString(),
      code: json['code']?.toString(),
      error: json['error']?.toString(),
      ticketId: ticketId,
      ticket: ticketRaw is Map ? _asMap(ticketRaw) : null,
      dryRun: json['dry_run'] == true,
      files: filesRaw is List
          ? filesRaw.map((e) => N1FileItem.fromJson(_asMap(e))).toList()
          : const [],
      sheetUrl: json['sheet_url']?.toString(),
      report: reportRaw is Map ? _asMap(reportRaw) : null,
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class N1FileItem {
  const N1FileItem({
    this.client = '',
    this.type = '',
    this.period = '',
    this.url = '',
    this.fileId = '',
    this.at = '',
    this.status = '',
  });

  final String client;
  final String type;
  final String period;
  final String url;
  final String fileId;
  final String at;
  final String status;

  bool get hasUrl => url.trim().isNotEmpty;

  factory N1FileItem.fromJson(Map<String, dynamic> json) {
    return N1FileItem(
      client: json['client']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      period: json['period']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      fileId: json['file_id']?.toString() ?? '',
      at: json['at']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }
}

/// Extrae URLs http(s) de un texto de respuesta N1 (reportes / links).
List<String> extractHttpUrls(String text) {
  final regex = RegExp(r'https?://[^\s<>\[\]()"\x27]+', caseSensitive: false);
  return regex
      .allMatches(text)
      .map((m) => m.group(0)!.replaceAll(RegExp(r'[.,;:]+$'), ''))
      .where((u) => u.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry('$k', v));
  return <String, dynamic>{};
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}
