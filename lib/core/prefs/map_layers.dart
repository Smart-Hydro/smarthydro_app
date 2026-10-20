import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Con qué se nombra cada tarjeta: el nombre del punto, su código de obra
/// (CO) o los dos juntos.
enum MapCardTitle { name, code, both }

/// Tamaño de la marca en el mapa. Solo estos dos, a medida real.
enum MapMarkSize { compact, full }

/// Qué muestra el mapa de puntos: las tarjetas sobre cada punto y qué
/// variables llevan. Queda guardado por usuario.
///
/// [coverage] queda en el modelo por si más adelante hay datos reales de
/// red; el mapa HOME hoy no la pinta ni la ofrece en el panel.
class MapLayers {
  const MapLayers({
    this.coverage = false,
    this.cards = true,
    this.flow = true,
    this.level = true,
    this.today = true,
    this.total = true,
    this.panelOpen = true,
    this.title = MapCardTitle.name,
    this.loggers = true,
    this.markSize = MapMarkSize.full,
  });

  /// Un punto sin código de obra va con su nombre aunque se pida CO.
  final MapCardTitle title;

  final bool coverage;
  final bool cards;
  final bool flow;
  final bool level;

  /// Consumo del día en m³.
  final bool today;

  /// Totalizador acumulado en m³.
  final bool total;

  /// El panel de capas abierto o recogido en su botón.
  final bool panelOpen;

  /// Dibujo / icono del logger. Apagado, queda el punto parpadeante.
  final bool loggers;

  final MapMarkSize markSize;

  MapLayers copyWith({
    bool? coverage,
    bool? cards,
    bool? flow,
    bool? level,
    bool? today,
    bool? total,
    bool? panelOpen,
    MapCardTitle? title,
    bool? loggers,
    MapMarkSize? markSize,
  }) {
    return MapLayers(
      coverage: coverage ?? this.coverage,
      cards: cards ?? this.cards,
      flow: flow ?? this.flow,
      level: level ?? this.level,
      today: today ?? this.today,
      total: total ?? this.total,
      panelOpen: panelOpen ?? this.panelOpen,
      title: title ?? this.title,
      loggers: loggers ?? this.loggers,
      markSize: markSize ?? this.markSize,
    );
  }

  Map<String, Object> toJson() => {
    'coverage': coverage,
    'cards': cards,
    'flow': flow,
    'level': level,
    'today': today,
    'total': total,
    'panelOpen': panelOpen,
    'title': title.name,
    'loggers': loggers,
    'markSize': markSize.name,
  };

  /// Lo que falte o no sea booleano queda como viene por defecto.
  factory MapLayers.fromJson(Map<String, dynamic> json) {
    const base = MapLayers();
    bool read(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    return MapLayers(
      coverage: read('coverage', base.coverage),
      cards: read('cards', base.cards),
      flow: read('flow', base.flow),
      level: read('level', base.level),
      today: read('today', base.today),
      total: read('total', base.total),
      panelOpen: read('panelOpen', base.panelOpen),
      title: MapCardTitle.values.firstWhere(
        (value) => value.name == json['title'],
        orElse: () => base.title,
      ),
      loggers: read('loggers', base.loggers),
      markSize: MapMarkSize.values.firstWhere(
        (value) => value.name == json['markSize'],
        orElse: () => base.markSize,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MapLayers &&
      other.coverage == coverage &&
      other.cards == cards &&
      other.flow == flow &&
      other.level == level &&
      other.today == today &&
      other.total == total &&
      other.panelOpen == panelOpen &&
      other.title == title &&
      other.loggers == loggers &&
      other.markSize == markSize;

  @override
  int get hashCode => Object.hash(
    coverage,
    cards,
    flow,
    level,
    today,
    total,
    panelOpen,
    title,
    loggers,
    markSize,
  );
}

class MapLayersNotifier extends Notifier<MapLayers> {
  MapLayersNotifier(this.userId);

  /// Sin usuario conocido, las capas se guardan en una llave común.
  final int? userId;

  /// Si el usuario cambia algo antes de leer lo guardado, gana lo nuevo.
  var _touched = false;

  static String storageKeyFor(int? userId) =>
      'smarthydro.map_layers.${userId ?? 'anon'}';

  @override
  MapLayers build() {
    unawaited(_restore());
    return const MapLayers();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKeyFor(userId));
      if (!ref.mounted || _touched || saved == null) return;
      final json = jsonDecode(saved);
      if (json is Map<String, dynamic>) state = MapLayers.fromJson(json);
    } catch (_) {
      // Sin almacenamiento o con un valor roto, quedan las capas por defecto.
    }
  }

  Future<void> set(MapLayers next) async {
    _touched = true;
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKeyFor(userId), jsonEncode(next.toJson()));
    } catch (_) {}
  }
}

final mapLayersProvider =
    NotifierProvider.family<MapLayersNotifier, MapLayers, int?>(
      MapLayersNotifier.new,
    );
