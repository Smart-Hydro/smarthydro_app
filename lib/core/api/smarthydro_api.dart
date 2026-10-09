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

  String get email => user['email'] as String? ?? '';
}

class SmartHydroApiException implements Exception {
  const SmartHydroApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SmartHydroApi {
  SmartHydroApi({Dio? dio})
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
          );

  final Dio _dio;

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
  }) async {
    final response = await _authorizedGet(
      '/api/ik/tickets/notifications/',
      token,
      queryParameters: {'unread_only': unreadOnly, 'page': 1},
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

  Future<List<Map<String, dynamic>>> systemEvents(String token) async {
    final response = await _authorizedGet(
      '/api/ik/control_center/system_events/',
      token,
      queryParameters: {'page': 1, 'page_size': 20},
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
  }) async {
    final response = await _authorizedGet(
      '/api/ik/compliance/',
      token,
      queryParameters: {'page': 1, 'page_size': 100, 'active_only': activeOnly},
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

  Future<List<Map<String, dynamic>>> supportTickets(String token) async {
    final response = await _authorizedGet(
      '/api/ik/tickets/',
      token,
      queryParameters: {'page': 1, 'page_size': 50, 'origin': 'CLIENTE'},
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

  static String _messageFor(DioException error) {
    final response = error.response;
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
