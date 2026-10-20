import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Un turno del chat N1. [role] es user, assistant o system.
class N1ChatTurn {
  const N1ChatTurn({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, String> toJson() => {'role': role, 'text': text};

  factory N1ChatTurn.fromJson(Map<String, dynamic> json) {
    return N1ChatTurn(
      role: '${json['role'] ?? 'assistant'}',
      text: '${json['text'] ?? ''}',
    );
  }
}

/// Sesión estable y bitácora local por usuario. N1 usa el mismo
/// session_id para recordar el hilo; la app guarda el texto.
class N1Memory {
  N1Memory._();

  static String sessionId({int? userId, String? email}) {
    if (userId != null) return 'sh-app-$userId';
    final who = email?.trim().toLowerCase() ?? '';
    if (who.isNotEmpty) return 'sh-app-$who';
    return 'sh-app-anon';
  }

  static String storageKeyFor(int? userId) =>
      'smarthydro.n1.chat.${userId ?? 'anon'}';

  static Future<List<N1ChatTurn>> load(int? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKeyFor(userId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) N1ChatTurn.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(int? userId, List<N1ChatTurn> turns) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKeyFor(userId),
        jsonEncode([for (final turn in turns) turn.toJson()]),
      );
    } catch (_) {}
  }

  static Future<void> append(int? userId, N1ChatTurn turn) async {
    final turns = [...await load(userId), turn];
    await save(userId, turns);
  }
}
