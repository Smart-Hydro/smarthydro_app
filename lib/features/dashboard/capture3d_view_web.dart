import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

final Set<String> _registered = {};
final Map<String, web.HTMLIFrameElement> _frames = {};

/// Registra (una vez por tipo de punto) un `HtmlElementView` que incrusta el
/// escenario Three.js en un iframe. El [viewType] es estable para que el
/// iframe sobreviva a los rebuils con datos nuevos.
Widget buildPlatformView(String viewType, String url) {
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe =
          web.document.createElement('iframe') as web.HTMLIFrameElement
            ..src = url
            ..style.border = '0'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.display = 'block'
            ..allowFullscreen = true;
      _frames[viewType] = iframe;
      return iframe;
    });
  }
  return HtmlElementView(viewType: viewType);
}

/// Envía valores vivos (nivel, caudal, estado) a la escena sin recargarla.
/// Si el iframe aún no termina de cargar, el mensaje se pierde sin problema:
/// los valores iniciales ya viajan en la URL.
void postCaptureUpdate(String viewType, Map<String, Object> message) {
  final window = _frames[viewType]?.contentWindow;
  if (window == null) return;
  final payload = <String, Object>{'source': 'smarthydro', ...message};
  window.postMessage(payload.jsify(), '*'.toJS);
}
