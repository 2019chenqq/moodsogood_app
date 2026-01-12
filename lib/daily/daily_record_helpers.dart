import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/daily_record.dart';

// Sentinel to distinguish between "not provided" and explicit null when copying.
const _unset = Object();

// ============================================================
// 頂層 Helper Functions
// ============================================================

Future<List<DailyRecord>> loadAllRecords(String uid) async {
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('dailyRecords')
      .get();

  return snap.docs
    .map((d) => DailyRecord.fromFirestore(d))
    .toList();
}

double? overallFrom(Map<String, dynamic> data) {
  final v = data['overallMood'];
  if (v is num) return v.toDouble();
  final emos = (data['emotions'] as List?)?.cast<Map>() ?? const [];
  for (final m in emos) {
    final key = (m['key'] ?? m['id'] ?? m['name'] ?? '').toString();
    if (key == '整體情緒' || key == 'overall') {
      final vv = m['value'];
      if (vv is num) return vv.toDouble();
    }
  }
  final vals = emos.map((m) => m['value']).where((x) => x is num).cast<num>().toList();
  if (vals.isEmpty) return null;
  return vals.reduce((a,b)=>a+b)/vals.length;
}

String formatDocDateTime(Map<String, dynamic> data, String docId) {
  // 優先 updatedAt，其次 createdAt；都沒有時，嘗試用 docId(yyyy-MM-dd)
  DateTime? t;

  final updated = data['updatedAt'];
  final created = data['createdAt'];
  if (updated is Timestamp) t = updated.toDate();
  if (t == null && created is Timestamp) t = created.toDate();

  // 如果 docId 是 yyyy-MM-dd，就補上 00:00 當作時間顯示
  if (t == null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(docId)) {
    t = DateTime.tryParse('$docId 00:00:00');
  }

  t ??= DateTime.now(); // 萬一還是沒有，就用現在

  // 顯示樣式（只日期與時間）
  return '${t.year.toString().padLeft(4, '0')}-'
         '${t.month.toString().padLeft(2, '0')}-'
         '${t.day.toString().padLeft(2, '0')} '
         '${t.hour.toString().padLeft(2, '0')}:'
         '${t.minute.toString().padLeft(2, '0')}';
}

// ============================================================
// Data Model Classes
// ============================================================

class EmotionItem {
  final String name;
  final int? value; // 0~10
  EmotionItem(this.name, {this.value});

  EmotionItem copyWith({String? name, Object? value = _unset}) {
    final int? nextValue = value == _unset ? this.value : value as int?;
    return EmotionItem(name ?? this.name, value: nextValue);
  }
}

class SymptomItem {
  final String name;

  SymptomItem({required this.name});

  SymptomItem copyWith({String? name}) => SymptomItem(name: name ?? this.name);
}

enum SleepFlag {
  good,
  ok,
  earlyWake,
  dreams,
  lightSleep,
  fragmented,
  insufficient,
  initInsomnia,
  interrupted,
  nocturia,
}

// 睡眠標記顯示用
String sleepFlagLabel(SleepFlag f) {
  switch (f) {
    case SleepFlag.good:
      return '優';
    case SleepFlag.ok:
      return '良好';
    case SleepFlag.earlyWake:
      return '早醒';
    case SleepFlag.dreams:
      return '多夢';
    case SleepFlag.lightSleep:
      return '淺眠';
    case SleepFlag.nocturia:
      return '夜尿';
    case SleepFlag.fragmented:
      return '睡睡醒醒';
    case SleepFlag.insufficient:
      return '睡眠不足';
    case SleepFlag.initInsomnia:
      return '入睡困難 (躺超過 30 分鐘才入睡)';
    case SleepFlag.interrupted:
      return '睡眠中斷 (醒來後超過 30 分鐘才又入睡)';
  }
}
