import 'dart:convert';

import 'package:dio/dio.dart';

import 'n1_config.dart';
import 'n1_models.dart';

/// Cliente HTTP del puente N1 App API (opción B: Token SmartHydro del usuario).
///
/// Contrato: `docs/INTEGRATION_FLUTTER.md` en smarthydro-n1 (AppApi.gs).
/// Ops: ping | capabilities | ask | report | list_files | create_ticket
class N1Api {
  N1Api({required N1Config config, Dio? dio})
    : _config = config,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 90),
              headers: const {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
              followRedirects: true,
              maxRedirects: 5,
              validateStatus: (code) => code != null && code < 500,
            ),
          );

  final N1Config _config;
  final Dio _dio;

  bool get isConfigured => _config.isConfigured;

  String get _base {
    final url = _config.webAppUrl.trim();
    if (url.isEmpty) {
      throw const N1ApiException(
        'Falta N1_WEB_APP_URL (dart-define).',
        code: 'no_config',
      );
    }
    return url;
  }

  /// GET salud pública (sin auth).
  Future<N1Health> health() async {
    try {
      final response = await _dio.get<dynamic>(_base);
      return N1Health.fromJson(_map(response.data));
    } on DioException catch (error) {
      throw N1ApiException(_messageFor(error), code: 'upstream');
    }
  }

  Future<N1Response> ping({required String token, required String requester}) {
    return _post(
      token: token,
      requester: requester,
      body: const {'op': 'ping'},
    );
  }

  Future<N1Response> ask({
    required String token,
    required String requester,
    required String text,
    String? sessionId,
    List<int>? pointsAllowed,
  }) {
    final body = <String, dynamic>{
      'op': 'ask',
      'text': text.trim(),
      if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
      'points_allowed': ?pointsAllowed,
    };
    return _post(token: token, requester: requester, body: body);
  }

  Future<N1Response> report({
    required String token,
    required String requester,
    String? query,
    String? type,
    String? client,
    String? point,
    List<int>? pointsAllowed,
  }) {
    final body = <String, dynamic>{
      'op': 'report',
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
      if (client != null && client.trim().isNotEmpty) 'client': client.trim(),
      if (point != null && point.trim().isNotEmpty) 'point': point.trim(),
      'points_allowed': ?pointsAllowed,
    };
    return _post(token: token, requester: requester, body: body);
  }

  Future<N1Response> listFiles({
    required String token,
    required String requester,
    String? client,
    String? type,
    int limit = 20,
  }) {
    final body = <String, dynamic>{
      'op': 'list_files',
      if (client != null && client.trim().isNotEmpty) 'client': client.trim(),
      if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
      'limit': limit.clamp(1, 50),
    };
    return _post(token: token, requester: requester, body: body);
  }

  /// Crea ticket vía N1 → API. La app solo muestra `ticket_id`.
  /// Acuse, asignación y avisos los maneja core_api_sh (no duplicar en la app).
  Future<N1Response> createTicket({
    required String token,
    required String requester,
    required String title,
    required String description,
    required List<int> points,
    String priority = 'MEDIA',
    int? category,
    List<int>? pointsAllowed,
    bool dryRun = false,
  }) {
    final body = <String, dynamic>{
      'op': 'create_ticket',
      'title': title.trim(),
      'description': description.trim(),
      'points': points,
      'priority': priority,
      'category': ?category,
      'points_allowed': ?pointsAllowed,
      if (dryRun) 'dry_run': true,
    };
    return _post(token: token, requester: requester, body: body);
  }

  Future<N1Response> _post({
    required String token,
    required String requester,
    required Map<String, dynamic> body,
  }) async {
    final email = requester.trim().toLowerCase();
    if (email.isEmpty) {
      throw const N1ApiException('Falta requester/email.', code: 'bad_request');
    }
    final payload = <String, dynamic>{
      ...body,
      'requester': email,
      'email': email,
    };
    try {
      final response = await _dio.post<dynamic>(
        _base,
        data: payload,
        options: Options(headers: {'Authorization': 'Token $token'}),
      );
      final data = _map(response.data);
      final result = N1Response.fromJson(data);
      if (!result.ok) {
        throw N1ApiException(
          result.error?.trim().isNotEmpty == true
              ? result.error!
              : 'N1 rechazó la solicitud.',
          code: result.code,
        );
      }
      return result;
    } on N1ApiException {
      rethrow;
    } on DioException catch (error) {
      throw N1ApiException(_messageFor(error), code: _codeFor(error));
    }
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry('$k', v));
    if (value is String && value.trim().isNotEmpty) {
      try {
        return _map(jsonDecode(value));
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  static String _messageFor(DioException error) {
    final data = _map(error.response?.data);
    final detail = data['error'] ?? data['message'] ?? data['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail;
    final code = error.response?.statusCode;
    if (code == 401 || code == 403) {
      return 'Token inválido o sin permiso para N1.';
    }
    if (code == 404) {
      return 'Web App N1 no encontrada. Revisa N1_WEB_APP_URL.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'No fue posible conectar con N1. Revisa tu conexión y la URL.';
    }
    return 'No se pudo completar la solicitud a N1.';
  }

  static String? _codeFor(DioException error) {
    final data = _map(error.response?.data);
    final code = data['code']?.toString();
    if (code != null && code.isNotEmpty) return code;
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) return 'unauthorized';
    return 'upstream';
  }
}
