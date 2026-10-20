import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthydro_app/core/n1/n1_memory.dart';

void main() {
  test('la sesión N1 es estable por usuario', () {
    expect(N1Memory.sessionId(userId: 7), 'sh-app-7');
    expect(N1Memory.sessionId(userId: 7), N1Memory.sessionId(userId: 7));
    expect(
      N1Memory.sessionId(email: 'Ana@Empresa.cl'),
      'sh-app-ana@empresa.cl',
    );
    expect(N1Memory.sessionId(), 'sh-app-anon');
  });

  test('la bitácora queda guardada por usuario', () async {
    SharedPreferences.setMockInitialValues({});
    await N1Memory.save(7, const [
      N1ChatTurn(role: 'user', text: 'cómo está P4'),
      N1ChatTurn(role: 'assistant', text: 'P4 está en línea'),
    ]);
    expect(await N1Memory.load(8), isEmpty);
    final turns = await N1Memory.load(7);
    expect(turns, hasLength(2));
    expect(turns.first.text, 'cómo está P4');
    expect(turns.last.role, 'assistant');
  });
}
