import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/smarthydro_api.dart';
import 'session_store.dart';

final smartHydroApiProvider = Provider<SmartHydroApi>((ref) {
  return SmartHydroApi();
});

final sessionStoreProvider = Provider<SessionStore>((ref) {
  return const SessionStore();
});

/// Sesión lista para pintar. [ready] es falso mientras se lee el almacenamiento.
class SessionSnapshot {
  const SessionSnapshot._({required this.ready, this.session});

  const SessionSnapshot.restoring() : this._(ready: false);

  const SessionSnapshot.signedOut() : this._(ready: true);

  const SessionSnapshot.signedIn(SmartHydroSession this.session)
    : ready = true;

  final bool ready;
  final SmartHydroSession? session;
}

class SessionNotifier extends Notifier<SessionSnapshot> {
  @override
  SessionSnapshot build() {
    if (kIsWeb) {
      final session = ref.read(sessionStoreProvider).readLocal();
      return session == null
          ? const SessionSnapshot.signedOut()
          : SessionSnapshot.signedIn(session);
    }
    unawaited(_restore());
    return const SessionSnapshot.restoring();
  }

  Future<void> _restore() async {
    SmartHydroSession? session;
    try {
      session = await ref
          .read(sessionStoreProvider)
          .load()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      session = null;
    }
    if (!ref.mounted) return;
    state = session == null
        ? const SessionSnapshot.signedOut()
        : SessionSnapshot.signedIn(session);
  }

  Future<void> signIn(SmartHydroSession session) async {
    try {
      await ref.read(sessionStoreProvider).save(session);
    } catch (_) {
      // La sesión igual entra. Un fallo de disco no puede dejar la pantalla vacía.
    }
    if (!ref.mounted) return;
    state = SessionSnapshot.signedIn(session);
  }

  Future<void> updateUser(Map<String, dynamic> user) async {
    final current = state.session;
    if (current == null) return;
    final next = SmartHydroSession(token: current.token, user: user);
    try {
      await ref.read(sessionStoreProvider).save(next);
    } catch (_) {}
    if (!ref.mounted) return;
    state = SessionSnapshot.signedIn(next);
  }

  Future<void> signOut() async {
    state = const SessionSnapshot.signedOut();
    try {
      await ref.read(sessionStoreProvider).clear();
    } catch (_) {}
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionSnapshot>(
  SessionNotifier.new,
);
