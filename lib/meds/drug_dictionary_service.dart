import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class DrugDictItem {
  final String zh;
  final String en;
  final List<String> alias;

  DrugDictItem({required this.zh, required this.en, required this.alias});

  factory DrugDictItem.fromJson(Map<String, dynamic> j) {
    return DrugDictItem(
      zh: (j['zh'] ?? '').toString(),
      en: (j['en'] ?? '').toString(),
      alias: (j['alias'] is List)
          ? (j['alias'] as List).map((x) => x.toString()).toList()
          : const [],
    );
  }
}

class DrugSuggestion {
  final String zh;
  final String en;
  final String source; // 'seed' or 'user'
  final int score;

  DrugSuggestion({
    required this.zh,
    required this.en,
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

    final raw = await rootBundle.loadString('assets/drug_dict/drug_dict_seed.json');
    final list = jsonDecode(raw) as List<dynamic>;
    _seed
      ..clear()
      ..addAll(list.map((e) => DrugDictItem.fromJson(e as Map<String, dynamic>)));

    await _loadUserDictionary();
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
          source: 'user',
          score: 1000 + s, // 一律壓過 seed
        ));
      }
    }

    // 2) 內建 seed 字典
    for (final item in _seed) {
      final s1 = _scoreMatch(q, _norm(item.zh));
      final s2 = _scoreAny(q, item.alias.map(_norm));
      final s = (s1 * 3) + s2; // 中文比 alias 更重要
      if (s > 0) {
        results.add(DrugSuggestion(
          zh: item.zh,
          en: item.en,
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

    await ref.set({
      'zh': zhName.trim(),
      'en': en,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

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
    var t = s.trim().toLowerCase();
    // 去空白、全形空白、常見符號
    t = t.replaceAll(RegExp(r'[\s　\-\_\(\)\[\]【】（）\.,/\\]'), '');
    return t;
  }

  // 只是給 UI 顯示用：對 userMap 的 key 找不到原 zh 時，退回 key 本身
  String _denormKey(String key) => key;

  int _scoreMatch(String q, String target) {
    if (q.isEmpty || target.isEmpty) return 0;
    if (target == q) return 200;
    if (target.startsWith(q)) return 120;
    if (target.contains(q)) return 60;
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
