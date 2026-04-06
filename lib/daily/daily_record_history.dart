import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../models/daily_record.dart'; // 確保引用正確
import '../utils/date_helper.dart';   // 確保引用正確
import 'record_detail_screen.dart';   // 確保引用正確
import '../models/period_cycle.dart';
import '../widgets/main_drawer.dart';
import '../pro/pro_page.dart';
import '../providers/pro_provider.dart';
import 'daily_record_repository.dart';
import 'emotion_page_checkbox.dart';

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
const bool kDemoUnlockAll = true;
class DailyRecordHistory extends StatefulWidget {
  const DailyRecordHistory({super.key, this.initialTab = 0});

  /// 0: 列表與週報, 1: 情緒趨勢圖
  final int initialTab;

  @override
  State<DailyRecordHistory> createState() => _DailyRecordHistoryState();
}

class _DailyRecordHistoryState extends State<DailyRecordHistory> with SingleTickerProviderStateMixin {
  DateFilter _dateFilter = DateFilter.last7;
  // MoodFilter 先暫時拿掉，因為圖表頁通常看全部比較準，或者你可以保留邏輯但只應用在列表
  
  // 分頁控制器
  late TabController _tabController;
  
  // 動態情緒選擇
  String _selectedEmotion = '';
  
  // 用於強制刷新的計數器
  int _refreshCounter = 0;

 String? _periodLabel(DailyRecord r) {
  if (r.isPeriod == true) {
    return '生理期';
  }
  return null;
}

  @override
  void initState() {
    super.initState();
    final safeIndex = widget.initialTab.clamp(0, 1);
    _tabController = TabController(length: 2, vsync: this, initialIndex: safeIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 從全局 ProProvider 取得 Pro 狀態
    final proProvider = context.watch<ProProvider>();
    final bool isPro = proProvider.isPro;
    
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('未登入')),
      );
    }

    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        toolbarHeight: 60,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '列表與週報'),
            Tab(text: '情緒趨勢圖'),
          ],
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
          listRecords = _applyDateFilter(listRecords, _dateFilter);
          listRecords.sort((a, b) => b.date.compareTo(a.date));

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('periodCycles')
                .orderBy('startDate', descending: true)
                .snapshots(),
            builder: (context, periodSnap) {
              final cycles = periodSnap.data?.docs
                  .map((doc) => PeriodCycle.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
                  .toList() ?? [];

              return TabBarView(
                controller: _tabController,
                children: [
                  _buildListPage(listRecords, dailyRecords, isPro),
                  _buildProChartContent(context, dailyRecords, availableEmotions, cycles, isPro),
                ],
              );
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
    final proProvider = context.read<ProProvider>();
    final isPro = proProvider.isPro;
    
    final endDate = DateTime.now();
    // 免費版：2年   Pro版：無限期
    final startDate = isPro 
        ? DateTime(2020, 1, 1)  // Pro 用戶查詢所有數據
        : endDate.subtract(const Duration(days: 730));  // 免費用戶只查詢最近 2 年
    
    debugPrint('📊 Loading records for ${isPro ? "Pro" : "Free"} user');
    debugPrint('👤 Using userId: $uid');
    debugPrint('📅 Date range: $startDate to $endDate');
    
    final Map<String, DailyRecord> recordsMap = {};

    // 🔧 改進：總是嘗試從本地加載作為備份
    // 這樣即使 Firebase 同步被禁用或失敗，仍然有數據可用
    try {
      final repo = DailyRecordRepository();
      debugPrint('🔍 [LOCAL BACKUP] Loading records from local SQLite for user=$uid from $startDate to $endDate');
      
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
    if (!isPro) {
      debugPrint('✅ [FREE USER] Data loaded from local storage');
      final allRecords = recordsMap.values.toList();
      debugPrint('📊 Total records loaded: ${allRecords.length}');
      return allRecords;
    }
    
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
        final record = DailyRecord.fromFirestore(doc);
        recordsMap[record.id] = record;
        debugPrint('  ☁️  Firebase: ${record.id} (${record.date})');
      }
    } catch (e, st) {
      debugPrint('⚠️  Firebase load failed (using local data): $e\nStacktrace: $st');
    }

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
      overallMood = emotions.length > 0 ? (sum / emotions.length).toDouble() : null;
    }
    
    return DailyRecord(
      id: record['id'] ?? '',
      date: date,
      emotions: emotions,
      overallMood: overallMood,
      symptoms: _parseBodySymptoms(record['bodySymptoms']),
      sleep: sleep,
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

    return (emotionsData as Map<String, dynamic>).entries
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
      quality: (map['quality'] as num?)?.toInt(),
      tookHypnotic: map['tookHypnotic'] ?? false,
      hypnoticName: map['hypnoticName'],
      hypnoticDose: map['hypnoticDose'],
      flags: (map['flags'] as List?)?.cast<String>() ?? const [],
      note: map['note'],
      naps: const [],
    );
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

