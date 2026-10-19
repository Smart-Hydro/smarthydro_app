import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/core/session/session_provider.dart';
import 'package:smarthydro_app/core/session/session_store.dart';

void main() {
  SmartHydroApi api401(List<String> expired) {
    final dio = Dio()..httpClientAdapter = _Unauthorized();
    return SmartHydroApi(dio: dio, onUnauthorized: expired.add);
  }

  test('un 401 con token avisa la sesión vencida con un texto claro', () async {
    final expired = <String>[];
    final api = api401(expired);

    await expectLater(
      api.pointsSummary('abc'),
      throwsA(
        isA<SmartHydroApiException>().having(
          (e) => e.message,
          'message',
          'Tu sesión expiró. Vuelve a ingresar.',
        ),
      ),
    );
    expect(expired, ['abc']);
  });

  test('un 401 del login no se trata como sesión vencida', () async {
    final expired = <String>[];
    final api = api401(expired);

    await expectLater(
      api.login(email: 'a@b.cl', password: 'x'),
      throwsA(isA<SmartHydroApiException>()),
    );
    expect(expired, isEmpty);
  });

  test('solo el token vigente cierra la sesión', () async {
    final container = ProviderContainer(
      overrides: [sessionStoreProvider.overrideWithValue(_MemoryStore())],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(sessionProvider.notifier);
    await notifier.signIn(
      const SmartHydroSession(token: 'nuevo', user: {'id': 1}),
    );

    await notifier.expire('anterior');
    expect(container.read(sessionProvider).session?.token, 'nuevo');

    await notifier.expire('nuevo');
    final state = container.read(sessionProvider);
    expect(state.session, isNull);
    expect(state.expired, isTrue);
  });
}

class _MemoryStore extends SessionStore {
  _MemoryStore();

  SmartHydroSession? _session;

  @override
  Future<SmartHydroSession?> load() async => _session;

  @override
  Future<void> save(SmartHydroSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

class _Unauthorized implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'detail': 'Invalid token.'}),
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
