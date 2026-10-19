import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthydro_app/core/prefs/home_view.dart';

void main() {
  test('sin preferencia el inicio abre en el mapa', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(homeViewProvider), HomeView.map);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(homeViewProvider), HomeView.map);
  });

  test('la vista elegida queda guardada para la próxima vez', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    await first.read(homeViewProvider.notifier).set(HomeView.network);
    first.dispose();

    final next = ProviderContainer();
    addTearDown(next.dispose);
    next.read(homeViewProvider);
    await Future<void>.delayed(Duration.zero);
    expect(next.read(homeViewProvider), HomeView.network);
  });
}
