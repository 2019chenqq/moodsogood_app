import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'medication_local_db.dart';

class MedSymptomComparePage extends StatefulWidget {
  const MedSymptomComparePage({super.key});

  @override
  State<MedSymptomComparePage> createState() => _MedSymptomComparePageState();
}

class _MedSymptomComparePageState extends State<MedSymptomComparePage> {
  String? _selectedMedId;
  Map<String, dynamic>? _selectedMedData;

  late final FlutterTts _tts;

  DateTime _anchorDate = DateTime.now();
  int _windowDays = 7;

  bool _loading = false;

  // 結果
  Map<String, double> _beforeSymptomRates = {};
  Map<String, double> _afterSymptomRates = {};
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

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();
    // Prefer Traditional Chinese if available
    _tts.setLanguage('zh-TW');
    _tts.setSpeechRate(0.45);
    
    // 初始化時從 Firebase 同步最新藥物到本地
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _syncFromFirebase(uid);
    }
  }

  Future<void> _syncFromFirebase(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final startTs = data['startDate'];
        DateTime? startDate;
        if (startTs is Timestamp) startDate = startTs.toDate();
        if (startTs is String) startDate = DateTime.tryParse(startTs);

        final mapped = {
          'id': doc.id,
          'name': data['name'],
          'dose': data['dose'],
          'dosePerUnit': data['dosePerUnit'],
          'pillCount': data['pillCount'],
          'concentrationMg': data['concentrationMg'],
          'concentrationMl': data['concentrationMl'],
          'intakeMl': data['intakeMl'],
          'unit': data['unit'],
          'type': data['type'],
          'intervalDays': data['intervalDays'],
          'times': (data['times'] as List?)?.cast<String>() ?? <String>[],
          'purposes': (data['purposes'] as List?)?.cast<String>() ?? <String>[],
          'note': data['note'],
          'startDate': startDate?.toString(),
          'isActive': data['isActive'] ?? true,
          'bodySymptoms': (data['bodySymptoms'] as List?)?.cast<String>() ?? <String>[],
          'purposeOther': data['purposeOther'],
          'createdAt': DateTime.now().toString(),
          'updatedAt': DateTime.now().toString(),
          'lastChangeAt': (data['lastChangeAt'] is Timestamp)
              ? (data['lastChangeAt'] as Timestamp).toDate().toString()
              : data['lastChangeAt']?.toString(),
        };

        await MedicationLocalDB().addMedication(uid, mapped);
      }
    } catch (e) {
      debugPrint('症狀比對頁同步 Firebase 失敗：$e');
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speakAnchorDate() async {
    try {
      final y = _anchorDate.year;
      final m = _anchorDate.month;
      final d = _anchorDate.day;
      final text = '調整日期為 $y 年 $m 月 $d 日';
      await _tts.speak(text);
    } catch (_) {
      // ignore TTS errors silently
    }
  }

  // -----------------------------
  // UI: 藥物選擇
  // -----------------------------
  Widget _buildMedPicker(String uid) {
    return _Card(
      title: '選擇藥物',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getMedsForCompare(uid),
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

          final meds = snap.data ?? [];
          if (meds.isEmpty) {
            return const Text('尚未建立藥物清單');
          }

          // Dropdown items
          final items = meds.map((med) {
            final name = (med['name'] ?? '').toString().trim();
            final medId = (med['id'] as String?) ?? '';
            final display = name.isEmpty ? medId : name;
            return DropdownMenuItem<String>(
              value: medId,
              child: Text(display),
            );
          }).toList();

          return DropdownButtonFormField<String>(
            value: _selectedMedId,
            items: items,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) async {
              final med = meds.firstWhere((x) => x['id'] == v);

              // Try to find an adjustment/update date in common fields
              DateTime? medAdjustedDate;
              for (final key in ['adjustedAt', 'adjustedDate', 'updatedAt', 'date', 'startDate']) {
                if (med.containsKey(key) && med[key] != null) {
                  final val = med[key];
                  if (val is DateTime) {
                    medAdjustedDate = val;
                  } else if (val is String) {
                    medAdjustedDate = DateTime.tryParse(val);
                  }
                  if (medAdjustedDate != null) break;
                }
              }

              setState(() {
                _selectedMedId = v;
                _selectedMedData = med;
                if (medAdjustedDate != null) {
                  _anchorDate = DateTime(
                    medAdjustedDate.year,
                    medAdjustedDate.month,
                    medAdjustedDate.day,
                  );
                }
              });

              // Speak the anchor date if we set one (or always speak current anchor)
              await _speakAnchorDate();
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
      subtitle: '例如回診調藥日，會拿前段 $_windowDays 天與後段 $_windowDays 天做比較',
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
  // 從本地 DB 獲取服用中的藥物
  Future<List<Map<String, dynamic>>> _getMedsForCompare(String uid) async {
    final all = await MedicationLocalDB().getMedicationsForDisplay(uid);
    return all.where((m) => (m['isActive'] ?? true) == true).toList();
  }

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
        start: _anchorDate, // 從調整當天開始
        endExclusive: _anchorDate.add(Duration(days: _windowDays)),
      );

      final beforeDocs = await _fetchDailyRecords(uid, beforeRange.$1, beforeRange.$2);
      final afterDocs = await _fetchDailyRecords(uid, afterRange.$1, afterRange.$2);

      final beforeAgg = _aggregateDailyRecords(beforeDocs);
      final afterAgg = _aggregateDailyRecords(afterDocs);

      setState(() {
        _beforeSymptomRates = beforeAgg.symptomRate;
        _afterSymptomRates = afterAgg.symptomRate;
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
  if (!startInclusive.isBefore(endExclusive)) {
    return [];
  }

  String id(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  final recordsRef = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('dailyRecords');

  final byDate = await recordsRef
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
      .where('date', isLessThan: Timestamp.fromDate(endExclusive))
      .get();

  final startId = id(startInclusive);
  // endExclusive 不含，所以用「前一天」作為 endId（含）
  final endId = id(endExclusive.subtract(const Duration(days: 1)));

  final byDocId = await recordsRef
      .where(FieldPath.documentId, isGreaterThanOrEqualTo: startId)
      .where(FieldPath.documentId, isLessThanOrEqualTo: endId)
      .get();

  final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
    for (final d in byDate.docs) d.id: d,
    for (final d in byDocId.docs) d.id: d,
  };

  return merged.values.toList();
}

  // -----------------------------
  // 解析 + 平均計算（你最可能需要微調的地方）
  // -----------------------------
  _AggResult _aggregateDailyRecords(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // 累積 sum & count
    final symptomDays = <String, int>{};
    final emotionSum = <String, double>{};
    final emotionCount = <String, int>{};

    int daysWithAny = 0;

    for (final d in docs) {
      final data = d.data();

      final symptomNames = _normalizeSymptomNameSet(
        data['symptoms'] ?? data['bodySymptoms'] ?? data['symptomScores'],
      );
      var emotions = _normalizeNameScoreMap(
        data['emotions'] ?? data['emotionScores'],
      );

      // 某些資料只存 overallMood，補成可比較欄位避免後段空白。
      if (emotions.isEmpty) {
        final overall = _toDouble(data['overallMood']);
        if (overall != null) {
          emotions = {'整體情緒': overall};
        }
      }

      if (symptomNames.isNotEmpty || emotions.isNotEmpty) {
        daysWithAny += 1;
      }

      for (final name in symptomNames) {
        symptomDays[name] = (symptomDays[name] ?? 0) + 1;
      }
      for (final e in emotions.entries) {
        emotionSum[e.key] = (emotionSum[e.key] ?? 0) + e.value;
        emotionCount[e.key] = (emotionCount[e.key] ?? 0) + 1;
      }
    }

    final symptomRate = <String, double>{};
    if (daysWithAny > 0) {
      for (final e in symptomDays.entries) {
        symptomRate[e.key] = (e.value / daysWithAny) * 100;
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
      symptomRate: symptomRate,
      emotionAvg: toAvg(emotionSum, emotionCount),
    );
  }

  Set<String> _normalizeSymptomNameSet(dynamic raw) {
    final out = <String>{};
    if (raw == null) return out;

    if (raw is List) {
      for (final item in raw) {
        if (item is String) {
          final name = item.trim();
          if (name.isNotEmpty) out.add(name);
          continue;
        }

        if (item is Map) {
          final name =
              (item['name'] ?? item['title'] ?? item['symptom'] ?? '').toString().trim();
          if (name.isNotEmpty) out.add(name);
        }
      }
      return out;
    }

    if (raw is Map) {
      for (final k in raw.keys) {
        final name = (k ?? '').toString().trim();
        if (name.isNotEmpty) out.add(name);
      }
      return out;
    }

    return out;
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

    final symptomDeltas = _buildSymptomDeltas(
      before: _beforeSymptomRates,
      after: _afterSymptomRates,
      worsenThreshold: 20,
    );

    final emotionDeltas = _buildEmotionDeltas(
      before: _beforeAvgEmotions,
      after: _afterAvgEmotions,
      worsenThreshold: 0.8,
    );

    final attentionSymptoms = symptomDeltas
        .where((x) => x.kind == _DeltaKind.newlyAppeared || x.kind == _DeltaKind.worsened)
        .toList();
    final attentionEmotions = emotionDeltas
        .where((x) => x.kind == _DeltaKind.newlyAppeared || x.kind == _DeltaKind.worsened)
        .toList();

    final improvedSymptoms = symptomDeltas.where((x) => x.kind == _DeltaKind.improved).toList();
    final improvedEmotions = emotionDeltas.where((x) => x.kind == _DeltaKind.improved).toList();

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
              const SizedBox(height: 8),
              Text('信心等級：${_confidenceText(_beforeDaysCount, _afterDaysCount)}'),
              Text('需關注症狀（新出現/惡化）：${attentionSymptoms.length} 項'),
              Text('需關注情緒（新出現/惡化）：${attentionEmotions.length} 項'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        _DeltaTable(
          title: '需關注：症狀（新出現/惡化）',
          rows: attentionSymptoms,
          isPercentage: true,
        ),
        const SizedBox(height: 12),

        _DeltaTable(
          title: '需關注：情緒（新出現/惡化）',
          rows: attentionEmotions,
        ),
        const SizedBox(height: 12),

        Card(
          child: ExpansionTile(
            title: const Text('展開完整分析（改善 + 全部差異）'),
            subtitle: const Text('用來輔助回診判讀，預設收合以維持畫面乾淨'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              _DeltaTable(
                title: '改善：症狀',
                rows: improvedSymptoms,
                isPercentage: true,
              ),
              const SizedBox(height: 10),
              _DeltaTable(
                title: '改善：情緒',
                rows: improvedEmotions,
              ),
              const SizedBox(height: 10),
              _DeltaTable(
                title: '全部差異：症狀',
                rows: symptomDeltas,
                isPercentage: true,
              ),
              const SizedBox(height: 10),
              _DeltaTable(
                title: '全部差異：情緒',
                rows: emotionDeltas,
              ),
              const SizedBox(height: 8),
              Text(
                '提醒：本頁顯示的是關聯趨勢，不等於因果。請合併睡眠、壓力與生活事件判讀。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _confidenceText(int beforeDays, int afterDays) {
    final minSide = beforeDays < afterDays ? beforeDays : afterDays;
    if (minSide >= 5) return '高（前後至少 5 天）';
    if (minSide >= 3) return '中（前後至少 3 天）';
    return '低（資料天數偏少）';
  }

  List<_MetricDelta> _buildSymptomDeltas({
    required Map<String, double> before,
    required Map<String, double> after,
    required double worsenThreshold,
  }) {
    final keys = {...before.keys, ...after.keys};
    final out = <_MetricDelta>[];

    for (final k in keys) {
      final b = before[k];
      final a = after[k] ?? 0;
      if (a <= 0) continue;

      if (b == null || b <= 0) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.newlyAppeared,
          severityScore: a,
        ));
        continue;
      }

      final diff = a - b;
      if (diff >= worsenThreshold) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.worsened,
          severityScore: diff,
        ));
      } else if (diff <= -worsenThreshold) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.improved,
          severityScore: -diff,
        ));
      } else {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.minor,
          severityScore: diff.abs(),
        ));
      }
    }

    out.sort((x, y) => y.severityScore.compareTo(x.severityScore));
    return out;
  }

  List<_MetricDelta> _buildEmotionDeltas({
    required Map<String, double> before,
    required Map<String, double> after,
    required double worsenThreshold,
  }) {
    final keys = {...before.keys, ...after.keys};
    final out = <_MetricDelta>[];

    for (final k in keys) {
      final b = before[k];
      final a = after[k];
      if (a == null) continue;

      final positive = _isPositiveEmotion(k);

      if (b == null) {
        out.add(_MetricDelta(
          name: k,
          before: null,
          after: a,
          kind: _DeltaKind.newlyAppeared,
          severityScore: a,
          positiveEmotion: positive,
        ));
        continue;
      }

      final rawDiff = a - b;
      final worsenDelta = positive ? -rawDiff : rawDiff;

      if (worsenDelta >= worsenThreshold) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.worsened,
          severityScore: worsenDelta,
          positiveEmotion: positive,
        ));
      } else if (worsenDelta <= -worsenThreshold) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.improved,
          severityScore: -worsenDelta,
          positiveEmotion: positive,
        ));
      } else {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.minor,
          severityScore: worsenDelta.abs(),
          positiveEmotion: positive,
        ));
      }
    }

    out.sort((x, y) => y.severityScore.compareTo(x.severityScore));
    return out;
  }

  bool _isPositiveEmotion(String name) {
    const positiveKeywords = [
      '開心',
      '快樂',
      '愉悅',
      '平靜',
      '安定',
      '動力',
      '能量',
      '希望',
      '專注',
      '食慾',
      '活動量',
    ];
    return positiveKeywords.any((k) => name.contains(k));
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
  final bool isPercentage;
  final double? highlightThreshold;

  const _CompareTable({
    required this.title,
    required this.before,
    required this.after,
    this.isPercentage = false,
    this.highlightThreshold,
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

              String fmt(double? x) {
                if (x == null) return '—';
                final base = x.toStringAsFixed(isPercentage ? 1 : 2);
                return isPercentage ? '$base%' : base;
              }

              String fmtDiff(double? b, double? a) {
                if (b == null || a == null) return '—';
                final value = (a - b).toStringAsFixed(isPercentage ? 1 : 2);
                return isPercentage ? '$value%' : value;
              }

              Color? highlightColor(double? value) {
                if (value == null || !isPercentage) return null;
                if (highlightThreshold == null) return null;
                if (value >= highlightThreshold!) {
                  return Theme.of(context).colorScheme.error;
                }
                return null;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(k)),
                    SizedBox(
                      width: 70,
                      child: Text(
                        fmt(b),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: highlightColor(b)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 70,
                      child: Text(
                        fmt(a),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: highlightColor(a)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 80,
                      child: Text(
                        fmtDiff(b, a),
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
              '欄位：前段 / 後段 / 差值（後-前）${isPercentage ? '，單位 %' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AfterOnlyTable extends StatelessWidget {
  final String title;
  final Map<String, double> data;
  final bool isPercentage;

  const _AfterOnlyTable({
    required this.title,
    required this.data,
    this.isPercentage = false,
  });

  @override
  Widget build(BuildContext context) {
    final keys = data.keys.toList()..sort();
    if (keys.isEmpty) {
      return _Hint(text: '$title：沒有新項目');
    }

    String fmt(double x) {
      final base = x.toStringAsFixed(isPercentage ? 1 : 2);
      return isPercentage ? '$base%' : base;
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
              final v = data[k]!;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(k)),
                    SizedBox(
                      width: 90,
                      child: Text(
                        fmt(v),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              '只顯示前段未出現、後段才出現的項目。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

enum _DeltaKind { newlyAppeared, worsened, improved, minor }

class _MetricDelta {
  final String name;
  final double? before;
  final double after;
  final _DeltaKind kind;
  final double severityScore;
  final bool positiveEmotion;

  const _MetricDelta({
    required this.name,
    required this.before,
    required this.after,
    required this.kind,
    required this.severityScore,
    this.positiveEmotion = false,
  });
}

class _DeltaTable extends StatelessWidget {
  final String title;
  final List<_MetricDelta> rows;
  final bool isPercentage;

  const _DeltaTable({
    required this.title,
    required this.rows,
    this.isPercentage = false,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _Hint(text: '$title：沒有項目');
    }

    String fmt(double? v) {
      if (v == null) return '—';
      final base = v.toStringAsFixed(isPercentage ? 1 : 2);
      return isPercentage ? '$base%' : base;
    }

    String diffText(_MetricDelta d) {
      if (d.before == null) return '新出現';
      final diff = d.after - d.before!;
      final sign = diff >= 0 ? '+' : '';
      final val = diff.toStringAsFixed(isPercentage ? 1 : 2);
      return isPercentage ? '$sign$val%' : '$sign$val';
    }

    String kindText(_DeltaKind k) {
      switch (k) {
        case _DeltaKind.newlyAppeared:
          return '新出現';
        case _DeltaKind.worsened:
          return '惡化';
        case _DeltaKind.improved:
          return '改善';
        case _DeltaKind.minor:
          return '輕微';
      }
    }

    Color? kindColor(BuildContext context, _DeltaKind k) {
      switch (k) {
        case _DeltaKind.newlyAppeared:
        case _DeltaKind.worsened:
          return Theme.of(context).colorScheme.error;
        case _DeltaKind.improved:
          return Colors.green;
        case _DeltaKind.minor:
          return Theme.of(context).colorScheme.onSurfaceVariant;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...rows.map((row) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(row.name)),
                    SizedBox(
                      width: 60,
                      child: Text(fmt(row.before), textAlign: TextAlign.right),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: Text(fmt(row.after), textAlign: TextAlign.right),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: Text(diffText(row), textAlign: TextAlign.right),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      child: Text(
                        kindText(row.kind),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: kindColor(context, row.kind)),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              '欄位：前段 / 後段 / 差值 / 分類${isPercentage ? '（單位 %）' : ''}',
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
  final Map<String, double> symptomRate;
  final Map<String, double> emotionAvg;

  _AggResult({
    required this.daysCount,
    required this.symptomRate,
    required this.emotionAvg,
  });
}
