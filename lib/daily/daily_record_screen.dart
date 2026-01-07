import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:moodsogood_app/quotes.dart';

import '../app_globals.dart';
import '../utils/date_helper.dart';
import '../models/daily_record.dart';
// import '../models/period_cycle.dart';
import '../quotes.dart';
import '../widgets/main_drawer.dart';
import '../widgets/emotion_slider.dart';

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

/// -------------------- 類型 & 小工具（頂層） --------------------

class EmotionItem {
  final String name;
  final int? value; // 0~10
  EmotionItem(this.name, {this.value});

  EmotionItem copyWith({String? name, int? value}) =>
      EmotionItem(name ?? this.name, value: value ?? this.value);
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

// 小睡：開始/結束時間（可跨日），自動計算時長
class NapItem {
  final TimeOfDay start;
  final TimeOfDay end;

  const NapItem({required this.start, required this.end});

  // 自動計算時長（含跨日）
  Duration get duration {
    final mins = DateHelper.calcDurationMinutes(start, end);
    return Duration(minutes: mins);
  }

  NapItem copyWith({TimeOfDay? start, TimeOfDay? end}) =>
      NapItem(start: start ?? this.start, end: end ?? this.end);
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

// 小節標題
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.trailing, Key? key}) : super(key: key);
  final String title;
  final Widget? trailing;

  String _formatDocDateTime(Map<String, dynamic> data, String docId) {
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

  // 你要的顯示樣式（只日期與時間）
  return '${t.year.toString().padLeft(4, '0')}-'
         '${t.month.toString().padLeft(2, '0')}-'
         '${t.day.toString().padLeft(2, '0')} '
         '${t.hour.toString().padLeft(2, '0')}:'
         '${t.minute.toString().padLeft(2, '0')}';
}

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// /// ------- 共用：Cupertino 滾輪選擇 -------
// /// 數字滾輪（支援標題）
// Future<int?> showWheelPicker(
//   BuildContext context, {
//   required int initial,
//   int min = 0,
//   int max = 10,
//   String? title, // ← 新增的參數
// }) async {
//   int value = initial.clamp(min, max);

//   return showModalBottomSheet<int>(
//     context: context,
//     showDragHandle: true,
//     builder: (ctx) {
//       return SizedBox(
//         height: 300,
//         child: Column(
//           children: [
//             if (title != null)
//               Padding(
//                 padding: const EdgeInsets.only(top: 8, bottom: 4),
//                 child: Text(
//                   title!,
//                   style: Theme.of(ctx).textTheme.titleMedium,
//                 ),
//               ),
//             Expanded(
//               child: CupertinoPicker(
//                 itemExtent: 40,
//                 scrollController: FixedExtentScrollController(
//                   initialItem: value - min,
//                 ),
//                 onSelectedItemChanged: (i) => value = min + i,
//                 children: [
//                   for (int i = min; i <= max; i++) Center(child: Text('$i')),
//                 ],
//               ),
//             ),
//             SafeArea(
//               top: false,
//               minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
//               child: Row(
//                 children: [
//                   Expanded(
//                     child: OutlinedButton(
//                       onPressed: () => Navigator.of(ctx).pop(),
//                       child: const Text('取消'),
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: FilledButton(
//                       onPressed: () => Navigator.of(ctx).pop(value),
//                       child: const Text('確定'),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       );
//     },
//   );
// }
Future<int?> showSliderPicker({
  required BuildContext context,
  required int initial,
  required int min,
  required int max,
  required String title,
}) async {
  int tempValue = initial;

  return showDialog<int>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: tempValue.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: max - min,
                  label: tempValue.toString(),
                  onChanged: (v) {
                    setState(() => tempValue = v.round());
                  },
                ),
                Text('$tempValue / $max'),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, tempValue),
            child: const Text('確定'),
          ),
        ],
      );
    },
  );
}
/// ------- 共用：輸入字串 Dialog -------
Future<String?> showTextDialog(
    BuildContext context, String title, String hint) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content:
          TextField(controller: c, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('確定')),
      ],
    ),
  );
}

/// -------------------- 主畫面 --------------------

class DailyRecordScreen extends StatefulWidget {
  const DailyRecordScreen({super.key});

  @override
  State<DailyRecordScreen> createState() => _DailyRecordScreenState();
}

class _DailyRecordScreenState extends State<DailyRecordScreen> {
  int _index = 0;
  bool _isSaving = false;
  bool _isPeriod = false;
  // ——— 目前紀錄日期與時間（給頁首顯示；docId 只吃日期） ———
  DateTime _recordDate = DateTime.now();
  TimeOfDay _recordTime = TimeOfDay.now();
  @override
  void initState() {
    super.initState();
    _loadExistingData(_recordDate); // 一進來就載入今天的紀錄（含生理期狀態）
  }

void _resetForm({bool keepPeriodStatus = false}) {
  setState(() {
    // 🔹 症狀
    _symptoms.clear();
    _symptoms.add(SymptomItem(name: ''));

    // 🔹 安眠藥相關
    tookHypnotic = false;
    hypnoticName = '';
    _hypnoticNameCtrl.clear();
    hypnoticDose = '';
    _hypnoticDoseCtrl.clear();

    // 🔹 睡眠時間
    sleepTime = null;
    wakeTime = null;
    finalWakeTime = null;
    midWakeList = '';
    _midWakeCtrl.clear();

    // 🔹 睡眠旗標、備註、品質
    _sleepFlags.clear();
    sleepNote = '';
    sleepQuality = null;

    // 🔹 小睡
    _naps.clear();

    // 🔹 生理期狀態：除非特別說「要保留」，才歸零
    if (!keepPeriodStatus) {
      _isPeriod = false;
    }
  });
}

