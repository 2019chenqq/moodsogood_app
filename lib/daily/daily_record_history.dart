import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/daily_record.dart'; // 確保引用正確
import '../utils/date_helper.dart';   // 確保引用正確
import 'record_detail_screen.dart';   // 確保引用正確
import '../models/period_cycle.dart';
import '../widgets/main_drawer.dart';
import '../quotes.dart';

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
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(child: Text('請先登入帳號'));
    }

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailyRecords')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(90) // 抓 90 天
        .withConverter<DailyRecord>(
          fromFirestore: (snap, _) => DailyRecord.fromFirestore(snap),
          toFirestore: (record, _) => record.toFirestore(),
        );

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
      // 修改 Scaffod 的 body 區塊
      body: StreamBuilder<QuerySnapshot>(
        // 1. 外層：先讀取經期資料
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('periodCycles')
            .orderBy('startDate', descending: true)
            .snapshots(),
        builder: (context, periodSnap) {
          // 處理經期資料 (如果還沒讀完或沒資料，就給空陣列)
          final cycles = periodSnap.data?.docs
              .map((doc) => PeriodCycle.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
              .toList() ?? [];

          // 2. 內層：再讀取原本的日記紀錄 (這是你原本的那段)
          return StreamBuilder<QuerySnapshot<DailyRecord>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('發生錯誤：${snapshot.error}'));
              }

              final docs = snapshot.data?.docs ?? [];
              var allRecords = docs.map((e) => e.data()).toList();
              
              // 確保排序：舊 -> 新 (畫圖用)
              allRecords.sort((a, b) => a.date.compareTo(b.date));

              // 取得所有出現過的情緒名稱
              final availableEmotions = _extractEmotionNames(allRecords);

              // 列表用的資料 (需過濾日期 + 反序)
              var listRecords = List<DailyRecord>.from(allRecords);
              listRecords = _applyDateFilter(listRecords, _dateFilter);
              listRecords.sort((a, b) => b.date.compareTo(a.date));

              return TabBarView(
                controller: _tabController,
                children: [
                  // 分頁 1: 列表
                  _buildListPage(listRecords, allRecords), 
                  
                  // 分頁 2: 圖表 (🔥 這裡把 cycles 傳進去了)
                  _buildChartPage(allRecords, availableEmotions, cycles),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // --- 分頁 1: 列表 UI ---
  Widget _buildListPage(List<DailyRecord> records, List<DailyRecord> allRecordsForSummary) {
    return Column(
      children: [
        // 簡易週報卡片
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: WeeklySummaryCard(allRecords: allRecordsForSummary),
        ),
        
        // 篩選器 (只影響列表)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: _buildDateFilterChips(),
        ),
        
        const Divider(height: 1),
        
        Expanded(
          child: records.isEmpty
              ? const Center(child: Text('沒有符合條件的紀錄'))
              : ListView.separated(
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final r = records[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Text(
                        DateHelper.toDisplay(r.date),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: _buildRecordSubtitle(context, r),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                         // 導航到詳細頁
                         final uid = FirebaseAuth.instance.currentUser?.uid;
                         if (uid != null) {
                           Navigator.push(context, MaterialPageRoute(
                             builder: (_) => RecordDetailScreen(uid: uid, docId: r.id),
                           ));
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
  Widget _buildChartPage(List<DailyRecord> allRecords, Set<String> emotionNames,
  List<PeriodCycle> cycles,) {
    // 1. 根據日期篩選資料 (圖表也要跟著篩選)
    final filteredRecords = _applyDateFilter(allRecords, _dateFilter);
    
    // 2. 決定是否使用移動平均線 (7天 & 30天都用，或者依照你說的只在長天期用)
    // 這裡邏輯：如果是「最近7天」，看原始數據；如果是「30天」或「全部」，看 MA7
    final bool useMA = _dateFilter != DateFilter.last7;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 上方控制區：篩選天數 + 情緒下拉選單
          Row(
            children: [
              // 天數篩選器 (簡化版，或者共用上面的 _buildDateFilterChips)
               Expanded(child: _buildDateFilterChips(compact: true)),
            ],
          ),
          const SizedBox(height: 12),
          
          // 情緒下拉選單
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: emotionNames.contains(_selectedEmotion) ? _selectedEmotion : '整體情緒',
                isExpanded: true,
                dropdownColor: Theme.of(context).cardColor,
                icon: Icon(Icons.arrow_drop_down, color: Theme.of(context).iconTheme.color),
                items: emotionNames.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedEmotion = val);
                },
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          Text(
            useMA ? '$_selectedEmotion (7日移動平均趨勢)' : '$_selectedEmotion (每日數值)',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // 圖表本體
         SizedBox( // <--- 改用 SizedBox
            height: 300,
            child: _ChartWidget(
              records: filteredRecords,     // 顯示範圍內的資料
              fullRecords: allRecords,      // 用來算 MA 的完整歷史資料 (因為算第一天的 MA 需要往前找)
              targetEmotion: _selectedEmotion,
              useMovingAverage: useMA,
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
  
  // 遍歷所有資料，找出所有用過的情緒標籤
  Set<String> _extractEmotionNames(List<DailyRecord> records) {
    final names = <String>{'整體情緒'}; // 預設必有
    for (var r in records) {
      for (var e in r.emotions) {
        if (e.name.isNotEmpty) names.add(e.name);
      }
    }
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
// 睡眠狀態的中英對照表
  final Map<String, String> _sleepFlagMap = const {
    'good': '優',
    'ok': '良好',
    'earlyWake': '早醒',
    'dreams': '多夢',
    'light': '淺眠',
    'nocturia': '夜尿',
    'fragile': '睡睡醒醒',
    'lack': '睡眠不足',
    'initInsomnia': '入睡困難',
    'maintInsomnia': '睡眠中斷',
  };
  Widget _buildRecordSubtitle(BuildContext context, DailyRecord r) {
    // ... 保持你原本的邏輯 ...
     final List<String> parts = [];
      if (r.overallMood != null) parts.add('情緒：${r.overallMood!.toStringAsFixed(1)}');
      // --- 🔥計算總睡眠時數 (夜間 + 小睡) ---
    final night = r.sleep.durationHours ?? 0;
    // 將所有小睡的分鐘數加總
    final napMinutes = r.sleep.naps.fold(0, (sum, nap) => sum + nap.durationMinutes);
    // 換算成小時 (除以 60) 並加上夜間睡眠
    final totalSleep = night + (napMinutes / 60.0);

    if (totalSleep > 0) {
      parts.add('睡眠：${totalSleep.toStringAsFixed(1)}hr');
    }

    if (r.sleep.flags.isNotEmpty) {
      final raw = r.sleep.flags.first;
      final label = _sleepFlagMap[raw] ?? raw;
      parts.add(label); 
    }
    
    return Text(parts.join(' · '), style: Theme.of(context).textTheme.bodyMedium);
  }
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

  @override
  Widget build(BuildContext context) {
    if (records.length < 2) {
      return const Center(child: Text('資料不足，無法顯示趨勢圖'));
    }

    final spots = <FlSpot>[];
    // 🔥 1. 準備生理期區塊列表
    final periodRanges = <VerticalRangeAnnotation>[];

    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      
      // 計算數值 (保持原本邏輯)
      double? value;
      if (useMovingAverage) {
        value = _calcMA7(r.date);
      } else {
        value = _getValue(r);
      }
      if (value != null) {
        spots.add(FlSpot(i.toDouble(), value));
      }
final hasPeriod = r.isPeriod || 
                        r.symptoms.contains('生理期') || 
                        r.symptoms.contains('月經');

      if (hasPeriod) {
        periodRanges.add(
          VerticalRangeAnnotation(
            x1: i - 0.4, 
            x2: i + 0.4,
            color: Colors.pink.withOpacity(0.15), // 粉紅色背景
          ),
        );
      }
    }

    if (spots.isEmpty) return const Center(child: Text('此情緒目前沒有數據'));
final lineColor = useMovingAverage ? Colors.orange : Colors.teal;
    return LineChart(
      LineChartData(
        minY: 0, maxY: 10,
        // 🔥 3. 加入這個設定：繪製背景區塊
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: periodRanges,
        ),
        gridData: FlGridData(show: true, horizontalInterval: 2, drawVerticalLine: false),
        titlesData: FlTitlesData(
          // ... (保持原本的設定) ...
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 2, reservedSize: 30, getTitlesWidget: (v, m) => Text(v.toInt().toString()))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (val, meta) {
                final index = val.toInt();
                if (index < 0 || index >= records.length) return const SizedBox.shrink();
                
                // 智慧標籤間距
                int interval = records.length > 10 ? 5 : 1;
                if (index % interval != 0) return const SizedBox.shrink();

                final d = records[index].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${d.month}/${d.day}', style: const TextStyle(fontSize: 10)),
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
            color: useMovingAverage ? Colors.orange : Colors.teal,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            // 🔥 4. 如果有生理期，線條下方就不填色了，以免顏色混雜太亂
            // 或者你可以保留，看你喜歡哪種效果
            belowBarData: BarAreaData(
              show: true, 
              color: lineColor.withOpacity(0.15), // 半透明填充
          ),)
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
                '平均睡眠：約 ${avgSleep.toStringAsFixed(1)} 小時',
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