bool _isHistoryLocked(bool isPro) {
  // 只開放最近 7 天
  if (_dateFilter == DateFilter.last7) return false;

  // 30 天 / 全部 → 非 Pro 鎖
  return !isPro;
}

  // --- 分頁 1: 列表 UI ---
  Widget _buildListPage(
  List<DailyRecord> records,
  List<DailyRecord> allRecordsForSummary,
  bool isPro,
) {
  return Column(
    children: [
      // ─────────────────────
      // 簡易週報卡片（永遠顯示）
      // ─────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: WeeklySummaryCard(allRecords: allRecordsForSummary),
      ),

      // ─────────────────────
      // 日期篩選器（7 / 30 / 全部）
      // ─────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: _buildDateFilterChips(),
      ),

      const Divider(height: 1),

      // ─────────────────────
      // 每日紀錄清單（此區依 Pro 狀態鎖）
      // ─────────────────────
      Expanded(
  child: _isHistoryLocked(isPro)
      ? _buildProLockedView(
        context: context,
          title: '記錄歷程',
          description: '查看 30 天與全部的每日記錄，需要升級 Pro',
        )
            : records.isEmpty
                ? const Center(child: Text('沒有符合條件的紀錄'))
                : ListView.separated(
                    itemCount: records.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final r = records[index];
                      final periodText = _periodLabel(r);

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          DateHelper.toDisplay(r.date),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (periodText != null)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4),
                                child: Text(
                                  periodText,
                                  style: const TextStyle(
                                    color: Colors.pink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            _buildRecordSubtitle(context, r),
                          ],
                        ),
                        trailing:
                            const Icon(Icons.chevron_right),
                        onTap: () {
                          final uid = FirebaseAuth
                              .instance.currentUser?.uid;
                          if (uid != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    RecordDetailScreen(
                                  uid: uid,
                                  docId: r.id,
                                ),
                              ),
                            ).then((_) {
                              // 返回時刷新頁面
                              setState(() => _refreshCounter++);
                            });
                          }
                        },
                      );
                    },
                  ),
      ),
    ],
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
  // Validate _selectedEmotion - if it's no longer in available emotions, reset it
  if (emotionNames.isNotEmpty && !emotionNames.contains(_selectedEmotion)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _selectedEmotion = emotionNames.first);
    });
  }
  
  // 1. 根據日期篩選資料
  final filteredRecords = _applyDateFilter(allRecords, _dateFilter);

  // 2. 是否使用移動平均（7 天 = 原始線，其餘 = MA）
  final bool useMA = _dateFilter != DateFilter.last7;

  // 3. 是否鎖定（非 Pro + 不是 7 天）
  final bool isLocked =
    !kDemoUnlockAll && !isPro && _dateFilter != DateFilter.last7;

  return Padding(
  padding: const EdgeInsets.all(16.0),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ===== 上方日期切換（永遠可點）=====
      Row(
        children: [
          Expanded(child: _buildDateFilterChips(compact: true)),
        ],
      ),
      const SizedBox(height: 12),

      // ===== 情緒下拉選單（永遠可點）=====
      Container(
  padding: const EdgeInsets.symmetric(horizontal: 12),
  decoration: BoxDecoration(
    color: Theme.of(context).inputDecorationTheme.fillColor ??
        Theme.of(context).cardColor,
    borderRadius: BorderRadius.circular(12),
  ),
  child: DropdownButtonHideUnderline(
    child: DropdownButton<String>(
      value: emotionNames.isEmpty 
          ? null
          : (emotionNames.contains(_selectedEmotion)
              ? _selectedEmotion
              : emotionNames.first),
      isExpanded: true,
      dropdownColor: Theme.of(context).cardColor,
      icon: Icon(
        Icons.arrow_drop_down,
        color: Theme.of(context).iconTheme.color,
      ),
      items: emotionNames.isEmpty
          ? [
              DropdownMenuItem(
                value: null,
                child: Text('無可用數據'),
              )
            ]
          : emotionNames
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e),
                ),
              )
              .toList(),
      style: TextStyle(
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),

      // 🔒 關鍵修改在這裡
      onChanged: isLocked
          ? null
          : (val) {
              if (val != null) {
                setState(() => _selectedEmotion = val);
              }
            },
    ),
  ),
),

      const SizedBox(height: 12),

      // ===== 圖表標題 =====
      Text(
        useMA
            ? '$_selectedEmotion（7 日移動平均趨勢）'
            : '$_selectedEmotion（每日數值）',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
      const SizedBox(height: 12),

      // ===== 圖表本體（唯一可以被鎖的地方）=====
      SizedBox(
        height: 215,
        child: SizedBox(
          width: double.infinity,
          child: Stack(
            children: [
              // ✅ 原本好看的圖表 UI（永遠存在）
              _ChartWidget(
                records: filteredRecords,
                fullRecords: allRecords,
                targetEmotion: _selectedEmotion,
                useMovingAverage: useMA,
              ),

              // 🔒 只有在鎖定時，才覆蓋圖表
              if (isLocked)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: Container(
                      color: Theme.of(context)
                        .scaffoldBackgroundColor
                        .withValues(alpha: 0.75),
                      alignment: Alignment.center,
                      child: _buildProLockedView(
                        context: context,
                        title: '情緒趨勢圖',
                        description:
                            '查看 30 天 / 全部的情緒趨勢，需要升級 Pro。',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  ),
);
}

  // --- 輔助方法 ---

  Widget _buildDateFilterChips({bool compact = false}) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('最近 7 天'),
          selected: _dateFilter == DateFilter.last7,
          onSelected: (_) => setState(() => _dateFilter = DateFilter.last7),
          visualDensity: compact ? VisualDensity.compact : null,
        ),
        ChoiceChip(
          label: const Text('最近 30 天'),
          selected: _dateFilter == DateFilter.last30,
          onSelected: (_) => setState(() => _dateFilter = DateFilter.last30),
          visualDensity: compact ? VisualDensity.compact : null,
        ),
        ChoiceChip(
          label: const Text('全部'),
          selected: _dateFilter == DateFilter.all,
          onSelected: (_) => setState(() => _dateFilter = DateFilter.all),
          visualDensity: compact ? VisualDensity.compact : null,
        ),
      ],
    );
  }
  
  // 遍歷所有資料，找出曾被選過的情緒標籤（排序跟情緒紀錄頁一致）
  List<String> _extractEmotionNames(List<DailyRecord> records) {
    final names = <String>{};

    debugPrint('🔍 Extracting selected emotion names from ${records.length} records');

    for (var r in records) {
      for (var e in r.emotions) {
        if (e.name.isNotEmpty && e.value != null && e.name != '整體情緒') {
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

        // 兩者都在情緒紀錄頁清單內：照清單順序
        if (ia != null && ib != null) return ia.compareTo(ib);

        // 只要其中一個在清單內，清單內的排前面
        if (ia != null) return -1;
        if (ib != null) return 1;

        // 兩者都不在預設清單：用名稱穩定排序
        return a.compareTo(b);
      });

    debugPrint('✅ Extracted ${sortedNames.length} selected emotions: $sortedNames');
    return sortedNames;
  }

  // 篩選邏輯
  List<DailyRecord> _applyDateFilter(List<DailyRecord> input, DateFilter filter) {
    if (filter == DateFilter.all) return input;
    final now = DateTime.now();
    final days = filter == DateFilter.last7 ? 6 : 29;
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
    // _isBeforeDay(a, b) 表示 a < b
    return input.where((r) => !r.date.isBefore(start)).toList();
  }
  
  Widget _buildRecordSubtitle(BuildContext context, DailyRecord r) {
    final List<String> parts = [];

    debugPrint('📝 Building subtitle for record ${r.id}: overallMood=${r.overallMood}, emotions count=${r.emotions.length}');

    if (r.sleep.durationHours != null) {
      parts.add('睡眠：${r.sleep.durationHours}hr');
    }
    if (r.sleep.flags.isNotEmpty) {
      parts.add(
        r.sleep.flags.map((f) => ksleepFlagMap[f] ?? f).join(' ')
      );
    }

    debugPrint('  Subtitle parts: $parts');
    return Text(
      parts.isEmpty ? '(無資料)' : parts.join(' · '),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}
Future<void> clearPeriodForRecord(BuildContext context, DailyRecord r) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  // 如果本來就不是生理期就不用清除
  if (r.isPeriod == false &&
      r.periodStartId == null &&
      r.periodEndId == null) {
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

  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('dailyRecords')
      .doc(r.id)
      .update({
    'isPeriod': false,
    'periodStartId': null,
    'periodEndId': null,
  });

  // 回到上一層會自動刷新，不用 setState
}

// --- 獨立出來的圖表 Widget (處理複雜的 MA 邏輯) ---
class _ChartWidget extends StatelessWidget {
  final List<DailyRecord> records;
  final List<DailyRecord> fullRecords;
  final String targetEmotion;
  final bool useMovingAverage;

  const _ChartWidget({
    required this.records,
    required this.fullRecords,
    required this.targetEmotion,
    required this.useMovingAverage,
  });

  /// 正規化日期（去除時間部分）
  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 建立經期粉紅區塊（依照日期距離 startDate 的天數作為 x 座標）
  List<VerticalRangeAnnotation> _buildPeriodRanges(
      List<DailyRecord> sorted, DateTime startDate) {
    final List<VerticalRangeAnnotation> list = [];
    int? periodStartDay;

    for (var r in sorted) {
      final dayD = _norm(r.date).difference(startDate).inDays;
      if (r.isPeriod) {
        periodStartDay ??= dayD;
      } else if (periodStartDay != null) {
        list.add(VerticalRangeAnnotation(
          x1: periodStartDay.toDouble() - 0.5,
          x2: (dayD - 1).toDouble() + 0.5,
          color: Colors.pink.withValues(alpha: 0.15),
        ));
        periodStartDay = null;
      }
    }
    // 若最後一筆仍為經期
    if (periodStartDay != null && sorted.isNotEmpty) {
      final lastDay = _norm(sorted.last.date).difference(startDate).inDays;
      list.add(VerticalRangeAnnotation(
        x1: periodStartDay.toDouble() - 0.5,
        x2: lastDay.toDouble() + 0.5,
        color: Colors.pink.withValues(alpha: 0.15),
      ));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Center(child: Text('資料不足，無法顯示趨勢圖'));
    }

    // ===== 1️⃣ 整理資料：依日期排序，建立「日期 → 數值」對照表 =====
    final sorted = List<DailyRecord>.from(records)
      ..sort((a, b) => a.date.compareTo(b.date));

    final Map<DateTime, double> dateValueMap = {}; // 可用實值（實線/實心點）
    final Map<DateTime, double> emptyPointValueMap = {}; // MA 視窗不足（空心點/虛線）
    for (var r in sorted) {
      final d = _norm(r.date);

      if (useMovingAverage) {
        final filledDays = _countFilledIn7Days(r.date);
        final v = _calcMA7(r.date, precomputedCount: filledDays);

        if (v != null) {
          if (filledDays >= 3) {
            // ✅ 前 7 天有 >=3 天有值：正常計算
            dateValueMap[d] = v;
          } else if (filledDays > 0) {
            // ⚪ 前 7 天有值但 <3 天：顯示空點 + 走虛線
            emptyPointValueMap[d] = v;
          }
        }
      } else {
        final v = _getValue(r);
        if (v != null) {
          dateValueMap[d] = v;
        }
      }
    }

    if (dateValueMap.isEmpty && emptyPointValueMap.isEmpty) {
      return const Center(child: Text('此情緒目前沒有數據'));
    }

    final sortedDates = {
      ...dateValueMap.keys,
      ...emptyPointValueMap.keys,
    }.toList()
      ..sort();
    final recordedCount = sortedDates.length;
    final startDate = sortedDates.first;
    final endDate = sortedDates.last;
    final totalDays = endDate.difference(startDate).inDays + 1;

    // x 軸值 = 距離第一個有紀錄日期的天數
    int dayIdx(DateTime d) => _norm(d).difference(startDate).inDays;

    final lineColor = useMovingAverage ? Colors.orange : Colors.teal;

    // ≥ 3 天才畫折線；否則只顯示圓點
    final showLine = recordedCount >= 3;

    // ===== 3️⃣ 建立 LineChartBarData =====
    final List<LineChartBarData> barDatas = [];
    bool hasDashedSegments = false;

    double? pointY(DateTime d) => dateValueMap[d] ?? emptyPointValueMap[d];

    if (!showLine) {
      // 📍 圓點模式（< 3 天）：只顯示圓點，無連線
      barDatas.add(LineChartBarData(
        spots: dateValueMap.keys
            .map((d) => FlSpot(dayIdx(d).toDouble(), dateValueMap[d]!))
            .toList(),
        isCurved: false,
        barWidth: 0,
        color: Colors.transparent,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 6,
            color: lineColor,
            strokeWidth: 2,
            strokeColor: lineColor.withValues(alpha: 0.4),
          ),
        ),
        belowBarData: BarAreaData(show: false),
      ));

      // MA 視窗不足（<3 天）時顯示空心點
      if (emptyPointValueMap.isNotEmpty) {
        hasDashedSegments = true;
        barDatas.add(LineChartBarData(
          spots: emptyPointValueMap.keys
              .map((d) => FlSpot(dayIdx(d).toDouble(), emptyPointValueMap[d]!))
              .toList(),
          isCurved: false,
          barWidth: 0,
          color: Colors.transparent,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 5,
              color: Colors.white,
              strokeWidth: 2,
              strokeColor: lineColor.withValues(alpha: 0.8),
            ),
          ),
          belowBarData: BarAreaData(show: false),
        ));
      }
    } else {
      // 📈 折線模式（≥ 3 天）
      // 實線：在有資料的位置連線，缺漏天插入 nullSpot 使線段斷開
      final solidSpots = <FlSpot>[];
      for (int d = 0; d < totalDays; d++) {
        final date = startDate.add(Duration(days: d));
        final v = dateValueMap[_norm(date)]; // 只有有效 MA 才走實線
        solidSpots.add(v != null ? FlSpot(d.toDouble(), v) : FlSpot.nullSpot);
      }
      barDatas.add(LineChartBarData(
        spots: solidSpots,
        isCurved: true,
        color: lineColor,
        barWidth: 3,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 4,
            color: lineColor,
            strokeWidth: 0,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          color: lineColor.withValues(alpha: 0.12),
        ),
      ));

      // MA 視窗不足（<3 天）時顯示空心點
      if (emptyPointValueMap.isNotEmpty) {
        hasDashedSegments = true;
        barDatas.add(LineChartBarData(
          spots: emptyPointValueMap.keys
              .map((d) => FlSpot(dayIdx(d).toDouble(), emptyPointValueMap[d]!))
              .toList(),
          isCurved: false,
          barWidth: 0,
          color: Colors.transparent,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 5,
              color: Colors.white,
              strokeWidth: 2,
              strokeColor: lineColor.withValues(alpha: 0.8),
            ),
          ),
          belowBarData: BarAreaData(show: false),
        ));
      }

      // 虛線：跨越「缺漏天」或「空心點」的連線段
      for (int i = 0; i < sortedDates.length - 1; i++) {
        final d1 = sortedDates[i];
        final d2 = sortedDates[i + 1];
        final y1 = pointY(d1);
        final y2 = pointY(d2);
        if (y1 == null || y2 == null) continue;

        final bool hasMissingCalendar = d2.difference(d1).inDays > 1;
        final bool includeEmptyPoint =
            emptyPointValueMap.containsKey(d1) || emptyPointValueMap.containsKey(d2);

        if (hasMissingCalendar || includeEmptyPoint) {
          hasDashedSegments = true;
          barDatas.add(LineChartBarData(
            spots: [
              FlSpot(dayIdx(d1).toDouble(), y1),
              FlSpot(dayIdx(d2).toDouble(), y2),
            ],
            isCurved: false,
            color: lineColor.withValues(alpha: 0.5),
            barWidth: 2,
            dashArray: [6, 5],
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ));
        }
      }
    }

    // ===== 4️⃣ 經期粉紅區塊 =====
    final periodRanges = _buildPeriodRanges(sorted, startDate);

    // ===== 5️⃣ X 軸標籤：只在有紀錄的位置顯示，最多 7 個 =====
    final labelPositions = <int>{};
    if (sortedDates.isNotEmpty) {
      final step = ((sortedDates.length - 1) / 6).ceil().clamp(1, sortedDates.length);
      for (int i = 0; i < sortedDates.length; i += step) {
        labelPositions.add(dayIdx(sortedDates[i]));
      }
      labelPositions.add(dayIdx(sortedDates.last));
    }

    // ===== 6️⃣ 繪製折線圖 =====
    final chart = LineChart(
      LineChartData(
        minY: 0,
        maxY: 10,
        minX: 0,
        maxX: (totalDays - 1).toDouble(),
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: periodRanges,
        ),
        gridData: FlGridData(
          show: true,
          horizontalInterval: 2,
          drawVerticalLine: false,
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              reservedSize: 30,
              getTitlesWidget: (v, m) => Text(v.toInt().toString()),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (val, meta) {
                final d = val.toInt();
                if (!labelPositions.contains(d)) return const SizedBox.shrink();
                final date = startDate.add(Duration(days: d));
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${date.month}/${date.day}',
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: barDatas,
      ),
    );

    // ===== 7️⃣ 組合圖表 + 虛線提示文字 =====
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: chart),
        if (hasDashedSegments)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 36),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 14,
                  child: CustomPaint(
                    painter: _DashedLegendPainter(
                        color: lineColor.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '虛線代表當日無紀錄',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // 取得單日特定情緒數值
  double? _getValue(DailyRecord r) {
    if (targetEmotion == '整體情緒') return r.overallMood;
    try {
      final e =
          r.emotions.firstWhere((element) => element.name == targetEmotion);
      return e.value?.toDouble();
    } catch (_) {
      return null;
    }
  }

  // 計算 targetDate 往前 7 天（含當天）中，有填值的天數
  int _countFilledIn7Days(DateTime targetDate) {
    final windowStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day)
            .subtract(const Duration(days: 6));
    final windowRecords = fullRecords.where((r) {
      return !r.date.isAfter(targetDate) && !r.date.isBefore(windowStart);
    }).toList();

    int count = 0;
    for (var r in windowRecords) {
      if (_getValue(r) != null) {
        count++;
      }
    }
    return count;
  }

  // 計算 7 日移動平均
  double? _calcMA7(DateTime targetDate, {int? precomputedCount}) {
    final windowStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day)
            .subtract(const Duration(days: 6));
    final windowRecords = fullRecords.where((r) {
      return !r.date.isAfter(targetDate) && !r.date.isBefore(windowStart);
    }).toList();
    if (windowRecords.isEmpty) return null;

    double total = 0;
    int count = 0;
    for (var r in windowRecords) {
      final v = _getValue(r);
      if (v != null) {
        total += v;
        count++;
      }
    }

    // 若外部已有算過填值天數，優先使用，避免重複邏輯差異
    final effectiveCount = precomputedCount ?? count;
    if (effectiveCount == 0) return null;
    return total / effectiveCount;
  }
}

