import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/brand.dart';
import '../../core/session/session_provider.dart';
import '../analysis/smart_analysis_screen.dart';
import '../profile/profile_screen.dart';
import '../compliance/compliance_screen.dart';
import '../geo/geo_smart_screen.dart';
import '../reports/reports_screen.dart';
import '../support/customer_support_screen.dart';
import '../../shared/navigation/hydro_page_route.dart';
import '../../shared/widgets/hydro_entrance.dart';
import '../../shared/widgets/hydro_glass.dart';
import '../../shared/widgets/liquid_nav.dart';
import '../../shared/widgets/water_atmosphere.dart';
import 'capture_stage.dart';
import 'capture3d_view.dart';
import 'point_link.dart';
import 'widgets/portfolio_network.dart';

class LiveDashboardScreen extends ConsumerStatefulWidget {
  const LiveDashboardScreen({required this.session, super.key});

  final SmartHydroSession session;

  @override
  ConsumerState<LiveDashboardScreen> createState() =>
      _LiveDashboardScreenState();
}

class _LiveDashboardScreenState extends ConsumerState<LiveDashboardScreen>
    with WidgetsBindingObserver {
  int _selectedTab = 0;
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic> _stats = const {};
  List<Map<String, dynamic>> _points = const [];
  Map<String, dynamic> _ticketNotifications = const {};
  Map<String, dynamic> _eventsSummary = const {};
  List<Map<String, dynamic>> _systemEvents = const [];
  String? _ticketError;
  String? _eventsError;
  bool _loadingNotifications = false;
  bool _notificationRequestInFlight = false;
  Timer? _notificationPoll;
  bool _notifyEmail = true;
  bool _savingEmailPreference = false;

  SmartHydroApi get _api => ref.read(smartHydroApiProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifyEmail = widget.session.user['notify_email'] != false;
    _loadDashboard();
    _loadNotifications();
    _startNotificationPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startNotificationPolling();
      _loadNotifications();
    } else {
      _notificationPoll?.cancel();
      _notificationPoll = null;
    }
  }

  void _startNotificationPolling() {
    if (_notificationPoll != null) return;
    _notificationPoll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadNotifications(),
    );
  }

  @override
  void dispose() {
    _notificationPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _api.dashboardStats(widget.session.token),
        _api.pointsSummary(widget.session.token),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _points = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
      if (_selectedTab == 2) _loadNotifications();
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'No se pudieron cargar tus datos. Intenta actualizar.';
        _loading = false;
      });
    }
  }

  Future<void> _loadNotifications() async {
    if (_notificationRequestInFlight) return;
    _notificationRequestInFlight = true;
    setState(() {
      _loadingNotifications = true;
      _ticketError = null;
      _eventsError = null;
    });
    try {
      final results = await Future.wait<Object?>([
        _api
            .ticketNotifications(widget.session.token)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
        _api
            .systemEventsSummary(widget.session.token)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
        _api
            .systemEvents(widget.session.token)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
      ]);
      if (!mounted) return;
      setState(() {
        final tickets = results[0];
        if (tickets is Map<String, dynamic>) {
          _ticketNotifications = tickets;
        } else {
          _ticketError = _messageFrom(tickets);
        }
        final summary = results[1];
        if (summary is Map<String, dynamic>) {
          _eventsSummary = summary;
        }
        final events = results[2];
        if (events is List<Map<String, dynamic>>) {
          _systemEvents = events;
        } else {
          _eventsError = _messageFrom(events);
        }
      });
    } finally {
      _notificationRequestInFlight = false;
      if (mounted) setState(() => _loadingNotifications = false);
    }
  }

  String _messageFrom(Object? error) => error is SmartHydroApiException
      ? error.message
      : 'No se pudo cargar esta sección.';

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    final id = notification['id'];
    final numericId = id is int ? id : int.tryParse('$id');
    if (numericId == null || notification['is_read'] == true) return;
    try {
      await _api.markTicketNotificationsRead(widget.session.token, [numericId]);
      await _loadNotifications();
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _toggleEmailNotifications(bool enabled) async {
    setState(() => _savingEmailPreference = true);
    try {
      await _api.setEmailNotifications(widget.session.token, enabled);
      if (!mounted) return;
      setState(() {
        _notifyEmail = enabled;
        _savingEmailPreference = false;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() => _savingEmailPreference = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _selectTab(int index) {
    setState(() => _selectedTab = index);
    if (index == 2) _loadNotifications();
  }

  void _signOut() => ref.read(sessionProvider.notifier).signOut();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final unreadCount = _ticketNotifications['unread_count'] as int? ?? 0;
    final page = _buildSelectedPage();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: WaterAtmosphere(opacity: 0.22)),
          SafeArea(
            child: Row(
              children: [
                if (wide)
                  LiquidNavRail(
                    selectedIndex: _selectedTab,
                    unreadCount: unreadCount,
                    onSelect: _selectTab,
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _AppHeader(
                        userName: widget.session.displayName,
                        unreadCount: unreadCount,
                        onRefresh: _selectedTab == 2
                            ? _loadNotifications
                            : _loadDashboard,
                        onNotifications: () => _selectTab(2),
                        onProfile: () => _selectTab(4),
                      ),
                      Expanded(
                        child: ClipRect(
                          child: AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 380),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              );
                              return FadeTransition(
                                opacity: curved,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.02),
                                    end: Offset.zero,
                                  ).animate(curved),
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(_selectedTab),
                              child: page,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : LiquidNavBar(
              selectedIndex: _selectedTab,
              unreadCount: unreadCount,
              onSelect: _selectTab,
            ),
    );
  }

  Widget _buildSelectedPage() {
    if (_loadError != null && _selectedTab < 2) {
      return _ErrorState(message: _loadError!, onRetry: _loadDashboard);
    }

    switch (_selectedTab) {
      case 0:
        return _loading
            ? const _LoadingState()
            : _DashboardTab(
                stats: _stats,
                points: _points,
                userName: widget.session.displayName,
                onRefresh: _loadDashboard,
                onOpenPoints: () => _selectTab(1),
                onSelectPoint: _openPoint,
              );
      case 1:
        return _loading
            ? const _LoadingState()
            : _PointsTab(
                points: _points,
                onSelectPoint: _openPoint,
                onOpenGeo: _openGeo,
                onOpenAnalysis: _openAnalysis,
              );
      case 2:
        return _NotificationsTab(
          tickets: _ticketNotifications,
          summary: _eventsSummary,
          events: _systemEvents,
          loading: _loadingNotifications,
          ticketError: _ticketError,
          eventsError: _eventsError,
          onRefresh: _loadNotifications,
          onMarkRead: _markAsRead,
          onOpenPoint: _openPointById,
          onEvent: _presentEvent,
        );
      case 3:
        return _MoreTab(
          onOpenCompliance: _openCompliance,
          onOpenSupport: _openSupport,
          onOpenGeo: _openGeo,
          onOpenAnalysis: _openAnalysis,
          onOpenReports: _openReports,
        );
      default:
        return HydroFrame(
          child: ProfileScreen(
            api: _api,
            session: widget.session,
            pointCount: _points.length,
            notifyEmail: _notifyEmail,
            savingEmailPreference: _savingEmailPreference,
            onNotifyEmailChanged: _toggleEmailNotifications,
            onUserUpdated: (user) =>
                ref.read(sessionProvider.notifier).updateUser(user),
            onSignOut: _signOut,
          ),
        );
    }
  }

  void _openPoint(Map<String, dynamic> point) {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        _PointDetailScreen(
          api: _api,
          token: widget.session.token,
          point: point,
        ),
      ),
    );
  }

  void _openGeo() {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        GeoSmartScreen(points: _points, onSelectPoint: _openPoint),
      ),
    );
  }

  void _openAnalysis() {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        SmartAnalysisScreen(
          api: _api,
          token: widget.session.token,
          points: _points,
        ),
      ),
    );
  }

  void _openCompliance() {
    Navigator.of(context).push<void>(
      hydroPageRoute(ComplianceScreen(api: _api, token: widget.session.token)),
    );
  }

  void _openSupport() {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        CustomerSupportScreen(
          api: _api,
          token: widget.session.token,
          points: _points,
        ),
      ),
    );
  }

  void _openReports() {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        ReportsScreen(api: _api, token: widget.session.token, points: _points),
      ),
    );
  }

  void _openPointById(dynamic rawId) {
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este evento no tiene un punto asociado.'),
        ),
      );
      return;
    }
    Map<String, dynamic>? point;
    for (final item in _points) {
      if (_int(item['id']) == id) {
        point = item;
        break;
      }
    }
    if (point != null) {
      _openPoint(point);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El punto asociado ya no está en tu lista.'),
        ),
      );
    }
  }

  Future<void> _presentEvent(Map<String, dynamic> event) async {
    final point = _map(event['point']);
    final pointId = _int(point['id'], _int(event['point_id'], -1));
    final hasPoint = pointId > 0;
    final label = _eventTypeLabel(event['event_type']?.toString());
    final severity = (event['severity'] as String? ?? 'INFO').toUpperCase();
    final title = event['title']?.toString().trim();
    final message = event['message']?.toString() ?? '';
    final when = _formatTimestamp(event['created'] ?? event['created_at']);
    final pointName =
        point['display_name'] ?? point['title'] ?? point['name'] ?? 'Punto';
    final created = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF102328),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (title == null || title.isEmpty) ? label : title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$label · $pointName · $when',
                  style: const TextStyle(
                    color: Color(0xFF9AB0B1),
                    fontSize: 12,
                  ),
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(message, style: const TextStyle(height: 1.4)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: hasPoint
                      ? () => Navigator.pop(context, 'point')
                      : null,
                  child: const Text('Ver punto'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: hasPoint
                      ? () => Navigator.pop(context, 'ticket')
                      : null,
                  child: const Text('Crear solicitud'),
                ),
                if (!hasPoint) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Este evento no trae un punto, así que no se puede abrir ni referenciar una solicitud.',
                    style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || created == null) return;
    if (created == 'point') {
      _openPointById(pointId);
      return;
    }
    final priority = switch (severity) {
      'CRITICAL' || 'ALERT' => 'ALTA',
      'WARNING' => 'MEDIA',
      _ => 'BAJA',
    };
    final subject = (title == null || title.isEmpty) ? label : title;
    final description = [
      'Evento #${event['id'] ?? '—'}',
      'Tipo: $label',
      'Severidad: $severity',
      'Fecha: $when',
      'Punto: $pointName',
      if (message.isNotEmpty) '',
      if (message.isNotEmpty) message,
    ].join('\n');
    await showSupportTicketSheet(
      context,
      api: _api,
      token: widget.session.token,
      points: _points,
      initialTitle: subject,
      initialDescription: description,
      initialPointId: pointId,
      initialPriority: priority,
      lockPoint: true,
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.userName,
    required this.unreadCount,
    required this.onRefresh,
    required this.onNotifications,
    required this.onProfile,
  });

  final String userName;
  final int unreadCount;
  final VoidCallback onRefresh;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          const _BrandCompact(),
          const Spacer(),
          IconButton(
            tooltip: 'Actualizar información',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Abrir notificaciones',
            onPressed: onNotifications,
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onProfile,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF24454A),
              child: Text(
                userName.isEmpty
                    ? 'SH'
                    : userName.substring(0, 1).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.stats,
    required this.points,
    required this.userName,
    required this.onRefresh,
    required this.onOpenPoints,
    required this.onSelectPoint,
  });

  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> points;
  final String userName;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenPoints;
  final ValueChanged<Map<String, dynamic>> onSelectPoint;

  @override
  Widget build(BuildContext context) {
    final total = points.isNotEmpty
        ? points.length
        : _int(_map(stats['points'])['total'], _int(stats['total_points']));
    final connected = points
        .where((point) => pointLinkOf(point) == PointLink.connected)
        .length;
    final gaps = points
        .where((point) => pointLinkOf(point) == PointLink.gap)
        .length;
    final incidents = points
        .where((point) => pointLinkOf(point) == PointLink.incident)
        .length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: HydroFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Saludo compacto con resumen del día.
            HydroEntrance(
              delay: const Duration(milliseconds: 40),
              child: _GreetingBanner(
                userName: userName,
                total: total,
                connected: connected,
                gaps: gaps,
                incidents: incidents,
              ),
            ),
            const SizedBox(height: 12),
            // Stats compactos en una sola fila (chips).
            HydroEntrance(
              delay: const Duration(milliseconds: 120),
              child: _CompactStats(
                total: total,
                connected: connected,
                gaps: gaps,
                incidents: incidents,
              ),
            ),
            const SizedBox(height: 14),
            // Vista general: cuerpos de agua navegables en perspectiva.
            HydroEntrance(
              delay: const Duration(milliseconds: 200),
              child: PortfolioNetwork(
                points: points,
                onPointSelected: onSelectPoint,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Tus puntos',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onOpenPoints,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Ver todos'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (points.isEmpty)
              const _EmptyState(
                icon: Icons.water_drop_outlined,
                title: 'Aún no tienes puntos asignados',
                message:
                    'Cuando tu cuenta tenga puntos asociados, aparecerán aquí.',
              )
            else
              for (var i = 0; i < points.take(5).length; i++) ...[
                HydroEntrance(
                  delay: Duration(milliseconds: 260 + i * 55),
                  child: _PointCard(
                    point: points[i],
                    onTap: () => onSelectPoint(points[i]),
                  ),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _PointsTab extends StatefulWidget {
  const _PointsTab({
    required this.points,
    required this.onSelectPoint,
    required this.onOpenGeo,
    required this.onOpenAnalysis,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<Map<String, dynamic>> onSelectPoint;
  final VoidCallback onOpenGeo;
  final VoidCallback onOpenAnalysis;

  @override
  State<_PointsTab> createState() => _PointsTabState();
}

class _PointsTabState extends State<_PointsTab> {
  final _searchController = TextEditingController();
  String _filter = 'Todos';
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.points
        .where((point) {
          final title = (point['title']?.toString() ?? '').toLowerCase();
          final project = (point['project_name']?.toString() ?? '')
              .toLowerCase();
          final client = (point['client_name']?.toString() ?? '').toLowerCase();
          final matchesSearch = '$title $project $client'.contains(_search);
          final link = pointLinkOf(point);
          final matchesFilter = switch (_filter) {
            'Conectados' => link == PointLink.connected,
            'Advertencias' => link == PointLink.gap,
            'Incidencias' => link == PointLink.incident,
            _ => true,
          };
          return matchesSearch && matchesFilter;
        })
        .toList(growable: false);

    return HydroFrame(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) =>
                setState(() => _search = value.trim().toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Buscar punto, proyecto o cliente',
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: const Color(0xFF112328),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final filter in const [
                'Todos',
                'Conectados',
                'Advertencias',
                'Incidencias',
              ])
                ChoiceChip(
                  label: Text(filter),
                  selected: _filter == filter,
                  visualDensity: VisualDensity.comfortable,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: widget.onOpenGeo,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Mapa'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: widget.onOpenAnalysis,
                  icon: const Icon(Icons.query_stats_rounded),
                  label: const Text('Análisis'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (widget.points.isEmpty)
            const _EmptyState(
              icon: Icons.location_off_outlined,
              title: 'Sin puntos asignados',
              message: 'No hay puntos disponibles para esta cuenta.',
            )
          else if (filtered.isEmpty)
            const _EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Sin resultados',
              message: 'Cambia el texto o filtro para encontrar un punto.',
            )
          else
            for (final point in filtered) ...[
              _PointCard(
                point: point,
                onTap: () => widget.onSelectPoint(point),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _NotificationsTab extends StatelessWidget {
  const _NotificationsTab({
    required this.tickets,
    required this.summary,
    required this.events,
    required this.loading,
    required this.ticketError,
    required this.eventsError,
    required this.onRefresh,
    required this.onMarkRead,
    required this.onOpenPoint,
    required this.onEvent,
  });

  final Map<String, dynamic> tickets;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> events;
  final bool loading;
  final String? ticketError;
  final String? eventsError;
  final VoidCallback onRefresh;
  final ValueChanged<Map<String, dynamic>> onMarkRead;
  final ValueChanged<dynamic> onOpenPoint;
  final ValueChanged<Map<String, dynamic>> onEvent;

  @override
  Widget build(BuildContext context) {
    final results = tickets['results'];
    final notifications = results is List
        ? results
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final event in events) {
      final stamp = event['created'] ?? event['created_at'];
      final parsed = DateTime.tryParse(stamp?.toString() ?? '')?.toLocal();
      final key = parsed == null
          ? 'Sin fecha'
          : '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(event);
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: HydroFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${_int(summary['total_events'])} incidencias en ${_int(summary['period_days'], 7)} días · ${_int(tickets['unread_count'])} avisos de soporte sin leer',
                      style: const TextStyle(color: Color(0xFF9AB0B1)),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'Actualizar avisos',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (loading) const HydroLinearBar(),
            _IncidentBoard(summary: summary),
            const SizedBox(height: 22),
            const _SectionTitle(title: 'Soporte y tickets'),
            if (ticketError != null)
              _InlineError(message: ticketError!, onRetry: onRefresh)
            else if (notifications.isEmpty && !loading)
              const _EmptyState(
                icon: Icons.mark_email_read_outlined,
                title: 'No tienes notificaciones de tickets',
                message:
                    'Los comentarios y cambios en tus solicitudes aparecerán aquí.',
              )
            else
              for (final notification in notifications) ...[
                _TicketNotificationCard(
                  notification: notification,
                  onMarkRead: () => onMarkRead(notification),
                ),
                const SizedBox(height: 9),
              ],
            const SizedBox(height: 24),
            const _SectionTitle(title: 'Eventos de sistema'),
            if (eventsError != null)
              _InlineError(message: eventsError!, onRetry: onRefresh)
            else if (events.isEmpty && !loading)
              const _EmptyState(
                icon: Icons.sensors_outlined,
                title: 'No hay eventos recientes',
                message:
                    'Las desconexiones y eventos de tus puntos aparecerán aquí.',
              )
            else
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      color: Color(0xFF9AB0B1),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final event in entry.value) ...[
                  _SystemEventCard(event: event, onTap: () => onEvent(event)),
                  const SizedBox(height: 12),
                ],
              ],
          ],
        ),
      ),
    );
  }
}

class _MoreTab extends StatelessWidget {
  const _MoreTab({
    required this.onOpenCompliance,
    required this.onOpenSupport,
    required this.onOpenGeo,
    required this.onOpenAnalysis,
    required this.onOpenReports,
  });

  final VoidCallback onOpenCompliance;
  final VoidCallback onOpenSupport;
  final VoidCallback onOpenGeo;
  final VoidCallback onOpenAnalysis;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    return HydroFrame(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _ActionCard(
            icon: Icons.map_outlined,
            title: 'GEO Smart',
            subtitle: 'Ubicación y estado de tus puntos con GPS',
            color: IkoluColors.cyan,
            onTap: onOpenGeo,
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.query_stats_rounded,
            title: 'Smart Análisis',
            subtitle: 'Consumo diario y mensual por punto',
            color: IkoluColors.cyan,
            onTap: onOpenAnalysis,
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.balance_rounded,
            title: 'DGA / SMA',
            subtitle: 'Cumplimiento, límites autorizados y mediciones',
            color: IkoluColors.cyan,
            onTap: onOpenCompliance,
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.support_agent_rounded,
            title: 'Soporte',
            subtitle: 'Crear y seguir solicitudes para tus puntos',
            color: IkoluColors.cyan,
            onTap: onOpenSupport,
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.table_view_outlined,
            title: 'Descarga de registros',
            subtitle: 'Consulta y comparte datos de telemetría en CSV',
            color: IkoluColors.cyan,
            onTap: onOpenReports,
          ),
          const SizedBox(height: 18),
          const _SectionCard(
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFFB19AFF)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'El agente de atención Yggdra será el siguiente módulo conversacional.',
                    style: TextStyle(color: Color(0xFFB5C7C5), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PointDetailScreen extends StatefulWidget {
  const _PointDetailScreen({
    required this.api,
    required this.token,
    required this.point,
  });

  final SmartHydroApi api;
  final String token;
  final Map<String, dynamic> point;

  @override
  State<_PointDetailScreen> createState() => _PointDetailScreenState();
}

class _PointDetailScreenState extends State<_PointDetailScreen> {
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _history = const [];
  List<Map<String, dynamic>> _replayRecords = const [];
  String? _error;
  String? _historyError;
  String? _replayError;
  bool _loading = true;
  bool _historyLoading = true;
  bool _replayLoading = true;
  int _historyDays = 7;
  int _selectedReplayIndex = 0;
  DateTimeRange _replayRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 1)),
    end: DateTime.now(),
  );
  Timer? _replayTimer;
  bool _use3d = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadReplay();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = _int(widget.point['id']);
      final detail = await widget.api.pointSummary(widget.token, id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
      await _loadHistory();
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadReplay() async {
    _replayTimer?.cancel();
    _replayTimer = null;
    setState(() {
      _replayLoading = true;
      _replayError = null;
      _selectedReplayIndex = 0;
    });
    try {
      final records = await widget.api.pointRecords(
        widget.token,
        _int(widget.point['id']),
        start: _replayRange.start,
        end: _replayRange.end,
      );
      records.sort((a, b) {
        final aTime =
            DateTime.tryParse(a['date_time']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            DateTime.tryParse(b['date_time']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });
      if (!mounted) return;
      setState(() {
        _replayRecords = records;
        _selectedReplayIndex = records.isEmpty ? 0 : records.length - 1;
        _replayLoading = false;
      });
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _replayError = error.message;
        _replayLoading = false;
      });
    }
  }

  Future<void> _chooseReplayRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: now,
      initialDateRange: _replayRange,
      helpText: 'Selecciona el período de reproducción',
      saveText: 'Cargar período',
    );
    if (!mounted || selected == null) return;
    if (selected.duration.inDays > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El período máximo disponible es de 31 días.'),
        ),
      );
      return;
    }
    setState(() => _replayRange = selected);
    _loadReplay();
  }

  void _replayRestart() {
    _replayTimer?.cancel();
    _replayTimer = null;
    setState(() => _selectedReplayIndex = 0);
  }

  /// El índice se deriva del tiempo transcurrido (no de ticks contados): si el
  /// navegador atrasa los timers (pestaña en segundo plano, render lento), el
  /// replay se reposiciona según el reloj en vez de dispararse en ráfaga, y la
  /// parada al final siempre se cumple.
  void _toggleReplay() {
    if (_replayTimer != null) {
      _replayTimer?.cancel();
      setState(() => _replayTimer = null);
      return;
    }
    if (_replayRecords.length < 2) return;
    const stepMs = 650;
    final last = _replayRecords.length - 1;
    final startIndex = _selectedReplayIndex >= last ? 0 : _selectedReplayIndex;
    if (startIndex != _selectedReplayIndex) {
      setState(() => _selectedReplayIndex = startIndex);
    }
    final clock = Stopwatch()..start();
    _replayTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = (startIndex + clock.elapsedMilliseconds ~/ stepMs).clamp(
        0,
        last,
      );
      if (next != _selectedReplayIndex) {
        setState(() => _selectedReplayIndex = next);
      }
      if (next >= last) {
        timer.cancel();
        setState(() => _replayTimer = null);
      }
    });
    setState(() {});
  }

  @override
  void dispose() {
    _replayTimer?.cancel();
    super.dispose();
  }

  /// Callback para redibujar el panel de historial mientras está abierto.
  VoidCallback? _refreshSheet;

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    _refreshSheet?.call();
    try {
      final history = await widget.api.pointCalendar(
        widget.token,
        _int(widget.point['id']),
        days: _historyDays,
      );
      if (!mounted) return;
      setState(() {
        _history = history;
        _historyLoading = false;
      });
      _refreshSheet?.call();
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = error.message;
        _historyLoading = false;
      });
      _refreshSheet?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _detail ?? widget.point;
    final telemetry = _map(data['latest_telemetry']);
    final dga = _map(data['dga']);
    final selectedRecord = _replayRecords.isEmpty
        ? null
        : _replayRecords[_selectedReplayIndex.clamp(
            0,
            _replayRecords.length - 1,
          )];
    final levelValue =
        selectedRecord?['water_table'] ??
        selectedRecord?['nivel'] ??
        telemetry['water_table'] ??
        telemetry['nivel'];
    final level = levelValue == null ? null : double.tryParse('$levelValue');
    final replayLevels = _replayRecords
        .map((record) {
          final value = record['water_table'] ?? record['nivel'];
          if (value is num) return value.toDouble();
          return double.tryParse('$value');
        })
        .whereType<double>()
        .toList(growable: false);
    final minimumLevel = replayLevels.isEmpty
        ? null
        : replayLevels.reduce((a, b) => a < b ? a : b);
    final maximumLevel = replayLevels.isEmpty
        ? null
        : replayLevels.reduce((a, b) => a > b ? a : b);
    final isSurface =
        (dga['type_dga'] as String? ?? '').toUpperCase() == 'SUPERFICIAL';
    final startedAt = selectedRecord == null
        ? null
        : DateTime.tryParse(selectedRecord['date_time']?.toString() ?? '');
    final title = data['title'] as String? ?? 'Punto de captación';
    final liveFlow = _optionalNumber(
      selectedRecord?['flow'] ?? telemetry['flow'],
    );
    final liveTotal = _optionalNumber(
      selectedRecord?['total_raw'] ??
          selectedRecord?['total'] ??
          telemetry['total'],
    );
    final levelRange = (minimumLevel != null && maximumLevel != null)
        ? maximumLevel - minimumLevel
        : 0.0;
    final levelFill = level == null
        ? null
        : levelRange.abs() < 0.0001
        ? 0.55
        : ((level - minimumLevel!) / levelRange).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: const Color(0xFF071114),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _use3d
                    ? Capture3DView(
                        levelMeters: level,
                        levelFill: levelFill,
                        flowLitersPerSecond: liveFlow,
                        isSurface: isSurface,
                        link: pointLinkOf(data),
                      )
                    : CaptureStage(
                        levelMeters: level,
                        levelFill: levelFill,
                        levelMin: minimumLevel,
                        levelMax: maximumLevel,
                        flowLitersPerSecond: liveFlow,
                        isSurface: isSurface,
                        link: pointLinkOf(data),
                        playing: _replayTimer != null,
                      ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: _ViewModeToggle(
                      use3d: _use3d,
                      onChanged: (value) => setState(() => _use3d = value),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Volver',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                data['project_name'] as String? ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF9AB0B1),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _CaptureTypeChip(isSurface: isSurface),
                      ],
                    ),
                  ),
                ),
                if (_loading || _replayLoading)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: HydroLinearBar(),
                  ),
              ],
            ),
          ),
          Material(
            color: const Color(0xFF102328),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      _InlineError(message: _error!, onRetry: _load),
                    if (_replayError != null)
                      _InlineError(
                        message: _replayError!,
                        onRetry: _loadReplay,
                      ),
                    _ReadoutStrip(
                      flow: liveFlow,
                      total: liveTotal,
                      level: level,
                      stamp: startedAt == null
                          ? 'Última medición ${_formatTimestamp(telemetry['date_time_medition'])}'
                          : _formatTimestamp(startedAt.toIso8601String()),
                    ),
                    const SizedBox(height: 12),
                    _ReplayBar(
                      playing: _replayTimer != null,
                      canReplay: _replayRecords.length > 1,
                      atStart: _selectedReplayIndex <= 0,
                      onToggle: _toggleReplay,
                      onRestart: _replayRestart,
                      onPickRange: _chooseReplayRange,
                      onHistory: _openHistory,
                    ),
                    if (_replayRecords.length > 1) ...[
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: IkoluColors.cyan,
                          inactiveTrackColor: const Color(0xFF26383A),
                          thumbColor: IkoluColors.cyan,
                          overlayColor: const Color(
                            0xFF00C8FF,
                          ).withValues(alpha: 0.2),
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                        ),
                        child: Slider(
                          value: _selectedReplayIndex.toDouble(),
                          min: 0,
                          max: (_replayRecords.length - 1).toDouble(),
                          divisions: _replayRecords.length - 1,
                          label: startedAt == null
                              ? null
                              : _formatTimestamp(startedAt.toIso8601String()),
                          semanticFormatterCallback: (value) =>
                              'Registro ${value.round() + 1} de ${_replayRecords.length}',
                          onChanged: (value) => setState(
                            () => _selectedReplayIndex = value.round(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatTimestamp(
                                _replayRecords.first['date_time']?.toString(),
                              ),
                              style: const TextStyle(
                                color: Color(0xFF8FA8A8),
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              '${_selectedReplayIndex + 1}/${_replayRecords.length}',
                              style: const TextStyle(
                                color: IkoluColors.cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _formatTimestamp(
                                _replayRecords.last['date_time']?.toString(),
                              ),
                              style: const TextStyle(
                                color: Color(0xFF8FA8A8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          isSurface
                              ? 'Sin lecturas en este período. Se muestra la última telemetría del agua superficial.'
                              : 'Sin lecturas en este período. Se muestra la última telemetría del pozo.',
                          style: const TextStyle(
                            color: Color(0xFF8FA8A8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    _PointQuickActions(
                      isSurface: isSurface,
                      onAnalysis: _openAnalysisForPoint,
                      onCompliance: _openComplianceForPoint,
                      onSupport: _createTicketForPoint,
                      onReports: _openReportsForPoint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAnalysisForPoint() {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        SmartAnalysisScreen(
          api: widget.api,
          token: widget.token,
          points: [widget.point],
        ),
      ),
    );
  }

  void _openComplianceForPoint() {
    Navigator.of(context).push<void>(
      hydroPageRoute(ComplianceScreen(api: widget.api, token: widget.token)),
    );
  }

  void _openReportsForPoint() {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        ReportsScreen(
          api: widget.api,
          token: widget.token,
          points: [widget.point],
        ),
      ),
    );
  }

  Future<void> _createTicketForPoint() async {
    final created = await showSupportTicketSheet(
      context,
      api: widget.api,
      token: widget.token,
      points: [widget.point],
      initialPointId: _int(widget.point['id']),
      lockPoint: true,
      initialTitle: 'Solicitud sobre ${widget.point['title'] ?? 'punto'}',
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud creada correctamente.')),
      );
    }
  }

  void _openHistory() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF102328),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            _refreshSheet = () => setSheet(() {});
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.75,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    const Text(
                      'Historial diario',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 7, label: Text('7 días')),
                        ButtonSegment(value: 30, label: Text('30 días')),
                      ],
                      selected: {_historyDays},
                      onSelectionChanged: (selection) {
                        setState(() => _historyDays = selection.first);
                        _loadHistory();
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_historyLoading)
                      const HydroLinearBar()
                    else if (_historyError != null)
                      _InlineError(
                        message: _historyError!,
                        onRetry: _loadHistory,
                      )
                    else if (_history.isEmpty)
                      _EmptyState(
                        icon: Icons.query_stats_rounded,
                        title: 'Sin historial para este período',
                        message: _historyDays == 7
                            ? 'No hay registros en los últimos 7 días. Prueba con 30 días.'
                            : 'No hay registros diarios disponibles en el rango seleccionado.',
                      )
                    else
                      for (final day in _history) ...[
                        _HistoryDayCard(day: day),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => _refreshSheet = null);
  }
}

/// Chip que distingue el tipo de captación en el encabezado del detalle.
class _CaptureTypeChip extends StatelessWidget {
  const _CaptureTypeChip({required this.isSurface});

  final bool isSurface;

  @override
  Widget build(BuildContext context) {
    final color = isSurface ? const Color(0xFF69B9FF) : IkoluColors.cyan;
    final label = isSurface ? 'Superficial' : 'Pozo';
    final icon = isSurface
        ? Icons.waves_rounded
        : Icons.vertical_align_bottom_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF071114).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Alterna entre la vista 2D (minimalista) y la vista 3D (Three.js).
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.use3d, required this.onChanged});

  final bool use3d;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const accent = IkoluColors.cyan;
    return Material(
      color: const Color(0xFF071114).withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeButton(
              label: '2D',
              selected: !use3d,
              accent: accent,
              onTap: () => onChanged(false),
            ),
            _ModeButton(
              label: '3D',
              selected: use3d,
              accent: accent,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : const Color(0xFF9AB0B1),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Barra de reproducción del Replay 4D con botón de inicio y efecto hover.
class _ReplayBar extends StatelessWidget {
  const _ReplayBar({
    required this.playing,
    required this.canReplay,
    required this.atStart,
    required this.onToggle,
    required this.onRestart,
    required this.onPickRange,
    required this.onHistory,
  });

  final bool playing;
  final bool canReplay;
  final bool atStart;
  final VoidCallback onToggle;
  final VoidCallback onRestart;
  final VoidCallback onPickRange;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HoverIconButton(
          tooltip: 'Volver al inicio del período',
          onPressed: canReplay && !atStart ? onRestart : null,
          icon: Icons.skip_previous_rounded,
        ),
        const SizedBox(width: 4),
        _HoverIconButton(
          filled: true,
          tooltip: playing ? 'Pausar' : 'Recorrer el caudal del período',
          onPressed: canReplay ? onToggle : null,
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        ),
        const Spacer(),
        _HoverIconButton(
          tooltip: 'Cambiar período',
          onPressed: onPickRange,
          icon: Icons.calendar_month_rounded,
        ),
        const SizedBox(width: 4),
        _HoverIconButton(
          tooltip: 'Historial diario',
          onPressed: onHistory,
          icon: Icons.history_rounded,
        ),
      ],
    );
  }
}

