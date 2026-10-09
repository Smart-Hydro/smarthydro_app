import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/smarthydro_api.dart';

final smartHydroApiProvider = Provider<SmartHydroApi>((ref) {
  return SmartHydroApi();
});

class SessionNotifier extends Notifier<SmartHydroSession?> {
  @override
  SmartHydroSession? build() => null;

  void signIn(SmartHydroSession session) => state = session;

  void updateUser(Map<String, dynamic> user) {
    final current = state;
    if (current == null) return;
    state = SmartHydroSession(token: current.token, user: user);
  }

  void signOut() => state = null;
}

final sessionProvider = NotifierProvider<SessionNotifier, SmartHydroSession?>(
  SessionNotifier.new,
);
