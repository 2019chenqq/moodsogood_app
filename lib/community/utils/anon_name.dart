import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnonNameService {
  static const _anonNamePrefsKey = 'communityAnonName';

  static const List<String> _animals = [
    '星狐',
    '雨鯨',
    '夜貓',
    '白鷺',
    '海獺',
    '松鼠',
    '風鹿',
    '山雀',
    '灰狼',
    '雲兔',
    '雪豹',
    '月貂',
    '霧鴞',
    '海豚',
    '石虎',
    '鯨歌',
    '晨鴿',
    '岩羊',
    '霜兔',
    '光鹿',
  ];

  static const List<String> _blockedWords = [
    '笨',
    '蠢',
    '醜',
    '死',
    '垃圾',
    '廢物',
    '渣',
    '幹',
    '靠北',
    '傻',
    '白痴',
    '智障',
    '弱智',
    '狗屎',
    '王八',
  ];

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_anonNamePrefsKey)?.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (existing != null && existing.isNotEmpty && !_isBadName(existing, user)) {
      return existing;
    }

    final generated = _generateName(user);
    await prefs.setString(_anonNamePrefsKey, generated);
    return generated;
  }

  static String _generateName(User? user) {
    final seedBase = (user?.uid ?? DateTime.now().millisecondsSinceEpoch.toString()).hashCode;
    var seed = seedBase.abs();

    for (var i = 0; i < 50; i += 1) {
      final animal = _animals[seed % _animals.length];
      final number = 100 + (seed % 900);
      final name = '$animal$number';

      if (!_isBadName(name, user)) {
        return name;
      }

      seed = (seed * 31 + i + 7).abs();
    }

    return '匿名者${seedBase.abs() % 1000}';
  }

  static bool _isBadName(String name, User? user) {
    final normalized = _normalize(name);

    for (final bad in _blockedWords) {
      if (normalized.contains(_normalize(bad))) return true;
    }

    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      if (normalized.contains(_normalize(displayName))) return true;
    }

    final email = user?.email;
    if (email != null && email.contains('@')) {
      final localPart = email.split('@').first.trim();
      if (localPart.isNotEmpty && normalized.contains(_normalize(localPart))) return true;
    }

    return false;
  }

  static String _normalize(String input) {
    return input.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }
}
