import 'package:flutter/material.dart';
import 'package:smarthydro_app/features/dashboard/point_link.dart';
import 'package:smarthydro_app/features/dashboard/widgets/portfolio_network.dart';
import 'package:smarthydro_app/shared/widgets/hydro_glass.dart';
import 'package:smarthydro_app/shared/widgets/workstation_backdrop.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DashboardPreviewApp());
}

class DashboardPreviewApp extends StatelessWidget {
  const DashboardPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF071114),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF66E0C2),
          surface: Color(0xFF12252A),
        ),
      ),
      home: const _PreviewHome(),
    );
  }
}

class _PreviewHome extends StatelessWidget {
  const _PreviewHome();

  static final points = <Map<String, dynamic>>[
    {
      'title': 'Pozo Norte',
      'type_dga': 'SUBTERRANEO',
      'project_name': 'Fundo Los Robles',
      'latest_telemetry': {
        'date_time_medition': DateTime.now().toIso8601String(),
        'days_not_connection': 0,
        'flow': 12.4,
      },
    },
    {
      'title': 'Canal Sur',
      'type_dga': 'SUPERFICIAL',
      'project_name': 'Estación Río',
      'latest_telemetry': {'is_error': true, 'flow': 0},
    },
    {
      'title': 'Pozo Este',
      'type_dga': 'SUBTERRANEO',
      'project_name': 'Sector B',
      'latest_telemetry': {
        'date_time_medition': DateTime.now()
            .subtract(const Duration(days: 3))
            .toIso8601String(),
        'days_not_connection': 3,
        'flow': 2.1,
      },
    },
    {
      'title': 'Pozo Valle',
      'type_dga': 'SUBTERRANEO',
      'project_name': 'Valle Central',
      'latest_telemetry': {
        'date_time_medition': DateTime.now().toIso8601String(),
        'days_not_connection': 0,
        'flow': 8.7,
      },
    },
    {
      'title': 'Captación Humedal',
      'type_dga': 'SUPERFICIAL',
      'project_name': 'Humedal Norte',
      'latest_telemetry': {
        'date_time_medition': DateTime.now().toIso8601String(),
        'days_not_connection': 0,
        'flow': 3.2,
      },
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const WorkstationBackdrop(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                PortfolioNetwork(points: points, onPointSelected: (_) {}),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in [
                      ('Puntos', '5', const Color(0xFF66E0C2)),
                      ('En línea', '3', const Color(0xFF66E0C2)),
                      ('Avisos', '1', const Color(0xFFFFC46B)),
                      ('Tensión', '1', const Color(0xFFFF847A)),
                    ])
                      SizedBox(
                        width: 90,
                        child: HydroGlass(
                          padding: const EdgeInsets.all(12),
                          radius: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$1,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFA9BFC0),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.$2,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: item.$3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 92,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final action in [
                        (
                          Icons.notifications_active_outlined,
                          'Avisos',
                          'Tickets',
                        ),
                        (Icons.query_stats_rounded, 'Análisis', '7/30 días'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: SizedBox(
                            width: 160,
                            child: HydroGlass(
                              padding: const EdgeInsets.all(14),
                              radius: 18,
    
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    action.$1,
                                    color: const Color(0xFF66E0C2),
                                  ),
                                  const Spacer(),
                                  Text(
                                    action.$2,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    action.$3,
                                    style: const TextStyle(
                                      color: Color(0xFF91A8AA),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Captaciones',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                for (final point in points.take(3)) ...[
                  HydroGlass(
                    padding: const EdgeInsets.all(12),
                    radius: 18,
                    child: Row(
                      children: [
                        MiniIsoWell(
                          link: pointLinkOf(point),
                          isSurface:
                              '${point['type_dga']}'.toUpperCase() ==
                              'SUPERFICIAL',
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                point['title'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                point['project_name'] as String,
                                style: const TextStyle(
                                  color: Color(0xFFA9BFC0),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
