import 'package:flutter/material.dart';

/// Stub para plataformas no web: el `HtmlElementView` no existe, así que se
/// devuelve un placeholder. En no-web [Capture3DView] ya cae al fallback 2D,
/// por lo que esto rara vez se usa.
Widget buildPlatformView(String viewType, String url) =>
    const SizedBox.shrink();

void postCaptureUpdate(String viewType, Map<String, Object> message) {}
