import 'dart:typed_data';

import 'package:dio/dio.dart';

class SmartHydroSession {
  const SmartHydroSession({required this.token, required this.user});

  final String token;
  final Map<String, dynamic> user;

  String get displayName {
    final firstName = (user['first_name'] as String? ?? '').trim();
    if (firstName.isNotEmpty) return firstName;
    return (user['email'] as String? ?? 'Usuario SmartHydro').trim();
  }

  String get fullName {
    final first = (user['first_name'] as String? ?? '').trim();
    final last = (user['last_name'] as String? ?? '').trim();
    final both = '$first $last'.trim();
    if (both.isNotEmpty) return both;
    return displayName;
  }

  String get email => user['email'] as String? ?? '';
}

class SmartHydroApiException implements Exception {
  const SmartHydroApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SmartHydroApi {
  SmartHydroApi({Dio? dio, this.onUnauthorized})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: const String.fromEnvironment(
                'SMART_HYDRO_API_BASE_URL',
                defaultValue: 'https://api.smarthydro.app',
              ),
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              headers: const {'Accept': 'application/json'},
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          final token = _tokenOf(error.requestOptions);
          if (error.response?.statusCode == 401 && token != null) {
            onUnauthorized?.call(token);
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;

  /// Un 401 con token (no el del login) es una sesión vencida o revocada.
  final void Function(String token)? onUnauthorized;

  /// Salud pública del API (`GET /health`). Sin auth.
  Future<bool> health() async {
    try {
      final response = await _dio.get<dynamic>('/health');
      final data = response.data;
      if (data is Map) {
        final status = data['status']?.toString().toLowerCase();
        return status == 'ok' || status == 'healthy' || status == 'up';
      }
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
    } on DioException {
      return false;
    }
  }

  Future<SmartHydroSession> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ik/login/',
        data: {'email': email.trim(), 'password': password},
      );
      final data = _map(response.data);
      final token = data['access_token'] as String?;
      if (data['success'] != true || token == null || token.isEmpty) {
        throw SmartHydroApiException(
          data['message'] as String? ?? 'No se pudo iniciar sesión.',
        );
      }
      return SmartHydroSession(token: token, user: _map(data['user']));
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Future<Map<String, dynamic>> dashboardStats(String token) async {
    final response = await _authorizedGet('/api/ik/dashboard_stats/', token);
    return _map(response.data);
  }

  Future<List<Map<String, dynamic>>> pointsSummary(String token) async {
    final response = await _authorizedGet('/api/ik/points_summary/', token);
    final data = response.data;
    if (data is List) return data.map(_map).toList(growable: false);
    final map = _map(data);
    final points = map['points'] ?? map['results'];
    if (points is List) return points.map(_map).toList(growable: false);
    return const [];
  }

  Future<Map<String, dynamic>> pointSummary(String token, int pointId) async {
    final response = await _authorizedGet(
      '/api/ik/point/$pointId/summary/',
      token,
    );
    return _map(response.data);
  }

  Future<List<Map<String, dynamic>>> projects(String token) async {
    final response = await _authorizedGet(
      '/api/project_catchments/all/',
      token,
    );
    final data = response.data;
    if (data is List) return data.map(_map).toList(growable: false);
    final nested = _map(data)['results'];
    if (nested is List) return nested.map(_map).toList(growable: false);
    return const [];
  }

  Future<Map<String, dynamic>> catchmentPoint(String token, int pointId) async {
    final response = await _authorizedGet(
      '/api/catchment_point/$pointId/',
      token,
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> createCatchmentPoint(
    String token,
    Map<String, dynamic> body,
  ) async {
    final response = await _authorizedSend(
      'POST',
      '/api/catchment_point/',
      token,
      body,
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> updateCatchmentPoint(
    String token,
    int pointId,
    Map<String, dynamic> body,
  ) async {
    final response = await _authorizedSend(
      'PATCH',
      '/api/catchment_point/$pointId/',
      token,
      body,
    );
    return _map(response.data);
  }

  Future<List<Map<String, dynamic>>> pointDgaConfigs(
    String token,
    int pointId,
  ) async {
    final response = await _authorizedGet(
      '/api/dga_data_config_catchment/',
      token,
      queryParameters: {'point_catchment': pointId},
    );
    final data = response.data;
    if (data is List) return data.map(_map).toList(growable: false);
    final nested = _map(data)['results'];
    if (nested is List) return nested.map(_map).toList(growable: false);
    return const [];
  }

  Future<Map<String, dynamic>> createDgaConfig(
    String token,
    Map<String, dynamic> body,
  ) async {
    final response = await _authorizedSend(
      'POST',
      '/api/dga_data_config_catchment/',
      token,
      body,
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> updateDgaConfig(
    String token,
    int configId,
    Map<String, dynamic> body,
  ) async {
    final response = await _authorizedSend(
      'PATCH',
      '/api/dga_data_config_catchment/$configId/',
      token,
      body,
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> patchPointConfig(
    String token,
    int pointId,
    Map<String, dynamic> body,
  ) async {
    final response = await _authorizedSend(
      'PATCH',
      '/api/ik/point/$pointId/config/',
      token,
      body,
    );
    return _map(response.data);
  }

  /// Ficha estática de la captación: d1 profundidad, d2 bomba, d3 sensor de
  /// nivel, d4 ducto de salida, d5 flujómetro y límites de procesamiento.
  Future<Map<String, dynamic>> pointConfig(String token, int pointId) async {
    final response = await _authorizedGet(
      '/api/ik/point/$pointId/config/',
      token,
    );
    final data = _map(response.data);
    final nested = data['config_data'] ?? data['config'];
    return nested is Map ? _map(nested) : data;
  }

  /// Variables configuradas del punto (CAUDAL, NIVEL, TOTALIZADO…). Define
  /// qué lecturas existen de verdad, independientemente de la telemetría.
  Future<List<Map<String, dynamic>>> pointVariables(
    String token,
    int pointId,
  ) async {
    final response = await _authorizedGet(
      '/api/ik/point/$pointId/variables/',
      token,
    );
    final data = _map(response.data);
    final list = data['variables'];
    if (list is List) return list.map(_map).toList(growable: false);
    return const [];
  }

  /// Esquemas. Sin filtro trae el catálogo; con [pointId] solo los del punto.
  Future<List<Map<String, dynamic>>> schemes(
    String token, {
    int? pointId,
  }) async {
    final response = await _authorizedGet(
      '/api/schemes_catchment/',
      token,
      queryParameters: {'points_catchment': ?pointId},
    );
    return _asList(response.data);
  }

  /// Esquemas ligados al punto. La lista puede venir plana o en `results`.
  Future<List<Map<String, dynamic>>> schemesForPoint(
    String token,
    int pointId,
  ) {
    return schemes(token, pointId: pointId);
  }

  Future<Map<String, dynamic>> createScheme(
    String token,
    Map<String, dynamic> body,
  ) async {
    final response = await _authorizedSend(
      'POST',
      '/api/schemes_catchment/',
      token,
      body,
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> updateScheme(
    String token,
    int schemeId,
    Map<String, dynamic> body,
  ) async {
    final response = await _authorizedSend(
      'PATCH',
      '/api/schemes_catchment/$schemeId/',
      token,
      body,
    );
    return _map(response.data);
  }

  Future<List<Map<String, dynamic>>> schemeVariables(
    String token,
    int schemeId,
  ) async {
    final response = await _authorizedGet(
      '/api/variable/',
      token,
      queryParameters: {'scheme_catchment': schemeId},
    );
    return _asList(response.data);
  }

  Future<Map<String, dynamic>> createVariable(
    String token,
    Map<String, dynamic> body,
  ) async {
    final response = await _authorizedSend(
      'POST',
      '/api/variable/',
      token,
      body,
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> updateVariable(
    String token,
    int variableId,
    Map<String, dynamic> body,
  ) async {
    final response = await _authorizedSend(
      'PATCH',
      '/api/variable/$variableId/',
      token,
      body,
    );
    return _map(response.data);
  }

  Future<void> deleteVariable(String token, int variableId) async {
    await _authorizedSend(
      'DELETE',
      '/api/variable/$variableId/',
      token,
      const {},
    );
  }

  Future<List<Map<String, dynamic>>> pointCalendar(
    String token,
    int pointId, {
    int days = 7,
  }) async {
    final response = await _authorizedGet(
      '/api/ik/point/$pointId/calendar/',
      token,
      queryParameters: {'days': days},
    );
    final data = _map(response.data)['calendar'];
    if (data is List) return data.map(_map).toList(growable: false);
    return const [];
  }

  Future<List<Map<String, dynamic>>> pointRecords(
    String token,
    int pointId, {
    required DateTime start,
    required DateTime end,
    int limit = 500,
  }) async {
    final response = await _authorizedGet(
      '/api/ik/point/$pointId/records/',
      token,
      queryParameters: {
        'start_date': _dateOnly(start),
        'end_date': _dateOnly(end),
        'limit': limit,
      },
    );
    final records = _map(response.data)['records'];
    if (records is List) return records.map(_map).toList(growable: false);
    return const [];
  }

  Future<Map<String, dynamic>> ticketNotifications(
    String token, {
    bool unreadOnly = false,
    int page = 1,
  }) async {
    final response = await _authorizedGet(
      '/api/ik/tickets/notifications/',
      token,
      queryParameters: {'unread_only': unreadOnly, 'page': page},
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> systemEventsSummary(
    String token, {
    int days = 7,
  }) async {
    final response = await _authorizedGet(
      '/api/ik/system-events/summary/',
      token,
      queryParameters: {'days': days},
    );
    return _map(response.data);
  }

  Future<List<Map<String, dynamic>>> systemEvents(
    String token, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _authorizedGet(
      '/api/ik/control_center/system_events/',
      token,
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    final data = response.data;
    if (data is List) return data.map(_map).toList(growable: false);
    final results = _map(data)['results'];
    if (results is List) return results.map(_map).toList(growable: false);
    return const [];
  }

  Future<List<Map<String, dynamic>>> compliancePoints(
    String token, {
    bool activeOnly = false,
    int pageSize = 100,
  }) async {
    final response = await _authorizedGet(
      '/api/ik/compliance/',
      token,
      queryParameters: {
        'page': 1,
        'page_size': pageSize,
        'active_only': activeOnly,
      },
    );
    final data = _map(response.data);
    final points = data['points'] ?? data['results'];
    if (points is List) return points.map(_map).toList(growable: false);
    return const [];
  }

  Future<Map<String, dynamic>> complianceFlowHistory(
    String token,
    int pointId, {
    int days = 90,
  }) async {
    final response = await _authorizedGet(
      '/api/ik/compliance/$pointId/flow_history/',
      token,
      queryParameters: {'days': days, 'page': 1, 'page_size': 100},
    );
    return _map(response.data);
  }

  Future<Map<String, dynamic>> complianceNearLimit(
    String token,
    int pointId, {
    int days = 90,
  }) async {
    final response = await _authorizedGet(
      '/api/ik/compliance/$pointId/near_limit/',
      token,
      queryParameters: {'days': days, 'page': 1, 'page_size': 100},
    );
    return _map(response.data);
  }

  Future<List<Map<String, dynamic>>> supportTickets(
    String token, {
    String? origin = 'CLIENTE',
    String? status,
    int pageSize = 50,
  }) async {
    final response = await _authorizedGet(
      '/api/ik/tickets/',
      token,
      queryParameters: {
        'page': 1,
        'page_size': pageSize,
        'origin': ?origin,
        'status': ?status,
      },
    );
    final data = _map(response.data);
    final results = data['results'];
    if (results is List) return results.map(_map).toList(growable: false);
    return const [];
  }

  Future<List<Map<String, dynamic>>> ticketCategories(String token) async {
    final response = await _authorizedGet('/api/ik/ticket-categories/', token);
    final data = response.data;
    if (data is List) return data.map(_map).toList(growable: false);
    final responseData = _map(data);
    final results = responseData['categories'] ?? responseData['results'];
    if (results is List) return results.map(_map).toList(growable: false);
    return const [];
  }

  Future<Map<String, dynamic>> createSupportTicket(
    String token, {
    required String title,
    required String description,
    required String priority,
    required List<int> pointIds,
    int? categoryId,
  }) async {
    final body = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'priority': priority,
      'points': pointIds,
      'origin': 'CLIENTE',
      'source': 'APP_CLIENTE',
    };
    if (categoryId != null) body['category'] = categoryId;
    try {
      final response = await _dio.post<dynamic>(
        '/api/ik/tickets/',
        data: body,
        options: _authOptions(token),
      );
      return _map(response.data);
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Future<Map<String, dynamic>> supportTicket(String token, int ticketId) async {
    final response = await _authorizedGet('/api/ik/tickets/$ticketId/', token);
    return _map(response.data);
  }

  Future<List<Map<String, dynamic>>> ticketComments(
    String token,
    int ticketId,
  ) async {
    final response = await _authorizedGet(
      '/api/ik/tickets/$ticketId/comments/',
      token,
    );
    final data = response.data;
    if (data is List) return data.map(_map).toList(growable: false);
    final results = _map(data)['results'];
    if (results is List) return results.map(_map).toList(growable: false);
    return const [];
  }

  Future<void> addTicketComment(
    String token,
    int ticketId,
    String content,
  ) async {
    try {
      await _dio.post<void>(
        '/api/ik/tickets/$ticketId/comments/',
        data: {'content': content.trim()},
        options: _authOptions(token),
      );
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Future<void> markTicketResolved(String token, int ticketId) async {
    try {
      await _dio.post<void>(
        '/api/ik/tickets/$ticketId/status/',
        data: {'status': 'RESUELTO'},
        options: _authOptions(token),
      );
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Future<void> markTicketNotificationsRead(String token, List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      await _dio.post<void>(
        '/api/ik/tickets/notifications/mark-read/',
        data: {'ids': ids},
        options: _authOptions(token),
      );
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Future<void> requestPasswordReset(String email) async {
    try {
      await _dio.post<void>(
        '/api/ik/auth/password-reset/',
        data: {'email': email.trim()},
      );
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Future<Map<String, dynamic>> updateProfile(
    String token, {
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/api/ik/me/',
        data: {
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'email': email.trim(),
        },
        options: _authOptions(token),
      );
      final data = _map(response.data);
      final user = _map(data['user']);
      if (data['success'] != true || user.isEmpty) {
        throw SmartHydroApiException(
          data['error'] as String? ?? 'No se pudo actualizar el perfil.',
        );
      }
      return user;
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Future<void> changePassword(
    String token, {
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/ik/me/password/',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
        options: _authOptions(token),
      );
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Future<void> setEmailNotifications(String token, bool enabled) async {
    try {
      await _dio.post<void>(
        '/api/ik/me/notify-email/',
        data: {'notify_email': enabled},
        options: _authOptions(token),
      );
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  /// Ficha DGA del punto y sus últimos intentos de envío (`modules.m2`).
  Future<Map<String, dynamic>> pointDgaDetail(String token, int pointId) async {
    final response = await _authorizedGet(
      '/api/catchment_point/$pointId/',
      token,
    );
    return _map(response.data);
  }

  /// Planilla DGA (MEE) en XLSX: cada medición del rango con su comprobante.
  Future<Uint8List> dgaWorkbook(
    String token,
    int pointId, {
    required DateTime start,
    required DateTime end,
  }) => _workbook(
    '/api/interaction_detail_dga/',
    token,
    pointId,
    start: start,
    end: end,
  );

  /// Mediciones del punto en XLSX (todas las lecturas del rango).
  Future<Uint8List> recordsWorkbook(
    String token,
    int pointId, {
    required DateTime start,
    required DateTime end,
  }) => _workbook(
    '/api/interaction_detail/',
    token,
    pointId,
    start: start,
    end: end,
  );

  Future<Uint8List> _workbook(
    String path,
    String token,
    int pointId, {
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        queryParameters: {
          'catchment_point': pointId,
          'date_time_medition__date__range':
              '${_dateOnly(start)},${_dateOnly(end)}',
        },
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 120),
          headers: {'Authorization': 'Token $token', 'Accept': xlsxMime},
        ),
      );
      final bytes = Uint8List.fromList(response.data ?? const []);
      // Un XLSX es un ZIP: si no parte con "PK" la API devolvió otra cosa.
      if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
        throw const SmartHydroApiException(
          'La API no devolvió una planilla válida.',
        );
      }
      return bytes;
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  static const xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  Future<Response<dynamic>> _authorizedSend(
    String method,
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    try {
      return await _dio.request<dynamic>(
        path,
        data: body,
        options: _authOptions(token).copyWith(method: method),
      );
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Future<Response<dynamic>> _authorizedGet(
    String path,
    String token, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
        options: _authOptions(token),
      );
    } on DioException catch (error) {
      throw SmartHydroApiException(_messageFor(error));
    }
  }

  Options _authOptions(String token) =>
      Options(headers: {'Authorization': 'Token $token'});

  static List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) return data.map(_map).toList(growable: false);
    final nested = _map(data)['results'];
    if (nested is List) return nested.map(_map).toList(growable: false);
    return const [];
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, item) => MapEntry('$key', item));
    return <String, dynamic>{};
  }

  static String _dateOnly(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String? _tokenOf(RequestOptions options) {
    final header = options.headers['Authorization'];
    if (header is! String || !header.startsWith('Token ')) return null;
    return header.substring('Token '.length);
  }

  static String _messageFor(DioException error) {
    final response = error.response;
    if (response?.statusCode == 401 && _tokenOf(error.requestOptions) != null) {
      return 'Tu sesión expiró. Vuelve a ingresar.';
    }
    final data = _map(response?.data);
    final detail = data['message'] ?? data['detail'] ?? data['error'];
    if (detail is String && detail.trim().isNotEmpty) return detail;
    if (response?.statusCode == 401) {
      return 'Credenciales inválidas o cuenta aún no verificada.';
    }
    if (response?.statusCode == 403) {
      return 'Tu cuenta no tiene permiso para esta información.';
    }
    if (response?.statusCode == 429) {
      return 'La API recibió muchas solicitudes. Espera un momento y vuelve a intentar.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'No fue posible conectar con SmartHydro. Revisa tu conexión e intenta nuevamente.';
    }
    return 'No se pudo completar la solicitud. Intenta nuevamente.';
  }
}
