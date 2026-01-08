import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/date_helper.dart';
import '../models/daily_record.dart';
import '../quotes.dart';
import '../widgets/main_drawer.dart';

import 'models/emotion_item.dart';
import 'models/symptom_item.dart';
import 'models/sleep_flag.dart';
import 'widgets/emotion_page.dart';
import 'widgets/symptom_page.dart';
import 'widgets/sleep_page.dart';
// import '../models/period_cycle.dart';

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
late final TextEditingController _hypnoticNameCtrl = TextEditingController();
late final TextEditingController _hypnoticDoseCtrl = TextEditingController();
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
  EmotionPage(
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
      _pageWrapper(SymptomPage(
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
      _pageWrapper(SleepPage(
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
