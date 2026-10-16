import 'capture_map_chrome_stub.dart'
    if (dart.library.js_interop) 'capture_map_chrome_web.dart'
    as impl;

/// Ajusta el crédito del mapa web para que no tape la franja de loggers.
void toneCaptureMapChrome() => impl.toneCaptureMapChrome();
