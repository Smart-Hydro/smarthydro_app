import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthydro_app/app.dart';

Future<void> _pumpLogin(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const ProviderScope(child: SmartHydroApp()));
  await tester.pump();
}

void main() {
  testWidgets(
    'muestra la pantalla de login antes de cualquier dato de cuenta',
    (tester) async {
      await _pumpLogin(tester);

      expect(find.text('Control de Captaciones'), findsOneWidget);
      expect(find.text('Correo corporativo'), findsOneWidget);
      expect(find.text('Contraseña de acceso'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
    },
  );

  testWidgets('valida los campos vacíos antes de llamar a la API', (
    tester,
  ) async {
    await _pumpLogin(tester);

    // El lockup de marca hace más alto el formulario: hay que hacerlo
    // visible antes de pulsar (como haría un usuario al hacer scroll).
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
  });

  testWidgets('ofrece recuperación de clave desde el login', (tester) async {
    await _pumpLogin(tester);

    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
  });
}
