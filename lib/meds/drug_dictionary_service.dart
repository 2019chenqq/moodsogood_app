import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import '../utils/firebase_sync_config.dart';

class DrugIngredient {
  final String name;
  final String strength;

  const DrugIngredient({
    required this.name,
    required this.strength,
  });

  String get label {
    final parts = [name.trim(), strength.trim()]
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.join(' ');
  }
}

class DrugDictItem {
  final String code;
  final List<String> zhNames;
  final String productEn;
  final List<DrugIngredient> ingredients;
  final String form;
  final String compoundType;
  final String packageAmount;
  final String packageUnit;
  final String atc;

  const DrugDictItem({
    required this.code,
    required this.zhNames,
    required this.productEn,
    required this.ingredients,
    required this.form,
    required this.compoundType,
    required this.packageAmount,
    required this.packageUnit,
    required this.atc,
  });

  String get zh => zhNames.isEmpty ? '' : zhNames.first;
  String get en => isCompound ? ingredientLines.join(' + ') : ingredientName;
  String get ingredientName =>
      ingredients.isEmpty ? '' : ingredients.first.name;
  String get ingredientStrength =>
      ingredients.isEmpty ? '' : ingredients.first.strength;
  String get concentration => hasPackageSpec ? ingredientStrength : '';
  String get packageDose => _joinAmountUnit(packageAmount, packageUnit);
  String get dose =>
      isCompound ? '' : (hasPackageSpec ? packageDose : ingredientStrength);
  bool get hasPackageSpec =>
      packageAmount.trim().isNotEmpty && packageUnit.trim().isNotEmpty;
  bool get isCompound => compoundType.contains('複') || ingredients.length > 1;
  List<String> get ingredientLines => ingredients
      .map((ingredient) => ingredient.label)
      .where((v) => v.isNotEmpty)
      .toList();
  List<String> get aliases => [
        productEn,
        ...ingredients.map((ingredient) => ingredient.name),
        ...ingredientLines,
      ].where((value) => value.trim().isNotEmpty).toList();

  static String _joinAmountUnit(String amount, String unit) {
    final a = amount.trim();
    final u = unit.trim();
    if (a.isEmpty || u.isEmpty) return '';
    return '$a $u';
  }
}

class DrugSuggestion {
  final String zh;
  final String en;
  final String dose;
  final String form;
  final String compoundType;
  final String concentration;
  final String packageAmount;
  final String packageUnit;
  final List<String> ingredientLines;
  final String source;
  final int score;

  const DrugSuggestion({
    required this.zh,
    required this.en,
    this.dose = '',
    this.form = '',
    this.compoundType = '',
    this.concentration = '',
    this.packageAmount = '',
    this.packageUnit = '',
    this.ingredientLines = const [],
    required this.source,
    required this.score,
  });

  Map<String, String> toInfoMap() => {
        'zh': zh,
        'en': en,
        'dose': dose,
        'form': form,
        'compoundType': compoundType,
        'concentration': concentration,
        'packageAmount': packageAmount,
        'packageUnit': packageUnit,
        'ingredientLines': ingredientLines.join('\n'),
        'isCompound': isCompound ? 'true' : 'false',
      };

  bool get isCompound =>
      compoundType.contains('複') || ingredientLines.length > 1;
}

class DrugDictionaryService {
  DrugDictionaryService._();

  static final DrugDictionaryService instance = DrugDictionaryService._();

  bool _loaded = false;
  final List<DrugDictItem> _seed = [];
  final Map<String, String> _userMap = {};

  Future<void> ensureLoaded() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('assets/drug_dict/CLEAN_DRUG.json');
    final list = jsonDecode(raw) as List<dynamic>;
    _seed
      ..clear()
      ..addAll(_buildItemsFromCleanRows(list.cast<Map<String, dynamic>>()));

