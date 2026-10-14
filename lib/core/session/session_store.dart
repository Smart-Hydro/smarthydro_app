import 'dart:convert';

import '../api/smarthydro_api.dart';
import 'session_box_io.dart'
    if (dart.library.js_interop) 'session_box_web.dart'
    as box;

/// Sesión guardada en el dispositivo. En web usa localStorage, que ya está
/// en el navegador y no depende de un plugin nuevo.
class SessionStore {
  const SessionStore();

  static const storageKey = 'smarthydro.session';

  /// Clave que escribe shared_preferences en web (`flutter.` + clave).
  static const prefsWebKey = 'flutter.smarthydro.session';

  /// Lectura síncrona. En web no hay que esperar un plugin.
  SmartHydroSession? readLocal() {
    if (!box.isWebStore) return null;
    try {
      final raw = box.readRaw(storageKey, prefsWebKey);
      final session = _decode(raw);
      if (session == null && raw != null) {
        box.clearRaw(storageKey, prefsWebKey);
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<SmartHydroSession?> load() async {
    if (box.isWebStore) return readLocal();
    try {
      final raw = await box.loadRaw(storageKey);
      final session = _decode(raw);
      if (raw != null && session == null) {
        await box.clearRaw(storageKey, prefsWebKey);
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SmartHydroSession session) async {
    final raw = jsonEncode({'token': session.token, 'user': session.user});
    await box.writeRaw(storageKey, prefsWebKey, raw);
  }

  Future<void> clear() => box.clearRaw(storageKey, prefsWebKey);

  SmartHydroSession? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final token = decoded['token'];
      final user = decoded['user'];
      if (token is! String || token.isEmpty || user is! Map) return null;
      return SmartHydroSession(
        token: token,
        user: user.map((key, value) => MapEntry('$key', value)),
      );
    } on FormatException {
      return null;
    }
  }
}