/// 虛線圖例畫筆（用於圖表下方的圖例小線條）
class _DashedLegendPainter extends CustomPainter {
  final Color color;
  _DashedLegendPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = (x + dashWidth).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLegendPainter oldDelegate) =>
      oldDelegate.color != color;
}

// 列舉與 DateFilter 定義保持不變
enum DateFilter { last7, last30, all }

/// —— 簡易週報卡片：計算最近 7 天的概況 —— //
class WeeklySummaryCard extends StatelessWidget {
  final List<DailyRecord> allRecords;

  const WeeklySummaryCard({super.key, required this.allRecords});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6)); // 最近 7 天（含今天）

    // 篩選出最近 7 天的紀錄
    final weekRecords = allRecords.where((r) {
      // 只比對日期部分，忽略時間
      final date = DateTime(r.date.year, r.date.month, r.date.day);
      return !date.isBefore(start);
    }).toList();

    final totalDays = 7;
    final recordedDays = weekRecords.length;


    // 計算睡眠平均 (改用 sleep.durationHours)
    final sleepValues = weekRecords.map((r) {
      // 1. 夜間睡眠 (可能為 null，轉為 0)
      final night = r.sleep.durationHours ?? 0;

      // 2. 小睡總和 (累加分鐘數)
      final napMinutes = r.sleep.naps.fold(0, (sum, nap) => sum + nap.durationMinutes);

      // 3. 總時數 (夜間 + 小睡轉小時)
      final total = night + (napMinutes / 60.0);

      // 如果 total 為 0，代表那天完全沒睡或沒紀錄，回傳 null 以便過濾
      return total > 0 ? total : null;
    }).where((v) => v != null).cast<double>().toList();

    final avgSleep = sleepValues.isEmpty
        ? null
        : sleepValues.reduce((a, b) => a + b) / sleepValues.length;

    // 鼓勵語句
    final String message;
    if (recordedDays == 0) {
      message = '這週還沒有開始記錄，沒關係，可以從今天慢慢來。';
    } else if (recordedDays <= 3) {
      message = '這週已經有 $recordedDays 天留下紀錄了，願意給自己這些時間，很不容易。';
    } else if (recordedDays < 7) {
      message = '這週大部分的日子你都有努力關心自己，已經很棒了。';
    } else {
      message = '這週每天都有陪自己走一下，謝謝你這麼努力地活著。';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '這週小結（最近 7 天）',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '有紀錄的天數：$recordedDays / $totalDays 天',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (avgSleep != null) ...[
              const SizedBox(height: 4),
              Text(
                '平均夜間睡眠：約 ${avgSleep.toStringAsFixed(1)} 小時',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[700],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
Widget _buildProLockedView({
  required BuildContext context,
  required String title,
  required String description,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProPage()),
              );
            },
            child: const Text('升級 Pro'),
          ),
        ],
      ),
    ),
  );
}