/// Botón de icono con realce al pasar el mouse, sin sombras ni paneles.
class _HoverIconButton extends StatefulWidget {
  const _HoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    const accent = IkoluColors.cyan;
    final base = widget.filled
        ? accent.withValues(alpha: 0.2)
        : const Color(0xFF0C1B20).withValues(alpha: 0.6);
    final hover = accent.withValues(alpha: widget.filled ? 0.34 : 0.14);
    final color = enabled
        ? (_hovered ? hover : base)
        : base.withValues(alpha: 0.4);
    final iconColor = enabled
        ? (_hovered || widget.filled ? accent : const Color(0xFFB4C7C8))
        : const Color(0xFF5A6B6D);
    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: Tooltip(
        message: widget.tooltip,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onPressed,
            child: AnimatedScale(
              scale: _hovered && enabled ? 1.06 : 1,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hovered && enabled
                        ? accent.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.06),
                    width: 1,
                  ),
                ),
                child: Icon(widget.icon, size: 20, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Acciones rápidas desde el detalle del punto: navegación a análisis,
/// cumplimiento, reportes y soporte, ya acotados al punto en pantalla.
/// Diseño minimal: una fila de iconos con etiqueta debajo, sin tarjetas.
class _PointQuickActions extends StatelessWidget {
  const _PointQuickActions({
    required this.isSurface,
    required this.onAnalysis,
    required this.onCompliance,
    required this.onSupport,
    required this.onReports,
  });

  final bool isSurface;
  final VoidCallback onAnalysis;
  final VoidCallback onCompliance;
  final VoidCallback onSupport;
  final VoidCallback onReports;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _QuickAction(
          icon: Icons.query_stats_rounded,
          label: 'Análisis',
          onTap: onAnalysis,
        ),
        _QuickAction(
          icon: Icons.balance_rounded,
          label: 'Cumplim.',
          onTap: onCompliance,
        ),
        _QuickAction(
          icon: Icons.table_view_outlined,
          label: 'Registros',
          onTap: onReports,
        ),
        _QuickAction(
          icon: Icons.support_agent_rounded,
          label: 'Soporte',
          onTap: onSupport,
          accent: const Color(0xFFFFC46B),
        ),
      ],
    );
  }
}

