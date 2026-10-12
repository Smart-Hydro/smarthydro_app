import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/n1/n1_api.dart';
import 'package:smarthydro_app/core/n1/n1_config.dart';
import 'package:smarthydro_app/core/n1/n1_models.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

void main() {
  group('N1Config', () {
    test('vacío no está configurado', () {
      expect(const N1Config(webAppUrl: '').isConfigured, isFalse);
      expect(const N1Config(webAppUrl: '  ').isConfigured, isFalse);
    });

    test('url no vacía está configurada', () {
      expect(
        const N1Config(
          webAppUrl: 'https://script.google.com/macros/s/abc/exec',
        ).isConfigured,
        isTrue,
      );
    });
  });

  group('N1Response', () {
    test('detecta pending por flags y por ⏳', () {
      expect(
        N1Response.fromJson({
          'ok': true,
          'pending': true,
          'text': 'trabajando',
        }).isPending,
        isTrue,
      );
      expect(
        N1Response.fromJson({
          'ok': true,
          'async': true,
          'text': 'ok',
        }).isPending,
        isTrue,
      );
      expect(
        N1Response.fromJson({
          'ok': true,
          'text': '⏳ cargando datos, reintenta en un momento',
        }).isPending,
        isTrue,
      );
      expect(
        N1Response.fromJson({'ok': true, 'text': 'Todo bien'}).isPending,
        isFalse,
      );
    });

    test('parsea ticket_id y files', () {
      final response = N1Response.fromJson({
        'ok': true,
        'ticket_id': 42,
        'files': [
          {
            'client': 'Iansa',
            'type': 'mensual',
            'url': 'https://drive.google.com/file/d/x',
          },
        ],
      });
      expect(response.ticketId, 42);
      expect(response.files, hasLength(1));
      expect(response.files.first.hasUrl, isTrue);
    });
  });

  group('extractHttpUrls', () {
    test('extrae links de texto de reporte', () {
      const text =
          'Listo: https://drive.google.com/file/d/abc/view y https://example.com/a.xlsx.';
      expect(extractHttpUrls(text), [
        'https://drive.google.com/file/d/abc/view',
        'https://example.com/a.xlsx',
      ]);
    });
  });

  group('N1Api', () {
    late Dio dio;
    late N1Api api;
    late List<RequestOptions> seen;

    setUp(() {
      seen = [];
      dio = Dio();
      api = N1Api(
        config: const N1Config(
          webAppUrl: 'https://script.google.com/macros/s/test/exec',
        ),
        dio: dio,
      );
    });

    test('ask envía op, requester y Token (opción B)', () async {
      dio.httpClientAdapter = _Adapter((options) async {
        seen.add(options);
        return _json({
          'ok': true,
          'text': 'P4 OK',
          'version': '2026-10-12-flutter-app',
        });
      });

      final result = await api.ask(
        token: 'tok-123',
        requester: 'cliente@empresa.cl',
        text: 'cómo está P4',
        sessionId: 's1',
        pointsAllowed: const [4],
      );

      expect(result.text, 'P4 OK');
      expect(seen, hasLength(1));
      final req = seen.single;
      expect(req.method, 'POST');
      expect(req.path, contains('/exec'));
      expect(req.headers['Authorization'], 'Token tok-123');
      final body = req.data as Map<String, dynamic>;
      expect(body['op'], 'ask');
      expect(body['requester'], 'cliente@empresa.cl');
      expect(body['text'], 'cómo está P4');
      expect(body['session_id'], 's1');
      expect(body['points_allowed'], [4]);
    });

    test('report pending marca isPending', () async {
      dio.httpClientAdapter = _Adapter((options) async {
        return _json({
          'ok': true,
          'text': '⏳ Lo estoy preparando: *mensual*',
          'async': true,
          'pending': true,
          'note': 'Encolado; cuando esté listo aparece en list_files',
        });
      });

      final result = await api.report(
        token: 'tok',
        requester: 'a@b.cl',
        query: 'excel mensual iansa por acá',
      );
      expect(result.isPending, isTrue);
    });

    test('list_files mapea urls', () async {
      dio.httpClientAdapter = _Adapter((options) async {
        return _json({
          'ok': true,
          'files': [
            {'client': 'Dole', 'type': 'dga', 'url': 'https://drive.x/1'},
          ],
        });
      });
      final result = await api.listFiles(
        token: 'tok',
        requester: 'a@b.cl',
        client: 'Dole',
      );
      expect(result.files.single.url, 'https://drive.x/1');
    });

    test(
      'create_ticket expone ticket_id y no inventa side-effects de app',
      () async {
        dio.httpClientAdapter = _Adapter((options) async {
          final body = options.data as Map<String, dynamic>;
          expect(body['op'], 'create_ticket');
          expect(body['title'], 'Sin telemetría');
          expect(body.containsKey('email_receipt'), isFalse);
          expect(body.containsKey('notify'), isFalse);
          return _json({
            'ok': true,
            'ticket_id': 99,
            'ticket': {'id': 99},
            'side_effects': {
              'n1_email': false,
              'n1_space_announce': false,
              'n1_assign_notify': false,
            },
          });
        });

        final result = await api.createTicket(
          token: 'tok',
          requester: 'a@b.cl',
          title: 'Sin telemetría',
          description: 'P4 sin datos',
          points: const [4],
          pointsAllowed: const [4],
        );
        expect(result.ticketId, 99);
        expect(result.raw['side_effects']['n1_email'], isFalse);
      },
    );

    test('error ok:false lanza N1ApiException con code', () async {
      dio.httpClientAdapter = _Adapter((options) async {
        return _json({
          'ok': false,
          'error': 'Token inválido o sin permiso.',
          'code': 'unauthorized',
        });
      });

      expect(
        () => api.ping(token: 'bad', requester: 'a@b.cl'),
        throwsA(
          isA<N1ApiException>()
              .having((e) => e.code, 'code', 'unauthorized')
              .having((e) => e.message, 'message', contains('Token')),
        ),
      );
    });

    test('sin N1_WEB_APP_URL falla con no_config', () async {
      final bare = N1Api(config: const N1Config(webAppUrl: ''));
      expect(
        () => bare.ask(token: 't', requester: 'a@b.cl', text: 'hola'),
        throwsA(
          isA<N1ApiException>().having((e) => e.code, 'code', 'no_config'),
        ),
      );
    });
  });
}
