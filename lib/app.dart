import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_env.dart';
import 'core/brand.dart';
import 'core/session/session_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/live_dashboard_screen.dart';
import 'shared/ui/hydro_ui.dart';
import 'shared/widgets/workstation_backdrop.dart';

class SmartHydroApp extends ConsumerWidget {
  const SmartHydroApp({super.key});

  static const _ocean = WorkstationBackdrop.base;
  static const _surface = Color(0xFF12252A);
  static final _navigatorKey = GlobalKey<NavigatorState>();
  static final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(sessionProvider);
    // Si la sesión entra, sale o expira con pantallas apiladas (detalle,
    // reportes...), no quedan rutas huérfanas con un token inválido.
    ref.listen(sessionProvider, (previous, next) {
      if (previous?.session?.token == next.session?.token) return;
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      if (next.expired) {
        _messengerKey.currentState
          ?..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('Tu sesión expiró. Vuelve a ingresar.'),
            ),
          );
      }
    });
    final scheme = ColorScheme.fromSeed(
      seedColor: IkoluColors.cyan,
      brightness: Brightness.dark,
      surface: _surface,
    );

    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'Ikolu · Smart Hydro',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            const WorkstationBackdrop(),
            if (child != null) Positioned.fill(child: child),
            if (AppEnv.isStaging)
              const Positioned(
                top: 10,
                right: 12,
                child: IgnorePointer(
                  child: Material(
                    color: Color(0xCC102226),
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        'Staging',
                        style: TextStyle(
                          color: Color(0xFF7EE0D0),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.transparent,
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
      home: _buildHome(auth),
    );
  }

  Widget _buildHome(SessionSnapshot auth) {
    if (!auth.ready) {
      return const Scaffold(
        key: ValueKey('restoring-session'),
        backgroundColor: _ocean,
        body: SizedBox.expand(),
      );
    }
    final session = auth.session;
    return AnimatedSwitcher(
      duration:
          WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .disableAnimations
          ? Duration.zero
          : HydroMotion.page,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: session == null
          ? const LoginScreen(key: ValueKey('login'))
          // Por token: editar el perfil cambia el usuario, no la sesión, y
          // no debe remontar el dashboard ni devolverlo a IoT.
          : LiveDashboardScreen(
              key: ValueKey('dashboard-${session.token}'),
              session: session,
            ),
    );
  }
}
