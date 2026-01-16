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
import '../quotes.dart';
import '../pro/pro_page.dart';
import '../providers/pro_provider.dart';
import 'daily_record_repository.dart';

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
  const DailyRecordHistory({super.key});

  @override
  State<DailyRecordHistory> createState() => _DailyRecordHistoryState();
}

class _DailyRecordHistoryState extends State<DailyRecordHistory> with SingleTickerProviderStateMixin {
  DateFilter _dateFilter = DateFilter.last7;
  // MoodFilter 先暫時拿掉，因為圖表頁通常看全部比較準，或者你可以保留邏輯但只應用在列表
  
  // 分頁控制器
  late TabController _tabController;
  
  // 動態情緒選擇
  String _selectedEmotion = '整體情緒';

 String? _periodLabel(DailyRecord r) {
  if (r.isPeriod == true) {
    return '🌸 生理期';
  }
  return null;
}

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        toolbarHeight: 120,
  centerTitle: true,
        title: const QuotesTitle(),
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

  /// 從本地 SQLite 和 Firebase 加載所有記錄，並合併去重（最近 90 天）
  Future<List<DailyRecord>> _loadAllRecords(String uid) async {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(const Duration(days: 90));
    
    final Map<String, DailyRecord> recordsMap = {};

    // 1. 先從本地 SQLite 加載
    try {
      final repo = DailyRecordRepository();
      debugPrint('🔍 Loading records from local SQLite for user=$uid from $startDate to $endDate');
      
      final localRecords = await repo.getDailyRecordsByDateRange(
        userId: uid,
        startDate: startDate,
        endDate: endDate,
      );
      
      debugPrint('✅ Loaded ${localRecords.length} records from local database');
      
      // 轉換並加入 Map（以 id 為 key）
      for (var localRecord in localRecords) {
        final record = _convertLocalRecordToDailyRecord(localRecord);
        recordsMap[record.id] = record;
        debugPrint('  📦 Local: ${record.id} (${record.date})');
      }
    } catch (e, st) {
      debugPrint('❌ Failed to load local records: $e\nStacktrace: $st');
    }

    // 2. 再從 Firebase 加載（總是讀取，即使 sync 關閉）
    try {
      debugPrint('🔍 Loading records from Firebase...');
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      debugPrint('✅ Loaded ${snapshot.docs.length} records from Firebase');

      for (var doc in snapshot.docs) {
        final record = DailyRecord.fromFirestore(doc);
        // Firebase 的數據優先（因為可能更完整）
        if (!recordsMap.containsKey(record.id)) {
          recordsMap[record.id] = record;
          debugPrint('  ☁️  Firebase: ${record.id} (${record.date})');
        }
      }
    } catch (e, st) {
      debugPrint('❌ Failed to load Firebase records: $e\nStacktrace: $st');
    }

    final allRecords = recordsMap.values.toList();
    debugPrint('📊 Total merged records: ${allRecords.length}');
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
      isPeriod: record['periodData'] != null 
          ? (record['periodData'] as Map?)?.containsKey('isPeriod') == true ? true : false
          : false,
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
                            );
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
  Set<String> emotionNames,
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
        height: 180,
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
  
  // 遍歷所有資料，找出有實際數據的情緒標籤
  Set<String> _extractEmotionNames(List<DailyRecord> records) {
    final names = <String>{};
    
    debugPrint('🔍 Extracting emotion names from ${records.length} records');
    
    // 檢查是否有 overallMood 數據
    final hasOverallMood = records.any((r) => r.overallMood != null && r.overallMood != 0);
    if (hasOverallMood) {
      names.add('整體情緒');
      debugPrint('  ✓ Found overallMood data');
    }
    
    // 只加入有 value 數據的情緒（自動去除「整體情緒」，因為已經在上面處理）
    for (var r in records) {
      for (var e in r.emotions) {
        if (e.name.isNotEmpty && e.value != null && e.name != '整體情緒') {
          names.add(e.name);
        }
      }
    }
    
    debugPrint('✅ Extracted ${names.length} unique emotions: $names');
    return names;
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

    if (r.overallMood != null) {
      parts.add('情緒：${r.overallMood!.toStringAsFixed(1)}');
    } else if (r.emotions.isNotEmpty) {
      // 如果沒有 overallMood，顯示情緒列表
      final emotionText = r.emotions
          .take(3)  // 只顯示前 3 個情緒
          .map((e) => '${e.name}${e.value}')
          .join(' ');
      parts.add('情緒：$emotionText');
    }
    
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
    super.key,
    required this.records,
    required this.fullRecords,
    required this.targetEmotion,
    required this.useMovingAverage,
  });
