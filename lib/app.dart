import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/smarthydro_api.dart';
import 'core/brand.dart';
import 'core/session/session_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/live_dashboard_screen.dart';
import 'shared/ui/hydro_ui.dart';

class SmartHydroApp extends ConsumerWidget {
  const SmartHydroApp({super.key});

  static const _ocean = Color(0xFF0B171B);
  static const _surface = Color(0xFF12252A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final scheme = ColorScheme.fromSeed(
      seedColor: IkoluColors.cyan,
      brightness: Brightness.dark,
      surface: _surface,
    );

    return MaterialApp(
      // Al cambiar el estado de sesión se reinicia el navegador raíz: si la
      // sesión expira con pantallas apiladas (detalle, reportes...), no
      // quedan rutas huérfanas sobre el login con un token inválido.
      key: ValueKey(session != null),
      title: 'Ikolu · Smart Hydro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _ocean,
        cardColor: _surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 4,
          titleTextStyle: HydroText.title,
          iconTheme: IconThemeData(color: Color(0xFFC9D8D8)),
        ),
        actionIconTheme: ActionIconThemeData(
          backButtonIconBuilder: (_) => const Icon(Icons.arrow_back_rounded),
        ),
        dividerColor: Colors.white.withValues(alpha: 0.08),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFE8F2F1),
          displayColor: const Color(0xFFE8F2F1),
        ),
      ),
      home: _buildHome(session),
    );
  }

  Widget _buildHome(SmartHydroSession? session) {
    return AnimatedSwitcher(
      duration:
          WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: session == null
          ? const LoginScreen(key: ValueKey('login'))
          : LiveDashboardScreen(
              key: ValueKey('dashboard-${session.hashCode}'),
              session: session,
            ),
    );
  }
}