    try {
      await _loadUserDictionary();
    } catch (_) {
      // Keep the bundled dictionary usable when Firestore is offline.
    }
    _loaded = true;
  }

  Future<List<DrugSuggestion>> suggest(String input, {int limit = 8}) async {
    await ensureLoaded();

    final q = _norm(input);
    if (q.isEmpty) return [];

    final results = <DrugSuggestion>[];

    for (final entry in _userMap.entries) {
      final s = _scoreMatch(q, entry.key);
      if (s > 0) {
        results.add(DrugSuggestion(
          zh: _denormKey(entry.key),
          en: entry.value,
          source: 'user',
          score: 1000 + s,
        ));
      }
    }

    for (final item in _seed) {
      final s1 = _scoreAny(q, item.zhNames.map(_norm));
      final s2 = _scoreAny(q, item.aliases.map(_norm));
      final s = (s1 * 3) + s2;
      if (s > 0) {
        results.add(_suggestionFromItem(item, s));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.length > limit ? results.take(limit).toList() : results;
  }

  Future<String?> findEnglishName(String input) async {
    final info = await findDrugInfo(input);
    return info?['en']?.trim().isNotEmpty == true ? info!['en'] : null;
  }

  Future<Map<String, String>?> findDrugInfo(String input) async {
    await ensureLoaded();

    final q = _norm(input);
    if (q.isEmpty) return null;

    for (final item in _seed) {
      final matchedZh = item.zhNames.any((name) => _norm(name) == q);
      final matchedAlias = item.aliases.any((name) => _norm(name) == q);
      if (matchedZh || matchedAlias) {
        return _suggestionFromItem(item, 1000).toInfoMap();
      }
    }

    final userMatch = _userMap[q]?.trim();
    if (userMatch != null && userMatch.isNotEmpty) {
      return {
        'zh': _denormKey(q),
        'en': userMatch,
        'dose': '',
        'form': '',
        'compoundType': '',
        'concentration': '',
        'packageAmount': '',
        'packageUnit': '',
        'ingredientLines': '',
        'isCompound': 'false',
      };
    }

    final suggestions = await suggest(input, limit: 1);
    if (suggestions.isEmpty || suggestions.first.score < 200) return null;
    return suggestions.first.toInfoMap();
  }

  double? parseDoseValue(String input) {
    final raw = _normalizeDoseText(input).replaceAll(',', '');
    if (raw.contains('+')) return null;
    if (raw.isEmpty) return null;
    final match = RegExp(r'((?:[0-9]+)?\.[0-9]+|[0-9]+)').firstMatch(raw);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  String? parseDoseUnit(String input) {
    final raw = _normalizeDoseText(input).toUpperCase();
    if (raw.isEmpty) return null;

    if (raw.contains('毫克') || raw.contains('公絲')) return 'mg';
    if (raw.contains('微克')) return 'mcg';
    if (raw.contains('公克')) return 'g';
    if (raw.contains('毫升') || raw.contains('公撮')) return 'mL';
    if (raw.contains('國際單位') || raw.contains('單位')) return 'IU';

    final match = RegExp(r'(MCG|MG|GM|G|ML|IU|UNIT|U)').firstMatch(raw);
    switch (match?.group(1)) {
      case 'MCG':
        return 'mcg';
      case 'MG':
        return 'mg';
      case 'GM':
      case 'G':
        return 'g';
      case 'ML':
        return 'mL';
      case 'IU':
      case 'UNIT':
      case 'U':
        return 'IU';
      default:
        return null;
    }
  }

  String _normalizeDoseText(String input) {
    final buffer = StringBuffer();
    for (final rune in input.trim().runes) {
      var code = rune;
      if (code == 0x3000) {
        code = 0x20;
      } else if (code >= 0xff01 && code <= 0xff5e) {
        code -= 0xfee0;
      }
      buffer.writeCharCode(code);
    }
    return buffer
        .toString()
        .replaceAll('．', '.')
        .replaceAll('・', '.')
        .replaceAll('。', '.')
        .replaceAll('／', '/');
  }

  String mapFormToMedType(String form) {
    final raw = form.trim();
    if (raw.isEmpty) return 'tablet';
    if (raw.contains('注射')) return 'injection';

    const liquidOrTopicalKeywords = [
      '液',
      '滴',
      '糖漿',
      '懸浮',
      '懸液',
      '乳膏',
      '軟膏',
      '凝膠',
      '乳劑',
      '洗劑',
      '外用',
    ];
    for (final keyword in liquidOrTopicalKeywords) {
      if (raw.contains(keyword)) return 'drops';
    }

    return 'tablet';
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

  Future<void> reloadUserDictionary() async {
    _userMap.clear();
    await _loadUserDictionary();
  }

  List<DrugDictItem> _buildItemsFromCleanRows(List<Map<String, dynamic>> rows) {
    final builders = <String, _DrugItemBuilder>{};

    for (final row in rows) {
      final code = _read(row, '藥品代號');
      final zh = _read(row, '藥品中文名稱');
      final productEn = _read(row, '藥品英文名稱');
      final ingredient = _firstNonEmpty([
        _read(row, '英文成分'),
        _extractIngredientName(_read(row, '成分拆分')),
        _extractIngredientName(_read(row, '成分')),
      ]);
      final strength = _resolveDoseText(row);
      final packageAmount = _read(row, '規格量');
      final packageUnit = _read(row, '規格單位');
      final compoundType = _read(row, '單複方');
      final form = _read(row, '劑型');
      final atc = _read(row, 'ATC代碼');
      if (zh.isEmpty && productEn.isEmpty) continue;

      final key = code.isNotEmpty ? code : '${_norm(zh)}|${_norm(productEn)}';
      final builder = builders.putIfAbsent(
        key,
        () => _DrugItemBuilder(
          code: code,
          productEn: productEn,
          form: form,
          compoundType: compoundType,
          packageAmount: packageAmount,
          packageUnit: packageUnit,
          atc: atc,
        ),
      );
      builder.addZh(zh);
      builder.addIngredient(ingredient, strength);
    }

    return builders.values.map((builder) => builder.build()).toList();
  }

  String _read(Map<String, dynamic> row, String key) {
    if (row.containsKey(key)) {
      final direct = row[key];
      return direct == null ? '' : direct.toString().trim();
    }

    final direct = row[key];
    if (direct != null) return direct.toString().trim();

    // Fallback for any future file that has the same column order but damaged keys.
    final index = const {
      '藥品代號': 0,
      '藥品英文名稱': 1,
      '藥品中文名稱': 2,
      '成分': 3,
      '規格量': 4,
      '規格單位': 5,
      '單複方': 6,
      '劑型': 7,
      'ATC代碼': 8,
      '成分拆分': 10,
      '英文成分': 11,
      '劑量': 12,
      '劑量數值': 13,
      '劑量單位': 14,
    }[key];
    if (index == null || index >= row.length) return '';
    return row.values.elementAt(index).toString().trim();
  }

  String _resolveDoseText(Map<String, dynamic> row) {
    final explicitDose = _read(row, '劑量');
    if (explicitDose.isNotEmpty) return explicitDose;

    final doseFromParts = _joinDose(_read(row, '劑量數值'), _read(row, '劑量單位'));
    if (doseFromParts.isNotEmpty) return doseFromParts;

    final packageDose = _joinDose(_read(row, '規格量'), _read(row, '規格單位'));
    if (packageDose.isNotEmpty) return packageDose;

    return _firstNonEmpty([
      _extractDoseText(_read(row, '成分拆分')),
      _extractDoseText(_read(row, '成分')),
    ]);
  }

  String _joinDose(String value, String unit) {
    final v = value.trim();
    final u = unit.trim();
    if (v.isEmpty || u.isEmpty) return '';
    return '$v $u';
  }

  String _extractDoseText(String input) {
    final normalized = _normalizeDoseText(input);
    final match = RegExp(
      r'((?:[0-9]+)?\.[0-9]+|[0-9]+)\s*(MCG|MG|GM|G|ML|IU|UNIT|U)\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) return '';
    final unit = parseDoseUnit(match.group(2) ?? '') ?? match.group(2) ?? '';
    return '${match.group(1)} $unit'.trim();
  }

  String _extractIngredientName(String input) {
    final normalized = _normalizeDoseText(input);
    return normalized
        .replaceFirst(
          RegExp(
            r'\s*((?:[0-9]+)?\.[0-9]+|[0-9]+)\s*(MCG|MG|GM|G|ML|IU|UNIT|U)\b.*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String _firstNonEmpty(Iterable<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  DrugSuggestion _suggestionFromItem(DrugDictItem item, int score) {
    return DrugSuggestion(
      zh: item.zh,
      en: item.en,
      dose: item.dose,
      form: item.form,
      compoundType: item.compoundType,
      concentration: item.concentration,
      packageAmount: item.packageAmount,
      packageUnit: item.packageUnit,
      ingredientLines: item.ingredientLines,
      source: 'seed',
      score: score,
    );
  }

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
      _userMap[d.id] = en;
    }
  }

  String _norm(String s) {
    final buffer = StringBuffer();
    for (final rune in s.trim().runes) {
      var code = rune;
      if (code == 0x3000) {
        code = 0x20;
      } else if (code >= 0xff01 && code <= 0xff5e) {
        code -= 0xfee0;
      }
      buffer.writeCharCode(code);
    }
    return buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^0-9a-z\u4e00-\u9fff]'), '');
  }

  String _denormKey(String key) => key;

  int _scoreMatch(String q, String target) {
    if (q.isEmpty || target.isEmpty) return 0;
    if (target == q) return 1000;
    if (target.startsWith(q)) return 800 - (target.length - q.length);
    if (target.contains(q)) return 500 - target.indexOf(q);
    return 0;
  }

  int _scoreAny(String q, Iterable<String> targets) {
    var best = 0;
    for (final t in targets) {
      final s = _scoreMatch(q, t);
      if (s > best) best = s;
    }
    return best;
  }
}

class _DrugItemBuilder {
  final String code;
  final String productEn;
  final String form;
  final String compoundType;
  final String packageAmount;
  final String packageUnit;
  final String atc;
  final List<String> zhNames = [];
  final List<DrugIngredient> ingredients = [];

  _DrugItemBuilder({
    required this.code,
    required this.productEn,
    required this.form,
    required this.compoundType,
    required this.packageAmount,
    required this.packageUnit,
    required this.atc,
  });

  void addZh(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !zhNames.contains(trimmed)) zhNames.add(trimmed);
  }

  void addIngredient(String name, String strength) {
    final ingredient =
        DrugIngredient(name: name.trim(), strength: strength.trim());
    if (ingredient.name.isEmpty && ingredient.strength.isEmpty) return;
    final exists = ingredients.any(
      (item) =>
          item.name == ingredient.name && item.strength == ingredient.strength,
    );
    if (!exists) ingredients.add(ingredient);
  }

  DrugDictItem build() {
    return DrugDictItem(
      code: code,
      zhNames: zhNames,
      productEn: productEn,
      ingredients: ingredients,
      form: form,
      compoundType: compoundType,
      packageAmount: packageAmount,
      packageUnit: packageUnit,
      atc: atc,
    );
  }
}
