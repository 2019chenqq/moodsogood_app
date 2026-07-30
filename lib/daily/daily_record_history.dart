import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../diary/diary_repository.dart';
import '../models/daily_record.dart'; // 確保引用正確
import '../models/weekly_record.dart';
import '../utils/date_helper.dart'; // 確保引用正確
import 'record_detail_screen.dart'; // 確保引用正確
import '../models/period_cycle.dart';
import '../widgets/main_drawer.dart';
import 'daily_record_repository.dart';
import 'widgets/emotion_balance_chart_widget.dart';
import 'widgets/emotion_page_checkbox.dart';
import 'widgets/history_chart_widget.dart';
import 'widgets/pro_locked_view.dart';
import 'widgets/weekly_summary_card.dart';
import 'weekly_record_repository.dart';
import '../utils/firebase_sync_config.dart';
import '../utils/health_data_encryption_service.dart';
import '../widgets/trend_range_selector.dart';
import '../constants/healing_design_system.dart';
import '../analytics_service.dart';

const Map<String, String> ksleepFlagMap = {
  'good': '優',
  'ok': '良好',
  'earlyWake': '早醒',
  'dreams': '多夢',
  'lightSleep': '淺眠',
  'nocturia': '夜尿',
  'fragmented': '睡睡醒醒',
  'insufficient': '睡眠不足',
  'initInsomnia': '入睡困難',
  'interrupted': '睡眠中斷',
};
const bool kDemoUnlockPro = true;

class _DiaryMoodScore {
  const _DiaryMoodScore({
    required this.score,
    required this.scale,
  });

  final double score;
  final int scale;
}

class DailyRecordHistory extends StatefulWidget {
  const DailyRecordHistory({super.key, this.initialTab = 0});

  /// 0: 紀錄列表與週摘要, 1: 睡眠摘要, 2: 情緒趨勢
  final int initialTab;

  @override
  State<DailyRecordHistory> createState() => _DailyRecordHistoryState();
}

class _DailyRecordHistoryState extends State<DailyRecordHistory> {
  static const String _overallMoodLabel = '整體情緒';

  int? _selectedRangeDays = 7;
  DateTimeRange? _selectedDateRange; // 新增：月曆自訂區間
  int _historyWeekStartDay = DateTime.monday; // ✅ 補上

  // 動態情緒選擇
  String _selectedEmotion = '';

  // 用於強制刷新的計數器
  int _refreshCounter = 0;
  Future<WeeklyRecord?>? _currentWeeklyRecordFuture;
  String? _weeklyRecordUserId;

  String? _periodLabel(DailyRecord r) {
    if (r.isPeriod == true) {
      return '生理期';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadHistoryWeekStartDay();
    AnalyticsService.logPage('record_history_page');
  }

  Future<void> _loadHistoryWeekStartDay() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('historyWeekStartDay');
    if (!mounted) return;
    setState(() {
      _historyWeekStartDay = _normalizeWeekday(saved);
    });
  }

