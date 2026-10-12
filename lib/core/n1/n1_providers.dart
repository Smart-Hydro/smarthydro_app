import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'n1_api.dart';
import 'n1_config.dart';

final n1ConfigProvider = Provider<N1Config>((ref) {
  return N1Config.fromEnvironment();
});

final n1ApiProvider = Provider<N1Api>((ref) {
  return N1Api(config: ref.watch(n1ConfigProvider));
});
