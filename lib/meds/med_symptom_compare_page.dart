import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MedSymptomComparePage extends StatefulWidget {
  const MedSymptomComparePage({super.key});

  @override
  State<MedSymptomComparePage> createState() => _MedSymptomComparePageState();
}

class _MedSymptomComparePageState extends State<MedSymptomComparePage> {
  String? _selectedMedId;
  Map<String, dynamic>? _selectedMedData;

  DateTime _anchorDate = DateTime.now();
  int _windowDays = 7;

  bool _loading = false;

  // 結果
  Map<String, double> _beforeAvgSymptoms = {};
  Map<String, double> _afterAvgSymptoms = {};
  Map<String, double> _beforeAvgEmotions = {};
  Map<String, double> _afterAvgEmotions = {};
  int _beforeDaysCount = 0;
  int _afterDaysCount = 0;

  String? _error;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('症狀交叉比對'),
        actions: [
          IconButton(
            tooltip: '重新計算',
            icon: const Icon(Icons.refresh),
            onPressed: uid == null ? null : _runCompare,
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('尚未登入'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMedPicker(uid),
                const SizedBox(height: 12),
                _buildAnchorPicker(),
                const SizedBox(height: 12),
                _buildWindowPicker(),
                const SizedBox(height: 16),

                ElevatedButton.icon(
                  onPressed: (_selectedMedId == null || _loading) ? null : _runCompare,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.analytics_outlined),
                  label: const Text('開始比對'),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],

                const SizedBox(height: 20),
                _buildResultSection(),
              ],
            ),
    );
  }

  // -----------------------------
  // UI: 藥物選擇
  // -----------------------------
  Widget _buildMedPicker(String uid) {
    final medsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('medications')
        .orderBy('isActive', descending: true)
        .orderBy('updatedAt', descending: true)
        .snapshots();

    return _Card(
      title: '選擇藥物',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: medsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            );
          }
          if (snap.hasError) {
            return Text('讀取藥物失敗：${snap.error}');
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Text('尚未建立藥物清單');
          }

          // Dropdown items
          final items = docs.map((d) {
            final data = d.data();
            final name = (data['name'] ?? '').toString().trim();
            final display = name.isEmpty ? d.id : name;
            final isActive = (data['isActive'] ?? true) == true;
            return DropdownMenuItem<String>(
              value: d.id,
              child: Text(isActive ? display : '$display（已停用）'),
            );
          }).toList();

          return DropdownButtonFormField<String>(
            value: _selectedMedId,
            items: items,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              setState(() {
                _selectedMedId = v;
                _selectedMedData = docs.firstWhere((x) => x.id == v).data();
              });
            },
          );
        },
      ),
    );
  }

  // -----------------------------
  // UI: 調整日（anchor）
  // -----------------------------
  Widget _buildAnchorPicker() {
    return _Card(
      title: '調整日期（比對基準日）',
      subtitle: '例如回診調藥日，會拿前後各 $_windowDays 天來算平均',
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_anchorDate.year.toString().padLeft(4, '0')}/'
              '${_anchorDate.month.toString().padLeft(2, '0')}/'
              '${_anchorDate.day.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton.icon(
            onPressed: _pickAnchorDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: const Text('選日期'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null) return;
    setState(() => _anchorDate = picked);
  }

  // -----------------------------
  // UI: 窗口天數
  // -----------------------------
  Widget _buildWindowPicker() {
    return _Card(
      title: '比較區間',
      child: Row(
        children: [
          const Text('前後各'),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _windowDays,
            items: const [
              DropdownMenuItem(value: 3, child: Text('3 天')),
              DropdownMenuItem(value: 7, child: Text('7 天')),
              DropdownMenuItem(value: 14, child: Text('14 天')),
              DropdownMenuItem(value: 30, child: Text('30 天')),
            ],
            onChanged: (v) => setState(() => _windowDays = v ?? 7),
          ),
          const SizedBox(width: 8),
          const Text('（含有填寫的日記錄才會計入）'),
        ],
      ),
    );
  }

  // -----------------------------
  // 計算主流程
  // -----------------------------
  Future<void> _runCompare() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_selectedMedId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final beforeRange = _dateRange(
        start: _anchorDate.subtract(Duration(days: _windowDays)),
        endExclusive: _anchorDate, // 不含 anchor 當天
      );

      final afterRange = _dateRange(
        start: _anchorDate.add(const Duration(days: 1)), // 從隔天開始
        endExclusive: _anchorDate.add(Duration(days: _windowDays + 1)),
      );

      final beforeDocs = await _fetchDailyRecords(uid, beforeRange.$1, beforeRange.$2);
      final afterDocs = await _fetchDailyRecords(uid, afterRange.$1, afterRange.$2);

      final beforeAgg = _aggregateDailyRecords(beforeDocs);
      final afterAgg = _aggregateDailyRecords(afterDocs);

      setState(() {
        _beforeAvgSymptoms = beforeAgg.symptomAvg;
        _afterAvgSymptoms = afterAgg.symptomAvg;
        _beforeAvgEmotions = beforeAgg.emotionAvg;
        _afterAvgEmotions = afterAgg.emotionAvg;
        _beforeDaysCount = beforeAgg.daysCount;
        _afterDaysCount = afterAgg.daysCount;
      });
    } catch (e) {
      setState(() => _error = '比對失敗：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // 回傳 (startInclusive, endExclusive)
  (DateTime, DateTime) _dateRange({required DateTime start, required DateTime endExclusive}) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(endExclusive.year, endExclusive.month, endExclusive.day);
    return (s, e);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchDailyRecords(
  String uid,
  DateTime startInclusive,
  DateTime endExclusive,
) async {
  String id(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  final startId = id(startInclusive);
  // endExclusive 不含，所以用「前一天」作為 endId（含）
  final endId = id(endExclusive.subtract(const Duration(days: 1)));

  final q = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('dailyRecords')
      .where(FieldPath.documentId, isGreaterThanOrEqualTo: startId)
      .where(FieldPath.documentId, isLessThanOrEqualTo: endId)
      .get();

  return q.docs;
}

  // -----------------------------
  // 解析 + 平均計算（你最可能需要微調的地方）
  // -----------------------------
  _AggResult _aggregateDailyRecords(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // 累積 sum & count
    final symptomSum = <String, double>{};
    final symptomCount = <String, int>{};
    final emotionSum = <String, double>{};
    final emotionCount = <String, int>{};

    int daysWithAny = 0;

    for (final d in docs) {
      final data = d.data();

      // 你可能有：data['symptoms']、data['symptomScores']、data['emotions']、data['emotionScores']…
      final symptoms = _normalizeNameScoreMap(
        data['symptoms'] ?? data['symptomScores'],
      );
      final emotions = _normalizeNameScoreMap(
        data['emotions'] ?? data['emotionScores'],
      );

      if (symptoms.isNotEmpty || emotions.isNotEmpty) {
        daysWithAny += 1;
      }

      for (final e in symptoms.entries) {
        symptomSum[e.key] = (symptomSum[e.key] ?? 0) + e.value;
        symptomCount[e.key] = (symptomCount[e.key] ?? 0) + 1;
      }
      for (final e in emotions.entries) {
        emotionSum[e.key] = (emotionSum[e.key] ?? 0) + e.value;
        emotionCount[e.key] = (emotionCount[e.key] ?? 0) + 1;
      }
    }

    Map<String, double> toAvg(Map<String, double> sum, Map<String, int> cnt) {
      final out = <String, double>{};
      for (final k in sum.keys) {
        final c = cnt[k] ?? 0;
        if (c <= 0) continue;
        out[k] = sum[k]! / c;
      }
      return out;
    }

    return _AggResult(
      daysCount: daysWithAny,
      symptomAvg: toAvg(symptomSum, symptomCount),
      emotionAvg: toAvg(emotionSum, emotionCount),
    );
  }

  /// 支援兩種常見結構：
  /// A) Map<String, num>：{'焦慮': 3, '頭痛': 2}
  /// B) List<Map>：[{'name':'焦慮','score':3}, {'name':'頭痛','score':2}]
  Map<String, double> _normalizeNameScoreMap(dynamic raw) {
    final out = <String, double>{};
    if (raw == null) return out;

    if (raw is Map) {
      raw.forEach((k, v) {
        final name = (k ?? '').toString().trim();
        final score = _toDouble(v);
        if (name.isNotEmpty && score != null) out[name] = score;
      });
      return out;
    }

    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final name = (item['name'] ?? item['title'] ?? '').toString().trim();
          final score = _toDouble(item['score'] ?? item['value']);
          if (name.isNotEmpty && score != null) out[name] = score;
        }
      }
      return out;
    }

    return out;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  // -----------------------------
  // 結果 UI
  // -----------------------------
  Widget _buildResultSection() {
    if (_beforeDaysCount == 0 && _afterDaysCount == 0) {
      return const _Hint(
        text: '尚未計算或沒有資料。請先選藥物、選基準日，按「開始比對」。',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Card(
          title: '摘要',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('前段（$_windowDays 天）納入：$_beforeDaysCount 天'),
              Text('後段（$_windowDays 天）納入：$_afterDaysCount 天'),
              if (_selectedMedData != null) ...[
                const SizedBox(height: 8),
                Text('藥物：${(_selectedMedData!['name'] ?? _selectedMedId).toString()}'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        _CompareTable(
          title: '症狀（平均）',
          before: _beforeAvgSymptoms,
          after: _afterAvgSymptoms,
        ),
        const SizedBox(height: 12),

        _CompareTable(
          title: '情緒（平均）',
          before: _beforeAvgEmotions,
          after: _afterAvgEmotions,
        ),
      ],
    );
  }
}

// -----------------------------
// 小元件
// -----------------------------
class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Card({required this.title, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text),
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  final String title;
  final Map<String, double> before;
  final Map<String, double> after;

  const _CompareTable({
    required this.title,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    final keys = {...before.keys, ...after.keys}.toList()..sort();

    if (keys.isEmpty) {
      return _Hint(text: '$title：沒有資料');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...keys.map((k) {
              final b = before[k];
              final a = after[k];
              final diff = (a ?? 0) - (b ?? 0);

              String fmt(double? x) => x == null ? '—' : x.toStringAsFixed(2);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(k)),
                    SizedBox(width: 70, child: Text(fmt(b), textAlign: TextAlign.right)),
                    const SizedBox(width: 10),
                    SizedBox(width: 70, child: Text(fmt(a), textAlign: TextAlign.right)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 80,
                      child: Text(
                        (b == null || a == null) ? '—' : diff.toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: (b == null || a == null)
                              ? null
                              : (diff > 0
                                  ? Theme.of(context).colorScheme.error
                                  : (diff < 0
                                      ? Colors.green
                                      : null)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              '欄位：前段 / 後段 / 差值（後-前）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------
// 聚合結果
// -----------------------------
class _AggResult {
  final int daysCount;
  final Map<String, double> symptomAvg;
  final Map<String, double> emotionAvg;

  _AggResult({
    required this.daysCount,
    required this.symptomAvg,
    required this.emotionAvg,
  });
}
