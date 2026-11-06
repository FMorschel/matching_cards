import 'package:shared_preferences/shared_preferences.dart';

/// Small things worth remembering between launches. Every call survives
/// storage being unavailable (private windows, blocked site data).
class Prefs {
  static const _nameKey = 'player_name';
  static const _tokenPrefix = 'token_';

  static Future<String> loadName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_nameKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, name);
    } catch (_) {}
  }

  static Future<String?> loadToken(String hostKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_tokenPrefix$hostKey');
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveToken(String hostKey, String? token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token == null) {
        await prefs.remove('$_tokenPrefix$hostKey');
      } else {
        await prefs.setString('$_tokenPrefix$hostKey', token);
      }
    } catch (_) {}
  }
}
