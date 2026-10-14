import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/core/session/session_provider.dart';
import 'package:smarthydro_app/core/session/session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restaura el token guardado al volver a abrir', () async {
    SharedPreferences.setMockInitialValues({
      SessionStore.storageKey: jsonEncode({
        'token': 'tok-persistido',
        'user': {'email': 'ana@ikolu.cl', 'first_name': 'Ana'},
      }),
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(sessionProvider, (_, _) {});

    await pumpEventQueue();

    final auth = container.read(sessionProvider);
    expect(auth.ready, isTrue);
    expect(auth.session?.token, 'tok-persistido');
    expect(auth.session?.displayName, 'Ana');
  });

  test('sin sesión guardada queda en el login', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(sessionProvider, (_, _) {});

    await pumpEventQueue();

    final auth = container.read(sessionProvider);
    expect(auth.ready, isTrue);
    expect(auth.session, isNull);
  });

  test('cerrar sesión borra el token guardado', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(sessionProvider, (_, _) {});
    await pumpEventQueue();

    await container
        .read(sessionProvider.notifier)
        .signIn(
          const SmartHydroSession(
            token: 'tok',
            user: {'email': 'ana@ikolu.cl', 'first_name': 'Ana'},
          ),
        );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SessionStore.storageKey), isNotNull);

    await container.read(sessionProvider.notifier).signOut();

    expect(container.read(sessionProvider).session, isNull);
    expect(prefs.getString(SessionStore.storageKey), isNull);
  });
}