class _QuickAction extends StatefulWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.accent ?? IkoluColors.cyan;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _hovered ? 1.12 : 1,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Icon(widget.icon, size: 22, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: _hovered ? color : const Color(0xFF8FA8A8),
                  fontSize: 10.5,
                  fontWeight: _hovered ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Franja de lectura minimal: caudal, total y nivel en una sola línea,
/// sin tarjeta contenedora. Los valores destacan con su acento.
class _ReadoutStrip extends StatelessWidget {
  const _ReadoutStrip({
    required this.flow,
    required this.total,
    required this.level,
    required this.stamp,
  });

  final double? flow;
  final double? total;
  final double? level;
  final String stamp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Readout(
              label: 'Caudal',
              value: flow == null ? '—' : flow!.toStringAsFixed(2),
              unit: 'L/s',
              accent: IkoluColors.cyan,
            ),
            _Readout(
              label: 'Total',
              value: total == null ? '—' : total!.toStringAsFixed(1),
              unit: 'm³',
              accent: const Color(0xFF69B9FF),
            ),
            _Readout(
              label: 'Nivel',
              value: level == null ? '—' : level!.toStringAsFixed(2),
              unit: 'm',
              accent: const Color(0xFFB39DDB),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          stamp,
          style: const TextStyle(color: Color(0xFF8FA8A8), fontSize: 10.5),
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
  });

  final String label;
  final String value;
  final String unit;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent.withValues(alpha: 0.8),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Color(0xFFF4FBF8),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDayCard extends StatelessWidget {
  const _HistoryDayCard({required this.day});

  final Map<String, dynamic> day;

  @override
  Widget build(BuildContext context) => _SectionCard(
    child: Row(
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          color: Color(0xFF69B9FF),
          size: 18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                day['date']?.toString() ?? 'Día',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Caudal prom. ${_display(day['avg_flow_lps'], 'L/s')} · nivel ${_display(day['avg_nivel_m'], 'm')}',
                style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
              ),
            ],
          ),
        ),
        Text(
          _display(day['consumption_m3'], 'm³'),
          style: const TextStyle(
            color: IkoluColors.cyan,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// Saludo compacto del dashboard con un resumen del estado de la cartera.
class _GreetingBanner extends StatelessWidget {
  const _GreetingBanner({
    required this.userName,
    required this.total,
    required this.connected,
    required this.gaps,
    required this.incidents,
  });

  final String userName;
  final int total;
  final int connected;
  final int gaps;
  final int incidents;

  @override
  Widget build(BuildContext context) {
    final ok = incidents == 0 && gaps == 0;
    final status = ok
        ? 'Toda tu red en línea'
        : incidents > 0
        ? '$incidents ${incidents == 1 ? 'incidencia' : 'incidencias'} en curso'
        : '$gaps ${gaps == 1 ? 'advertencia' : 'advertencias'} por revisar';
    final statusColor = ok
        ? IkoluColors.connected
        : incidents > 0
        ? const Color(0xFFFF847A)
        : const Color(0xFFFFC46B);
    return HydroGlass(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: IkoluColors.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: IkoluMark(size: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, $userName',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                  color: IkoluColors.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const Text(
                'puntos',
                style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stats compactos del estado de la red en una fila de chips.
class _CompactStats extends StatelessWidget {
  const _CompactStats({
    required this.total,
    required this.connected,
    required this.gaps,
    required this.incidents,
  });

  final int total;
  final int connected;
  final int gaps;
  final int incidents;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatChip(
          label: 'En línea de $total',
          value: '$connected',
          color: IkoluColors.connected,
          icon: Icons.sensors_rounded,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Advertencias',
          value: '$gaps',
          color: const Color(0xFFFFC46B),
          icon: Icons.water_damage_outlined,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Incidencias',
          value: '$incidents',
          color: const Color(0xFFFF847A),
          icon: Icons.report_outlined,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: HydroGlass(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        radius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Color(0xFFF4FBF8),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointCard extends StatelessWidget {
  const _PointCard({required this.point, required this.onTap});

  final Map<String, dynamic> point;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final telemetry = _map(point['latest_telemetry']);
    final link = pointLinkOf(point);
    final color = switch (link) {
      PointLink.connected => IkoluColors.connected,
      PointLink.gap => const Color(0xFFFFC46B),
      PointLink.incident => const Color(0xFFFF847A),
    };
    return _SectionCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.water_drop_rounded, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point['title'] as String? ?? 'Punto sin nombre',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  point['project_name'] as String? ??
                      point['client_name'] as String? ??
                      'Proyecto',
                  style: const TextStyle(
                    color: Color(0xFFA9BFC0),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${pointLinkLabel(link)} · caudal ${_display(telemetry['flow'], 'L/s')} · ${_formatTimestamp(telemetry['date_time_medition'])}',
                  style: const TextStyle(
                    color: Color(0xFFC3D3D2),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF91A8AA)),
        ],
      ),
    );
  }
}

class _TicketNotificationCard extends StatelessWidget {
  const _TicketNotificationCard({
    required this.notification,
    required this.onMarkRead,
  });

  final Map<String, dynamic> notification;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final read = notification['is_read'] == true;
    return _SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            read
                ? Icons.mark_email_read_outlined
                : Icons.mark_email_unread_outlined,
            color: read ? const Color(0xFF82999A) : IkoluColors.cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification['ticket_title'] as String? ??
                      'Actualización de soporte',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  notification['message'] as String? ?? '',
                  style: const TextStyle(color: Color(0xFFB5C7C5), height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTimestamp(notification['created']),
                  style: const TextStyle(
                    color: Color(0xFF81999A),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (!read)
            IconButton(
              tooltip: 'Marcar como leída',
              onPressed: onMarkRead,
              icon: const Icon(Icons.done_rounded),
            ),
        ],
      ),
    );
  }
}

class _SystemEventCard extends StatelessWidget {
  const _SystemEventCard({required this.event, required this.onTap});

  final Map<String, dynamic> event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final severity = (event['severity'] as String? ?? '').toUpperCase();
    final color = severity == 'CRITICAL' || severity == 'ALERT'
        ? const Color(0xFFFF847A)
        : severity == 'WARNING'
        ? const Color(0xFFFFC46B)
        : const Color(0xFF69B9FF);
    final point = _map(event['point']);
    final pointName =
        event['point_title'] ??
        point['name'] ??
        point['title'] ??
        event['point_name'] ??
        'Punto';
    return _SectionCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _eventTypeLabel(event['event_type']?.toString()),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event['title'] as String? ?? 'Evento de sistema',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  event['message'] as String? ?? '',
                  style: const TextStyle(color: Color(0xFFB5C7C5), height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(
                  '$pointName · ${_formatTimestamp(event['created'] ?? event['created_at'])}',
                  style: const TextStyle(
                    color: Color(0xFF81999A),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF91A8AA)),
        ],
      ),
    );
  }
}