    // ——— 情緒/症狀/睡眠本地狀態 ———
  final List<EmotionItem> _emotions = [
    EmotionItem('整體情緒'),
    EmotionItem('焦慮程度'),
    EmotionItem('憂鬱程度'),
    EmotionItem('空虛程度'),
    EmotionItem('無聊程度'),
    EmotionItem('難過程度'),
    EmotionItem('開心程度'),
    EmotionItem('無望感'),
    EmotionItem('孤獨感'),
    EmotionItem('動力'),
    EmotionItem('自殺意念'),
    EmotionItem('食慾'),
    EmotionItem('能量'),
    EmotionItem('活動量'),
    EmotionItem('疲倦程度'),
  ];

  final List<SymptomItem> _symptoms = [SymptomItem(name: '')];

  bool tookHypnotic = false;
  String hypnoticName = '';
  String hypnoticDose = '';
  TimeOfDay? sleepTime;
  TimeOfDay? wakeTime;
  TimeOfDay? finalWakeTime; // 甦醒時刻
String midWakeList = '';  // 半夜醒來 (字串)
late final TextEditingController _midWakeCtrl = TextEditingController(); // 控制器
  final Set<SleepFlag> _sleepFlags = {};
  String sleepNote = '';
  int? sleepQuality; // 1~10；null 表示尚未填寫
  final List<NapItem> _naps = [];

  // ——— 共用：包裹每個分頁（頁首 + 內容 + 底部儲存鈕） ———
  Widget _pageWrapper(Widget child) {
    return Column(
      children: [
        _RecordHeader(
          dateText: DateHelper.toDisplay(_recordDate),
          timeText: DateHelper.formatTime(_recordTime),
          onPickDate: _pickRecordDate,
          onPickTime: _pickRecordTime,
        ),
        Expanded(child: child),
        // _footerSave(),
      ],
    );
  }

Future<void> _loadExistingData(DateTime date) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final docId = DateHelper.toId(date);

  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailyRecords')
        .doc(docId)
        .get();

    if (doc.exists && doc.data() != null) {
      // -------------------------
      // A. 這一天已經有紀錄 → 完整讀取
      // -------------------------
      final record = DailyRecord.fromFirestore(doc);
      final s = record.sleep;

      setState(() {
        // --- 情緒 ---
        if (record.emotions.isNotEmpty) {
          _emotions.clear();

          // 確保「整體情緒」永遠排第一
          final all = record.emotions;
          all.sort((a, b) {
            if (a.name == '整體情緒') return -1;
            if (b.name == '整體情緒') return 1;
            return 0;
          });

          _emotions.addAll(
            all.map(
              (e) => EmotionItem(e.name, value: e.value),
            ),
          );
        }
if (record.overallMood != null) {
          _emotions.removeWhere((e) => e.name == '整體情緒');
          _emotions.insert(
            0,
            EmotionItem(
              '整體情緒',
              value: record.overallMood!.round(), 
            ),
          );
        }
        // --- 症狀 ---
        if (record.symptoms.isNotEmpty) {
          _symptoms
            ..clear()
            ..addAll(record.symptoms.map((n) => SymptomItem(name: n)));
        }

        // --- 睡眠 ---
        tookHypnotic = s.tookHypnotic;
        hypnoticName = s.hypnoticName ?? '';
        _hypnoticNameCtrl.text = hypnoticName;
        hypnoticDose = s.hypnoticDose ?? '';
        _hypnoticDoseCtrl.text = hypnoticDose;

        sleepTime = s.sleepTime;
        wakeTime = s.wakeTime;
        finalWakeTime = s.finalWakeTime;

        midWakeList = s.midWakeList ?? '';
        _midWakeCtrl.text = midWakeList;

        // 睡眠標籤
        _sleepFlags.clear();
        for (final f in s.flags) {
          try {
            final match = SleepFlag.values.firstWhere((e) => e.name == f);
            _sleepFlags.add(match);
          } catch (_) {}
        }

        sleepNote = s.note ?? '';
        sleepQuality = s.quality;

        // 小睡
        _naps
          ..clear()
          ..addAll(
            s.naps.map(
              (n) => NapItem(start: n.start, end: n.end),
            ),
          );

        // -------------------------
        // 🔥 生理期狀態（今日已有紀錄 → 就用紀錄的）
        // -------------------------
        _isPeriod = record.isPeriod == true;
      });
    } else {
  // -------------------------
  // B. 今日沒有紀錄 → 自動推算生理期（看昨天）
  // -------------------------
  await _loadPeriodState(date);

  // -------------------------
  // C. 清空其他欄位，但保留剛推算的 _isPeriod
  // -------------------------
  _resetForm(keepPeriodStatus: true);
}
  } catch (e) {
    debugPrint('讀取資料錯誤: $e');
  }
}
  
