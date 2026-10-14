import 'package:web/web.dart' as web;

const isWebStore = true;

String? readRaw(String key, String altKey) {
  final storage = web.window.localStorage;
  return storage.getItem(key) ?? storage.getItem(altKey);
}

Future<String?> loadRaw(String key) async => null;

Future<void> writeRaw(String key, String altKey, String value) async {
  final storage = web.window.localStorage;
  storage.setItem(key, value);
  storage.removeItem(altKey);
}

Future<void> clearRaw(String key, String altKey) async {
  final storage = web.window.localStorage;
  storage.removeItem(key);
  storage.removeItem(altKey);
}
