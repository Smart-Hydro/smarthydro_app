import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/brand.dart';
import '../../core/n1/n1_providers.dart';
import '../../core/session/session_provider.dart';
import '../analysis/analysis_screen.dart';
import '../assistant/assistant_screen.dart';
import '../profile/profile_screen.dart';
import '../compliance/compliance_screen.dart';
import '../compliance/point_compliance_screen.dart';
import '../geo/geo_smart_screen.dart';
import '../reports/reports_screen.dart';
import '../support/customer_support_screen.dart';
import '../../shared/navigation/hydro_page_route.dart';
import '../../shared/ui/hydro_ui.dart';
import '../../shared/widgets/hydro_glass.dart';
import '../../shared/widgets/liquid_nav.dart';
import 'capture_stage.dart';
import 'point_link.dart';
import 'point_history_sheet.dart';
import 'point_system.dart';
import 'point_system_screen.dart';
import 'point_meta.dart';
import 'widgets/capture_network_map.dart';
import 'widgets/hydraulic_board.dart';

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
  List<Map<String, dynamic>> _points = const [];
  Map<String, dynamic> _ticketNotifications = const {};
  List<Map<String, dynamic>> _openTickets = const [];
  List<Map<String, dynamic>> _compliance = const [];
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
    _loadOpenTickets();
    _loadCompliance();
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final points = await _api.pointsSummary(widget.session.token);
      if (!mounted) return;
      setState(() {
        _points = points;
        _loading = false;
      });
      if (_selectedTab == 1) _loadNotifications();
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

  Future<void> _loadOpenTickets() async {
    try {
      final batches = await Future.wait([
        for (final status in _openTicketStatuses)
          _api
              .supportTickets(
                widget.session.token,
                origin: null,
                status: status,
                pageSize: 50,
              )
              .catchError((Object _) => const <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      final seen = <String>{};
      final open = <Map<String, dynamic>>[];
      for (final batch in batches) {
        for (final ticket in batch) {
          if (!_ticketIsOpen(ticket)) continue;
          if (seen.add('${ticket['id']}')) open.add(ticket);
        }
      }
      setState(() => _openTickets = open);
    } catch (_) {
      // El resumen sigue con la telemetría si el listado de SLA no responde.
    }
  }

  Future<void> _loadCompliance() async {
    try {
      final points = await _api.compliancePoints(
        widget.session.token,
        pageSize: 200,
      );
      if (!mounted) return;
      setState(() => _compliance = points);
    } catch (_) {
      // El resumen sigue sin el avance DGA si esa consulta no responde.
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
    if (index == 1) _loadNotifications();
  }

  void _signOut() => ref.read(sessionProvider.notifier).signOut();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final unreadCount = _ticketNotifications['unread_count'] as int? ?? 0;
    final page = _buildSelectedPage();
    final switcher = ClipRect(
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
          key: ValueKey((_selectedTab, _loading && _selectedTab == 0)),
          child: page,
        ),
      ),
    );

    final isHome = _selectedTab == 0;
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Home: el cuerpo pasa DETRÁS del menú glass (mapa full-bleed).
      extendBody: isHome && !wide,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Home: mapa edge-to-edge (sin SafeArea que deje franja).
          // Otras tabs: SafeArea + header normal.
          if (isHome)
            Positioned.fill(child: switcher)
          else
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
                          onNotifications: () => _selectTab(liquidAvisosIndex),
                          onProfile: () => _selectTab(liquidProfileIndex),
                        ),
                        Expanded(child: switcher),
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
          : Material(
              type: MaterialType.transparency,
              child: LiquidNavBar(
                selectedIndex: _selectedTab,
                unreadCount: unreadCount,
                onSelect: _selectTab,
              ),
            ),
    );
  }

  Widget _buildSelectedPage() {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    if (_loadError != null && _selectedTab == 0) {
      return _ErrorState(message: _loadError!, onRetry: _loadDashboard);
    }

    switch (_selectedTab) {
      case 0:
        return _loading
            ? const _HomeLoading()
            : _DashboardTab(
                points: _points,
                openTickets: _openTickets,
                compliance: _compliance,
                bottomInset: wide ? 12 : 88,
                onRefresh: _loadDashboard,
                onOpenSupport: _openSupport,
                onRequestSupport: _requestSupportFor,
                onOpenCompliance: _openPointCompliance,
                onSelectPoint: _openPoint,
              );
      case 1:
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
      case 2:
        return _MoreTab(
          onOpenCompliance: _openCompliance,
          onOpenSupport: _openSupport,
          onOpenAssistant: _openAssistant,
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
        PointDetailScreen(api: _api, token: widget.session.token, point: point),
      ),
    );
  }

  void _openAssistant() {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        AssistantScreen(
          n1Api: ref.read(n1ApiProvider),
          session: widget.session,
          points: _points,
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
        AnalysisScreen(api: _api, token: widget.session.token, points: _points),
      ),
    );
  }

  void _openCompliance() {
    Navigator.of(context).push<void>(
      hydroPageRoute(ComplianceScreen(api: _api, token: widget.session.token)),
    );
  }

  void _openPointCompliance(Map<String, dynamic> point) {
    final id = _int(point['id']);
    if (id <= 0) return;
    Navigator.of(context).push<void>(
      hydroPageRoute(
        PointComplianceScreen(
          api: _api,
          token: widget.session.token,
          pointId: id,
          pointTitle: point['title']?.toString(),
        ),
      ),
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

  Future<void> _requestSupportFor(Map<String, dynamic> point) async {
    final id = _int(point['id']);
    if (id <= 0 || !mounted) return;
    final title = point['title']?.toString().trim();
    final created = await showSupportTicketSheet(
      context,
      api: _api,
      token: widget.session.token,
      points: _points,
      initialPointId: id,
      initialTitle: title == null || title.isEmpty ? null : 'Soporte · $title',
      lockPoint: true,
    );
    if (created == true && mounted) {
      await _loadOpenTickets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud creada correctamente.')),
      );
    }
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
      constraints: const BoxConstraints(maxWidth: 640),
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
    required this.onNotifications,
    required this.onProfile,
  });

  final String userName;
  final int unreadCount;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          const _BrandCompact(),
          const Spacer(),
          IconButton(
            tooltip: 'Ver avisos',
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

class _DashboardTab extends StatefulWidget {
  const _DashboardTab({
    required this.points,
    required this.openTickets,
    required this.compliance,
    required this.bottomInset,
    required this.onRefresh,
    required this.onOpenSupport,
    required this.onRequestSupport,
    required this.onOpenCompliance,
    required this.onSelectPoint,
  });

  final List<Map<String, dynamic>> points;
  final List<Map<String, dynamic>> openTickets;
  final List<Map<String, dynamic>> compliance;
  final double bottomInset;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenSupport;
  final ValueChanged<Map<String, dynamic>> onRequestSupport;
  final ValueChanged<Map<String, dynamic>> onOpenCompliance;
  final ValueChanged<Map<String, dynamic>> onSelectPoint;

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  _SummaryLens _lens = _SummaryLens.all;
  final GlobalKey _resumenKey = GlobalKey();
  double _resumenHeight = _ModeHandle.height;

  void _syncResumenHeight() {
    final box = _resumenKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if ((box.size.height - _resumenHeight).abs() < 0.5) return;
    setState(() => _resumenHeight = box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncResumenHeight();
    });
    final wide = MediaQuery.sizeOf(context).width >= 980;
    if (!wide) {
      return HydraulicBoard(
        map: (context, toSummary) => _mapView(toSummary),
        summary: (context, toMap) => _summaryView(toMap),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _mapView(null)),
        const SizedBox(width: 1, child: ColoredBox(color: Color(0x1AFFFFFF))),
        SizedBox(width: 380, child: _summaryList()),
      ],
    );
  }

  Widget _mapView(VoidCallback? toSummary) {
    final topSafe = MediaQuery.paddingOf(context).top;
    final resumen = captureResumenInsets(
      bottomInset: widget.bottomInset,
      handleHeight: _resumenHeight,
      gap: _ModeHandle.openGap,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // El painter del mapa pinta TODO el rect; solo el contenido
        // (puntos/tags) respeta safe top + bottom nav.
        CaptureNetworkMap(
          points: widget.points,
          openTickets: widget.openTickets,
          compliance: widget.compliance,
          onPointSelected: widget.onSelectPoint,
          onRequestSupport: widget.onRequestSupport,
          topInset: topSafe + 8,
          bottomInset: widget.bottomInset + (toSummary == null ? 0 : 44),
          // La ficha abierta queda 10 px sobre Resumen. En ancho no hay chip.
          openBottomClearance: toSummary == null ? 8 : resumen.cardClearance,
        ),
        if (toSummary != null)
          Positioned(
            left: 0,
            right: 0,
            // Encima del LiquidNavBar flotante (~66 + padding).
            bottom: resumen.handleBottom,
            child: _ModeHandle(
              key: _resumenKey,
              label: 'Resumen',
              icon: Icons.expand_more,
              onCommit: toSummary,
            ),
          ),
      ],
    );
  }

  Widget _summaryView(VoidCallback toMap) {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: _ModeHandle(
            label: 'Mapa',
            icon: Icons.expand_less,
            upward: true,
            onCommit: toMap,
          ),
        ),
        Expanded(child: _summaryList()),
      ],
    );
  }

  Widget _summaryList() {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: 28 + widget.bottomInset),
          children: [
            if (wide)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Actualizar resumen',
                  onPressed: () => widget.onRefresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ),
            if (widget.points.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: _EmptyState(
                  icon: Icons.water_drop_outlined,
                  title: 'Aún no tienes puntos asignados',
                  message:
                      'Cuando tu cuenta tenga puntos asociados, el resumen aparecerá aquí.',
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _NetworkPanel(
                  points: widget.points,
                  openTickets: widget.openTickets,
                  compliance: widget.compliance,
                  lens: _lens,
                  onLens: (value) => setState(() => _lens = value),
                  onOpenPoint: widget.onSelectPoint,
                  onOpenSupport: widget.onOpenSupport,
                  onOpenCompliance: widget.onOpenCompliance,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeHandle extends StatefulWidget {
  const _ModeHandle({
    super.key,
    required this.label,
    required this.icon,
    required this.onCommit,
    this.upward = false,
  });

  /// Alto de respaldo hasta medir el chip. El layout real manda.
  static const double height = 36;

  /// La ficha abierta queda esta distancia sobre el chip.
  static const double openGap = 10;

  final String label;
  final IconData icon;
  final VoidCallback onCommit;
  final bool upward;

  @override
  State<_ModeHandle> createState() => _ModeHandleState();
}

class _ModeHandleState extends State<_ModeHandle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  var _drag = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool _matches(double velocity) {
    if (widget.upward) return _drag < -36 || velocity < -280;
    return _drag > 36 || velocity > 280;
  }

  Widget _arrow(int index, bool reduce) {
    final phase = reduce ? 0.0 : (_pulse.value + index * 0.22) % 1.0;
    final crest = reduce
        ? (index == 0 ? 1.0 : 0.45)
        : math.sin(phase * math.pi);
    final travel = widget.upward ? -1.0 : 1.0;
    return Transform.translate(
      offset: Offset(0, reduce ? 0 : travel * 6 * crest),
      child: Opacity(
        opacity: (0.25 + 0.75 * crest).clamp(0.0, 1.0),
        child: Icon(widget.icon, size: 20, color: const Color(0xFF8EE6D8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: widget.upward ? 'Volver al mapa' : 'Ver el resumen',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onCommit,
        onVerticalDragStart: (_) => _drag = 0,
        onVerticalDragUpdate: (details) => _drag += details.delta.dy,
        onVerticalDragEnd: (details) {
          if (_matches(details.primaryVelocity ?? 0)) widget.onCommit();
          _drag = 0;
        },
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final wave = reduce
                ? 0.35
                : 0.5 + 0.5 * math.sin(_pulse.value * math.pi * 2);
            return Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF66E0C2,
                  ).withValues(alpha: 0.10 + 0.16 * wave),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 14, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 28,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Transform.translate(
                              offset: Offset(0, widget.upward ? -7 : 7),
                              child: _arrow(1, reduce),
                            ),
                            _arrow(0, reduce),
                          ],
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: const Color(
                            0xFFF4FBFA,
                          ).withValues(alpha: 0.72 + 0.28 * wave),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _SummaryLens { all, attention, dga, sla }

/// Estado general de la red y, en cada punto, la lectura, el aviso y el cumplimiento.
class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel({
    required this.points,
    required this.openTickets,
    required this.compliance,
    required this.lens,
    required this.onLens,
    required this.onOpenPoint,
    required this.onOpenSupport,
    required this.onOpenCompliance,
  });

  final List<Map<String, dynamic>> points;
  final List<Map<String, dynamic>> openTickets;
  final List<Map<String, dynamic>> compliance;
  final _SummaryLens lens;
  final ValueChanged<_SummaryLens> onLens;
  final ValueChanged<Map<String, dynamic>> onOpenPoint;
  final VoidCallback onOpenSupport;
  final ValueChanged<Map<String, dynamic>> onOpenCompliance;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    var online = 0;
    var warnings = 0;
    var incidents = 0;
    var flow = 0.0;
    var flowCount = 0;
    var within = 0;
    var near = 0;
    var over = 0;
    final complianceById = <int, Map<String, dynamic>>{};
    for (final item in compliance) {
      final id = _int(item['point_id']);
      if (id > 0) complianceById[id] = item;
    }
    var dgaPoints = 0;
    var slaCount = 0;
    for (final point in points) {
      switch (pointLinkOf(point)) {
        case PointLink.connected:
          online += 1;
        case PointLink.gap:
          warnings += 1;
        case PointLink.incident:
          incidents += 1;
      }
      final value = _optionalNumber(_map(point['latest_telemetry'])['flow']);
      if (value != null) {
        flow += value;
        flowCount += 1;
      }
      final id = _int(point['id']);
      final item = complianceById[id];
      if (item != null || DgaInfo.tryParse(_map(point['dga'])) != null) {
        dgaPoints += 1;
      }
      switch (_complianceLevel(item)) {
        case 'safe':
          within += 1;
        case 'warning':
          near += 1;
        case 'critical':
          over += 1;
        default:
          break;
      }
      if (_slasForPoint(openTickets, id).isNotEmpty) slaCount += 1;
    }
    final ordered = [
      for (final point in _orderedPoints(points))
        if (_matchesLens(point, lens, complianceById, openTickets)) point,
    ];
    final glow = incidents > 0
        ? const Color(0xFFFF847A)
        : warnings > 0
        ? const Color(0xFFFFC46B)
        : const Color(0xFF66E0C2);
    Widget reading(Map<String, dynamic> point) {
      final id = _int(point['id']);
      final slas = _slasForPoint(openTickets, id);
      final item = complianceById[id];
      return _ReadingRow(
        point: point,
        slas: slas,
        compliance: item,
        onTap: () => _openReadingSheet(
          context,
          point: point,
          slas: slas,
          compliance: item,
          onOpenPoint: onOpenPoint,
          onOpenSupport: onOpenSupport,
          onOpenCompliance: item == null ? null : () => onOpenCompliance(point),
        ),
      );
    }

    return HydroGlass(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _StatusRing(
                online: online,
                warnings: warnings,
                incidents: incidents,
                total: points.length,
                glow: glow,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MixLine(
                      label: 'Conectado',
                      value: online,
                      color: const Color(0xFF66E0C2),
                    ),
                    _MixLine(
                      label: 'Advertencia',
                      value: warnings,
                      color: const Color(0xFFFFC46B),
                    ),
                    _MixLine(
                      label: 'Incidencia',
                      value: incidents,
                      color: const Color(0xFFFF847A),
                    ),
                    if (flowCount > 0 ||
                        within + near + over > 0 ||
                        slaCount > 0) ...[
                      const SizedBox(height: 8),
                      if (flowCount > 0)
                        Text(
                          'Caudal ${_fmtNum(flow)} L/s',
                          style: const TextStyle(
                            color: Color(0xFFE7F4F2),
                            fontSize: 12,
                          ),
                        ),
                      if (within + near + over > 0)
                        Text(
                          'Dentro $within · Cerca $near · Excede $over',
                          style: const TextStyle(
                            color: Color(0xFF9AB0B1),
                            fontSize: 12,
                          ),
                        ),
                      if (slaCount > 0)
                        GestureDetector(
                          onTap: () => _openSupportSheet(
                            context,
                            tickets: openTickets,
                            onOpenSupport: onOpenSupport,
                          ),
                          child: Text(
                            '$slaCount con SLA abierto',
                            style: const TextStyle(
                              color: Color(0xFFFFC46B),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (warnings + incidents > 0 || dgaPoints > 0 || slaCount > 0) ...[
            const SizedBox(height: 12),
            _LensBar(
              lens: lens,
              onLens: onLens,
              attention: warnings + incidents > 0,
              dga: dgaPoints > 0,
              sla: slaCount > 0,
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1, color: Color(0x224C6A6E)),
          if (ordered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Nada en este grupo.',
                style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
              ),
            )
          else
            for (var index = 0; index < ordered.length; index++) ...[
              reading(ordered[index]),
              if (index != ordered.length - 1)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0x184C6A6E),
                ),
            ],
        ],
      ),
    );
  }
}

class _LensBar extends StatelessWidget {
  const _LensBar({
    required this.lens,
    required this.onLens,
    required this.attention,
    required this.dga,
    required this.sla,
  });

  final _SummaryLens lens;
  final ValueChanged<_SummaryLens> onLens;
  final bool attention;
  final bool dga;
  final bool sla;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _lensChip('Todos', _SummaryLens.all),
        if (attention) _lensChip('Atención', _SummaryLens.attention),
        if (dga) _lensChip('DGA', _SummaryLens.dga),
        if (sla) _lensChip('SLA', _SummaryLens.sla),
      ],
    );
  }

  Widget _lensChip(String label, _SummaryLens value) {
    final selected = lens == value;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: () => onLens(value),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF66E0C2) : const Color(0x14F7FBFA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF08211C)
                    : const Color(0xFFD5E6E4),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRing extends StatelessWidget {
  const _StatusRing({
    required this.online,
    required this.warnings,
    required this.incidents,
    required this.total,
    required this.glow,
  });

  final int online;
  final int warnings;
  final int incidents;
  final int total;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    final slices = <(double, Color)>[
      if (online > 0) (online.toDouble(), const Color(0xFF66E0C2)),
      if (warnings > 0) (warnings.toDouble(), const Color(0xFFFFC46B)),
      if (incidents > 0) (incidents.toDouble(), const Color(0xFFFF847A)),
    ];
    final round = slices.length > 1 ? 8.0 : 0.0;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label:
          '$online conectados, $warnings en advertencia, $incidents con incidencia',
      child: SizedBox(
        width: 132,
        height: 132,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      glow.withValues(alpha: 0.28),
                      glow.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  centerSpaceRadius: 42,
                  centerSpaceColor: Colors.transparent,
                  sectionsSpace: slices.length > 1 ? 4 : 0,
                  pieTouchData: PieTouchData(enabled: false),
                  sections: [
                    for (final slice in slices)
                      PieChartSectionData(
                        value: slice.$1,
                        color: slice.$2,
                        radius: 16,
                        showTitle: false,
                        cornerRadius: round,
                      ),
                  ],
                ),
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$total',
                  style: const TextStyle(
                    color: Color(0xFFF4FBFA),
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  total == 1 ? 'punto' : 'puntos',
                  style: const TextStyle(
                    color: Color(0xFF9AB0B1),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MixLine extends StatelessWidget {
  const _MixLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final quiet = value == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: quiet ? color.withValues(alpha: 0.35) : color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: quiet
                    ? const Color(0xFF7E9496)
                    : const Color(0xFFD5E6E4),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              color: quiet ? const Color(0xFF7E9496) : color,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({
    required this.point,
    required this.slas,
    required this.compliance,
    required this.onTap,
  });

  final Map<String, dynamic> point;
  final List<Map<String, dynamic>> slas;
  final Map<String, dynamic>? compliance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final telemetry = _map(point['latest_telemetry']);
    final link = pointLinkOf(point);
    final color = _statusColor(link);
    final surface = _pointIsSurface(point);
    final title = point['title']?.toString() ?? 'Punto';
    final flow = _optionalNumber(telemetry['flow']);
    final level = _optionalNumber(
      telemetry['water_table'] ?? telemetry['nivel'],
    );
    final reading = _formatTimestamp(telemetry['date_time_medition']);
    final reason = _linkReason(point);
    final info = compliance == null
        ? DgaInfo.tryParse(_map(point['dga']))
        : null;
    final measures = [
      reading,
      if (flow != null) '${_fmtNum(flow)} L/s',
      if (level != null) 'nivel ${_fmtNum(level)} m',
    ].join(' · ');
    final slaLine = _slaSummary(slas);
    return Semantics(
      button: true,
      label: '$title, ${reason ?? pointLinkLabel(link)}, $reading',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${surface ? 'Superficial' : 'Pozo'} · ${reason ?? pointLinkLabel(link)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 12, height: 1.3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      measures,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9AB0B1),
                        fontSize: 11,
                      ),
                    ),
                    if (compliance != null) ...[
                      const SizedBox(height: 6),
                      _ComplianceGlance(item: compliance!),
                    ],
                    if (slaLine != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        slaLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _slaIsOverdue(slas.first)
                              ? const Color(0xFFFF847A)
                              : const Color(0xFFFFC46B),
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (info != null) ...[
                      const SizedBox(height: 6),
                      _SoftTag(
                        label: _complianceLabel(info),
                        color: const Color(0xFF8EE6D8),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFF91A8AA),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftTag extends StatelessWidget {
  const _SoftTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ComplianceGlance extends StatelessWidget {
  const _ComplianceGlance({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final level = _complianceLevel(item);
    final color = _complianceColor(level);
    final auth = _optionalNumber(item['authorized_flow']);
    final flow = _optionalNumber(item['flow']);
    final pct = _optionalNumber(item['pct_consumed']);
    final ratio = auth != null && auth > 0 && flow != null
        ? (flow / auth).clamp(0.0, 1.0)
        : pct == null
        ? null
        : (pct / 100).clamp(0.0, 1.0);
    final detail = [
      if (auth != null && auth > 0 && flow != null)
        '${_fmtNum(flow)} / ${_fmtNum(auth)} L/s',
      if (pct != null) 'totalizado ${pct.toStringAsFixed(0)}%',
    ].join(' · ');
    final phrase = _compliancePhrase(level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [phrase, if (detail.isNotEmpty) detail].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (ratio != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: const Color(0x3326383A),
              color: color,
            ),
          ),
        ],
      ],
    );
  }
}

class _SheetFact extends StatelessWidget {
  const _SheetFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

void _openReadingSheet(
  BuildContext context, {
  required Map<String, dynamic> point,
  required List<Map<String, dynamic>> slas,
  required Map<String, dynamic>? compliance,
  required ValueChanged<Map<String, dynamic>> onOpenPoint,
  required VoidCallback onOpenSupport,
  required VoidCallback? onOpenCompliance,
}) {
  final telemetry = _map(point['latest_telemetry']);
  final link = pointLinkOf(point);
  final color = _statusColor(link);
  final surface = _pointIsSurface(point);
  final title = point['title']?.toString() ?? 'Punto';
  final place = [
    _str(point['project_name']),
    _str(point['client_name']),
  ].whereType<String>().join(' · ');
  final flow = _optionalNumber(telemetry['flow']);
  final level = _optionalNumber(telemetry['water_table'] ?? telemetry['nivel']);
  final total = _optionalNumber(telemetry['total'] ?? telemetry['total_raw']);
  final reading = _formatTimestamp(telemetry['date_time_medition']);
  final reason = _linkReason(point);
  final info = DgaInfo.tryParse(_map(point['dga']));
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF102328),
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      final cap = MediaQuery.sizeOf(sheetContext).height * 0.72;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: cap),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${surface ? 'Superficial' : 'Pozo'} · ${reason ?? pointLinkLabel(link)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                if (place.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    place,
                    style: const TextStyle(
                      color: Color(0xFF9AB0B1),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (reason != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    link == PointLink.incident ? 'Incidencia' : 'Advertencia',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    reason,
                    style: const TextStyle(
                      color: Color(0xFFD5E6E4),
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Última lectura',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                _SheetFact(label: 'Hora', value: reading),
                if (flow != null)
                  _SheetFact(label: 'Caudal', value: '${_fmtNum(flow)} L/s'),
                if (level != null)
                  _SheetFact(label: 'Nivel', value: '${_fmtNum(level)} m'),
                if (total != null)
                  _SheetFact(
                    label: 'Totalizador',
                    value: '${_fmtNum(total)} m³',
                  ),
                if (compliance != null || info != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Cumplimiento',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (compliance != null) ...[
                    const SizedBox(height: 8),
                    _ComplianceGlance(item: compliance),
                    if (_optionalNumber(compliance['authorized_total']) != null)
                      _SheetFact(
                        label: 'Total autorizado',
                        value:
                            '${_fmtNum(_optionalNumber(compliance['authorized_total'])!)} m³',
                      ),
                    if (_optionalNumber(compliance['annual_consumption']) !=
                        null)
                      _SheetFact(
                        label: 'Consumo anual',
                        value:
                            '${_fmtNum(_optionalNumber(compliance['annual_consumption'])!)} m³',
                      ),
                    if (_int(_map(compliance['flow_history'])['count']) > 0)
                      _SheetFact(
                        label: 'Sobre el límite',
                        value:
                            '${_int(_map(compliance['flow_history'])['count'])} lecturas',
                      ),
                    if (_int(_map(compliance['near_limit_history'])['count']) >
                        0)
                      _SheetFact(
                        label: 'Cerca del límite',
                        value:
                            '${_int(_map(compliance['near_limit_history'])['count'])} lecturas',
                      ),
                  ],
                  if (info != null)
                    for (final field in info.fields)
                      _SheetFact(label: field.label, value: field.value),
                  if (info != null && info.fields.isEmpty && compliance == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Obra DGA activa.',
                        style: TextStyle(color: Color(0xFFD5E6E4)),
                      ),
                    ),
                ],
                if (slas.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'SLA abierto',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  for (final ticket in slas) _SlaNote(ticket: ticket),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    onOpenPoint(point);
                  },
                  child: const Text('Ver el punto'),
                ),
                if (onOpenCompliance != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      onOpenCompliance();
                    },
                    child: const Text('Ver cumplimiento'),
                  ),
                ],
                if (slas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      onOpenSupport();
                    },
                    child: const Text('Abrir soporte'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

void _openSupportSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> tickets,
  required VoidCallback onOpenSupport,
}) {
  final shown = _sortedSlas(tickets).take(8).toList(growable: false);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF102328),
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      final cap = MediaQuery.sizeOf(sheetContext).height * 0.72;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: cap),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'SLA abierto',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  '${tickets.length} en curso',
                  style: const TextStyle(color: Color(0xFFFFC46B)),
                ),
                const SizedBox(height: 8),
                for (final ticket in shown) _SlaNote(ticket: ticket),
                if (tickets.length > shown.length) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Hay más SLA en soporte.',
                    style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    onOpenSupport();
                  },
                  child: const Text('Abrir soporte'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SlaNote extends StatelessWidget {
  const _SlaNote({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    final title = _str(ticket['title']) ?? 'Solicitud';
    final overdue = _slaIsOverdue(ticket);
    final deadline = _slaDeadline(ticket);
    final clock = deadline == null
        ? null
        : overdue
        ? 'Vencido ${_formatTimestamp(deadline.toIso8601String())}'
        : 'Vence ${_formatTimestamp(deadline.toIso8601String())}';
    final points = ticket['points'];
    final names = points is List
        ? points
              .whereType<Map>()
              .map((item) => _str(item['title']))
              .whereType<String>()
              .join(' · ')
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            [
              'SLA ${_ticketStatusLabel(ticket['status'])}',
              ?clock,
              if (names.isNotEmpty) names,
            ].join(' · '),
            style: TextStyle(
              color: overdue
                  ? const Color(0xFFFF847A)
                  : const Color(0xFFD5E6E4),
              height: 1.35,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

const _openTicketStatuses = [
  'ABIERTO',
  'EN_ANALISIS',
  'EN_ORDEN_TRABAJO',
  'ESPERA_CLIENTE',
  'ESPERA_PROVEEDOR',
];

bool _ticketIsOpen(Map<String, dynamic> ticket) {
  final status = '${ticket['status']}'.toUpperCase();
  return _openTicketStatuses.contains(status);
}

String _ticketStatusLabel(dynamic status) => switch ('$status'.toUpperCase()) {
  'ABIERTO' => 'abierto',
  'EN_ANALISIS' => 'en análisis',
  'EN_ORDEN_TRABAJO' => 'en orden de trabajo',
  'ESPERA_CLIENTE' => 'espera cliente',
  'ESPERA_PROVEEDOR' => 'espera proveedor',
  _ => 'abierto',
};

DateTime? _slaDeadline(Map<String, dynamic> ticket) {
  DateTime? parse(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed?.toLocal();
  }

  final responded = ticket['sla_responded_at'];
  final waitingResponse =
      responded == null || '$responded'.isEmpty || '$responded' == 'null';
  final response = parse(ticket['sla_deadline_response']);
  final resolution = parse(ticket['sla_deadline_resolution']);
  if (waitingResponse && response != null) return response;
  return resolution ?? response;
}

bool _slaIsOverdue(Map<String, dynamic> ticket) {
  final deadline = _slaDeadline(ticket);
  return deadline != null && deadline.isBefore(DateTime.now());
}

List<Map<String, dynamic>> _sortedSlas(List<Map<String, dynamic>> tickets) {
  final copy = [...tickets];
  copy.sort((a, b) {
    final overdueA = _slaIsOverdue(a);
    final overdueB = _slaIsOverdue(b);
    if (overdueA != overdueB) return overdueA ? -1 : 1;
    final left = _slaDeadline(a);
    final right = _slaDeadline(b);
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  });
  return copy;
}

List<Map<String, dynamic>> _slasForPoint(
  List<Map<String, dynamic>> tickets,
  int pointId,
) {
  if (pointId <= 0) return const [];
  return _sortedSlas([
    for (final ticket in tickets)
      if (_ticketIsOpen(ticket) && systemItemMatchesPoint(ticket, pointId))
        ticket,
  ]);
}

/// Motivo concreto de una advertencia o incidencia. Null si el punto está al día.
String? _complianceLevel(Map<String, dynamic>? item) {
  if (item == null) return null;
  final level = _map(item['compliance_warning'])['level']?.toString();
  if (level == null || level.isEmpty || level == 'null') return 'unknown';
  return level;
}

String _compliancePhrase(String? level) => switch (level) {
  'critical' => 'Excede el caudal',
  'warning' => 'Cerca del límite',
  'safe' => 'Dentro del límite',
  _ => 'Sin caudal autorizado',
};

Color _complianceColor(String? level) => switch (level) {
  'critical' => const Color(0xFFFF847A),
  'warning' => const Color(0xFFFFC46B),
  'safe' => const Color(0xFF66E0C2),
  _ => const Color(0xFF9AB0B1),
};

bool _matchesLens(
  Map<String, dynamic> point,
  _SummaryLens lens,
  Map<int, Map<String, dynamic>> complianceById,
  List<Map<String, dynamic>> tickets,
) {
  final id = _int(point['id']);
  return switch (lens) {
    _SummaryLens.all => true,
    _SummaryLens.attention => pointLinkOf(point) != PointLink.connected,
    _SummaryLens.dga =>
      complianceById.containsKey(id) ||
          DgaInfo.tryParse(_map(point['dga'])) != null,
    _SummaryLens.sla => _slasForPoint(tickets, id).isNotEmpty,
  };
}

String? _linkReason(Map<String, dynamic> point) {
  final telemetry = _map(point['latest_telemetry']);
  if (telemetry['is_error'] == true) {
    return 'La última lectura llegó con error';
  }
  final rawDays = telemetry['days_not_connection'];
  final days = rawDays is num
      ? rawDays.toDouble()
      : double.tryParse('$rawDays');
  if (days != null && days > 0) {
    final whole = days.round();
    return whole <= 1
        ? 'Sin conexión hace 1 día'
        : 'Sin conexión hace $whole días';
  }
  final stamp = telemetry['date_time_medition']?.toString();
  if (stamp == null || stamp.isEmpty || stamp == 'null') return 'Sin lectura';
  return null;
}

String? _slaSummary(List<Map<String, dynamic>> slas) {
  if (slas.isEmpty) return null;
  final first = slas.first;
  final deadline = _slaDeadline(first);
  final clock = deadline == null
      ? null
      : _slaIsOverdue(first)
      ? 'vencido'
      : 'vence ${_formatTimestamp(deadline.toIso8601String())}';
  final extra = slas.length > 1 ? ' · +${slas.length - 1}' : '';
  return [
        'SLA ${_ticketStatusLabel(first['status'])}',
        ?clock,
        _str(first['title']) ?? 'Solicitud',
      ].join(' · ') +
      extra;
}

List<Map<String, dynamic>> _orderedPoints(List<Map<String, dynamic>> points) {
  int rank(PointLink link) => switch (link) {
    PointLink.incident => 0,
    PointLink.gap => 1,
    PointLink.connected => 2,
  };
  DateTime? stamp(Map<String, dynamic> point) {
    return DateTime.tryParse(
      _map(point['latest_telemetry'])['date_time_medition']?.toString() ?? '',
    );
  }

  final copy = [...points];
  copy.sort((a, b) {
    final byLink = rank(pointLinkOf(a)).compareTo(rank(pointLinkOf(b)));
    if (byLink != 0) return byLink;
    final left = stamp(a);
    final right = stamp(b);
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  });
  return copy;
}

Color _statusColor(PointLink link) => switch (link) {
  PointLink.connected => const Color(0xFF66E0C2),
  PointLink.gap => const Color(0xFFFFC46B),
  PointLink.incident => const Color(0xFFFF847A),
};

String _complianceLabel(DgaInfo info) {
  final code = info.code;
  if (code != null && code.length <= 16) return 'DGA $code';
  return 'Cumplimiento';
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
            _IncidentBoard(summary: summary),
            const SizedBox(height: 22),
            const _SectionTitle(title: 'Soporte y tickets'),
            if (ticketError != null)
              _InlineError(message: ticketError!, onRetry: onRefresh)
            else if (notifications.isEmpty && loading)
              const _BoneRows(count: 2)
            else if (notifications.isEmpty)
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
            else if (events.isEmpty && loading)
              const _BoneRows(count: 4)
            else if (events.isEmpty)
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
    required this.onOpenAssistant,
    required this.onOpenGeo,
    required this.onOpenAnalysis,
    required this.onOpenReports,
  });

  final VoidCallback onOpenCompliance;
  final VoidCallback onOpenSupport;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenGeo;
  final VoidCallback onOpenAnalysis;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _ActionCard(
        icon: Icons.map_outlined,
        title: 'GEO Smart',
        subtitle: 'Ubicación y estado de tus puntos con GPS',
        color: IkoluColors.cyan,
        onTap: onOpenGeo,
      ),
      _ActionCard(
        icon: Icons.query_stats_rounded,
        title: 'Análisis',
        subtitle: 'Rendimiento y errores de cada punto',
        color: IkoluColors.cyan,
        onTap: onOpenAnalysis,
      ),
      _ActionCard(
        icon: Icons.balance_rounded,
        title: 'DGA / SMA',
        subtitle: 'Cumplimiento, límites autorizados y mediciones',
        color: IkoluColors.cyan,
        onTap: onOpenCompliance,
      ),
      _ActionCard(
        icon: Icons.smart_toy_outlined,
        title: 'Asistente',
        subtitle: 'Consulta a SmartHydro N1: estado, reportes y tickets',
        color: IkoluColors.cyan,
        onTap: onOpenAssistant,
      ),
      _ActionCard(
        icon: Icons.support_agent_rounded,
        title: 'Soporte',
        subtitle: 'Crear y seguir solicitudes para tus puntos',
        color: IkoluColors.cyan,
        onTap: onOpenSupport,
      ),
      _ActionCard(
        icon: Icons.table_view_outlined,
        title: 'Descarga de registros',
        subtitle: 'Consulta y comparte datos de telemetría en CSV',
        color: IkoluColors.cyan,
        onTap: onOpenReports,
      ),
    ];
    return HydroFrame(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final two = constraints.maxWidth >= 720;
          final children = <Widget>[];
          if (!two) {
            for (var i = 0; i < cards.length; i++) {
              children.add(cards[i]);
              if (i != cards.length - 1) {
                children.add(const SizedBox(height: 10));
              }
            }
          } else {
            for (var i = 0; i < cards.length; i += 2) {
              final next = i + 1 < cards.length ? cards[i + 1] : null;
              children.add(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[i]),
                    const SizedBox(width: 10),
                    Expanded(child: next ?? const SizedBox.shrink()),
                  ],
                ),
              );
              children.add(const SizedBox(height: 10));
            }
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: children,
          );
        },
      ),
    );
  }
}

