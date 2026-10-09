import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthydro_app/app.dart';

void main() {
  testWidgets('solicita autenticación antes de mostrar datos de cuenta', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SmartHydroApp()));

    expect(find.text('Bienvenido de vuelta'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('valida los campos vacíos antes de llamar a la API', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SmartHydroApp()));

    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
  });
}
