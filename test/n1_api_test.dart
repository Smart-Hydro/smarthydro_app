import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/n1/n1_api.dart';
import 'package:smarthydro_app/core/n1/n1_config.dart';
import 'package:smarthydro_app/core/n1/n1_identity.dart';
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

    test('default prod apunta al /exec verificado', () {
      expect(N1Config.defaultProdWebAppUrl, contains('/macros/s/'));
      expect(N1Config.defaultProdWebAppUrl, endsWith('/exec'));
      expect(N1Config.fromEnvironment().isConfigured, isTrue);
      expect(
        N1Config.fromEnvironment().webAppUrl,
        N1Config.defaultProdWebAppUrl,
      );
    });
  });

  group('N1Identity', () {
    test('n1DecorateAskText agrega cliente y nombre si faltan', () {
      expect(
        n1DecorateAskText(
          'cómo están mis puntos',
          name: 'Constanza Hidd',
          clients: const ['Iansa'],
        ),
        'cómo están mis puntos (cliente Iansa; soy Constanza Hidd)',
      );
      expect(
        n1DecorateAskText(
          'estado Iansa P4',
          name: 'Ana',
          clients: const ['Iansa'],
        ),
        'estado Iansa P4 (soy Ana)',
      );
      expect(n1DecorateAskText('hola'), 'hola');
    });

    test('n1ClientNamesOf deduplica client_name', () {
      expect(
        n1ClientNamesOf([
          {'client_name': 'Iansa'},
          {'client_name': 'iansa'},
          {'client': 'Dole'},
        ]),
        ['Iansa', 'Dole'],
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

    test(
      'ask manda nombre y cliente para que N1 no pregunte quién es',
      () async {
        late Map<String, dynamic> body;
        dio.httpClientAdapter = _Adapter((options) async {
          body = options.data as Map<String, dynamic>;
          return _json({'ok': true, 'text': 'ok'});
        });

        await api.ask(
          token: 'tok-123',
          requester: 'constanza.hidd@iansa.cl',
          text: 'cómo están mis puntos',
          name: 'Constanza Hidd',
          clients: const ['Iansa'],
        );

        expect(body['name'], 'Constanza Hidd');
        expect(body['first_name'], 'Constanza');
        expect(body['client'], 'Iansa');
        expect(
          body['text'],
          'cómo están mis puntos (cliente Iansa; soy Constanza Hidd)',
        );
      },
    );

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

    test('en web el token va en el cuerpo, sin Authorization', () async {
      late RequestOptions seen;
      final dio =
          Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                headers: const {'Accept': 'application/json'},
              ),
            )
            ..httpClientAdapter = _Adapter((options) async {
              seen = options;
              return _json({'ok': true, 'text': 'ok', 'via': 'token'});
            });
      final api = N1Api(
        config: const N1Config(
          webAppUrl: 'https://script.google.com/macros/s/test/exec',
        ),
        dio: dio,
        embedTokenInBody: true,
      );
      await api.ask(
        token: 'tok-web',
        requester: 'cliente@empresa.cl',
        text: 'hola',
      );
      expect(seen.headers['Authorization'], isNull);
      expect(seen.contentType, contains('text/plain'));
      expect(seen.followRedirects, isTrue);
      // Dio web registra xhr.upload si hay connectTimeout: eso no es
      // "simple request" y Apps Script no responde CORS al OPTIONS.
      expect(seen.connectTimeout, Duration.zero);
      expect(
        seen.sendTimeout == null || seen.sendTimeout == Duration.zero,
        isTrue,
      );
      expect(seen.extra['withCredentials'], isFalse);
      final raw = seen.data;
      expect(raw, isA<String>());
      final body = jsonDecode(raw as String) as Map<String, dynamic>;
      expect(body['token'], 'tok-web');
      expect(body['op'], 'ask');
      expect(body['requester'], 'cliente@empresa.cl');
    });

    test('POST 302 → GET Location (Apps Script echo)', () async {
      final calls = <RequestOptions>[];
      dio.httpClientAdapter = _Adapter((options) async {
        calls.add(options);
        if (calls.length == 1) {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': [
                'https://script.googleusercontent.com/macros/echo?k=1',
              ],
            },
          );
        }
        return _json({
          'ok': false,
          'error': 'Autorización requerida (Token o sobre HMAC).',
          'code': 'unauthorized',
        });
      });

      await expectLater(
        () => api.ping(token: 'bad', requester: 'a@b.cl'),
        throwsA(
          isA<N1ApiException>().having((e) => e.code, 'code', 'unauthorized'),
        ),
      );
      expect(calls, hasLength(2));
      expect(calls[0].method, 'POST');
      expect(calls[0].followRedirects, isFalse);
      expect(calls[1].method, 'GET');
      expect(
        calls[1].uri.toString(),
        contains('googleusercontent.com/macros/echo'),
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