class PointDetailScreen extends StatefulWidget {
  const PointDetailScreen({
    required this.api,
    required this.token,
    required this.point,
    super.key,
  });

  final SmartHydroApi api;
  final String token;
  final Map<String, dynamic> point;

  @override
  State<PointDetailScreen> createState() => _PointDetailScreenState();
}

class _PointDetailScreenState extends State<PointDetailScreen> {
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _replayRecords = const [];
  String? _error;
  String? _replayError;
  bool _loading = true;
  bool _replayLoading = true;
  int _selectedReplayIndex = 0;
  DateTimeRange _replayRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 1)),
    end: DateTime.now(),
  );
  bool _replayCustom = false;
  Timer? _replayTimer;
  CaptureProfile _profile = const CaptureProfile();
  PointVariables _variables = PointVariables.unknownCatalog;
  String? _loggerToken;
  bool _configTelemetry = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadReplay();
    _loadProfile();
  }

  /// Ficha estática + variables del punto. Cada llamada es independiente:
  /// si falla el catálogo de variables, igual se aplica la config del pozo.
  Future<void> _loadProfile() async {
    final id = _int(widget.point['id']);
    Map<String, dynamic>? config;
    var variables = PointVariables.unknownCatalog;
    try {
      config = await widget.api.pointConfig(widget.token, id);
    } catch (_) {
      config = null;
    }
    try {
      final vars = await widget.api.pointVariables(widget.token, id);
      variables = PointVariables.fromJson(vars);
    } catch (_) {
      variables = PointVariables.unknownCatalog;
    }
    if (!mounted) return;
    setState(() {
      if (config != null) {
        _profile = CaptureProfile.fromConfig(config);
        _loggerToken = _str(config['token_service']);
        _configTelemetry = config['is_telemetry'] == true;
      }
      _variables = variables;
    });
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
    setState(() {
      _replayRange = selected;
      _replayCustom = true;
    });
    _loadReplay();
  }

  /// Período que muestra la barra del replay.
  String get _replayLabel {
    if (!_replayCustom) return 'Últimas 24 h';
    final start = _replayRange.start;
    final end = _replayRange.end;
    if (DateUtils.isSameDay(start, end)) return historyShortDate(start);
    return '${start.day} – ${historyShortDate(end)}';
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
    final rawFlow = _optionalNumber(
      selectedRecord?['flow'] ?? telemetry['flow'],
    );
    final rawTotal = _optionalNumber(
      selectedRecord?['total_raw'] ??
          selectedRecord?['total'] ??
          telemetry['total'],
    );
    // Solo lecturas cuya variable está configurada en el punto.
    final liveFlow = _variables.hasFlow ? rawFlow : null;
    final liveTotal = _variables.hasTotal ? rawTotal : null;
    final liveLevel = _variables.hasLevel ? level : null;
    final loggerInfo = LoggerInfo(
      token: _loggerToken,
      model: loggerModelOf(data),
      frequency: _str(data['frecuency'] ?? data['frequency']),
      telemetry: _configTelemetry || data['is_telemetry'] == true,
      variables: _variables.items,
      dga: DgaInfo.tryParse(dga),
    );
    final replayFlows = _replayRecords
        .map((record) => _optionalNumber(record['flow']))
        .whereType<double>();
    final flowMax = replayFlows.isEmpty
        ? null
        : replayFlows.reduce((a, b) => a > b ? a : b);
    final levelRange = (minimumLevel != null && maximumLevel != null)
        ? maximumLevel - minimumLevel
        : 0.0;
    final levelFill = liveLevel == null
        ? null
        : levelRange.abs() < 0.0001
        ? 0.55
        : ((liveLevel - minimumLevel!) / levelRange).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: const Color(0xFF071114),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CaptureStage(
                  levelMeters: liveLevel,
                  levelFill: levelFill,
                  levelMin: _variables.hasLevel ? minimumLevel : null,
                  levelMax: _variables.hasLevel ? maximumLevel : null,
                  flowLitersPerSecond: liveFlow,
                  isSurface: isSurface,
                  link: pointLinkOf(data),
                  profile: _profile,
                  playing: _replayTimer != null,
                  flowMax: _variables.hasFlow && flowMax != null && flowMax > 0
                      ? flowMax
                      : null,
                  totalCubicMeters: liveTotal,
                  loggerInfo: loggerInfo,
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 0, 0),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: const HydroBackButton(backdrop: true),
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _InlineError(message: _error!, onRetry: _load),
                    ),
                  if (_replayError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _InlineError(
                        message: _replayError!,
                        onRetry: _loadReplay,
                      ),
                    ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, (1 - t) * 18),
                        child: child,
                      ),
                    ),
                    child: _PointGlassDock(
                      title: title,
                      subtitle: data['project_name'] as String? ?? '',
                      link: pointLinkOf(data),
                      dgaActive: loggerInfo.dga != null,
                      playing: _replayTimer != null,
                      replayLabel: _replayLabel,
                      canReplay: _replayRecords.length > 1,
                      atStart: _selectedReplayIndex <= 0,
                      onToggleReplay: _toggleReplay,
                      onRestart: _replayRestart,
                      onPickRange: _chooseReplayRange,
                      onHistory: _openHistory,
                      onAnalysis: _openAnalysisForPoint,
                      onCompliance: _openComplianceForPoint,
                      onReports: _openReportsForPoint,
                      onSystem: _openSystemForPoint,
                      onSupport: _createTicketForPoint,
                    ),
                  ),
                  if (_replayTimer != null && _replayRecords.length > 1) ...[
                    const SizedBox(height: 8),
                    _ReplayScrubber(
                      index: _selectedReplayIndex,
                      total: _replayRecords.length,
                      label: startedAt == null
                          ? null
                          : _formatTimestamp(startedAt.toIso8601String()),
                      startLabel: _formatTimestamp(
                        _replayRecords.first['date_time']?.toString(),
                      ),
                      endLabel: _formatTimestamp(
                        _replayRecords.last['date_time']?.toString(),
                      ),
                      onChanged: (value) =>
                          setState(() => _selectedReplayIndex = value.round()),
                    ),
                  ],
                ],
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
        AnalysisScreen(
          api: widget.api,
          token: widget.token,
          points: [widget.point],
        ),
      ),
    );
  }

  void _openComplianceForPoint() {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        PointComplianceScreen(
          api: widget.api,
          token: widget.token,
          pointId: _int(widget.point['id']),
          pointTitle: widget.point['title']?.toString(),
        ),
      ),
    );
  }

  void _openSystemForPoint() {
    Navigator.of(context).push<void>(
      hydroPageRoute(
        PointSystemScreen(
          api: widget.api,
          token: widget.token,
          pointId: _int(widget.point['id']),
          pointTitle: widget.point['title']?.toString() ?? 'Punto',
          points: [widget.point],
        ),
      ),
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
    showPointHistorySheet(
      context,
      api: widget.api,
      token: widget.token,
      pointId: _int(widget.point['id']),
      pointTitle: _str((_detail ?? widget.point)['title']),
      hasFlow: _variables.hasFlow,
      hasLevel: _variables.hasLevel,
      hasTotal: _variables.hasTotal,
      onReplayDay: _replayDay,
    );
  }

  /// Carga un día completo en el visor y lo reproduce desde el inicio.
  Future<void> _replayDay(DateTime day) async {
    _replayTimer?.cancel();
    setState(() {
      _replayTimer = null;
      _replayRange = DateTimeRange(start: day, end: day);
      _replayCustom = true;
    });
    await _loadReplay();
    if (!mounted || _replayRecords.length < 2) return;
    setState(() => _selectedReplayIndex = 0);
    _toggleReplay();
  }
}

