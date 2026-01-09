import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/date_helper.dart';
import '../models/daily_record.dart';
import '../widgets/main_drawer.dart';
import '../quotes.dart';

// Import refactored modules
import 'daily_record_helpers.dart';
import 'daily_record_dialogs.dart';
import 'daily_record_widgets.dart';
import 'daily_record_pages.dart';

/// Main Screen
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
  TimeOfDay? finalWakeTime;
  String midWakeList = '';
  late final TextEditingController _midWakeCtrl = TextEditingController();
  late final TextEditingController _hypnoticNameCtrl = TextEditingController();
  late final TextEditingController _hypnoticDoseCtrl = TextEditingController();
  final Set<SleepFlag> _sleepFlags = {};
  String sleepNote = '';
  int? sleepQuality;
  final List<NapItem> _naps = [];

  // ——— 共用：包裹每個分頁（頁首 + 內容 + 底部儲存鈕） ———
  Widget _pageWrapper(Widget child) {
    return Column(
      children: [
        RecordHeader(
          dateText: DateHelper.toDisplay(_recordDate),
          timeText: DateHelper.formatTime(_recordTime),
          onPickDate: _pickRecordDate,
          onPickTime: _pickRecordTime,
        ),
        Expanded(child: child),
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
        // A. 這一天已經有紀錄 → 完整讀取
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

          // 生理期狀態
          _isPeriod = record.isPeriod == true;
        });
      } else {
        // B. 今日沒有紀錄 → 自動推算生理期（看昨天）
        await _loadPeriodState(date);

        // C. 清空其他欄位，但保留剛推算的 _isPeriod
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
      final yesterdayDate = currentDate.subtract(const Duration(days: 1));
      final yesterdayId = DateHelper.toId(yesterdayDate);

      final yesterdaySnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .doc(yesterdayId)
          .get();

      if (!yesterdaySnap.exists || yesterdaySnap.data() == null) {
        _isPeriod = false;
        return;
      }

      final yesterdayRecord = DailyRecord.fromFirestore(yesterdaySnap);

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

  Future<void> _pickRecordDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) {
      setState(() => _recordDate = picked);
      await _loadExistingData(_recordDate);
    }
  }

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
      final oldSnap = await ref.get();
      String? oldStartId;
      bool oldIsPeriod = false;

      if (oldSnap.exists && oldSnap.data() != null) {
        final old = DailyRecord.fromFirestore(oldSnap);
        oldStartId = old.periodStartId;
        oldIsPeriod = old.isPeriod;
      }

      final payload = <String, dynamic>{
        'emotions': _emotions
            .map((e) => {'name': e.name, 'value': e.value})
            .toList(),
        'symptoms': _symptoms.map((s) => s.name).toList(),
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
          'naps': _naps
              .map((n) => {
                    'start': DateHelper.formatTime(n.start),
                    'end': DateHelper.formatTime(n.end),
                    'minutes': DateHelper.calcDurationMinutes(n.start, n.end),
                  })
              .toList(),
        },
        'savedAt': FieldValue.serverTimestamp(),
      };

      try {
        final e = _emotions.firstWhere((x) => x.name.contains('整體情緒'));
        if (e.value != null) {
          payload['overallMood'] = (e.value!) * 1.0;
        }
      } catch (_) {
        debugPrint("⚠️ 沒找到整體情緒，無法寫入 overallMood");
      }

      if (_isPeriod == true) {
        payload['isPeriod'] = true;
        payload['periodStartId'] = oldStartId ?? docId;
        payload['periodEndId'] = null;
      } else {
        payload['isPeriod'] = false;
        if (oldIsPeriod == true) {
          payload['periodEndId'] = docId;
        }
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

  Future<void> _pickRecordTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _recordTime,
    );
    if (picked != null) setState(() => _recordTime = picked);
  }

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
          () => _symptoms.add(
              SymptomItem(name: '症狀 ${_symptoms.length + 1}')),
        ),
        onRename: (i) async {
          final name = await showTextDialog(
              context, '重新命名', _symptoms[i].name);
          if (name != null && name.trim().isNotEmpty) {
            setState(() => _symptoms[i] =
                _symptoms[i].copyWith(name: name.trim()));
          }
        },
        onDelete: (i) => setState(() => _symptoms.removeAt(i)),
        isPeriod: _isPeriod,
        onTogglePeriod: (v) => setState(() => _isPeriod = v),
      )),
      _pageWrapper(SleepPage(
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
        flags: _sleepFlags,
        onToggleFlag: (f) => setState(() {
          if (_sleepFlags.contains(f)) {
            _sleepFlags.remove(f);
          } else {
            _sleepFlags.add(f);
          }
        }),
        sleepNote: sleepNote,
        onChangeNote: (v) => setState(() => sleepNote = v),
        sleepQuality: sleepQuality,
        onPickValue: () async {
          final v = await showSliderPicker(
            context: context,
            initial: sleepQuality ?? 1,
            min: 1,
            max: 10,
            title: '選擇睡眠品質',
          );
          if (v != null) setState(() => sleepQuality = v);
        },
        finalWakeTime: finalWakeTime,
        onPickFinalWakeTime: () async {
          final t =
              await showTimePicker(context: context, initialTime: TimeOfDay.now());
          if (t != null) setState(() => finalWakeTime = t);
        },
        midWakeCtrl: _midWakeCtrl,
        onChangeMidWake: (v) => setState(() => midWakeList = v),
        tookHypnotic: tookHypnotic,
        onToggleHypnotic: (v) => setState(() => tookHypnotic = v),
        hypnoticName: hypnoticName,
        onChangeHypnoticName: (v) => setState(() => hypnoticName = v),
        hypnoticDose: hypnoticDose,
        onChangeHypnoticDose: (v) => setState(() => hypnoticDose = v),
        hypnoticNameCtrl: _hypnoticNameCtrl,
        hypnoticDoseCtrl: _hypnoticDoseCtrl,
        naps: _naps,
        onAddNap: () async {
          final start = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.now(),
            helpText: '入睡時間',
            confirmText: '確定',
            cancelText: '取消',
          );
          if (start == null) return;

          final end = await showTimePicker(
            context: context,
            initialTime: start,
            helpText: '起床時間',
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
          setState(
              () => _naps[i] = _naps[i].copyWith(start: start, end: end));
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
              onPressed: _saveAll,
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