Future<void> _loadPeriodState(DateTime currentDate) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  try {
    // 只看「昨天」那一天
    final yesterdayDate = currentDate.subtract(const Duration(days: 1));
    final yesterdayId = DateHelper.toId(yesterdayDate);

    final yesterdaySnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailyRecords')
        .doc(yesterdayId)
        .get();

    if (!yesterdaySnap.exists || yesterdaySnap.data() == null) {
      // 昨天沒有紀錄 → 不自動延續
      _isPeriod = false;
      return;
    }

    final yesterdayRecord = DailyRecord.fromFirestore(yesterdaySnap);

    // 🔥 規則：
    // 昨天是生理期（isPeriod == true）
    // 並且昨天沒有被標成結束日（periodEndId == null）
    // → 今天預設延續經期
    if (yesterdayRecord.isPeriod == true &&
        yesterdayRecord.periodEndId == null) {
      _isPeriod = true;
      debugPrint('🔄 自動延續生理期到今天（昨天是經期中）');
    } else {
      _isPeriod = false;
      debugPrint('⏹ 昨天不是經期中或已經結束，不延續');
    }
  } catch (e) {
    debugPrint('讀取昨天的生理期狀態失敗: $e');
    _isPeriod = false;
  }
}

Future<void> _savePeriod(String todayId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final col = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('dailyRecords');

  // 先抓「今天」舊的狀態
  final todayDoc = await col.doc(todayId).get();
  final bool oldIsPeriod = todayDoc.data()?['isPeriod'] == true;

  // 算出「昨天」的 id
  final yesterdayDate = _recordDate.subtract(const Duration(days: 1));
  final yesterdayId = DateHelper.toId(yesterdayDate);
  final yesterdayDoc = await col.doc(yesterdayId).get();
  final bool yesterdayIsPeriod =
      yesterdayDoc.exists && (yesterdayDoc.data()?['isPeriod'] == true);
  final String? yesterdayPeriodStart =
      yesterdayDoc.data()?['periodStart'] as String?;

  if (_isPeriod) {
    // 🔥 現在這一天是「經期中」

    // 如果昨天也是經期，而且有 periodStart，就沿用那個起始日
    String periodStartToUse;
    if (yesterdayIsPeriod && yesterdayPeriodStart != null) {
      periodStartToUse = yesterdayPeriodStart;
    } else {
      // 否則代表這是新的第一天
      periodStartToUse = todayId;
    }

    await col.doc(todayId).set(
      {
        'isPeriod': true,
        'periodStart': periodStartToUse,
        'periodEnd': null, // 這一天還沒結束
      },
      SetOptions(merge: true),
    );
  } else {
    // 🔥 現在這一天「沒有經期」

    // 如果原本是經期，代表這一天是「結束日」
    if (oldIsPeriod) {
      await col.doc(todayId).set(
        {
          'isPeriod': false,
          'periodEnd': todayId,
        },
        SetOptions(merge: true),
      );
    } else {
      // 原本就不是經期，只更新 isPeriod
      await col.doc(todayId).set(
        {
          'isPeriod': false,
        },
        SetOptions(merge: true),
      );
    }
  }
}
   Future<void> _pickRecordDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) {
      setState(() => _recordDate = picked);
      // 🔥 重點：切換日期後，讀取那天的資料
      await _loadExistingData(_recordDate);
    }
  }
  // ——— 儲存：users/{uid}/dailyRecords/{yyyy-MM-dd}（同日合併） ———
  Future<void> _saveAll() async {
  if (_isSaving) return;

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final date = _recordDate;
  final docId = DateHelper.toId(date);

  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('dailyRecords')
      .doc(docId);

  setState(() => _isSaving = true);

  try {
    // 讀取舊資料（用來銜接生理期開始日）
    final oldSnap = await ref.get();
    String? oldStartId;
    bool oldIsPeriod = false;

    if (oldSnap.exists && oldSnap.data() != null) {
      final old = DailyRecord.fromFirestore(oldSnap);
      oldStartId = old.periodStartId;
      oldIsPeriod = old.isPeriod;
    }

    // ----- 準備要寫進 Firebase 的資料 -----
    final payload = <String, dynamic>{
      'emotions': _emotions.map((e) => {'name': e.name, 'value': e.value}).toList(),
      'symptoms': _symptoms.map((s) => s.name).toList(),

      // 睡眠資料
      'sleep': {
        'tookHypnotic': tookHypnotic,
        'hypnoticName': hypnoticName,
        'hypnoticDose': hypnoticDose,
        'sleepTime': DateHelper.formatTime(sleepTime),
        'wakeTime': DateHelper.formatTime(wakeTime),
        'flags': _sleepFlags.map((f) => f.name).toList(),
        'note': sleepNote,
        'quality': sleepQuality,
        'finalWakeTime': DateHelper.formatTime(finalWakeTime),
        'midWakeList': midWakeList,
        'naps': _naps.map((n) => {
              'start': DateHelper.formatTime(n.start),
              'end': DateHelper.formatTime(n.end),
              'minutes': DateHelper.calcDurationMinutes(n.start, n.end),
            }).toList(),
      },

      'savedAt': FieldValue.serverTimestamp(),
    };
try {
  final e = _emotions.firstWhere((x) => x.name.contains('整體情緒'));
  if (e.value != null) {
    payload['overallMood'] = (e.value!) * 1.0; // 確保寫入 double
  }
} catch (_) {
  debugPrint("⚠️ 沒找到整體情緒，無法寫入 overallMood");
}
    // 🔥 生理期手動判斷邏輯
    if (_isPeriod == true) {
      // ---- 若今天是生理期 ----
      payload['isPeriod'] = true;

      // A. 若舊資料沒有開始日 → 今天就是經期開始
      payload['periodStartId'] = oldStartId ?? docId;

      // B. 經期中不可能有結束日
      payload['periodEndId'] = null;

    } else {
      // ---- 若今天不是生理期 ----
      payload['isPeriod'] = false;

      // 若昨天是經期，而今天關閉 → 今天是經期結束
      if (oldIsPeriod == true) {
        payload['periodEndId'] = docId;
      }

      // 非經期時不應動 periodStartId（保留）
      payload['periodStartId'] = oldStartId;
    }

    await ref.set(payload, SetOptions(merge: true));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已儲存成功！')),
    );

  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}


  /// 若「整體情緒」有填，直接用；否則回退到所有有數字項目的平均
  double? _overallFromEmotions(List list) {
    // 1) 找「整體情緒」項目
    for (final e in list.cast<Map>()) {
      final name = (e['name'] ?? '').toString();
      final v = e['value'];
      if (name == '整體情緒' && v is num) {
        return v.toDouble();
      }
    }
    // 2) 平均其他有值的項目
    final vals = list
        .cast<Map>()
        .map((e) => e['value'])
        .where((v) => v is num)
        .cast<num>()
        .map((n) => n.toDouble())
        .toList();
    if (vals.isEmpty) return null;
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    return double.parse(avg.toStringAsFixed(1));
  }

  Future<void> _pickRecordTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _recordTime,
    );
    if (picked != null) setState(() => _recordTime = picked);
  }

  // emotion actions
  Future<void> _addEmotion() async {
    final name = await showTextDialog(context, '新增情緒項目', '項目名稱');
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _emotions.add(EmotionItem(name.trim())));
    }
  }

  Future<void> _renameEmotion(int i) async {
    final name = await showTextDialog(context, '重新命名', _emotions[i].name);
    if (i == 0) return;
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _emotions[i] = _emotions[i].copyWith(name: name.trim()));
    }
  }

  void _deleteEmotion(int i) => setState(() => _emotions.removeAt(i));

  Future<int?> showSliderPicker(
  BuildContext context, {
  required int initial,
  int min = 0,
  int max = 10,
}) async {
  int temp = initial.clamp(min, max);

  return showDialog<int>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('選擇分數'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$temp / $max'),
                Slider(
                  value: temp.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: max - min,
                  onChanged: (v) => setState(() => temp = v.round()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, temp),
                child: const Text('確定'),
              ),
            ],
          );
        },
      );
    },
  );
}
  // 記錄日期/時間

  @override
  Widget build(BuildContext context) {
    final pages = [
      _pageWrapper(
  _EmotionPage(
  items: _emotions,
  onAdd: _addEmotion,
  onRename: _renameEmotion,
  onDelete: _deleteEmotion,
  onChangeValue: (i, v) {
    setState(() {
      _emotions[i] = _emotions[i].copyWith(value: v);
    });
  },
),
),
      _pageWrapper(_SymptomPage(
        items: _symptoms,
        onAdd: () => setState(
          () => _symptoms.add(SymptomItem(name: '症狀 ${_symptoms.length + 1}')),
        ),
        onRename: (i) async {
          final name = await showTextDialog(context, '重新命名', _symptoms[i].name);
          if (name != null && name.trim().isNotEmpty) {
            setState(
                () => _symptoms[i] = _symptoms[i].copyWith(name: name.trim()));
          }
        },
        onDelete: (i) => setState(() => _symptoms.removeAt(i)),
        isPeriod: _isPeriod,
        onTogglePeriod: (v) => setState(() => _isPeriod = v),
      )),
      _pageWrapper(_SleepPage(
        // 1) 基本睡眠時間
        sleepTime: sleepTime,
        wakeTime: wakeTime,
        onPickSleepTime: () async {
          final t = await showTimePicker(
              context: context, initialTime: TimeOfDay.now());
          if (t != null) setState(() => sleepTime = t);
        },
        onPickWakeTime: () async {
          final t = await showTimePicker(
              context: context, initialTime: TimeOfDay.now());
          if (t != null) setState(() => wakeTime = t);
        },

        // 2) 夜間睡眠的多選旗標
        flags: _sleepFlags,
        onToggleFlag: (f) => setState(() {
          if (_sleepFlags.contains(f)) {
            _sleepFlags.remove(f);
          } else {
            _sleepFlags.add(f);
          }
        }),

        // 3) 睡眠註記、主觀品質
        sleepNote: sleepNote,
        onChangeNote: (v) => setState(() => sleepNote = v),
        sleepQuality: sleepQuality,
        onPickValue: () async { // 修正: 改成 onPickQuality，並移除 (i)
          final v = await showSliderPicker(
            context,
            initial: sleepQuality ?? 1,
            min: 1,
            max: 10,
          );
          if (v != null) setState(() => sleepQuality = v);
        },
        finalWakeTime: finalWakeTime,
        onPickFinalWakeTime: () async {
           final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
           if (t != null) setState(() => finalWakeTime = t);
        },
        midWakeCtrl: _midWakeCtrl,
        onChangeMidWake: (v) => setState(() => midWakeList = v),

        // 4) 安眠藥
        tookHypnotic: tookHypnotic,
        onToggleHypnotic: (v) => setState(() => tookHypnotic = v),
        hypnoticName: hypnoticName,
        onChangeHypnoticName: (v) => setState(() => hypnoticName = v),
        hypnoticDose: hypnoticDose,
        onChangeHypnoticDose: (v) => setState(() => hypnoticDose = v),
        hypnoticNameCtrl: _hypnoticNameCtrl,
        hypnoticDoseCtrl: _hypnoticDoseCtrl,

        // 5) 小睡（開始/結束 → 自動算時長）
        naps: _naps,
        onAddNap: () async {
          final start = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.now(),
            helpText: '入睡時間',
            // 第一次選：入睡時間
            confirmText: '確定',
            cancelText: '取消',
          );
          if (start == null) return;

          final end = await showTimePicker(
            context: context,
            initialTime: start,
            helpText: '起床時間',
            // 第二次選：起床時間 ✅
            confirmText: '確定',
            cancelText: '取消',
          );
          if (end == null) return;

          if (start.hour == end.hour && start.minute == end.minute) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('開始與結束時間不可相同')),
            );
            return;
          }
          setState(() => _naps.add(NapItem(start: start, end: end)));
        },
        onEditNap: (i) async {
          final curr = _naps[i];

          final start = await showTimePicker(
            context: context,
            initialTime: curr.start,
            helpText: '入睡時間',
            confirmText: '確定',
            cancelText: '取消',
          );
          if (start == null) return;

          final end = await showTimePicker(
            context: context,
            initialTime: curr.end,
            helpText: '起床時間',
            // 第二次選：起床時間 ✅
            confirmText: '確定',
            cancelText: '取消',
          );
          if (end == null) return;

          if (start.hour == end.hour && start.minute == end.minute) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('開始與結束時間不可相同')),
            );
            return;
          }
          setState(() => _naps[i] = _naps[i].copyWith(start: start, end: end));
        },
        onDeleteNap: (i) => setState(() => _naps.removeAt(i)),
      )),
    ];

    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        toolbarHeight: 120,
  centerTitle: true,
          title: const QuotesTitle(), 
        actions: [
          // 如果正在儲存，顯示轉圈圈；否則顯示儲存圖示
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 80,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '儲存',
              onPressed: _saveAll, // 直接呼叫修改後的方法
            ),
        ],
      ),
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.sentiment_satisfied), label: '情緒'),
          BottomNavigationBarItem(icon: Icon(Icons.healing), label: '症狀'),
          BottomNavigationBarItem(
              icon: Icon(Icons.nightlight_round), label: '睡眠'),
        ],
      ),
    );
  }
}


