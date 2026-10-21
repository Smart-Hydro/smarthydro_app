import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resumen lateral de escritorio: abierto o modo solo mapa. Queda en el equipo.
class WebSummaryNotifier extends Notifier<bool> {
  static const storageKey = 'smarthydro.web_summary';

  @override
  bool build() {
    unawaited(_restore());
    return true;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      if (prefs.containsKey(storageKey)) {
        state = prefs.getBool(storageKey) ?? true;
      }
    } catch (_) {
      // Sin almacenamiento, el resumen sigue a la vista.
    }
  }

  Future<void> set(bool open) async {
    state = open;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(storageKey, open);
    } catch (_) {}
  }
}

final webSummaryProvider = NotifierProvider<WebSummaryNotifier, bool>(
  WebSummaryNotifier.new,
);
