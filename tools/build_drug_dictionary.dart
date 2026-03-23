import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;


void main() async {
  final projectRoot = Directory.current.path;
  final sourcePath = p.join(projectRoot, 'tools', 'drug_source.json');
  final sourceFile = File(sourcePath);

  if (!sourceFile.existsSync()) {
    throw Exception('❌ 找不到 drug_source.json：$sourcePath');
  }

  final raw = jsonDecode(await sourceFile.readAsString(encoding: utf8));

  if (raw is! List) {
    throw Exception('❌ 預期 drug_source.json 是 JSON array');
  }

  // 🔧 根據實際 JSON 欄位名稱調整（先用最常見版本）
  String? getZhName(Map<String, dynamic> r) =>
      r['中文品名'] ?? r['藥品名稱'] ?? r['品名'];

  String? getIngredientEn(Map<String, dynamic> r) =>
      r['英文成分名'] ?? r['成分'] ?? r['主成分'];

  String? getAtc(Map<String, dynamic> r) =>
      r['ATC Code'] ?? r['ATC'] ?? r['atc_code'];

  final Map<String, Map<String, dynamic>> dict = {};

  for (final row in raw) {
    if (row is! Map<String, dynamic>) continue;

    final zh = getZhName(row)?.trim();
    final en = getIngredientEn(row)?.trim();

    if (zh == null || zh.isEmpty || en == null || en.isEmpty) continue;

    dict.putIfAbsent(en, () => {
          'ingredientEn': en,
          'ingredientZh': '',
          'zhNames': <String>{},
          'atc': getAtc(row)?.trim() ?? '',
        });

    (dict[en]!['zhNames'] as Set<String>).add(zh);
  }

  List<Map<String, dynamic>> output = [];

  for (final entry in dict.values) {
    final zhSet = entry['zhNames'] as Set<String>;
    final en = entry['ingredientEn'] as String;

    final Set<String> keywords = {};

    // 中文關鍵字（前綴）
    for (final zh in zhSet) {
      for (int i = 1; i <= zh.length; i++) {
        keywords.add(zh.substring(0, i));
      }
    }

    // 英文成分關鍵字（前綴、小寫）
    for (int i = 1; i <= en.length; i++) {
      keywords.add(en.substring(0, i).toLowerCase());
    }

    output.add({
      'ingredientEn': en,
      'ingredientZh': entry['ingredientZh'],
      'zhNames': zhSet.toList(),
      'atc': entry['atc'],
      'keywords': keywords.toList(),
      'source': 'MOHW',
    });
  }

  final outFile = File('drug_dictionary_firestore.json');
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
    encoding: utf8,
  );

  print('✅ drug_dictionary_firestore.json generated (${output.length} items)');
}
