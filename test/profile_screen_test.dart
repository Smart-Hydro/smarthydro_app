import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/core/api/smarthydro_api.dart';
import 'package:smarthydro_app/features/profile/profile_screen.dart';

Widget _profile({
  required Size size,
  bool notify = true,
  ValueChanged<bool>? onNotify,
  VoidCallback? onSignOut,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: true),
    child: MaterialApp(
      home: Scaffold(
        body: ProfileScreen(
          api: SmartHydroApi(),
          session: const SmartHydroSession(
            token: 'token',
            user: {
              'first_name': 'Ana',
              'last_name': 'Rojas',
              'email': 'ana@smarthydro.app',
              'username': 'ana',
            },
          ),
          pointCount: 12,
          notifyEmail: notify,
          savingEmailPreference: false,
          onNotifyEmailChanged: onNotify ?? (_) {},
          onUserUpdated: (_) {},
          onSignOut: onSignOut ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('en teléfono la cuenta queda en una columna alineada', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_profile(size: const Size(390, 844)));
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-layout-narrow')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-layout-wide')), findsNothing);
    expect(find.text('Cuenta'), findsOneWidget);
    expect(find.text('Ana Rojas'), findsOneWidget);
    expect(find.text('@ana'), findsWidgets);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('puntos en la red'), findsOneWidget);
    expect(find.text('Información personal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en escritorio persona y contraseña van en dos columnas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_profile(size: const Size(1200, 900)));
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-layout-wide')), findsOneWidget);
    final personal = tester.getTopLeft(find.text('Información personal'));
    final password = tester.getTopLeft(find.text('Contraseña'));
    expect(password.dx, greaterThan(personal.dx + 200));
    expect((password.dy - personal.dy).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('editar valida el nombre y cancelar vuelve a la lectura', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_profile(size: const Size(390, 900)));
    await tester.pump();

    await tester.tap(find.text('Editar'));
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'Nombre'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), '');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pump();
    expect(find.text('Ingresa tu nombre.'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    expect(find.text('Ana'), findsWidgets);
    expect(find.widgetWithText(TextFormField, 'Nombre'), findsNothing);
  });

  testWidgets('la contraseña corta y el cierre de sesión responden', (
    tester,
  ) async {
    var signedOut = false;
    var notify = true;
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _profile(
        size: const Size(390, 900),
        onNotify: (value) => notify = value,
        onSignOut: () => signedOut = true,
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Cambiar contraseña'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña actual'),
      'actual',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nueva contraseña'),
      'corta',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar contraseña'),
      'corta',
    );
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pump();
    expect(find.text('Usa al menos 8 caracteres.'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(notify, isFalse);

    await tester.tap(find.byKey(const ValueKey('profile-sign-out')));
    await tester.pump();
    expect(signedOut, isTrue);
    expect(tester.takeException(), isNull);
  });
}
