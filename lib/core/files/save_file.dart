import 'dart:typed_data';

import 'save_file_io.dart'
    if (dart.library.js_interop) 'save_file_web.dart'
    as impl;

/// Guarda [bytes] como archivo: descarga directa en web, hoja de compartir
/// en móvil.
Future<void> saveBytes(Uint8List bytes, String filename, String mimeType) =>
    impl.saveBytes(bytes, filename, mimeType);

/// Abre un enlace externo (en web, una pestaña nueva).
Future<bool> openExternal(String url) => impl.openExternal(url);

/// Nombre de archivo seguro: sin espacios ni caracteres especiales.
String safeFileName(String text) {
  const accents = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ü': 'u', //
    'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ñ': 'N', 'Ü': 'U',
  };
  final plain = text.split('').map((c) => accents[c] ?? c).join();
  return plain
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
}
