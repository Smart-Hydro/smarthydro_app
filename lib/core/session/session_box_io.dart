import 'package:shared_preferences/shared_preferences.dart';

const isWebStore = false;

String? readRaw(String key, String altKey) => null;

Future<String?> loadRaw(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(key);
}

Future<void> writeRaw(String key, String altKey, String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, value);
}

Future<void> clearRaw(String key, String altKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(key);
}
