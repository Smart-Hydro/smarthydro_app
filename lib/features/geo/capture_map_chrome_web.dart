import 'package:web/web.dart' as web;

/// El control de MapLibre sale como una barra blanca. La deja oscura y chica,
/// del mismo tono que el mapa, sin tapar los nombres de abajo.
void toneCaptureMapChrome() {
  const css = '''
.maplibregl-ctrl-attrib {
  background-color: rgba(11, 23, 27, 0.82) !important;
  border-radius: 8px !important;
  box-shadow: none !important;
  max-width: 70vw !important;
}
.maplibregl-ctrl-attrib-inner {
  color: #C5D5D4 !important;
  font-size: 10px !important;
}
.maplibregl-ctrl-attrib a,
.maplibregl-ctrl-attrib a:visited {
  color: #8FD0E4 !important;
}
.maplibregl-ctrl-attrib-button {
  background-color: rgba(11, 23, 27, 0.82) !important;
}
''';
  void inject(web.ShadowRoot root) {
    if (root.getElementById('capture-attrib-tone') != null) return;
    final style = web.HTMLStyleElement()..id = 'capture-attrib-tone';
    style.textContent = css;
    root.append(style);
  }

  final panes = web.document.querySelectorAll('flt-glass-pane');
  for (var index = 0; index < panes.length; index++) {
    final node = panes.item(index);
    if (node case final web.Element element) {
      final shadow = element.shadowRoot;
      if (shadow != null) inject(shadow);
    }
  }
}
