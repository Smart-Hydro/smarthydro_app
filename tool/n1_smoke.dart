// Smoke N1 desde el cliente de la app (sin UI).
// Uso: dart run tool/n1_smoke.dart
import 'package:smarthydro_app/core/n1/n1_api.dart';
import 'package:smarthydro_app/core/n1/n1_config.dart';
import 'package:smarthydro_app/core/n1/n1_models.dart';

Future<void> main() async {
  final config = N1Config.fromEnvironment();
  final api = N1Api(config: config);
  stdout('N1 URL: ${config.webAppUrl}');
  stdout('configured: ${api.isConfigured}');

  final health = await api.health();
  stdout('health: ok=${health.ok} version=${health.version} ops=${health.ops}');
  if (!health.ok) {
    throw StateError('health no ok');
  }

  final caps = await api.capabilitiesPublic();
  final list = caps['capabilities'];
  final n = list is List ? list.length : 0;
  stdout(
    'capabilities(GET): ok=${caps['ok']} version=${caps['version']} count=$n',
  );
  if (caps['ok'] != true || n == 0) {
    throw StateError('capabilities vacío o no ok');
  }

  // ping requiere Token SmartHydro real; sin él esperamos unauthorized
  // tras POST→302→GET echo (el cliente no debe re-POSTear el Location).
  try {
    final ping = await api.ping(
      token: 'smoke-invalid',
      requester: 'smoke@smarthydro.cl',
    );
    stdout('ping: ok=${ping.ok} via=${ping.via} email unexpected success');
  } on N1ApiException catch (e) {
    stdout('ping (sin token válido): code=${e.code} msg=${e.message}');
    if (e.code != 'unauthorized') {
      throw StateError(
        'ping debía fallar con unauthorized (POST→echo), got ${e.code}',
      );
    }
  }

  stdout('SMOKE OK');
}

void stdout(String s) {
  // ignore: avoid_print
  print(s);
}