// 記錄日期/時間列
class _RecordHeader extends StatelessWidget {
  const _RecordHeader({
    super.key,
    required this.dateText,
    required this.timeText,
    required this.onPickDate,
    required this.onPickTime,
  });

  final String dateText;
  final String timeText;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickTime;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.calendar_today),
                title: const Text('日期', style: TextStyle(fontSize: 12)),
                subtitle: Text(dateText),
                onTap: () async => await onPickDate(),
              ),
            ),
            Expanded(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.access_time),
                title: const Text('時間', style: TextStyle(fontSize: 12)),
                subtitle: Text(timeText),
                onTap: () async => await onPickTime(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 情緒分頁
class _EmotionPage extends StatelessWidget {
  const _EmotionPage({
    Key? key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onChangeValue 
  }) : super(key: key);

  final List<EmotionItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
final void Function(int index, int value) onChangeValue;


 @override
Widget build(BuildContext context) {
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // 🔹 情緒清單（Slider 版）
      ...List.generate(items.length, (i) {
        final item = items[i];
const Map<String, String> emotionDisplayTextMap = {
    '整體情緒': '今天整體過得還好嗎？',
    '焦慮程度': '今天有感到緊繃或不安嗎？',
    '憂鬱程度': '今天心情有比較低落嗎？',
    '空虛程度': '有一種空空的感覺嗎？',
    '無聊程度': '今天有提不起勁嗎？',
    '難過程度': '今天有比較想哭或委屈嗎？',
    '開心程度': '今天有感到一點點開心嗎？',
    '無望感': '有覺得看不到出口嗎？',
    '孤獨感': '今天有覺得自己被落下嗎？',
    '動力': '今天做事有力氣嗎？',
    '自殺意念': '有出現讓你感到害怕的念頭嗎？',
    '食慾': '今天吃東西還順利嗎？',
    '能量': '今天身體的能量還夠嗎？',
    '活動量': '今天有稍微動一動嗎？',
    '疲倦程度': '今天是不是很累了？',
  };

  const emotionRightIconMap = {
  '整體情緒': 'assets/emotion/overall.png',
  '焦慮程度': 'assets/emotion/anxious.png',
  '憂鬱程度': 'assets/emotion/depression.png',
  '空虛程度': 'assets/emotion/absence.png',
  '無聊程度': 'assets/emotion/boring.png',
  '難過程度': 'assets/emotion/sad.png',
  '開心程度': 'assets/emotion/happy.png',
  '無望感': 'assets/emotion/despair.png',
  '孤獨感': 'assets/emotion/loneliness.png',
  '動力': 'assets/emotion/power.png',
  '自殺意念': 'assets/emotion/自殺意念.png',
  '食慾': 'assets/emotion/食慾.png',
  '能量': 'assets/emotion/energy.png',
  '活動量': 'assets/emotion/活動量.png',
  '疲倦程度': 'assets/emotion/tired.png',
};

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 情緒名稱 + 編輯 / 刪除
                Row(
                  children: [
                    Expanded(
                      child: Text(
  emotionDisplayTextMap[item.name] ?? item.name,
  style: Theme.of(context).textTheme.titleMedium,
)
                    ),
                    if (i != 0)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => onRename(i),
                      ),
                    if (i != 0)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onDelete(i),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                // 🎚️ 情緒 Slider
                EmotionSlider(
  label: item.name,
  value: item.value ?? 1,
  onChanged: (v) => onChangeValue(i, v),
leftIcon: 'assets/emotion/default.png',

  rightIcon: emotionRightIconMap[item.name]
      ?? 'assets/emotion/default.png',


  gradientColors: const [
    Color(0xFF9AD0EC),
    Color(0xFFFFE08A),
  ],
),
              ],
            ),
          ),
        );
      }),

      const SizedBox(height: 12),

      // ➕ 新增情緒
      OutlinedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('新增情緒項目'),
      ),
    ],
  );
}
}

