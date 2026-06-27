import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../utils/firebase_sync_config.dart';

class DrugDictItem {
  final List<String> zhNames;
  final String en;
  final List<String> alias;
  final String dose;
  final String form;

  DrugDictItem({
    required this.zhNames,
    required this.en,
    required this.alias,
    required this.dose,
    required this.form,
  });

  String get zh => zhNames.isEmpty ? '' : zhNames.first;

  factory DrugDictItem.fromJson(Map<String, dynamic> j) {
    final zhRaw = j['zh'];
    final zhNames = zhRaw is List
        ? zhRaw
            .map((x) => x.toString().trim())
            .where((x) => x.isNotEmpty)
            .toList()
        : zhRaw is String
            ? zhRaw
                .split(RegExp(r'[,/|]'))
                .map((x) => x.trim())
                .where((x) => x.isNotEmpty)
                .toList()
            : <String>[];

    return DrugDictItem(
      zhNames: zhNames,
      en: (j['en'] ?? '').toString(),
      alias: (j['alias'] is List)
          ? (j['alias'] as List).map((x) => x.toString()).toList()
          : const [],
      dose: (j['dose'] ?? '').toString(),
      form: (j['form'] ?? '').toString(),
    );
  }
}

class DrugSuggestion {
  final String zh;
  final String en;
  final String dose;
  final String form;
  final String source; // 'seed' or 'user'
  final int score;

  DrugSuggestion({
    required this.zh,
    required this.en,
    this.dose = '',
    this.form = '',
    required this.source,
    required this.score,
  });
}

class DrugDictionaryService {
  DrugDictionaryService._();

  static final DrugDictionaryService instance = DrugDictionaryService._();

  bool _loaded = false;
  final List<DrugDictItem> _seed = [];

  // 使用者自訂字典快取：key(normalizedZh) -> en
  final Map<String, String> _userMap = {};

  // ======= Public API =======

  Future<void> ensureLoaded() async {
    if (_loaded) return;

    final raw =
        await rootBundle.loadString('assets/drug_dict/drug_dict_nhi.json');
    final list = jsonDecode(raw) as List<dynamic>;
    _seed
      ..clear()
      ..addAll(
          list.map((e) => DrugDictItem.fromJson(e as Map<String, dynamic>)));

    try {
      await _loadUserDictionary();
    } catch (_) {
      // The bundled seed dictionary should still work when Firestore is offline.
    }
    _loaded = true;
  }

