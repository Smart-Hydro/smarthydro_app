import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

final Set<String> _registered = {};

/// Registra (una vez por URL) un `HtmlElementView` que incrusta el escenario
/// Three.js en un iframe apuntando a `capture3d.html`.
Widget buildPlatformView(String url) {
  final viewType = 'capture3d-${url.hashCode}';
  if (!_registered.contains(viewType)) {
    _registered.add(viewType);
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        ..allowFullscreen = true;
      return iframe;
    });
  }
  return HtmlElementView(viewType: viewType);
}
