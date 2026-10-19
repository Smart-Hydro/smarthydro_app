import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Con qué vista abre el inicio: el mapa (como el observatorio) o la red,
/// que también muestra los puntos sin ubicación. Queda guardada en el equipo.
enum HomeView { map, network }

class HomeViewNotifier extends Notifier<HomeView> {
  static const storageKey = 'smarthydro.home_view';

  @override
  HomeView build() {
    unawaited(_restore());
    return HomeView.map;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKey);
      if (!ref.mounted) return;
      if (saved == HomeView.network.name) state = HomeView.network;
    } catch (_) {
      // Sin almacenamiento, el inicio sigue en el mapa.
    }
  }

  Future<void> set(HomeView view) async {
    state = view;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, view.name);
    } catch (_) {}
  }
}

final homeViewProvider = NotifierProvider<HomeViewNotifier, HomeView>(
  HomeViewNotifier.new,
);