  /// 輸入中文（或混合），回傳建議列表（越相關越前）
  Future<List<DrugSuggestion>> suggest(String input, {int limit = 8}) async {
    await ensureLoaded();

    final q = _norm(input);
    if (q.isEmpty) return [];

    final results = <DrugSuggestion>[];

    // 1) 使用者自訂字典：優先度最高
    for (final entry in _userMap.entries) {
      final zhNorm = entry.key;
      final en = entry.value;
      final s = _scoreMatch(q, zhNorm);
      if (s > 0) {
        results.add(DrugSuggestion(
          zh: _denormKey(zhNorm),
          en: en,
          dose: '',
          form: '',
          source: 'user',
          score: 1000 + s, // 一律壓過 seed
        ));
      }
    }

    // 2) 內建 seed 字典
    for (final item in _seed) {
      final s1 = _scoreAny(q, item.zhNames.map(_norm));
      final s2 = _scoreAny(q, item.alias.map(_norm));
      final s = (s1 * 3) + s2; // 中文比 alias 更重要
      if (s > 0) {
        results.add(DrugSuggestion(
          zh: item.zh,
          en: item.en,
          dose: item.dose,
          form: item.form,
          source: 'seed',
          score: s,
        ));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    if (results.length > limit) return results.take(limit).toList();
    return results;
  }

  /// 使用者確認後，寫入個人字典（中文 -> 英文）
  Future<String?> findEnglishName(String input) async {
    await ensureLoaded();

    final q = _norm(input);
    if (q.isEmpty) return null;

    final userMatch = _userMap[q]?.trim();
    if (userMatch != null && userMatch.isNotEmpty) return userMatch;

    for (final item in _seed) {
      final matchedZh = item.zhNames.any((name) => _norm(name) == q);
      final matchedAlias = item.alias.any((name) => _norm(name) == q);
      if ((matchedZh || matchedAlias) && item.en.trim().isNotEmpty) {
        return item.en.trim();
      }
    }

    final suggestions = await suggest(input, limit: 1);
    if (suggestions.isEmpty) return null;
    final best = suggestions.first;
    return best.score >= 200 && best.en.trim().isNotEmpty
        ? best.en.trim()
        : null;
  }

  /// 回傳完整藥物資訊（含劑量、劑型），用於自動填入
  Future<Map<String, String>?> findDrugInfo(String input) async {
    await ensureLoaded();

    final q = _norm(input);
    if (q.isEmpty) return null;

    // 先找精確匹配的 seed 項目
    for (final item in _seed) {
      final matchedZh = item.zhNames.any((name) => _norm(name) == q);
      final matchedAlias = item.alias.any((name) => _norm(name) == q);
      if (matchedZh || matchedAlias) {
        return {
          'en': item.en.trim(),
          'dose': item.dose.trim(),
          'form': item.form.trim(),
        };
      }
    }

    // 無精確匹配，回傳 suggest 中最接近的
    final suggestions = await suggest(input, limit: 1);
    if (suggestions.isEmpty) return null;
    final best = suggestions.first;
    if (best.score < 200) return null;
    return {
      'en': best.en.trim(),
      'dose': best.dose.trim(),
      'form': best.form.trim(),
    };
  }

  double? parseDoseValue(String input) {
    final raw = input.trim().replaceAll(',', '');
    if (raw.isEmpty) return null;
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(raw);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  String? parseDoseUnit(String input) {
    final raw = input.trim().toUpperCase();
    if (raw.isEmpty) return null;

    final match = RegExp(r'\b(MG|G|ML|IU)\b').firstMatch(raw);
    if (match == null) return null;

    switch (match.group(1)) {
      case 'MG':
        return 'mg';
      case 'G':
        return 'g';
      case 'ML':
        return 'mL';
      case 'IU':
        return 'IU';
      default:
        return null;
    }
  }

  String mapFormToMedType(String form) {
    final raw = form.trim();
    if (raw.isEmpty) return 'tablet';

    if (raw.contains('注射')) return 'injection';

    const tabletKeywords = [
      '錠',
      '丸',
      '膠囊',
      '顆粒',
      '粉劑',
      '粉末',
      '散劑',
      '糖衣',
      '膜衣',
      '緩釋',
      '持續',
      '腸溶',
      '可溶',
      '口溶',
      '口含',
      '口頰',
      '微粒',
      '發泡',
    ];

    for (final keyword in tabletKeywords) {
      if (raw.contains(keyword)) return 'tablet';
    }

    return 'drops';
  }

  Future<void> saveUserMapping({
    required String zhName,
    required String enName,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final zhNorm = _norm(zhName);
    final en = enName.trim();
    if (zhNorm.isEmpty || en.isEmpty) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('drugDictionary')
        .doc(zhNorm);

    if (FirebaseSyncConfig.shouldSync()) {
      await ref.set({
        'zh': zhName.trim(),
        'en': en,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    _userMap[zhNorm] = en;
  }

  /// 重新載入使用者字典（例如登入切換帳號）
  Future<void> reloadUserDictionary() async {
    _userMap.clear();
    await _loadUserDictionary();
  }

  // ======= Internal =======

  Future<void> _loadUserDictionary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('drugDictionary')
        .limit(500)
        .get();

    for (final d in snap.docs) {
      final data = d.data();
      final en = (data['en'] ?? '').toString().trim();
      if (en.isEmpty) continue;
      _userMap[d.id] = en; // docId = normalizedZh
    }
  }

  String _norm(String s) {
    final buffer = StringBuffer();
    for (final rune in s.trim().runes) {
      var code = rune;
      if (code == 0x3000) {
        code = 0x20;
      } else if (code >= 0xFF01 && code <= 0xFF5E) {
        code -= 0xFEE0;
      }
      buffer.writeCharCode(code);
    }

    final t = buffer.toString().toLowerCase();
    return t.replaceAll(RegExp(r'[^0-9a-z\u4e00-\u9fff]'), '');
  }

  // 只是給 UI 顯示用：對 userMap 的 key 找不到原 zh 時，退回 key 本身
  String _denormKey(String key) => key;

  int _scoreMatch(String q, String target) {
    if (q.isEmpty || target.isEmpty) return 0;
    if (target == q) return 1000;
    if (target.startsWith(q)) return 800;
    if (q.startsWith(target)) return 700;
    if (q.length >= 2 && target.contains(q)) return 500;
    if (target.length >= 2 && q.contains(target)) return 450;
    return 0;
  }

  int _scoreAny(String q, Iterable<String> targets) {
    var best = 0;
    for (final t in targets) {
      best = best < _scoreMatch(q, t) ? _scoreMatch(q, t) : best;
    }
    return best;
  }
}
