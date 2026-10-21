import 'package:flutter/material.dart';

import 'hydro_ui.dart';

/// Código de obra DGA, si el punto lo trae.
String? capturePointCode(Map<String, dynamic> point) {
  final direct = _plain(point['code_dga']);
  if (direct != null) return direct;
  final dga = point['dga'];
  if (dga is Map) return _plain(dga['code_dga'] ?? dga['code']);
  return null;
}

int? capturePointId(Map<String, dynamic> point) {
  final id = point['id'];
  if (id is int) return id;
  return int.tryParse('$id');
}

/// Filtra por nombre o código DGA. Vacío o solo espacios deja todos.
List<Map<String, dynamic>> filterCapturePoints(
  List<Map<String, dynamic>> points,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return List<Map<String, dynamic>>.of(points);
  return [
    for (final point in points)
      if (_matches(point, needle)) point,
  ];
}

bool _matches(Map<String, dynamic> point, String needle) {
  final title = '${point['title'] ?? ''}'.toLowerCase();
  final code = (capturePointCode(point) ?? '').toLowerCase();
  return title.contains(needle) || code.contains(needle);
}

String? _plain(dynamic raw) {
  if (raw == null) return null;
  final text = '$raw'.trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
}

/// Disparador compacto del encabezado: abre el modal para elegir el punto.
class CapturePointFilter extends StatelessWidget {
  const CapturePointFilter({
    required this.points,
    required this.selectedId,
    required this.onChanged,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final int? selectedId;
  final ValueChanged<int> onChanged;

  Map<String, dynamic>? get _selected {
    for (final point in points) {
      if (capturePointId(point) == selectedId) return point;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final point = _selected;
    final title = '${point?['title'] ?? 'Elegir punto'}';
    final code = point == null ? null : capturePointCode(point);
    return Tooltip(
      message: 'Cambiar punto',
      child: InkWell(
        key: const ValueKey('capture-point-filter'),
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final picked = await showCapturePointPicker(
            context: context,
            points: points,
            selectedId: selectedId,
          );
          if (picked != null && picked != selectedId) onChanged(picked);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HydroTone.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (code != null) ...[
              const Text(
                ' · ',
                style: TextStyle(
                  color: HydroTone.faint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Flexible(
                child: Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HydroTone.faint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const Icon(
              Icons.expand_more_rounded,
              color: HydroTone.accent,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal en móvil y web: buscador chico y lista de puntos con código DGA.
Future<int?> showCapturePointPicker({
  required BuildContext context,
  required List<Map<String, dynamic>> points,
  int? selectedId,
}) {
  return showDialog<int>(
    context: context,
    barrierColor: const Color(0x59000000),
    builder: (context) => Dialog(
      backgroundColor: const Color(0xFF12292F),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: _CapturePointPickerBody(
          points: points,
          selectedId: selectedId,
        ),
      ),
    ),
  );
}

class _CapturePointPickerBody extends StatefulWidget {
  const _CapturePointPickerBody({
    required this.points,
    required this.selectedId,
  });

  final List<Map<String, dynamic>> points;
  final int? selectedId;

  @override
  State<_CapturePointPickerBody> createState() =>
      _CapturePointPickerBodyState();
}

class _CapturePointPickerBodyState extends State<_CapturePointPickerBody> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = filterCapturePoints(widget.points, _query.text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Elegir punto de captación',
                  style: TextStyle(
                    color: HydroTone.fog,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: HydroTone.faint,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('capture-point-search'),
            controller: _query,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: HydroTone.fog, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Nombre o código DGA',
              hintStyle: TextStyle(
                color: HydroTone.faint.withValues(alpha: 0.85),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: HydroTone.faint,
                size: 20,
              ),
              isDense: true,
              filled: true,
              fillColor: const Color(0x22000000),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text(
                      'Ningún punto coincide',
                      style: TextStyle(color: HydroTone.faint),
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final point = visible[index];
                      final id = capturePointId(point);
                      final selected = id != null && id == widget.selectedId;
                      final code = capturePointCode(point);
                      return ListTile(
                        key: ValueKey('capture-point-$id'),
                        dense: true,
                        selected: selected,
                        selectedTileColor: HydroTone.accent.withValues(
                          alpha: 0.12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: Text(
                          '${point['title'] ?? 'Punto'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? HydroTone.accent
                                : HydroTone.fog,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: code == null
                            ? null
                            : Text(
                                code,
                                style: const TextStyle(
                                  color: HydroTone.faint,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        trailing: selected
                            ? const Icon(
                                Icons.check_rounded,
                                color: HydroTone.accent,
                                size: 18,
                              )
                            : null,
                        onTap: id == null
                            ? null
                            : () => Navigator.of(context).pop(id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
