import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

class HistoryStore {
  static const int maxItems = 5;

  static String scopedKey(String key, {String? userKey}) {
    if (userKey == null || userKey.isEmpty) return key;
    return "${userKey}::$key";
  }

  static Future<List<String>> clearLegacyHistory(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    final removed = <String>[];
    for (final key in keys) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
        removed.add(key);
      }
    }
    return removed;
  }

  static String normalizeValue(String value) {
    final cleaned = value
        .replaceAll("\uFFFD", "")
        // Remove control chars and bidi marks that can render as gibberish.
        .replaceAll(RegExp(r"[\u0000-\u001F\u007F]"), "")
        .replaceAll(RegExp(r"[\u200E\u200F\u202A-\u202E\u2066-\u2069]"), "");
    return cleaned.trim();
  }

  static Future<List<String>> getHistory(String key, {String? userKey}) async {
    final prefs = await SharedPreferences.getInstance();
    final scoped = scopedKey(key, userKey: userKey);
    final raw = prefs.getString(scoped);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final list = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    final sanitized = list.map(normalizeValue).where((e) => e.isNotEmpty).toList();
    bool differs = sanitized.length != list.length;
    if (!differs) {
      for (int i = 0; i < list.length; i++) {
        if (list[i] != sanitized[i]) {
          differs = true;
          break;
        }
      }
    }
    if (differs) {
      await prefs.setString(scoped, jsonEncode(sanitized));
    }
    return sanitized;
  }

  static Future<void> addValue(String key, String value, {String? userKey}) async {
    final trimmed = normalizeValue(value);
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = await getHistory(key, userKey: userKey);
    final deduped = existing.where((e) => e.toLowerCase() != trimmed.toLowerCase()).toList();
    final updated = [trimmed, ...deduped];
    final limited = updated.take(maxItems).toList();
    final scoped = scopedKey(key, userKey: userKey);
    await prefs.setString(scoped, jsonEncode(limited));
  }
}
