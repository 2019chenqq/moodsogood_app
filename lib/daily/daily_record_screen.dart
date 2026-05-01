import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../utils/date_helper.dart';
import '../utils/firebase_sync_config.dart';
import '../models/daily_record.dart';
import '../widgets/main_drawer.dart';
import 'daily_record_repository.dart';

// Import refactored modules
import 'daily_record_helpers.dart';
import 'daily_record_dialogs.dart';
import 'daily_record_widgets.dart';
import 'daily_record_pages.dart';
import 'emotion_page_checkbox.dart';

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
  final Set<DateTime> _periodSelectedDates = <DateTime>{};
  DateTime _periodFocusedMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _periodCycleLength = 28;
  bool _isUpdatingPeriodCalendar = false;
  bool _useNewEmotionPage = true; // 可切換新舊情緒頁
  int? _lastSuicidalValue;

  // ——— 目前紀錄日期與時間（給頁首顯示；docId 只吃日期） ———
  DateTime _recordDate = DateTime.now();
  TimeOfDay _recordTime = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
    _loadPeriodCalendarState();
    _loadExistingData(_recordDate); // 一進來就載入今天的紀錄（含生理期狀態）
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DateTime> _periodStarts() {
    final sorted = _periodSelectedDates.toList()..sort();
    if (sorted.isEmpty) return const [];

    final starts = <DateTime>[];
    for (final day in sorted) {
      final prev = day.subtract(const Duration(days: 1));
      if (!_periodSelectedDates.contains(prev)) {
        starts.add(day);
      }
    }
    return starts;
  }

  int _inferCycleLengthFromDays(Set<DateTime> markedDays, {int fallback = 28}) {
    if (markedDays.isEmpty) return fallback;
    final sorted = markedDays.toList()..sort();
    final starts = <DateTime>[];
    for (final day in sorted) {
      final prev = day.subtract(const Duration(days: 1));
      if (!markedDays.contains(prev)) {
        starts.add(day);
      }
    }
    if (starts.length < 2) return fallback;

    final intervals = <int>[];
    for (int i = 1; i < starts.length; i++) {
      final diff = _dateOnly(starts[i]).difference(_dateOnly(starts[i - 1])).inDays;
      if (diff >= 15 && diff <= 60) {
        intervals.add(diff);
      }
    }
    if (intervals.isEmpty) return fallback;

    final sum = intervals.fold<int>(0, (acc, v) => acc + v);
    final avg = (sum / intervals.length).round();
    return avg.clamp(21, 45);
  }

  DateTime? _predictedNextPeriodStart() {
    final starts = _periodStarts();
    if (starts.isEmpty) return null;
    return starts.last.add(Duration(days: _periodCycleLength));
  }

  int? _arrivalDeltaDays() {
    final starts = _periodStarts();
    if (starts.length < 2) return null;
    final previous = starts[starts.length - 2];
    final latest = starts.last;
    final expected = previous.add(Duration(days: _periodCycleLength));
    return _dateOnly(latest).difference(_dateOnly(expected)).inDays;
  }

  Future<void> _loadPeriodCalendarState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();
    final startDate = _dateOnly(now.subtract(const Duration(days: 540)));
    final endDate = _dateOnly(now.add(const Duration(days: 365)));
    final selected = <DateTime>{};

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCycle = prefs.getInt('period_cycle_length');
      if (savedCycle != null && savedCycle >= 21 && savedCycle <= 45) {
        _periodCycleLength = savedCycle;
      }

      final savedDays = prefs.getStringList('period_selected_dates') ?? const [];
      for (final id in savedDays) {
        final d = DateTime.tryParse(id);
        if (d != null) selected.add(_dateOnly(d));
      }
    } catch (_) {}

    try {
      final repo = DailyRecordRepository();
      final localRecords = await repo.getDailyRecordsByDateRange(
        userId: uid,
        startDate: startDate,
        endDate: endDate,
      );
      for (final row in localRecords) {
        final periodData = row['periodData'];
        final isPeriod = periodData is Map && periodData['isPeriod'] == true;
        if (!isPeriod) continue;
        final date = DateTime.tryParse(row['date']?.toString() ?? '');
        if (date != null) {
          selected.add(_dateOnly(date));
        }
      }
    } catch (_) {}

    if (FirebaseSyncConfig.shouldSync()) {
      try {
        final configRef = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('periodTracker');
        final configSnap = await configRef.get();
        final config = configSnap.data();
        final cloudCycle = (config?['cycleLength'] as num?)?.toInt();
        if (cloudCycle != null && cloudCycle >= 21 && cloudCycle <= 45) {
          _periodCycleLength = cloudCycle;
        }

        final periodSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('dailyRecords')
            .where('date',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
            .get();

        for (final doc in periodSnap.docs) {
          if (doc.data()['isPeriod'] != true) continue;
          final ts = doc.data()['date'] as Timestamp?;
          if (ts != null) {
            selected.add(_dateOnly(ts.toDate()));
          }
        }
      } catch (e) {
        debugPrint('讀取生理期月曆資料失敗: $e');
      }
    }

    if (!mounted) return;
    _periodCycleLength = _inferCycleLengthFromDays(
      selected,
      fallback: _periodCycleLength,
    );
    setState(() {
      _periodSelectedDates
        ..clear()
        ..addAll(selected);
      _isPeriod = _periodSelectedDates.contains(_dateOnly(_recordDate));
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('period_cycle_length', _periodCycleLength);
    } catch (_) {}
  }

  Future<void> _persistPeriodDatesToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = _periodSelectedDates.toList()
        ..sort();
      await prefs.setStringList(
        'period_selected_dates',
        ids.map(DateHelper.toId).toList(),
      );
    } catch (_) {}
  }

  Future<void> _upsertPeriodDayLocal({
    required String uid,
    required DateTime day,
    required bool isPeriod,
    String? startId,
  }) async {
    final repo = DailyRecordRepository();
    final existing = await repo.getDailyRecord(userId: uid, date: day);

    await repo.saveDailyRecord(
      id: DateHelper.toId(day),
      userId: uid,
      date: day,
      emotions: (existing?['emotions'] as Map?)?.cast<String, dynamic>(),
      sleep: (existing?['sleep'] as Map?)?.cast<String, dynamic>(),
      bodySymptoms: (existing?['bodySymptoms'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      dailyActivities:
          (existing?['dailyActivities'] as Map?)?.cast<String, dynamic>(),
      medicines: (existing?['medicines'] as List?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
      periodData: {
        'isPeriod': isPeriod,
        'periodStartId': isPeriod ? startId : null,
        'periodEndId': null,
        'cycleLength': _periodCycleLength,
      },
    );
  }

  Future<void> _applyPeriodDaysUpdate({
    required Set<DateTime> days,
    required bool isPeriod,
    String? startId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || days.isEmpty || _isUpdatingPeriodCalendar) return;

    setState(() => _isUpdatingPeriodCalendar = true);
    try {
      if (isPeriod) {
        _periodSelectedDates.addAll(days);
      } else {
        _periodSelectedDates.removeAll(days);
      }
      _isPeriod = _periodSelectedDates.contains(_dateOnly(_recordDate));
      _periodCycleLength = _inferCycleLengthFromDays(
        _periodSelectedDates,
        fallback: _periodCycleLength,
      );
      await _persistPeriodDatesToPrefs();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('period_cycle_length', _periodCycleLength);
      } catch (_) {}

      for (final day in days) {
        await _upsertPeriodDayLocal(
          uid: uid,
          day: day,
          isPeriod: isPeriod,
          startId: startId,
        );
      }

      if (FirebaseSyncConfig.shouldSync()) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('periodTracker')
            .set({
          'cycleLength': _periodCycleLength,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final batch = FirebaseFirestore.instance.batch();
        for (final day in days) {
          final docId = DateHelper.toId(day);
          final ref = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('dailyRecords')
              .doc(docId);
          batch.set(
            ref,
            {
              'date': Timestamp.fromDate(day),
              'isPeriod': isPeriod,
              'periodStartId': isPeriod ? startId : null,
              'periodEndId': null,
              'periodCycleLength': _periodCycleLength,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('更新生理期月曆失敗: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新生理期資料失敗：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingPeriodCalendar = false);
      }
    }
  }

  Future<void> _onTapPeriodDate(DateTime date) async {
    final day = _dateOnly(date);
    if (_periodSelectedDates.contains(day)) {
      await _applyPeriodDaysUpdate(days: {day}, isPeriod: false);
      return;
    }

    final startId = DateHelper.toId(day);
    final autoDays = Set<DateTime>.from(
      List.generate(7, (i) => day.add(Duration(days: i))),
    );
    await _applyPeriodDaysUpdate(
      days: autoDays,
      isPeriod: true,
      startId: startId,
    );
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
  final List<EmotionItem> _emotions =
      kEmotionCheckboxNames.map((name) => EmotionItem(name)).toList();

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
    if (uid == null) {
      debugPrint('❌ No user ID found');
      return;
    }

    final docId = DateHelper.toId(date);
    debugPrint(
        '🔄 _loadExistingData called: uid=$uid, date=$date (ISO: ${date.toIso8601String()}), docId=$docId');

    try {
      // 1. 先嘗試從本地 SQLite 加載
      final repo = DailyRecordRepository();
      debugPrint('📦 Attempting to load from local SQLite...');
      var localData = await repo.getDailyRecord(userId: uid, date: date);

      if (localData != null) {
        debugPrint('✅ Loaded record from local SQLite: $docId');
        _applyLocalRecordData(localData, date);
        return;
      }

      debugPrint('⚠️  No local record found, trying Firebase...');

      // 2. 如果本地沒有，再從 Firebase 加載
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .doc(docId)
          .get();

      if (doc.exists && doc.data() != null) {
        debugPrint('✅ Loaded record from Firebase: $docId');
        // A. 這一天已經有紀錄 → 完整讀取
        final record = DailyRecord.fromFirestore(doc);
        _applyFirebaseRecordData(record, date);
      } else {
        debugPrint(
            '⚠️  No record found in Firebase either, loading period state...');
        // B. 今日沒有紀錄 → 自動推算生理期（看昨天）
        await _loadPeriodState(date);

        // C. 清空其他欄位，但保留剛推算的 _isPeriod
        _resetForm(keepPeriodStatus: true);
      }
    } catch (e, st) {
      debugPrint('❌ 讀取資料錯誤: $e\nStacktrace: $st');
    }
  }

  /// 從本地 SQLite 記錄應用數據
  void _applyLocalRecordData(Map<String, dynamic> data, DateTime date) {
    debugPrint('🔄 _applyLocalRecordData: data keys = ${data.keys.toList()}');

    // 解析 emotions 和其他 JSON 字段
    List<Emotion> emotions = [];
    if (data['emotions'] != null) {
      try {
        Map<String, dynamic> emotionMap;
        if (data['emotions'] is String) {
          emotionMap = jsonDecode(data['emotions']) as Map<String, dynamic>;
        } else if (data['emotions'] is Map) {
          emotionMap = data['emotions'] as Map<String, dynamic>;
        } else {
          throw TypeError();
        }
        debugPrint('✅ Parsed emotions from JSON: $emotionMap');
        emotionMap.forEach((name, value) {
          emotions.add(Emotion(name: name, value: value as int?));
        });
        debugPrint('✅ Total emotions parsed: ${emotions.length}');
      } catch (e) {
        debugPrint('❌ Failed to parse emotions: $e');
      }
    } else {
      debugPrint('⚠️  No emotions field in data');
    }

    List<String> symptoms = [];
    if (data['bodySymptoms'] != null) {
      try {
        List<dynamic> symptomList;
        if (data['bodySymptoms'] is String) {
          symptomList = jsonDecode(data['bodySymptoms']) as List<dynamic>;
        } else if (data['bodySymptoms'] is List) {
          symptomList = data['bodySymptoms'] as List<dynamic>;
        } else {
          throw TypeError();
        }
        symptoms = symptomList.cast<String>();
        debugPrint('✅ Parsed symptoms: ${symptoms.length} items');
      } catch (e) {
        debugPrint('❌ Failed to parse symptoms: $e');
      }
    }

    Map<String, dynamic>? periodData;
    if (data['periodData'] != null) {
      try {
        if (data['periodData'] is String) {
          periodData = jsonDecode(data['periodData']) as Map<String, dynamic>;
        } else if (data['periodData'] is Map) {
          periodData = data['periodData'] as Map<String, dynamic>;
        } else {
          throw TypeError();
        }
        debugPrint('✅ Parsed periodData: $periodData');
      } catch (e) {
        debugPrint('❌ Failed to parse periodData: $e');
      }
    }

    SleepData sleepData = SleepData();
    if (data['sleep'] != null) {
      try {
        Map<String, dynamic> sleepMap;
        if (data['sleep'] is String) {
          sleepMap = jsonDecode(data['sleep']) as Map<String, dynamic>;
        } else if (data['sleep'] is Map) {
          sleepMap = data['sleep'] as Map<String, dynamic>;
        } else {
          throw TypeError();
        }
        sleepData = _parseSleepDataFromMap(sleepMap);
        debugPrint('✅ Parsed sleep data successfully');
      } catch (e, st) {
        debugPrint('❌ Failed to parse sleep: $e\nStacktrace: $st');
      }
    } else {
      debugPrint('⚠️  No sleep field in data');
    }

    debugPrint('🎨 Applying parsed data to UI...');
    setState(() {
      // 應用情緒
      if (emotions.isNotEmpty) {
        for (var i = 0; i < _emotions.length; i++) {
          final savedEmotion =
              emotions.where((e) => e.name == _emotions[i].name).firstOrNull;
          if (savedEmotion != null) {
            _emotions[i] = EmotionItem(
              _emotions[i].name,
              value: savedEmotion.value,
            );
          } else {
            _emotions[i] = EmotionItem(_emotions[i].name);
          }
        }
        debugPrint('✅ Applied ${emotions.length} emotions to UI');
      }

      // 應用症狀
      if (symptoms.isNotEmpty) {
        _symptoms
          ..clear()
          ..addAll(symptoms.map((n) => SymptomItem(name: n)));
        debugPrint('✅ Applied ${symptoms.length} symptoms to UI');
      }

      // 應用睡眠數據
      tookHypnotic = sleepData.tookHypnotic;
      hypnoticName = sleepData.hypnoticName ?? '';
      _hypnoticNameCtrl.text = hypnoticName;
      hypnoticDose = sleepData.hypnoticDose ?? '';
      _hypnoticDoseCtrl.text = hypnoticDose;

      sleepTime = sleepData.sleepTime;
      wakeTime = sleepData.wakeTime;
      finalWakeTime = sleepData.finalWakeTime;

      midWakeList = sleepData.midWakeList ?? '';
      _midWakeCtrl.text = midWakeList;

      // 睡眠標籤
      _sleepFlags.clear();
      for (final f in sleepData.flags) {
        try {
          final match = SleepFlag.values.firstWhere((e) => e.name == f);
          _sleepFlags.add(match);
        } catch (_) {}
      }

      sleepNote = sleepData.note ?? '';
      sleepQuality = sleepData.quality;

      // 小睡
      _naps
        ..clear()
        ..addAll(sleepData.naps);

      // 生理期狀態（月曆資料優先）
      final localPeriod = periodData?['isPeriod'] == true;
      _isPeriod = _periodSelectedDates.contains(_dateOnly(date)) || localPeriod;

      debugPrint('✅ All data applied to UI successfully');
    });
  }

  /// 從 Firebase 記錄應用數據
  void _applyFirebaseRecordData(DailyRecord record, DateTime date) {
    final s = record.sleep;

    setState(() {
      // --- 情緒 ---
      if (record.emotions.isNotEmpty) {
        for (var i = 0; i < _emotions.length; i++) {
          final savedEmotion = record.emotions
              .where((e) => e.name == _emotions[i].name)
              .firstOrNull;
          if (savedEmotion != null) {
            _emotions[i] = EmotionItem(
              _emotions[i].name,
              value: savedEmotion.value,
            );
          } else {
            _emotions[i] = EmotionItem(_emotions[i].name);
          }
        }
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

        // 生理期狀態（月曆資料優先）
        _isPeriod =
          _periodSelectedDates.contains(_dateOnly(date)) || record.isPeriod;
    });
  }

  /// 從 Map 解析睡眠數據
  SleepData _parseSleepDataFromMap(Map<String, dynamic> sleepMap) {
    return SleepData(
      tookHypnotic: sleepMap['tookHypnotic'] ?? false,
      hypnoticName: sleepMap['hypnoticName'],
      hypnoticDose: sleepMap['hypnoticDose'],
      sleepTime: sleepMap['sleepTime'] != null
          ? DateHelper.parseTime(sleepMap['sleepTime'])
          : null,
      wakeTime: sleepMap['wakeTime'] != null
          ? DateHelper.parseTime(sleepMap['wakeTime'])
          : null,
      finalWakeTime: sleepMap['finalWakeTime'] != null
          ? DateHelper.parseTime(sleepMap['finalWakeTime'])
          : null,
      midWakeList: sleepMap['midWakeList'],
      flags: List<String>.from(sleepMap['flags'] ?? []),
      note: sleepMap['note'],
      quality: sleepMap['quality'],
      naps: (sleepMap['naps'] as List?)
              ?.map((n) => NapItem(
                    start: DateHelper.parseTime(n['start']) ??
                        const TimeOfDay(hour: 0, minute: 0),
                    end: DateHelper.parseTime(n['end']) ??
                        const TimeOfDay(hour: 0, minute: 0),
                  ))
              .toList() ??
          [],
    );
  }

  Future<void> _loadPeriodState(DateTime currentDate) async {
    _isPeriod = _periodSelectedDates.contains(_dateOnly(currentDate));
  }

  Future<void> _pickRecordDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _recordDate = picked;
        _periodFocusedMonth = DateTime(picked.year, picked.month, 1);
      });
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
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'emotions': _emotions
            .where((e) => e.value != null)
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
        'periodCycleLength': _periodCycleLength,
      };

      // 計算整體情緒：所有已選情緒的平均值
      final selectedEmotions = _emotions.where((e) => e.value != null).toList();
      if (selectedEmotions.isNotEmpty) {
        final sum = selectedEmotions.fold<int>(0, (acc, e) => acc + e.value!);
        payload['overallMood'] = (sum / selectedEmotions.length);
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

        payload['periodNextExpectedStart'] =
          _predictedNextPeriodStart()?.toIso8601String();
        payload['periodArrivalDeltaDays'] = _arrivalDeltaDays();

      // Only sync to Firebase if enabled
      if (FirebaseSyncConfig.shouldSync()) {
        await ref.set(payload, SetOptions(merge: true));
      }

      // Always save to local database
      try {
        final repo = DailyRecordRepository();
        debugPrint('🏁 Start saving to local database...');
        debugPrint(
            '📅 Saving with date: $_recordDate (ISO: ${_recordDate.toIso8601String()})');
        debugPrint('👤 Saving with userId: $uid');

        final emotionsToSave = Map<String, dynamic>.from(_emotions
            .where((e) =>
                e.value != null &&
                e.name != '整體情緒') // Exclude overallMood from emotions
            .toList()
            .asMap()
            .map((k, v) => MapEntry(v.name, v.value)));
        debugPrint('📊 Emotions to save: $emotionsToSave');

        final symptomsToSave = _symptoms
            .map((s) => s.name)
            .where((name) => name.isNotEmpty)
            .toList();
        debugPrint(
            '🩹 Symptoms to save: $symptomsToSave (from _symptoms: ${_symptoms.map((s) => s.name).toList()})');

        await repo.saveDailyRecord(
          id: docId,
          userId: uid,
          date: _recordDate,
          emotions: emotionsToSave,
          bodySymptoms: symptomsToSave,
          sleep: {
            'sleepTime':
                sleepTime != null ? DateHelper.formatTime(sleepTime!) : null,
            'wakeTime':
                wakeTime != null ? DateHelper.formatTime(wakeTime!) : null,
            'finalWakeTime': finalWakeTime != null
                ? DateHelper.formatTime(finalWakeTime!)
                : null,
            'midWakeList': midWakeList,
            'quality': sleepQuality,
            'tookHypnotic': tookHypnotic,
            'hypnoticName': hypnoticName,
            'hypnoticDose': hypnoticDose,
            'flags': _sleepFlags.map((f) => f.name).toList(),
            'note': sleepNote,
            'naps': _naps
                .map((n) => {
                      'start': DateHelper.formatTime(n.start),
                      'end': DateHelper.formatTime(n.end),
                      'minutes': DateHelper.calcDurationMinutes(n.start, n.end),
                    })
                .toList(),
          },
          periodData: {
            'isPeriod': _isPeriod,
            'periodStartId': _isPeriod ? (oldStartId ?? docId) : oldStartId,
            'periodEndId': !_isPeriod && oldIsPeriod ? docId : null,
            'cycleLength': _periodCycleLength,
            'nextExpectedStart':
                _predictedNextPeriodStart()?.toIso8601String(),
            'arrivalDeltaDays': _arrivalDeltaDays(),
          },
        );
        debugPrint('✅ Local save completed successfully');
      } catch (e) {
        debugPrint('❌ Local storage failed: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本地存儲失敗：$e')),
        );
        return;
      }

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

  void _maybeShowEmergencyAlert() {
    if (!mounted) return;

    final suicidal = _emotions
        .where((e) => e.name == '自殺意念')
        .map((e) => e.value)
        .firstOrNull;

    final lastValue = _lastSuicidalValue ?? 0;
    _lastSuicidalValue = suicidal ?? 0;

    if (suicidal != null && suicidal >= 7 && lastValue < 7) {
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: const Text('緊急提醒'),
          content: const Text(
            '自殺意念分數偏高，請立刻聯絡緊急求助專線或馬上前往急診。\n\n'
            '【立即危險】\n'
            '📞 撥打 119（救護車／急診）\n\n'
            '【有人可以陪你】\n'
            '📞 生命線\n'
            '1995（24 小時）\n'
            '對象：情緒崩潰、想活不下去、需要有人陪你撐過此刻\n\n'
            '📞 安心專線（衛福部）\n'
            '1925（24 小時）\n'
            '對象：自殺意念、心理危機、重度低潮\n\n'
            '📞 張老師\n'
            '1980\n'
            '服務時間：每日 9:00–22:00（依地區略有不同）\n'
            '對象：情緒支持、談話陪伴',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? Theme.of(context).colorScheme.surface
        : const Color.fromARGB(255, 200, 206, 231);
    final pages = [
      // 情緒頁
      _pageWrapper(
        _useNewEmotionPage
            ? EmotionPageCheckbox(
                items: _emotions,
                onAdd: _addEmotion,
                onRename: _renameEmotion,
                onDelete: _deleteEmotion,
                onToggleChecked: (i, checked) {
                  setState(() {
                    _emotions[i] = _emotions[i].copyWith(
                      value: checked ? (_emotions[i].value ?? 5) : null,
                    );
                  });
                  _maybeShowEmergencyAlert();
                },
                onChangeValue: (i, v) {
                  setState(() {
                    _emotions[i] = _emotions[i].copyWith(value: v);
                  });
                  _maybeShowEmergencyAlert();
                },
              )
            : EmotionPage(
                items: _emotions,
                onAdd: _addEmotion,
                onRename: _renameEmotion,
                onDelete: _deleteEmotion,
                onChangeValue: (i, v) {
                  setState(() {
                    _emotions[i] = _emotions[i].copyWith(value: v);
                  });
                  _maybeShowEmergencyAlert();
                },
              ),
      ),
      _pageWrapper(SymptomPage(
        items: _symptoms,
        onAdd: () async {
          final name = await showTextDialog(context, '新增症狀', '症狀名稱');
          if (name != null && name.trim().isNotEmpty) {
            setState(() => _symptoms.add(SymptomItem(name: name.trim())));
          }
        },
        onRename: (i) async {
          final name = await showTextDialog(context, '重新命名', _symptoms[i].name);
          if (name != null && name.trim().isNotEmpty) {
            setState(
                () => _symptoms[i] = _symptoms[i].copyWith(name: name.trim()));
          }
        },
        onDelete: (i) => setState(() => _symptoms.removeAt(i)),
        onTogglePreset: (name, selected) {
          setState(() {
            if (selected) {
              if (!_symptoms.any((s) => s.name == name)) {
                _symptoms.add(SymptomItem(name: name));
              }
            } else {
              _symptoms.removeWhere((s) => s.name == name);
              if (_symptoms.isEmpty) {
                _symptoms.add(SymptomItem(name: ''));
              }
            }
          });
        },
        isPeriod: _isPeriod,
        onTogglePeriod: (v) => setState(() => _isPeriod = v),
        periodMarkedDays: _periodSelectedDates,
        periodFocusedMonth: _periodFocusedMonth,
        onTapPeriodDate: _onTapPeriodDate,
        onChangePeriodMonth: (month) {
          setState(() {
            _periodFocusedMonth = DateTime(month.year, month.month, 1);
          });
        },
        periodCycleLength: _periodCycleLength,
        nextExpectedStart: _predictedNextPeriodStart(),
        arrivalDeltaDays: _arrivalDeltaDays(),
        periodBusy: _isUpdatingPeriodCalendar,
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
          final t = await showTimePicker(
              context: context, initialTime: TimeOfDay.now());
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
          setState(() => _naps[i] = _naps[i].copyWith(start: start, end: end));
        },
        onDeleteNap: (i) => setState(() => _naps.removeAt(i)),
      )),
    ];
    final currentIndex = _index >= pages.length ? 0 : _index;

    return Scaffold(
      backgroundColor: scaffoldBg, // 淺色保持藍綠，深色改用系統底色
      drawer: const MainDrawer(),
      appBar: AppBar(
        toolbarHeight: 60,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: pages[currentIndex]),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveAll,
                    icon: const Icon(Icons.save),
                    label: Text(_isSaving ? '儲存中…' : '儲存全部'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
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