/// Barra de reproducción del Replay 4D con botón de inicio y efecto hover.
class _PointGlassDock extends StatelessWidget {
  const _PointGlassDock({
    required this.title,
    required this.subtitle,
    required this.link,
    required this.dgaActive,
    required this.playing,
    required this.replayLabel,
    required this.canReplay,
    required this.atStart,
    required this.onToggleReplay,
    required this.onRestart,
    required this.onPickRange,
    required this.onHistory,
    required this.onAnalysis,
    required this.onCompliance,
    required this.onReports,
    required this.onSystem,
    required this.onSupport,
  });

  final String title;
  final String subtitle;
  final PointLink link;
  final bool dgaActive;
  final bool playing;
  final String replayLabel;
  final bool canReplay;
  final bool atStart;
  final VoidCallback onToggleReplay;
  final VoidCallback onRestart;
  final VoidCallback onPickRange;
  final VoidCallback onHistory;
  final VoidCallback onAnalysis;
  final VoidCallback onCompliance;
  final VoidCallback onReports;
  final VoidCallback onSystem;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    final linkColor = switch (link) {
      PointLink.connected => IkoluColors.connected,
      PointLink.gap => const Color(0xFFFFC46B),
      PointLink.incident => const Color(0xFFFF847A),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F2227).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: linkColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pointLinkLabel(link),
                    style: TextStyle(
                      color: linkColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (dgaActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: IkoluColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'DGA',
                      style: TextStyle(
                        color: IkoluColors.cyan,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // Fila 1: el replay del punto, con su acción principal destacada.
            Row(
              children: [
                Expanded(
                  child: _ReplayPill(
                    playing: playing,
                    label: replayLabel,
                    onTap: canReplay ? onToggleReplay : null,
                  ),
                ),
                const SizedBox(width: 8),
                _RoundAction(
                  icon: Icons.skip_previous_rounded,
                  tooltip: 'Volver al inicio',
                  onTap: !atStart && canReplay ? onRestart : null,
                ),
                const SizedBox(width: 6),
                _RoundAction(
                  icon: Icons.date_range_rounded,
                  tooltip: 'Elegir rango',
                  onTap: onPickRange,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Fila 2: herramientas del punto, repartidas a lo ancho.
            Row(
              children: [
                Expanded(
                  child: _DockTile(
                    icon: Icons.history_rounded,
                    label: 'Historial',
                    onTap: onHistory,
                  ),
                ),
                Expanded(
                  child: _DockTile(
                    icon: Icons.query_stats_rounded,
                    label: 'Análisis',
                    onTap: onAnalysis,
                  ),
                ),
                Expanded(
                  child: _DockTile(
                    icon: Icons.verified_outlined,
                    label: 'Cumplim.',
                    onTap: onCompliance,
                  ),
                ),
                Expanded(
                  child: _DockTile(
                    icon: Icons.table_view_outlined,
                    label: 'Registros',
                    onTap: onReports,
                  ),
                ),
                Expanded(
                  child: _DockTile(
                    icon: Icons.sensors_outlined,
                    label: 'Sistema',
                    onTap: onSystem,
                  ),
                ),
                Expanded(
                  child: _DockTile(
                    icon: Icons.support_agent_rounded,
                    label: 'Soporte',
                    onTap: onSupport,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Acción principal del replay: cápsula con relleno suave y su estado.
class _ReplayPill extends StatelessWidget {
  const _ReplayPill({
    required this.playing,
    required this.label,
    required this.onTap,
  });

  final bool playing;

  /// Período cargado en el visor (`Últimas 24 h`, `Vie 9 oct`…).
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    const accent = IkoluColors.cyan;
    return Material(
      color: accent.withValues(alpha: enabled ? (playing ? 0.26 : 0.16) : 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  size: 20,
                  color: accent.withValues(alpha: enabled ? 1 : 0.4),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: playing ? 'Pausar' : 'Reproducir'),
                      TextSpan(
                        text: '  ·  $label',
                        style: TextStyle(
                          color: const Color(
                            0xFFE8F2F1,
                          ).withValues(alpha: enabled ? 0.8 : 0.35),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent.withValues(alpha: enabled ? 1 : 0.4),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: enabled ? 0.07 : 0.03),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(
              icon,
              size: 19,
              color: const Color(
                0xFFE8F2F1,
              ).withValues(alpha: enabled ? 0.9 : 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

/// Herramienta del punto: icono y rótulo, sin color propio.
class _DockTile extends StatelessWidget {
  const _DockTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: const Color(
                0xFFE8F2F1,
              ).withValues(alpha: enabled ? 0.9 : 0.35),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: const Color(
                    0xFFE8F2F1,
                  ).withValues(alpha: enabled ? 0.78 : 0.35),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayScrubber extends StatelessWidget {
  const _ReplayScrubber({
    required this.index,
    required this.total,
    required this.onChanged,
    this.label,
    required this.startLabel,
    required this.endLabel,
  });

  final int index;
  final int total;
  final String? label;
  final String startLabel;
  final String endLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F2227).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
        child: Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: IkoluColors.cyan,
                inactiveTrackColor: const Color(0xFF26383A),
                thumbColor: IkoluColors.cyan,
                overlayColor: const Color(0xFF00C8FF).withValues(alpha: 0.2),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: index.toDouble(),
                min: 0,
                max: (total - 1).toDouble(),
                divisions: total - 1,
                label: label,
                onChanged: onChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    startLabel,
                    style: const TextStyle(
                      color: Color(0xFF8FA8A8),
                      fontSize: 10.5,
                    ),
                  ),
                  Text(
                    '${index + 1}/$total',
                    style: const TextStyle(
                      color: IkoluColors.cyan,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    endLabel,
                    style: const TextStyle(
                      color: Color(0xFF8FA8A8),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                    fontSize: 9.5,
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
                    fontSize: 9.5,
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

class _BoneRows extends StatelessWidget {
  const _BoneRows({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => HydroShimmer(
    child: Column(
      children: [for (var i = 0; i < count; i++) HydroBoneRow(seed: i)],
    ),
  );
}

/// Reserva el mismo hueco que el mapa: el visor arriba y el pase al resumen abajo.
class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return HydroShimmer(
      child: Column(
        children: const [
          Expanded(child: ColoredBox(color: Color(0x0FFFFFFF))),
          SizedBox(height: 52),
        ],
      ),
    );
  }
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

String? _str(dynamic value) {
  if (value == null) return null;
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
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

bool _pointIsSurface(Map<String, dynamic> point) {
  final dga = point['dga'];
  if (dga is Map) {
    return '${dga['type_dga']}'.toUpperCase() == 'SUPERFICIAL';
  }
  return '${point['type_dga']}'.toUpperCase() == 'SUPERFICIAL';
}

String _fmtNum(double value) {
  final abs = value.abs();
  if (abs >= 100) return value.toStringAsFixed(0);
  if (abs >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
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
