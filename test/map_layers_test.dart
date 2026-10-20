import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthydro_app/core/prefs/map_layers.dart';

void main() {
  test('sin preferencia el mapa abre con todas las capas', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(mapLayersProvider(7)), const MapLayers());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(mapLayersProvider(7)), const MapLayers());
  });

  test('las capas quedan guardadas por usuario', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    const chosen = MapLayers(
      coverage: false,
      level: false,
      panelOpen: false,
      title: MapCardTitle.both,
      loggers: false,
      markSize: MapMarkSize.compact,
    );
    await first.read(mapLayersProvider(7).notifier).set(chosen);
    first.dispose();

    final next = ProviderContainer();
    addTearDown(next.dispose);
    next.read(mapLayersProvider(7));
    next.read(mapLayersProvider(8));
    await Future<void>.delayed(Duration.zero);
    expect(next.read(mapLayersProvider(7)), chosen);
    expect(next.read(mapLayersProvider(8)), const MapLayers());
  });

  test('un valor roto o incompleto deja lo de por defecto', () async {
    SharedPreferences.setMockInitialValues({
      MapLayersNotifier.storageKeyFor(7): '{"cards": false, "flow": "x"}',
      MapLayersNotifier.storageKeyFor(8): 'no es json',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(mapLayersProvider(7));
    container.read(mapLayersProvider(8));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(mapLayersProvider(7)), const MapLayers(cards: false));
    expect(container.read(mapLayersProvider(8)), const MapLayers());
  });
}