class _IncidentBoard extends StatelessWidget {
  const _IncidentBoard({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final severity = _map(summary['by_severity']);
    final critical = _int(severity['CRITICAL']);
    final warning = _int(severity['WARNING']);
    final info = _int(severity['INFO']);
    final timeline = summary['timeline'];
    final days = timeline is List
        ? timeline
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final peak = days.fold<int>(1, (maxCount, day) {
      final count = _int(day['count']);
      return count > maxCount ? count : maxCount;
    });

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Incidencias de telemetría',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Desconexiones, errores de medición y saltos. No incluye reglas solo configuradas.',
            style: TextStyle(
              color: Color(0xFF9AB0B1),
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _IncidentCount(
                label: 'Críticas',
                value: critical,
                color: const Color(0xFFFF847A),
              ),
              _IncidentCount(
                label: 'Avisos',
                value: warning,
                color: const Color(0xFFFFC46B),
              ),
              _IncidentCount(
                label: 'Info',
                value: info,
                color: const Color(0xFF69B9FF),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SeverityTrack(critical: critical, warning: warning, info: info),
          if (days.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: (_int(day['count']) / peak)
                                      .clamp(0.08, 1),
                                  widthFactor: 1,
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: IkoluColors.cyan,
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _shortDay(day['date']),
                              style: const TextStyle(
                                color: Color(0xFF81999A),
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IncidentCount extends StatelessWidget {
  const _IncidentCount({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
        ),
      ],
    ),
  );
}

class _SeverityTrack extends StatelessWidget {
  const _SeverityTrack({
    required this.critical,
    required this.warning,
    required this.info,
  });

  final int critical;
  final int warning;
  final int info;

  @override
  Widget build(BuildContext context) {
    final total = critical + warning + info;
    if (total == 0) {
      return const Text(
        'Sin incidencias en el período.',
        style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            if (critical > 0)
              Expanded(
                flex: critical,
                child: const ColoredBox(color: Color(0xFFFF847A)),
              ),
            if (warning > 0)
              Expanded(
                flex: warning,
                child: const ColoredBox(color: Color(0xFFFFC46B)),
              ),
            if (info > 0)
              Expanded(
                flex: info,
                child: const ColoredBox(color: Color(0xFF69B9FF)),
              ),
          ],
        ),
      ),
    );
  }
}

String _eventTypeLabel(String? type) => switch (type) {
  'DISCONNECTION' => 'Desconexión',
  'RECONNECTION' => 'Reconexión',
  'MEASUREMENT_ERROR' => 'Error de medición',
  'COUNTER_RESET' => 'Reinicio de contador',
  'MASSIVE_JUMP_BLOCKED' => 'Salto bloqueado',
  'TOKEN_REFRESH' => 'Token',
  'API_ERROR' => 'Error de API',
  _ => 'Evento',
};

String _shortDay(dynamic value) {
  final text = value?.toString() ?? '';
  if (text.length >= 10) return text.substring(8, 10);
  return text;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SectionCard(
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: Color(0xFF91A8AA)),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HydroGlass(onTap: onTap, child: child);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => _SectionCard(
    child: Column(
      children: [
        Icon(icon, color: IkoluColors.cyan, size: 27),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF9AB0B1), height: 1.4),
        ),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _SectionCard(
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFFF847A)),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => const HydroLoading();
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: _InlineError(message: message, onRetry: onRetry),
    ),
  );
}

class _BrandCompact extends StatelessWidget {
  const _BrandCompact();

  @override
  Widget build(BuildContext context) => const IkoluBrand(size: 26);
}

double? _optionalNumber(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

int _int(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  return int.tryParse('$value') ?? fallback;
}

String _display(dynamic value, String unit) {
  if (value == null || '$value'.isEmpty || value == 'null') return 'Sin dato';
  return '$value $unit';
}

String _formatTimestamp(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (parsed == null) return 'Sin lectura';
  final day = parsed.day.toString().padLeft(2, '0');
  final month = parsed.month.toString().padLeft(2, '0');
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  return const {};
}