  Future<void> _updateHistoryWeekStartDay(int weekday) async {
    final normalized = _normalizeWeekday(weekday);
    if (_historyWeekStartDay == normalized) return;
    setState(() => _historyWeekStartDay = normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('historyWeekStartDay', normalized);
  }

  int _normalizeWeekday(int? weekday) {
    if (weekday == null ||
        weekday < DateTime.monday ||
        weekday > DateTime.sunday) {
      return DateTime.monday;
    }
    return weekday;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _currentWeekStart() {
    final today = _dateOnly(DateTime.now());
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  Future<WeeklyRecord?> _weeklyRecordFuture(String uid) {
    if (_currentWeeklyRecordFuture == null || _weeklyRecordUserId != uid) {
      _weeklyRecordUserId = uid;
      _currentWeeklyRecordFuture = WeeklyRecordRepository().getWeeklyRecord(
        userId: uid,
        weekStart: _currentWeekStart(),
      );
    }
    return _currentWeeklyRecordFuture!;
  }

  String _weekdayText(int weekday) {
    const labels = {
      DateTime.monday: '星期一',
      DateTime.tuesday: '星期二',
      DateTime.wednesday: '星期三',
      DateTime.thursday: '星期四',
      DateTime.friday: '星期五',
      DateTime.saturday: '星期六',
      DateTime.sunday: '星期日',
    };
    return labels[weekday] ?? '星期一';
  }

  bool _hasSleepContent(SleepData s) {
    final hasMedication = s.tookHypnotic ||
        (s.hypnoticName?.trim().isNotEmpty ?? false) ||
        (s.hypnoticDose?.trim().isNotEmpty ?? false);
    final hasTime =
        s.sleepTime != null || s.wakeTime != null || s.finalWakeTime != null;
    final hasOther = (s.midWakeList?.trim().isNotEmpty ?? false) ||
        s.quality != null ||
        s.flags.isNotEmpty ||
        s.naps.isNotEmpty ||
        (s.note?.trim().isNotEmpty ?? false);
    return hasMedication || hasTime || hasOther;
  }

  bool _isNoDataRecord(DailyRecord r) {
    final hasEmotions = r.emotions.any((e) => e.value != null && e.value! > 0);
    final hasSymptoms = r.symptoms.any((s) => s.trim().isNotEmpty);
    final hasMood = r.overallMood != null;
    final hasSleep = _hasSleepContent(r.sleep);
    final hasPeriod = r.isPeriod;

    return !hasEmotions && !hasSymptoms && !hasMood && !hasSleep && !hasPeriod;
  }

  Future<void> _cleanupNoDataRecords(
    String uid,
    Map<String, DailyRecord> recordsMap,
  ) async {
    final idsToDelete = recordsMap.values
        .where(_isNoDataRecord)
        .map((r) => r.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();

    if (idsToDelete.isEmpty) return;

    debugPrint(
        '🧹 Cleaning ${idsToDelete.length} no-data records from history');

    final repo = DailyRecordRepository();
    for (final id in idsToDelete) {
      try {
        await repo.deleteDailyRecord(id);
      } catch (e) {
        debugPrint('⚠️ Local delete failed for $id: $e');
      }
    }

    if (FirebaseSyncConfig.shouldSync()) {
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final id in idsToDelete) {
          final ref = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('dailyRecords')
              .doc(id);
          batch.delete(ref);
        }
        await batch.commit();
      } catch (e) {
        debugPrint('⚠️ Cloud delete failed for no-data records: $e');
      }
    }

    for (final id in idsToDelete) {
      recordsMap.remove(id);
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 29)),
            end: now,
          ),
      helpText: '選擇日期區間',
      confirmText: '確認',
      cancelText: '取消',
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = DateTimeRange(
          start:
              DateTime(picked.start.year, picked.start.month, picked.start.day),
          end: DateTime(picked.end.year, picked.end.month, picked.end.day),
        );
      });
    }
  }

  int get _selectedSpanDays {
    if (_selectedDateRange == null) return _selectedRangeDays ?? 7;
    return _selectedDateRange!.end
            .difference(_selectedDateRange!.start)
            .inDays +
        1;
  }

  int? get _selectedSummaryTotalDays {
    if (_selectedDateRange != null) return _selectedSpanDays;
    return _selectedRangeDays;
  }

  String get _selectedSummarySubtitle {
    if (_selectedDateRange != null) {
      final start = _selectedDateRange!.start;
      final end = _selectedDateRange!.end;
      return '${start.month}/${start.day} – ${end.month}/${end.day}';
    }

    final days = _selectedRangeDays;
    if (days == null) return '全部紀錄';

    final today = _dateOnly(DateTime.now());
    final start = today.subtract(Duration(days: days - 1));
    return '近 $days 天（${start.month}/${start.day} – ${today.month}/${today.day}）';
  }

  bool _shouldUseMonthlyChartForRecords(List<DailyRecord> records) {
    if (records.length < 2) return false;
    final dates = records.map((r) => _dateOnly(r.date)).toList()..sort();
    return dates.last.difference(dates.first).inDays > 365;
  }

  @override
  Widget build(BuildContext context) {
    final bool isPro = kDemoUnlockPro;
    final pageIndex = widget.initialTab.clamp(0, 2);
    final pageTitle = switch (pageIndex) {
      1 => '睡眠摘要',
      2 => '情緒趨勢',
      _ => '紀錄歷程',
    };

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('未登入')),
      );
    }

    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      drawer: const MainDrawer(),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 60,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: HealingDesignSystem.adaptiveAppBarForeground(context),
          ),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          pageTitle,
          style: TextStyle(
            color: HealingDesignSystem.adaptiveAppBarForeground(context),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: FutureBuilder<List<DailyRecord>>(
        future: _loadAllRecords(uid),
        key: ValueKey(_refreshCounter), // 使用 ValueKey 強制重新構建
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('發生錯誤：${snapshot.error}'));
          }

          final dailyRecords = snapshot.data ?? [];
          dailyRecords.sort((a, b) => a.date.compareTo(b.date));

          // 取得所有出現過的情緒名稱
          final availableEmotions = _extractEmotionNames(dailyRecords);

          // 列表用的資料 (需過濾日期 + 反序)
          var listRecords = List<DailyRecord>.from(dailyRecords);
          listRecords = _applyDateFilter(listRecords);
          listRecords.sort((a, b) => b.date.compareTo(a.date));

          final periodQuery = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('periodCycles')
              .orderBy('startDate', descending: true);
          return StreamBuilder<List<HealthDocument>>(
            stream: HealthDataEncryptionService.watchEncrypted(periodQuery),
            builder: (context, periodSnap) {
              final cycles = periodSnap.data
                      ?.map((doc) => PeriodCycle.fromData(doc.id, doc.data))
                      .toList() ??
                  [];

              return switch (pageIndex) {
                1 => _buildSleepAnalysisPage(listRecords, isPro),
                2 => _buildProChartContent(
                    context,
                    dailyRecords,
                    availableEmotions,
                    cycles,
                    isPro,
                  ),
                _ => _buildListPage(listRecords, isPro, uid),
              };
            },
          );
        },
      ),
    );
  }

  /// 從本地 SQLite 和/或 Firebase 加載所有記錄
  /// - 免費用戶：僅從本地 SQLite 加載（最近 90 天）
  /// - Pro 用戶：從 Firebase 加載所有數據
  Future<List<DailyRecord>> _loadAllRecords(String uid) async {
    final bool isPro = kDemoUnlockPro;

    final endDate = DateTime.now();
    // 免費版：2年   Pro版：無限期
    final startDate = isPro
        ? DateTime(2020, 1, 1) // Pro 用戶查詢所有數據
        : endDate.subtract(const Duration(days: 730)); // 免費用戶只查詢最近 2 年

    debugPrint('📊 Loading records for ${isPro ? "Pro" : "Free"} user');
    debugPrint('👤 Using userId: $uid');
    debugPrint('📅 Date range: $startDate to $endDate');

    final Map<String, DailyRecord> recordsMap = {};

    // 🔧 改進：總是嘗試從本地加載作為備份
    // 這樣即使 Firebase 同步被禁用或失敗，仍然有數據可用
    try {
      final repo = DailyRecordRepository();
      debugPrint(
          '🔍 [LOCAL BACKUP] Loading records from local SQLite for user=$uid from $startDate to $endDate');

      final localRecords = await repo.getDailyRecordsByDateRange(
        userId: uid,
        startDate: startDate,
        endDate: endDate,
      );

      debugPrint('✅ Loaded ${localRecords.length} records from local database');

      for (var localRecord in localRecords) {
        final record = _convertLocalRecordToDailyRecord(localRecord);
        recordsMap[record.id] = record;
        debugPrint('  📦 Local: ${record.id} (${record.date})');
      }
    } catch (e) {
      debugPrint('❌ Local load failed (non-critical): $e');
    }

    // 免費用戶：從本地加載即可
    // Fake Pro gates only the UI range, not records available in free windows.
    // Merge Firebase as a backup so 7/30-day history does not disappear.

    // Pro 用戶：也從 Firebase 加載並合併
    try {
      debugPrint('🔍 [PRO USER] Loading records from Firebase...');
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .orderBy('date', descending: true)
          .get();

      debugPrint('✅ Loaded ${snapshot.docs.length} records from Firebase');

      for (var doc in snapshot.docs) {
        final data = await HealthDataEncryptionService.decryptData(doc.data());
        final record = DailyRecord.fromData(doc.id, data);
        recordsMap[record.id] = record;
        debugPrint('  ☁️  Firebase: ${record.id} (${record.date})');
      }
    } catch (e, st) {
      debugPrint(
          '⚠️  Firebase load failed (using local data): $e\nStacktrace: $st');
    }

    await _cleanupNoDataRecords(uid, recordsMap);

    final allRecords = recordsMap.values.toList();
    debugPrint('📊 Total records loaded: ${allRecords.length}');
    return allRecords;
  }

  /// 將單個本地記錄轉換為 DailyRecord 對象
  DailyRecord _convertLocalRecordToDailyRecord(Map<String, dynamic> record) {
    final date = DateTime.tryParse(record['date'] ?? '') ?? DateTime.now();
    final emotions = _parseEmotionsFromLocal(record['emotions']);
    final sleep = _parseSleepFromLocal(record['sleep']);

    // 計算整體情緒：所有情緒的平均值
    double? overallMood;
    if (emotions.isNotEmpty) {
      final sum = emotions.fold<int>(0, (acc, e) => acc + (e.value ?? 0));
      overallMood = (sum / emotions.length).toDouble();
    }

    return DailyRecord(
      id: record['id'] ?? '',
      date: date,
      emotions: emotions,
      overallMood: overallMood,
      symptoms: _parseBodySymptoms(record['bodySymptoms']),
      sleep: sleep,
      moodScale: (record['moodScale'] as num?)?.toInt() ?? 10,
      isPeriod: (record['periodData'] as Map?)?['isPeriod'] == true,
    );
  }

  /// 從本地存儲的 JSON 中解析情緒數據
  List<Emotion> _parseEmotionsFromLocal(dynamic emotionsData) {
    if (emotionsData == null) return [];
    if (emotionsData is String) {
      try {
        emotionsData = jsonDecode(emotionsData);
      } catch (e) {
        return [];
      }
    }
    if (emotionsData is! Map) return [];

    return (emotionsData as Map<String, dynamic>)
        .entries
        .where((e) =>
            (e.value as num?)?.toInt() != null &&
            (e.value as num).toInt() != 0 &&
            e.key != '整體情緒') // Exclude overallMood from emotions list
        .map((e) {
      return Emotion(name: e.key, value: (e.value as num?)?.toInt() ?? 0);
    }).toList();
  }

  /// 從本地存儲的 JSON 中解析睡眠數據
  SleepData _parseSleepFromLocal(dynamic sleepData) {
    if (sleepData == null) {
      return SleepData(
        sleepTime: null,
        wakeTime: null,
        quality: null,
        tookHypnotic: false,
        hypnoticName: null,
        hypnoticDose: null,
        flags: const [],
        note: null,
        naps: const [],
      );
    }

    if (sleepData is String) {
      try {
        sleepData = jsonDecode(sleepData);
      } catch (e) {
        return SleepData(
          sleepTime: null,
          wakeTime: null,
          quality: null,
          tookHypnotic: false,
          flags: const [],
          naps: const [],
        );
      }
    }

    if (sleepData is! Map) {
      return SleepData(
        sleepTime: null,
        wakeTime: null,
        quality: null,
        tookHypnotic: false,
        flags: const [],
        naps: const [],
      );
    }

    final map = sleepData as Map<String, dynamic>;
    return SleepData(
      sleepTime: _parseTime(map['sleepTime']),
      wakeTime: _parseTime(map['wakeTime']),
      finalWakeTime: _parseTime(map['finalWakeTime']),
      quality: (map['quality'] as num?)?.toInt(),
      tookHypnotic: map['tookHypnotic'] ?? false,
      hypnoticName: map['hypnoticName'],
      hypnoticDose: map['hypnoticDose'],
      flags: (map['flags'] as List?)?.cast<String>() ?? const [],
      note: map['note'],
      naps: _parseNapsFromLocal(map['naps']),
    );
  }

  List<NapItem> _parseNapsFromLocal(dynamic napsData) {
    if (napsData is String) {
      try {
        napsData = jsonDecode(napsData);
      } catch (_) {
        return const [];
      }
    }
    if (napsData is! List) return const [];

    return napsData
        .whereType<Map>()
        .map((e) => NapItem.fromMap(e.cast<String, dynamic>()))
        .toList();
  }

  /// 解析時間字符串（格式 HH:MM）
  TimeOfDay? _parseTime(dynamic timeStr) {
    if (timeStr == null || timeStr is! String) return null;
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// 解析身體症狀
  List<String> _parseBodySymptoms(dynamic symptomsData) {
    if (symptomsData == null) return [];
    if (symptomsData is String) {
      try {
        symptomsData = jsonDecode(symptomsData);
      } catch (e) {
        return [];
      }
    }
    if (symptomsData is List) {
      return symptomsData.map((s) => s.toString()).toList();
    }
    return [];
  }

  Future<Map<DateTime, _DiaryMoodScore>> _loadDiaryMoodScores(
    String uid,
  ) async {
    final endDate = DateTime.now();
    final startDate = kDemoUnlockPro
        ? DateTime(2020, 1, 1)
        : endDate.subtract(const Duration(days: 730));
    final scores = <DateTime, _DiaryMoodScore>{};

    try {
      final entries = await DiaryRepository().list(limit: 5000);
      final start = _dateOnly(startDate);
      final end = _dateOnly(endDate);
      for (final entry in entries) {
        final score = entry.moodScore;
        if (score == null) continue;
        final date = _dateOnly(entry.date);
        if (date.isBefore(start) || date.isAfter(end)) continue;
        scores[date] = _DiaryMoodScore(score: score, scale: 10);
      }
    } catch (e) {
      debugPrint('Diary local mood load failed: $e');
    }

    try {
      final startId = DateHelper.toId(startDate);
      final endId = DateHelper.toId(endDate);
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('diary')
          .orderBy(FieldPath.documentId)
          .startAt([startId]).endAt([endId]).get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final date = DateTime.tryParse(doc.id);
        if (date == null) continue;

        final score = (data['overallMood'] as num?)?.toDouble() ??
            (data['moodScore'] as num?)?.toDouble();
        if (score == null) continue;
        final scale = (data['diaryMoodScale'] as num?)?.toInt();
        scores[_dateOnly(date)] = _DiaryMoodScore(
          score: score,
          scale: scale == 5 ? 5 : 10,
        );
      }
    } catch (e, st) {
      debugPrint('Diary Firebase mood load failed: $e\nStacktrace: $st');
    }

    return scores;
  }

  Map<DateTime, _DiaryMoodScore> _applyDiaryMoodDateFilter(
    Map<DateTime, _DiaryMoodScore> input,
  ) {
    if (_selectedDateRange != null) {
      final start = _dateOnly(_selectedDateRange!.start);
      final end = _dateOnly(_selectedDateRange!.end);
      return Map.fromEntries(input.entries.where((entry) {
        final date = _dateOnly(entry.key);
        return !date.isBefore(start) && !date.isAfter(end);
      }));
    }

    final days = _selectedRangeDays;
    if (days == null) return input;

    final today = _dateOnly(DateTime.now());
    final start = today.subtract(Duration(days: days - 1));
    return Map.fromEntries(input.entries.where((entry) {
      final date = _dateOnly(entry.key);
      return !date.isBefore(start) && !date.isAfter(today);
    }));
  }

  bool _isHistoryLocked(bool isPro) {
    if (isPro) return false;

    if (_selectedDateRange != null) return true;

    final days = _selectedRangeDays;

    if (days == 7 || days == 30) return false;

    return true;
  }

  Widget _buildListPage(
    List<DailyRecord> records,
    bool isPro,
    String uid,
  ) {
    final bool isLocked = _isHistoryLocked(isPro);

    return Container(
      color: HealingDesignSystem.adaptiveBackground(context),
      child: Column(
        children: [
          // ─────────────────────
          // 範圍摘要卡片（永遠顯示）
          // ─────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FutureBuilder<WeeklyRecord?>(
              future: _weeklyRecordFuture(uid),
              builder: (context, weeklySnapshot) {
                return WeeklySummaryCard(
                  records: records,
                  title: '狀態小結',
                  subtitle: _selectedSummarySubtitle,
                  totalDays: _selectedSummaryTotalDays,
                  currentWeeklyRecord: weeklySnapshot.data,
                );
              },
            ),
          ),

          // ─────────────────────
          // 日期篩選器
          // ─────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: HealingDesignSystem.adaptiveCardDecoration(
                context,
                radius: HealingDesignSystem.radiusM,
              ),
              child: Column(
                children: [
                  _buildDateRangeDropdown(),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ─────────────────────
          // 每日紀錄清單（此區依 Pro 狀態鎖）
          // ─────────────────────
          Expanded(
            child: isLocked
                ? buildProLockedView(
                    context: context,
                    title: '進階紀錄回顧',
                    description: '查看近 90 天、全部紀錄與自訂日期區間，需要升級 Pro。',
                  )
                : records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 54,
                              color: HealingDesignSystem.primaryBlue
                                  .withOpacity(0.3),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '沒有符合條件的紀錄',
                              style: TextStyle(
                                color: HealingDesignSystem.mutedText,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final r = records[index];
                          final periodText = _periodLabel(r);
                          final nightMinutes = _nightSleepMinutes(r.sleep);
                          final sleepText = nightMinutes != null
                              ? DateHelper.formatDurationText(nightMinutes)
                              : null;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                    HealingDesignSystem.radiusM),
                                onTap: () {
                                  final uid =
                                      FirebaseAuth.instance.currentUser?.uid;
                                  if (uid != null) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RecordDetailScreen(
                                          uid: uid,
                                          docId: r.id,
                                        ),
                                      ),
                                    ).then((_) {
                                      setState(() => _refreshCounter++);
                                    });
                                  }
                                },
                                child: Ink(
                                  decoration: HealingDesignSystem
                                      .adaptiveCardDecoration(
                                    context,
                                    radius: HealingDesignSystem.radiusM,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: HealingDesignSystem
                                                .adaptiveFill(context),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.calendar_today_rounded,
                                            color:
                                                HealingDesignSystem.primaryBlue,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                DateHelper.toDisplay(r.date),
                                                style: TextStyle(
                                                  color: HealingDesignSystem
                                                      .adaptivePrimaryText(
                                                          context),
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if (periodText != null) ...[
                                                const SizedBox(height: 3),
                                                Text(
                                                  periodText,
                                                  style: const TextStyle(
                                                    color: Colors.pink,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                              if (sleepText != null) ...[
                                                const SizedBox(height: 3),
                                                Text(
                                                  '睡眠：$sleepText',
                                                  style: TextStyle(
                                                    color: HealingDesignSystem
                                                        .adaptiveSecondaryText(
                                                            context),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color:
                                              HealingDesignSystem.primaryBlue,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  double? _averageInt(List<int> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  String _durationText(double? minutes) {
    if (minutes == null) return '-';
    return DateHelper.formatDurationText(minutes.round());
  }

  String _topSleepFlagsText(List<DailyRecord> records) {
    final counts = <String, int>{};
    for (final record in records) {
      for (final flag in record.sleep.flags) {
        counts[flag] = (counts[flag] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return '尚無標籤';

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        return a.key.compareTo(b.key);
      });

    return entries
        .take(3)
        .map((e) => '${ksleepFlagMap[e.key] ?? e.key} ${e.value}天')
        .join('・');
  }

  Widget _sleepMetricTile({
    required IconData icon,
    required String label,
    required String value,
    String? caption,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
        border: Border.all(
          color: HealingDesignSystem.adaptiveCardBorder(context),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: HealingDesignSystem.primaryBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: HealingDesignSystem.adaptiveSecondaryText(context),
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: HealingDesignSystem.adaptivePrimaryText(context),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 3),
            Text(
              caption,
              style: TextStyle(
                color: HealingDesignSystem.adaptiveSecondaryText(context),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSleepAnalysisPage(List<DailyRecord> records, bool isPro) {
    final bool isLocked = _isHistoryLocked(isPro);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final metricCardExtent =
        120.0 + ((textScale > 1.0 ? textScale - 1.0 : 0.0) * 36.0);
    final sleepRecords =
        records.where((r) => _hasSleepContent(r.sleep)).toList();

    final nightMinutesList = <int>[];
    final dailyTotalMinutesList = <int>[];
    final qualityList = <int>[];
    var napDays = 0;
    var napCount = 0;
    var napMinutesTotal = 0;
    var hypnoticDays = 0;

    for (final record in sleepRecords) {
      final nightMinutes = _nightSleepMinutes(record.sleep);
      if (nightMinutes != null) {
        nightMinutesList.add(nightMinutes);
      }

      final napMinutes = record.sleep.naps
          .fold<int>(0, (total, nap) => total + nap.durationMinutes);
      if (record.sleep.naps.isNotEmpty) {
        napDays += 1;
        napCount += record.sleep.naps.length;
        napMinutesTotal += napMinutes;
      }

      final totalMinutes = (nightMinutes ?? 0) + napMinutes;
      if (totalMinutes > 0) {
        dailyTotalMinutesList.add(totalMinutes);
      }

      final quality = record.sleep.quality;
      if (quality != null) qualityList.add(quality);
      if (record.sleep.tookHypnotic) hypnoticDays += 1;
    }

    final avgNight = _averageInt(nightMinutesList);
    final avgDaily = _averageInt(dailyTotalMinutesList);
    final avgQuality = qualityList.isEmpty
        ? null
        : qualityList.reduce((a, b) => a + b) / qualityList.length;
    final shortestNight = nightMinutesList.isEmpty
        ? null
        : nightMinutesList.reduce((a, b) => a < b ? a : b);
    final longestNight = nightMinutesList.isEmpty
        ? null
        : nightMinutesList.reduce((a, b) => a > b ? a : b);
    final avgNap = napCount == 0 ? null : napMinutesTotal / napCount;

    return Container(
      color: HealingDesignSystem.adaptiveBackground(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: HealingDesignSystem.adaptiveCardDecoration(
              context,
              radius: HealingDesignSystem.radiusM,
            ),
            child: _buildDateRangeDropdown(),
          ),
          const SizedBox(height: 12),
          if (isLocked)
            buildProLockedView(
              context: context,
              title: '進階睡眠摘要',
              description: '查看近 90 天、全部紀錄與自訂日期區間，需要升級 Pro。',
            )
          else
            Container(
              decoration: HealingDesignSystem.adaptiveCardDecoration(context),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color:
                              HealingDesignSystem.primaryBlue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.nightlight_round,
                          color: HealingDesignSystem.primaryBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '睡眠摘要',
                            style: TextStyle(
                              color: HealingDesignSystem.adaptivePrimaryText(
                                  context),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _selectedSummarySubtitle,
                            style: TextStyle(
                              color: HealingDesignSystem.adaptiveSecondaryText(
                                  context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      mainAxisExtent: metricCardExtent,
                    ),
                    children: [
                      _sleepMetricTile(
                        icon: Icons.bedtime_outlined,
                        label: '平均夜眠',
                        value: _durationText(avgNight),
                        caption: '${nightMinutesList.length} 天有夜眠時間',
                      ),
                      _sleepMetricTile(
                        icon: Icons.dark_mode_outlined,
                        label: '平均全日睡眠',
                        value: _durationText(avgDaily),
                        caption: '夜眠 + 小睡',
                      ),
                      _sleepMetricTile(
                        icon: Icons.star_border_rounded,
                        label: '平均睡眠品質',
                        value: avgQuality == null
                            ? '-'
                            : avgQuality.toStringAsFixed(1),
                        caption: '${qualityList.length} 天有品質分數',
                      ),
                      _sleepMetricTile(
                        icon: Icons.event_available_outlined,
                        label: '睡眠紀錄天數',
                        value: '${sleepRecords.length} 天',
                        caption: _selectedSummaryTotalDays == null
                            ? null
                            : '共 $_selectedSummaryTotalDays 天',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: HealingDesignSystem.adaptiveFill(context),
                      borderRadius:
                          BorderRadius.circular(HealingDesignSystem.radiusM),
                      border: Border.all(
                        color: HealingDesignSystem.adaptiveCardBorder(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '睡眠狀況',
                          style: TextStyle(
                            color: HealingDesignSystem.adaptivePrimaryText(
                                context),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _topSleepFlagsText(sleepRecords),
                          style: TextStyle(
                            color: HealingDesignSystem.adaptiveSecondaryText(
                                context),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _sleepMetricTile(
                          icon: Icons.compress_rounded,
                          label: '最短夜眠',
                          value: shortestNight == null
                              ? '-'
                              : DateHelper.formatDurationText(shortestNight),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _sleepMetricTile(
                          icon: Icons.expand_rounded,
                          label: '最長夜眠',
                          value: longestNight == null
                              ? '-'
                              : DateHelper.formatDurationText(longestNight),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _sleepMetricTile(
                          icon: Icons.airline_seat_individual_suite_outlined,
                          label: '小睡',
                          value: napCount == 0 ? '-' : '$napCount 次',
                          caption: napCount == 0
                              ? null
                              : '$napDays 天，平均 ${_durationText(avgNap)}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _sleepMetricTile(
                          icon: Icons.medication_outlined,
                          label: '安眠藥紀錄',
                          value: hypnoticDays == 0 ? '-' : '$hypnoticDays 天',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 依照 moodScale 將紀錄分成 5 點與 10 點兩個群組
  bool _isFivePointScaleRecord(DailyRecord record) {
    return record.moodScale == 5;
  }

  List<DailyRecord> _recordsWithScale(List<DailyRecord> records, int scale) {
    if (scale == 5) {
      return records.where(_isFivePointScaleRecord).toList();
    }
    return records.where((r) => r.moodScale == scale).toList();
  }

  /// 將 diaryMoodScores 也依照對應的 daily record 分組
  Map<DateTime, double> _filterDiaryScoresByScale(
    Map<DateTime, _DiaryMoodScore> scores,
    int scale,
  ) {
    return Map.fromEntries(
      scores.entries
          .where((e) => e.value.scale == scale)
          .map((e) => MapEntry(e.key, e.value.score)),
    );
  }

  // --- 分頁 2: 圖表 UI (重點修改) ---
  Widget _buildProChartContent(
    BuildContext context,
    List<DailyRecord> allRecords,
    List<String> emotionNames,
    List<PeriodCycle> cycles,
    bool isPro,
  ) {
    final filteredRecords = _applyDateFilter(allRecords);
    final bool useMA = _selectedRangeDays == null || _selectedRangeDays! > 7;
    final bool isLocked = _isHistoryLocked(isPro);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // 按 moodScale 分組
    final records5 = _recordsWithScale(filteredRecords, 5);
    final records10 = _recordsWithScale(filteredRecords, 10);
    final has5 = records5.isNotEmpty;

    return FutureBuilder<Map<DateTime, _DiaryMoodScore>>(
      future: uid == null
          ? Future.value(const <DateTime, _DiaryMoodScore>{})
          : _loadDiaryMoodScores(uid),
      builder: (context, diarySnapshot) {
        final allDiaryScores = _applyDiaryMoodDateFilter(
          diarySnapshot.data ?? const <DateTime, _DiaryMoodScore>{},
        );

        // 合併 emotions：從 5 分和 10 分 records 中萃取
        final mergedChartEmotionNames = <String>{
          ..._extractEmotionNames(records5),
          ..._extractEmotionNames(records10),
        };
        final chartEmotionNames = mergedChartEmotionNames.toList()..sort();
        if (allDiaryScores.isNotEmpty &&
            !chartEmotionNames.contains(_overallMoodLabel)) {
          chartEmotionNames.insert(0, _overallMoodLabel);
        }

        if (chartEmotionNames.isNotEmpty && _selectedEmotion.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedEmotion = chartEmotionNames.first);
            }
          });
        }

        final activeEmotion = _selectedEmotion.isNotEmpty &&
                chartEmotionNames.contains(_selectedEmotion)
            ? _selectedEmotion
            : (chartEmotionNames.isNotEmpty ? chartEmotionNames.first : '');

        // 將 diaryScores 也依 moodScale 分組
        final diary5 = _filterDiaryScoresByScale(allDiaryScores, 5);
        final diary10 = _filterDiaryScoresByScale(allDiaryScores, 10);

        // 檢查各量表是否有該情緒的資料
        bool hasChartData(
            List<DailyRecord> recs, Map<DateTime, double> diScores) {
          if (activeEmotion == _overallMoodLabel) return diScores.isNotEmpty;
          return recs
              .any((r) => r.emotions.any((e) => e.name == activeEmotion));
        }

        final has5Data = hasChartData(records5, diary5);
        final has10Data = hasChartData(records10, diary10);

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildDateRangeDropdown(compact: true),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildWeekStartSelector(),
              ),
              const SizedBox(height: 12),
              if (isLocked)
                Expanded(
                  child: buildProLockedView(
                    context: context,
                    title: '進階情緒趨勢',
                    description: '查看近 90 天、全部與自訂日期區間的情緒趨勢，需要升級 Pro。',
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      Text(
                        '情緒平衡趨勢圖',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                      if (useMA) ...[
                        const SizedBox(height: 2),
                        Text(
                          '使用 7 天移動平均',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: HealingDesignSystem.adaptiveSecondaryText(
                                context),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '以正向感受平均減去負向感受平均，協助觀察整體感受傾向的變化。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: HealingDesignSystem.adaptiveSecondaryText(
                              context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (has5) ...[
                        Text(
                          '5 點量表',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: HealingDesignSystem.adaptiveAccent(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 210,
                          width: double.infinity,
                          child: EmotionBalanceTrendChartWidget(
                            records: records5,
                            fullRecords: records5,
                            useMovingAverage: useMA,
                            forceMonthlyAverage:
                                _shouldUseMonthlyChartForRecords(records5),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      const Divider(height: 24),
                      Text(
                        '正向 / 負向感受趨勢圖',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                      if (useMA) ...[
                        const SizedBox(height: 2),
                        Text(
                          '使用 7 天移動平均',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: HealingDesignSystem.adaptiveSecondaryText(
                                context),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '分別呈現正向感受與負向感受的平均起伏。未分類的自訂情緒暫不納入平均。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: HealingDesignSystem.adaptiveSecondaryText(
                              context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (has5) ...[
                        Text(
                          '5 點量表',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: HealingDesignSystem.adaptiveAccent(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 210,
                          width: double.infinity,
                          child: EmotionBalanceChartWidget(
                            records: records5,
                            fullRecords: records5,
                            useMovingAverage: useMA,
                            forceMonthlyAverage:
                                _shouldUseMonthlyChartForRecords(records5),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      const Divider(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                                  .inputDecorationTheme
                                  .fillColor ??
                              Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: chartEmotionNames.isEmpty
                                ? null
                                : activeEmotion,
                            isExpanded: true,
                            dropdownColor: Theme.of(context).cardColor,
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: Theme.of(context).iconTheme.color,
                            ),
                            items: chartEmotionNames.isEmpty
                                ? [
                                    const DropdownMenuItem(
                                      value: null,
                                      child: Text('尚無情緒資料'),
                                    )
                                  ]
                                : chartEmotionNames
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e),
                                      ),
                                    )
                                    .toList(),
                            style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedEmotion = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 5 點量表圖表（如有資料）
                      if (has5Data) ...[
                        Text(
                          '新版情緒趨勢｜5 點量表',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: HistoryChartWidget(
                            records: records5,
                            fullRecords: records5,
                            targetEmotion: activeEmotion,
                            useMovingAverage: useMA,
                            forceMonthlyAverage:
                                _shouldUseMonthlyChartForRecords(records5),
                            diaryMoodScores: diary5,
                            overallMoodLabel: _overallMoodLabel,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // 10 點量表圖表（如有資料）
                      if (has10Data) ...[
                        Text(
                          '過去紀錄｜10 點量表',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: HistoryChartWidget(
                            records: records10,
                            fullRecords: records10,
                            targetEmotion: activeEmotion,
                            useMovingAverage: useMA,
                            forceMonthlyAverage:
                                _shouldUseMonthlyChartForRecords(records10),
                            diaryMoodScores: diary10,
                            overallMoodLabel: _overallMoodLabel,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!has5Data && !has10Data)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 32),
                            child: Text(
                              '所選時間範圍內沒有此情緒的資料',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // --- 輔助方法 ---
  // --- 輔助方法 ---

  Widget _buildDateRangeDropdown({bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrendRangeSelector(
          selectedDays: _selectedRangeDays,
          onChanged: (value) {
            if (value == 7) {
              setState(() {
                _selectedRangeDays = 7;
                _selectedDateRange = null;
              });
              return;
            }

            if (value == 30) {
              setState(() {
                _selectedRangeDays = 30;
                _selectedDateRange = null;
              });
              return;
            }

            setState(() {
              _selectedRangeDays = value;
              _selectedDateRange = null;
            });
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickDateRange,
          icon: const Icon(Icons.calendar_month),
          label: Text(
            _selectedDateRange == null
                ? '月曆選擇區間'
                : '${_selectedDateRange!.start.year}/${_selectedDateRange!.start.month}/${_selectedDateRange!.start.day}'
                    ' ~ '
                    '${_selectedDateRange!.end.year}/${_selectedDateRange!.end.month}/${_selectedDateRange!.end.day}',
          ),
        ),
      ],
    );
  }

  Widget _buildWeekStartSelector() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_view_week,
              size: 18, color: HealingDesignSystem.primaryBlue),
          const SizedBox(width: 8),
          Text(
            '週開始',
            style: TextStyle(
              color: HealingDesignSystem.adaptivePrimaryText(context),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _historyWeekStartDay,
              style: TextStyle(
                color: HealingDesignSystem.adaptivePrimaryText(context),
                fontSize: 13,
              ),
              dropdownColor: HealingDesignSystem.adaptiveSurface(context),
              icon: const Icon(Icons.arrow_drop_down,
                  color: HealingDesignSystem.primaryBlue),
              onChanged: (value) {
                if (value != null) {
                  _updateHistoryWeekStartDay(value);
                }
              },
              items: [
                for (int weekday = DateTime.monday;
                    weekday <= DateTime.sunday;
                    weekday++)
                  DropdownMenuItem<int>(
                    value: weekday,
                    child: Text(_weekdayText(weekday)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 遍歷所有資料，找出曾被選過的情緒標籤（排序跟情緒紀錄頁一致）
  List<String> _extractEmotionNames(List<DailyRecord> records) {
    final names = <String>{};

    debugPrint(
        'Extracting selected emotion names from ${records.length} records');

    for (final r in records) {
      for (final e in r.emotions) {
        if (e.name.isNotEmpty &&
            e.value != null &&
            e.name != _overallMoodLabel) {
          names.add(e.name);
        }
      }
    }

    final orderMap = <String, int>{
      for (int i = 0; i < kEmotionCheckboxNames.length; i++)
        kEmotionCheckboxNames[i]: i,
    };

    final sortedNames = names.toList()
      ..sort((a, b) {
        final ia = orderMap[a];
        final ib = orderMap[b];
        if (ia != null && ib != null) return ia.compareTo(ib);
        if (ia != null) return -1;
        if (ib != null) return 1;
        return a.compareTo(b);
      });

    debugPrint(
        'Extracted ${sortedNames.length} selected emotions: $sortedNames');
    return sortedNames;
  }

  List<DailyRecord> _applyDateFilter(List<DailyRecord> input) {
    if (_selectedDateRange != null) {
      final start = _dateOnly(_selectedDateRange!.start);
      final end = _dateOnly(_selectedDateRange!.end);
      return input.where((r) {
        final date = _dateOnly(r.date);
        return !date.isBefore(start) && !date.isAfter(end);
      }).toList();
    }

    final days = _selectedRangeDays;
    if (days == null) return input;

    final today = _dateOnly(DateTime.now());
    final start = today.subtract(Duration(days: days - 1));
    return input.where((r) {
      final date = _dateOnly(r.date);
      return !date.isBefore(start) && !date.isAfter(today);
    }).toList();
  }

  int? _nightSleepMinutes(SleepData sleep) {
    final end = sleep.finalWakeTime ?? sleep.wakeTime;
    if (sleep.sleepTime == null || end == null) return null;
    final minutes = DateHelper.calcDurationMinutes(sleep.sleepTime!, end);
    return minutes > 0 ? minutes : null;
  }

  Widget _buildRecordSubtitle(BuildContext context, DailyRecord r) {
    final List<String> parts = [];

    debugPrint(
        '📝 Building subtitle for record ${r.id}: overallMood=${r.overallMood}, emotions count=${r.emotions.length}');

    final nightMinutes = _nightSleepMinutes(r.sleep);
    if (nightMinutes != null) {
      parts.add('睡眠：${DateHelper.formatDurationText(nightMinutes)}');
    }
    if (r.sleep.flags.isNotEmpty) {
      parts.add(r.sleep.flags.map((f) => ksleepFlagMap[f] ?? f).join(' '));
    }

    debugPrint('  Subtitle parts: $parts');
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(parts.join(' · '),
        style: Theme.of(context).textTheme.bodyMedium);
  }
}

Future<void> clearPeriodForRecord(BuildContext context, DailyRecord r) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  // 如果本來就不是生理期就不用清除
  if (r.isPeriod == false && r.periodStartId == null && r.periodEndId == null) {
    return;
  }

  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(DateHelper.toDisplay(r.date)),
        content: const Text('要把這一天的生理期紀錄清除嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      );
    },
  );

  if (confirm != true) return;

  final reference = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('dailyRecords')
      .doc(r.id);
  await HealthDataEncryptionService.updateEncrypted(reference, {
    'isPeriod': false,
    'periodStartId': null,
    'periodEndId': null,
  });

  // 回到上一層會自動刷新，不用 setState
}

// --- 獨立出來的圖表 Widget (處理複雜的 MA 邏輯) ---
enum DateFilter { last7, last30, all }

/// —— 簡易週報卡片：計算最近 7 天的概況 —— //