List<VerticalRangeAnnotation> buildPeriodRanges(List<DailyRecord> records) {
  final List<VerticalRangeAnnotation> list = [];

  int? startIndex; // 連續經期的開始
  for (int i = 0; i < records.length; i++) {
    final r = records[i];
    final isPeriod = r.isPeriod;

    if (isPeriod) {
      startIndex ??= i; // 開始新的經期段
    }

    // 結束點（遇到非經期 or 最後一天）
    if ((!isPeriod || i == records.length - 1) && startIndex != null) {
      final endIndex = isPeriod ? i : i - 1;

      list.add(
        VerticalRangeAnnotation(
          x1: startIndex.toDouble() - 0.4,
          x2: endIndex.toDouble() + 0.4,
          color: Colors.pink.withValues(alpha: 0.15),
        ),
      );

      startIndex = null; // 重置
    }
  }

  return list;
}

  @override
Widget build(BuildContext context) {
  if (records.length < 2) {
    return const Center(child: Text('資料不足，無法顯示趨勢圖'));
  }

  // ===== 1️⃣ 準備情緒曲線點 =====
  final spots = <FlSpot>[];

  for (int i = 0; i < records.length; i++) {
    final r = records[i];

    double? value;
    if (useMovingAverage) {
      value = _calcMA7(r.date);
    } else {
      value = _getValue(r);
    }

    if (value != null) {
      spots.add(FlSpot(i.toDouble(), value));
    }
  }

  if (spots.isEmpty) {
    return const Center(child: Text('此情緒目前沒有數據'));
  }

  // ===== 2️⃣ 🔥 在這裡「一次性」產生經期粉紅區塊 =====
  final periodRanges = buildPeriodRanges(records);
  debugPrint('🩸 periodRanges count = ${periodRanges.length}');

  final lineColor = useMovingAverage ? Colors.orange : Colors.teal;

  // ===== 3️⃣ 繪製圖表 =====
  return LineChart(
    LineChartData(
      minY: 0,
      maxY: 10,

      // 🌸 經期粉紅色背景
      rangeAnnotations: RangeAnnotations(
        verticalRangeAnnotations: periodRanges,
      ),

      gridData: FlGridData(
        show: true,
        horizontalInterval: 2,
        drawVerticalLine: false,
      ),

      titlesData: FlTitlesData(
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 2,
            reservedSize: 30,
            getTitlesWidget: (v, m) =>
                Text(v.toInt().toString()),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (val, meta) {
              final index = val.toInt();
              if (index < 0 || index >= records.length) {
                return const SizedBox.shrink();
              }

              final int interval = records.length > 10 ? 5 : 1;
              if (index % interval != 0) {
                return const SizedBox.shrink();
              }

              final d = records[index].date;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${d.month}/${d.day}',
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
      ),

      borderData: FlBorderData(show: false),

      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: lineColor,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: lineColor.withValues(alpha: 0.15),
          ),
        ),
      ],
    ),
  );
}


  // 取得單日特定情緒數值
  double? _getValue(DailyRecord r) {
    if (targetEmotion == '整體情緒') return r.overallMood;
    // 找特定情緒
    try {
      final e = r.emotions.firstWhere((element) => element.name == targetEmotion);
      return e.value?.toDouble();
    } catch (_) {
      return null;
    }
  }

  // 計算 7 日移動平均
  double? _calcMA7(DateTime targetDate) {
    // 找出 targetDate 以及前 6 天 (共 7 天) 的所有紀錄
    // 注意：這裡假設 fullRecords 是已經依照日期排序好的
    
    final windowStart = DateTime(targetDate.year, targetDate.month, targetDate.day).subtract(const Duration(days: 6));
    
    final windowRecords = fullRecords.where((r) {
      // 必須 <= targetDate 且 >= windowStart
      // 因為 r.date 可能有時間，統一正規化比較保險，但這裡簡化處理直接比
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

    if (count == 0) return null;
    return total / count;
  }
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

    // 計算情緒平均 (改用 overallMood)
    final moodValues = weekRecords
        .map((r) => r.overallMood)
        .where((v) => v != null)
        .cast<double>()
        .toList();

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

    final avgMood = moodValues.isEmpty
        ? null
        : moodValues.reduce((a, b) => a + b) / moodValues.length;

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
            if (avgMood != null) ...[
              const SizedBox(height: 4),
              Text(
                '平均情緒：約 ${avgMood.toStringAsFixed(1)} / 10',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
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
              // ✅ 先用提示取代跳頁，避免 ProPage 不存在造成編譯錯
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