/// 症狀分頁
class _SymptomPage extends StatelessWidget {
  final List<SymptomItem> items;
  final VoidCallback onAdd;
  final Future<void> Function(int index) onRename;
  final void Function(int index) onDelete;
  
  
  // 接收外部傳入的狀態
  final bool isPeriod;
  final ValueChanged<bool> onTogglePeriod;

  const _SymptomPage({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.isPeriod,
    required this.onTogglePeriod,
  });

  @override
  Widget build(BuildContext context) {
    // 根據開關狀態決定顏色
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = Colors.pinkAccent;
    // 開啟時的背景 (ON)
    final activeBg = isDark 
      ? Colors.pinkAccent.withValues(alpha: 0.15) // 深色模式：深一點的粉紅透光
      : Colors.pink.withValues(alpha: 0.1);       // 淺色模式：淺粉紅

    // 關閉時的顏色 (OFF) - 這就是修正的關鍵！
    final inactiveColor = isDark ? Colors.pink.shade200 : Colors.pink.shade200;
    final inactiveBg = isDark 
        ? const Color(0xFF2A1C20)  // 🔥 深色模式：改成「帶有粉色調的深灰」，讓白字浮現
        : const Color(0xFFFFF5F7); // 淺色模式：原本的櫻花白

        final titleColor = isPeriod
        ? (isDark ? Colors.pinkAccent : Colors.pink)
        : (isDark ? Colors.white : Colors.grey.shade700);

    final subTitleColor = isPeriod
        ? (isDark ? Colors.pink.shade200 : Colors.pink.shade300)
        : Colors.grey;
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. 生理期卡片
        Card(
          elevation: 0,
          // 邊框：沒來時也有淡淡的粉色邊框
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isPeriod ? activeColor : inactiveColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          // 背景：隨時都有顏色
          color: isPeriod ? activeBg : inactiveBg,
          
          child: SwitchListTile(
            // 圖示：沒來時是可愛的淡粉色水滴
            secondary: Icon(
              Icons.water_drop, 
              color: isPeriod ? activeColor : inactiveColor,
              size: 28,
            ),
            
            // 🔥 標題：開啟顯示「生理期中」，關閉顯示「生理期來了嗎？」
            title: Text(
              isPeriod ? '生理期中 🩸' : '生理期來了嗎？',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPeriod ? Colors.pink : colorScheme.onSurface,
              ),
            ),
            
            // 副標題：只有開啟時才顯示詳細資訊 (或你可以簡化顯示)
            subtitle: Text(
              isPeriod ? '紀錄中...' : '紀錄週期，預測下次經期',
              style: TextStyle(
                color: isPeriod ? Colors.pink.shade300 : Colors.grey,
              ),
            ),
            
            // 開關本體
            value: isPeriod, 
            activeColor: activeColor,
            onChanged: (v) => onTogglePeriod(v),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // 2. 症狀列表 (保持原本邏輯)
        // ✅ 獨立的提醒卡（放在症狀列表前面）
Card(
  elevation: 0,
  color: const Color(0xFFFFF1CC),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: BorderSide(color: Colors.amber.withValues(alpha: 0.35), width: 1),
  ),
  child: Padding(
    padding: const EdgeInsets.all(14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('溫柔提醒', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text(
                '不用很完整，想到什麼寫什麼就好。\n'
                '也可以先寫一個最明顯的感覺：例如「心悸」「胸悶」「頭痛」。',
                style: TextStyle(color: Colors.black54, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  ),
),

const SizedBox(height: 14),

// ✅ 你的症狀卡列表（原封不動邏輯，只有你要的 subtitle）
...List.generate(items.length, (i) {
  final s = items[i];
  final isEmpty = s.name.trim().isEmpty;

  final subtitleText = (i == 0)
      ? '今天身體或心裡，哪裡怪怪的嗎？'
      : (isEmpty ? '點一下可以修改' : null);

  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        title: Text(
          isEmpty ? (i == 0 ? '例如：手抖、疲倦、嗜睡…' : '症狀 ${i + 1}') : s.name,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isEmpty ? Colors.black.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.9),
          ),
        ),
        subtitle: subtitleText == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  subtitleText,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.45),
                    height: 1.3,
                  ),
                ),
              ),
        onTap: () => onRename(i),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => onDelete(i),
        ),
      ),
    ),
  );
}),

        
        // 3. 新增按鈕
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('新增症狀'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

/// 睡眠分頁
late final TextEditingController _hypnoticNameCtrl = TextEditingController();
late final TextEditingController _hypnoticDoseCtrl = TextEditingController();

class _SleepPage extends StatelessWidget {
  _SleepPage({
    super.key,
    required this.sleepTime,
    required this.wakeTime,
    required this.onPickSleepTime,
    required this.onPickWakeTime,
    required this.finalWakeTime,
    required this.onPickFinalWakeTime,
    required this.midWakeCtrl,
    required this.onChangeMidWake,
    required this.flags,
    required this.onToggleFlag,
    required this.sleepNote,
    required this.onChangeNote,
    required this.sleepQuality,
    required this.onPickValue,
    required this.naps,
    required this.onAddNap,
    required this.onEditNap,
    required this.onDeleteNap,
    required this.tookHypnotic,
    required this.onToggleHypnotic,
    required this.hypnoticName,
    required this.onChangeHypnoticName,
    required this.hypnoticDose,
    required this.onChangeHypnoticDose,
    required this.hypnoticNameCtrl,
    required this.hypnoticDoseCtrl,
  });

  final TimeOfDay? sleepTime;
  final TimeOfDay? wakeTime;
  final Future<void> Function() onPickSleepTime;
  final Future<void> Function() onPickWakeTime;
  final TimeOfDay? finalWakeTime;
  final Future<void> Function() onPickFinalWakeTime;
  final TextEditingController midWakeCtrl;
  final ValueChanged<String> onChangeMidWake;

  final Set<SleepFlag> flags;
  final void Function(SleepFlag) onToggleFlag;

  final String sleepNote;
  final void Function(String) onChangeNote;

  final int? sleepQuality; // 1~10
  final Future<void> Function() onPickValue;

  final List<NapItem> naps;
  final Future<void> Function() onAddNap;
  final Future<void> Function(int) onEditNap;
  final void Function(int) onDeleteNap;

  final bool tookHypnotic;
  final ValueChanged<bool> onToggleHypnotic;
  final String hypnoticName;
  final ValueChanged<String> onChangeHypnoticName;
  final String hypnoticDose;
  final ValueChanged<String> onChangeHypnoticDose;
  final TextEditingController hypnoticNameCtrl;
  final TextEditingController hypnoticDoseCtrl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SwitchListTile(
            secondary: const Icon(Icons.medication_outlined, color: Colors.purple),
            title: const Text('前一晚是否有吃安眠藥？'),
            value: tookHypnotic,
            onChanged: onToggleHypnotic,
          ),
        ),
        if (tookHypnotic) ...[
          const SizedBox(height: 8),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                  Text('安眠藥名稱與劑量',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hypnoticNameCtrl,
                    decoration: const InputDecoration(
                      hintText: '例如：Clonazepam（克癇平）',
                      border: OutlineInputBorder(),
                                        isDense: true,
                                        prefixIcon: Icon(Icons.local_pharmacy_outlined),
                    ),
                     
                                    onChanged: onChangeHypnoticName,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hypnoticDoseCtrl,
                    decoration: const InputDecoration(
                      hintText: '例如：0.5 mg',
                      border: OutlineInputBorder(),
                      isDense: true,
                    prefixIcon: Icon(Icons.numbers),),
                                        onChanged: onChangeHypnoticDose,
                  ),
                ],
              ),
            ),
          ),
        ],
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.bed_outlined, color: Colors.indigo),
            title: const Text('前一日準備睡覺時間'),
            subtitle: Text(sleepTime == null ? '—' : DateHelper.formatTime(sleepTime!)),
            onTap: onPickSleepTime,
          ),
        ),
        const SizedBox(height: 8),
        const Text('夜間睡眠狀況（可多選）',
            style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: (() {
            // 你想要的顯示順序（夜尿在「淺眠」之後、「睡睡醒醒」之前）
            const desired = [
              '優',
              '良好',
              '早醒',
              '多夢',
              '淺眠',
              '夜尿', // ← 放在這裡
              '睡睡醒醒',
              '睡眠不足',
              '入睡困難 (躺超過 30 分鐘才入睡)',
              '睡眠中斷 (醒來後超過 30 分鐘才又入睡)',
            ];

            // 根據中文標籤排序，不受 enum 定義順序影響
            final list = SleepFlag.values.toList()
              ..sort((a, b) {
                int ia = desired.indexOf(sleepFlagLabel(a));
                int ib = desired.indexOf(sleepFlagLabel(b));
                if (ia < 0) ia = 999;
                if (ib < 0) ib = 999;
                return ia.compareTo(ib);
              });

            return list.map((f) {
              final selected = flags.contains(f);
              return FilterChip(
                label: Text(sleepFlagLabel(f)),
                selected: selected,
                onSelected: (_) => onToggleFlag(f),
              );
            }).toList();
          })(),
        ),
        
        const SizedBox(height: 12),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.star_border_rounded, color: Colors.amber),
            title: const Text('自覺睡眠品質'),
            subtitle: Text(sleepQuality == null ? '—' : '$sleepQuality'),
            onTap: onPickValue,
          ),
        ),
        const SizedBox(height: 12),
        const Text('睡眠註記', style: TextStyle(fontWeight: FontWeight.w600)),
        TextField(
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: '例如：一直做夢，感覺好像沒睡覺，起床精神很差', border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.edit_note, color: Colors.grey),),
                        onChanged: onChangeNote,
        ),
        const SizedBox(height: 24),
        // 這裡可以把 _SectionTitle 換成 Text，或者確保你有定義 _SectionTitle
        const Text('中途與甦醒', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),

        // 截圖小撇步提示卡
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFCC80)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡 紀錄小撇步', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
                    const SizedBox(height: 4),
                    Text(
                      '半夜醒來或剛睡醒時不想開 App？\n試試「手機截圖」！起床後再看相簿時間回填即可，減少看螢幕的焦慮。',
                      style: TextStyle(fontSize: 13, color: Colors.brown.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 1. 半夜醒來時間
        TextField(
          controller: midWakeCtrl, // ✅ 使用傳入的 controller
          decoration: const InputDecoration(
            labelText: '半夜醒來時間 (可留白)',
            hintText: '例：03:15, 05:40 (看截圖時間)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.access_time_outlined),
          ),
          onChanged: onChangeMidWake, // ✅ 使用傳入的 callback
        ),

        const SizedBox(height: 16),

        // 2. 最終甦醒時刻 (睜開眼)
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.wb_twilight, color: Colors.orange),
            title: const Text('甦醒時刻 (睜開眼)'),
            subtitle: Text(
              finalWakeTime == null ? '尚未設定' : DateHelper.formatTime(finalWakeTime),
              style: TextStyle(color: finalWakeTime == null ? Colors.grey : Colors.black),
            ),
            onTap: onPickFinalWakeTime,
          ),
        ),

        // 3. 離床活動時間 (原本的 wakeTime 移到這裡)
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.directions_run, color: Colors.blue),
            title: const Text('離床活動時間'),
            subtitle: Text(
              wakeTime == null ? '—' : DateHelper.formatTime(wakeTime),
            ),
            onTap: onPickWakeTime,
          ),
        ),
        
        const SizedBox(height: 16),
        const Text('小睡（可新增多筆）', style: TextStyle(fontWeight: FontWeight.w600)),
        ...List.generate(naps.length, (i) {
          final n = naps[i];
          return Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.timer_outlined, color: Colors.teal),
              title: Text('${DateHelper.formatTime(n.start)} – ${DateHelper.formatTime(n.end)}'),
              subtitle: Text('時長：${DateHelper.formatDurationText(n.duration.inMinutes)}'),
              onTap: () => onEditNap(i),
              trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDeleteNap(i)),
            ),
          );
        }),
        OutlinedButton.icon(
            onPressed: onAddNap,
            icon: const Icon(Icons.add),
            label: const Text('新增小睡')),
      ],
    );
  }
}

/// -------------------- 小元件 --------------------
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {Key? key}) : super(key: key);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

class _ListTileButton extends StatelessWidget {
  const _ListTileButton(
      {super.key,
      required this.label,
      required this.valueText,
      required this.onTap});

  final String label;
  final String valueText;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        title: Text(label),
        subtitle: Text(valueText),
        trailing: const Icon(Icons.keyboard_arrow_down),
        onTap: onTap,
      ),
    );
  }
}

class _SaveHintButton extends StatelessWidget {
  const _SaveHintButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.save_outlined),
      label: const Text('儲存'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: const StadiumBorder(),
      ),
      onPressed: onPressed,
    );
  }
}
