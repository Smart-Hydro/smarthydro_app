import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/app.dart';

void main() {
  testWidgets('solicita autenticación antes de mostrar datos de cuenta', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SmartHydroApp()));
    // WaterAtmosphere loops forever; advance past staggered HydroEntrance.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('Control de Captaciones'), findsOneWidget);
    expect(find.text('Correo corporativo'), findsOneWidget);
    expect(find.text('Contraseña de acceso'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('valida los campos vacíos antes de llamar a la API', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SmartHydroApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
  });
}
