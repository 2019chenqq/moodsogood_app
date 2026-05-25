import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../constants/healing_design_system.dart';
import 'medication_local_db.dart';
import '../analytics_service.dart';

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
      backgroundColor: HealingDesignSystem.softBlue,
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.softBlue,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: HealingDesignSystem.deepText),
        title: const Text(
          '症狀交叉比對',
          style: TextStyle(
            color: HealingDesignSystem.deepText,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '重新計算',
            icon: const Icon(Icons.refresh, color: HealingDesignSystem.deepText),
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

                FilledButton.icon(
                  onPressed: (_selectedMedId == null || _loading) ? null : _runCompare,
                  style: FilledButton.styleFrom(
                    backgroundColor: HealingDesignSystem.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
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
     AnalyticsService.logPage('med_symptom_compare_page');
    
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
            decoration: InputDecoration(
              filled: true,
              fillColor: HealingDesignSystem.softBlue.withOpacity(0.7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: HealingDesignSystem.lineColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: HealingDesignSystem.lineColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: HealingDesignSystem.primaryBlue, width: 1.2),
              ),
              isDense: true,
            ),
            onChanged: (v) async {
              final med = meds.firstWhere((x) => x['id'] == v);

              setState(() {
                _selectedMedId = v;
                _selectedMedData = med;
              });

              // 從 medAdjustments 取該藥最近一筆調整日期
              DateTime? medAdjustedDate;
              try {
                final uid2 = FirebaseAuth.instance.currentUser?.uid;
                if (uid2 != null) {
                  final adjSnap = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid2)
                      .collection('medAdjustments')
                      .orderBy('date', descending: true)
                      .get();

                  for (final doc in adjSnap.docs) {
                    final items = doc.data()['items'];
                    if (items is! List) continue;
                    final hasThisMed = items.any((item) =>
                        item is Map && item['medDocId']?.toString() == v);
                    if (!hasThisMed) continue;

                    final rawDate = doc.data()['date'];
                    if (rawDate is Timestamp) {
                      medAdjustedDate = rawDate.toDate();
                    } else if (rawDate is String) {
                      medAdjustedDate = DateTime.tryParse(rawDate);
                    }
                    if (medAdjustedDate != null) break;
                  }
                }
              } catch (e) {
                debugPrint('取調整日期失敗：$e');
              }

              // fallback：lastChangeAt → startDate（不用 updatedAt，它會是今天）
              if (medAdjustedDate == null) {
                for (final key in ['lastChangeAt', 'startDate']) {
                  final val = med[key];
                  if (val == null) continue;
                  if (val is DateTime) {
                    medAdjustedDate = val;
                  } else if (val is String) {
                    medAdjustedDate = DateTime.tryParse(val);
                  }
                  if (medAdjustedDate != null) break;
                }
              }

              if (medAdjustedDate != null) {
                setState(() {
                  _anchorDate = DateTime(
                    medAdjustedDate!.year,
                    medAdjustedDate.month,
                    medAdjustedDate.day,
                  );
                });
              }

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
      subtitle: '只有含日記紀錄的天數才計入比對',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [3, 7, 14, 30].map((days) {
          final sel = _windowDays == days;
          return GestureDetector(
            onTap: () => setState(() => _windowDays = days),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel
                    ? HealingDesignSystem.primaryBlue.withOpacity(0.14)
                    : HealingDesignSystem.softBlue,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: sel
                      ? HealingDesignSystem.primaryBlue
                      : HealingDesignSystem.lineColor,
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Text(
                '前後各 $days 天',
                style: TextStyle(
                  color: sel
                      ? HealingDesignSystem.primaryBlue
                      : HealingDesignSystem.deepText,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
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
      worsenThreshold: 30,
    );

    final emotionDeltas = _buildEmotionDeltas(
      before: _beforeAvgEmotions,
      after: _afterAvgEmotions,
      worsenThreshold: 3,
    );

    final symptomItems = symptomDeltas.map((d) => _toCompareItem(d, true)).toList();
    final emotionItems = emotionDeltas.map((d) => _toCompareItem(d, false)).toList();

    final attentionCount =
        symptomDeltas.where((x) => x.kind == _DeltaKind.newlyAppeared || x.kind == _DeltaKind.worsened).length +
        emotionDeltas.where((x) => x.kind == _DeltaKind.newlyAppeared || x.kind == _DeltaKind.worsened).length;
    final improvedCount =
        symptomDeltas.where((x) => x.kind == _DeltaKind.improved).length +
        emotionDeltas.where((x) => x.kind == _DeltaKind.improved).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResultSummaryCard(
          medName: (_selectedMedData?['name'] ?? _selectedMedId ?? '').toString(),
          windowDays: _windowDays,
          beforeDays: _beforeDaysCount,
          afterDays: _afterDaysCount,
          confidence: _confidenceText(_beforeDaysCount, _afterDaysCount),
          attentionCount: attentionCount,
          improvedCount: improvedCount,
        ),
        const SizedBox(height: 14),
        SymptomCompareResultPanel(
          symptomItems: symptomItems,
          emotionItems: emotionItems,
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

  CompareItem _toCompareItem(_MetricDelta d, bool isPercentage) {
    String fmt(double? v) {
      if (v == null) return '—';
      final base = v.toStringAsFixed(1);
      return isPercentage ? '$base%' : base;
    }

    final diffVal = d.before == null ? null : (d.after - d.before!);
    final diffText = diffVal == null
        ? '新出現'
        : (isPercentage
            ? '${diffVal >= 0 ? '+' : ''}${diffVal.toStringAsFixed(1)}%'
            : '${diffVal >= 0 ? '+' : ''}${diffVal.toStringAsFixed(1)}');

    final type = switch (d.kind) {
      _DeltaKind.improved => CompareChangeType.improved,
      _DeltaKind.worsened => CompareChangeType.worsened,
      _DeltaKind.newlyAppeared => CompareChangeType.newAppeared,
      _DeltaKind.minor => CompareChangeType.mild,
    };

    return CompareItem(
      name: d.name,
      before: fmt(d.before),
      after: fmt(d.after),
      diff: diffText,
      type: type,
    );
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
      final bVal = (b ?? 0);
      final a = after[k] ?? 0;
      if (a <= 0 && bVal <= 0) continue;

      if (b == null || bVal <= 0) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: a >= 60 ? _DeltaKind.newlyAppeared : _DeltaKind.minor,
          severityScore: a,
          isEmotion: false,
        ));
        continue;
      }

      final diff = a - bVal;
      if (diff >= 30) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.worsened,
          severityScore: diff,
          isEmotion: false,
        ));
      } else if (diff <= -30) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.improved,
          severityScore: -diff,
          isEmotion: false,
        ));
      } else if (diff.abs() > 0) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.minor,
          severityScore: diff.abs(),
          isEmotion: false,
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

      if (b == null) {
        if (a < 1) continue;
        out.add(_MetricDelta(
          name: k,
          before: null,
          after: a,
          kind: a >= 6 ? _DeltaKind.newlyAppeared : _DeltaKind.minor,
          severityScore: a,
          positiveEmotion: false,
          isEmotion: true,
        ));
        continue;
      }

      final rawDiff = a - b;
      if (rawDiff >= 3) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.worsened,
          severityScore: rawDiff,
          positiveEmotion: false,
          isEmotion: true,
        ));
      } else if (rawDiff <= -3) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.improved,
          severityScore: -rawDiff,
          positiveEmotion: false,
          isEmotion: true,
        ));
      } else if (rawDiff.abs() >= 1) {
        out.add(_MetricDelta(
          name: k,
          before: b,
          after: a,
          kind: _DeltaKind.minor,
          severityScore: rawDiff.abs(),
          positiveEmotion: false,
          isEmotion: true,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HealingDesignSystem.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HealingDesignSystem.lineColor),
        boxShadow: [
          BoxShadow(
            color: HealingDesignSystem.primaryBlue.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: HealingDesignSystem.deepText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: const TextStyle(
                color: HealingDesignSystem.mutedText,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: HealingDesignSystem.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HealingDesignSystem.lineColor),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: HealingDesignSystem.primaryBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: HealingDesignSystem.mutedText,
                fontSize: 13,
              ),
            ),
          ),
        ],
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
  final bool isEmotion;

  const _MetricDelta({
    required this.name,
    required this.before,
    required this.after,
    required this.kind,
    required this.severityScore,
    this.positiveEmotion = false,
    this.isEmotion = false,
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
// 分析摘要卡
// -----------------------------
class _ResultSummaryCard extends StatelessWidget {
  final String medName;
  final int windowDays;
  final int beforeDays;
  final int afterDays;
  final String confidence;
  final int attentionCount;
  final int improvedCount;

  const _ResultSummaryCard({
    required this.medName,
    required this.windowDays,
    required this.beforeDays,
    required this.afterDays,
    required this.confidence,
    required this.attentionCount,
    required this.improvedCount,
  });

  @override
  Widget build(BuildContext context) {
    final confShort = confidence.split('（').first;
    final confColor = confShort == '高'
        ? HealingDesignSystem.successGreen
        : (confShort == '中' ? HealingDesignSystem.warningOrange : HealingDesignSystem.dangerRed);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HealingDesignSystem.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HealingDesignSystem.lineColor),
        boxShadow: [
          BoxShadow(
            color: HealingDesignSystem.primaryBlue.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: HealingDesignSystem.primaryGradient(),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '分析摘要',
                      style: TextStyle(
                        color: HealingDesignSystem.deepText,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (medName.isNotEmpty)
                      Text(
                        medName,
                        style: const TextStyle(
                          color: HealingDesignSystem.mutedText,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: confColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: confColor.withOpacity(0.30)),
                ),
                child: Text(
                  '信心：$confShort',
                  style: TextStyle(
                    color: confColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InfoPill(
                  label: '前段納入',
                  value: '$beforeDays 天',
                  color: HealingDesignSystem.mutedText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoPill(
                  label: '後段納入',
                  value: '$afterDays 天',
                  color: HealingDesignSystem.primaryBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoPill(
                  label: '比對窗口',
                  value: '$windowDays 天',
                  color: HealingDesignSystem.deepText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CountPill(
                  label: '需關注',
                  count: attentionCount,
                  color: HealingDesignSystem.dangerRed,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CountPill(
                  label: '可能改善',
                  count: improvedCount,
                  color: HealingDesignSystem.successGreen,
                  icon: Icons.trending_down_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _CountPill({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count 項',
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
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
enum CompareChangeType {
  improved,
  worsened,
  newAppeared,
  mild,
}

class CompareItem {
  final String name;
  final String before;
  final String after;
  final String diff;
  final CompareChangeType type;

  const CompareItem({
    required this.name,
    required this.before,
    required this.after,
    required this.diff,
    required this.type,
  });
}

class SymptomCompareResultPanel extends StatelessWidget {
  final List<CompareItem> symptomItems;
  final List<CompareItem> emotionItems;

  const SymptomCompareResultPanel({
    super.key,
    required this.symptomItems,
    required this.emotionItems,
  });

  @override
  Widget build(BuildContext context) {
    final allItems = [...symptomItems, ...emotionItems];

    final warningItems = allItems
        .where((e) =>
            e.type == CompareChangeType.worsened ||
            e.type == CompareChangeType.newAppeared)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (warningItems.isNotEmpty) ...[
          _HighlightCard(items: warningItems),
          const SizedBox(height: 12),
        ],
        if (symptomItems.isNotEmpty) ...[
          _CompareSectionCard(
            title: '症狀比對',
            subtitle: '調藥前後身體症狀出現率的變化（單位 %）',
            items: symptomItems,
          ),
          const SizedBox(height: 12),
        ],
        if (emotionItems.isNotEmpty) ...[
          _CompareSectionCard(
            title: '情緒比對',
            subtitle: '調藥前後情緒指標平均分的變化',
            items: emotionItems,
          ),
          const SizedBox(height: 12),
        ],
        const _DisclaimerCard(),
      ],
    );
  }
}

class _AnalysisSummaryCard extends StatelessWidget {
  final int improved;
  final int worsened;
  final int newAppeared;

  const _AnalysisSummaryCard({
    required this.improved,
    required this.worsened,
    required this.newAppeared,
  });

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.insights_rounded, color: Color(0xFF4F8FA8)),
              SizedBox(width: 8),
              Text(
                '本次分析摘要',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF243B4A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SummaryPill(
                  label: '改善',
                  value: improved.toString(),
                  color: const Color(0xFF2E7D32),
                  icon: Icons.trending_down_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryPill(
                  label: '惡化',
                  value: worsened.toString(),
                  color: const Color(0xFFD05A5A),
                  icon: Icons.trending_up_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryPill(
                  label: '新出現',
                  value: newAppeared.toString(),
                  color: const Color(0xFFF2994A),
                  icon: Icons.auto_awesome_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '提醒：此結果呈現關聯趨勢，不等於因果。請搭配睡眠、壓力、生活事件與回診狀況一起判斷。',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF5F6F7A),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final List<CompareItem> items;

  const _HighlightCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: HealingDesignSystem.dangerRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: HealingDesignSystem.dangerRed,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '需要優先留意',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: HealingDesignSystem.deepText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CompareRow(item: item, compact: true),
              )),
        ],
      ),
    );
  }
}

class _CompareSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<CompareItem> items;

  const _CompareSectionCard({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return _SoftCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          iconColor: HealingDesignSystem.primaryBlue,
          collapsedIconColor: HealingDesignSystem.mutedText,
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: HealingDesignSystem.deepText,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              subtitle,
              style: const TextStyle(
                color: HealingDesignSystem.mutedText,
                fontSize: 12,
              ),
            ),
          ),
          children: [
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CompareRow(item: item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  final CompareItem item;
  final bool compact;

  const _CompareRow({
    required this.item,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(item.type);
    final label = _typeLabel(item.type);
    final icon = _typeIcon(item.type);

    return Container(
      padding: EdgeInsets.all(compact ? 11 : 13),
      decoration: BoxDecoration(
        color: HealingDesignSystem.softBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HealingDesignSystem.lineColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: HealingDesignSystem.deepText,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 3,
                  children: [
                    Text(
                      '前：${item.before}',
                      style: const TextStyle(
                        color: HealingDesignSystem.mutedText,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '後：${item.after}',
                      style: const TextStyle(
                        color: HealingDesignSystem.mutedText,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '差異：${item.diff}',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(CompareChangeType type) {
    switch (type) {
      case CompareChangeType.improved:
        return HealingDesignSystem.successGreen;
      case CompareChangeType.worsened:
        return HealingDesignSystem.dangerRed;
      case CompareChangeType.newAppeared:
        return HealingDesignSystem.warningOrange;
      case CompareChangeType.mild:
        return HealingDesignSystem.mutedText;
    }
  }

  String _typeLabel(CompareChangeType type) {
    switch (type) {
      case CompareChangeType.improved:
        return '改善';
      case CompareChangeType.worsened:
        return '惡化';
      case CompareChangeType.newAppeared:
        return '新出現';
      case CompareChangeType.mild:
        return '輕微';
    }
  }

  IconData _typeIcon(CompareChangeType type) {
    switch (type) {
      case CompareChangeType.improved:
        return Icons.arrow_downward_rounded;
      case CompareChangeType.worsened:
        return Icons.arrow_upward_rounded;
      case CompareChangeType.newAppeared:
        return Icons.auto_awesome_rounded;
      case CompareChangeType.mild:
        return Icons.remove_rounded;
    }
  }
}

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HealingDesignSystem.warningOrange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HealingDesignSystem.warningOrange.withOpacity(0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: HealingDesignSystem.warningOrange,
            size: 18,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '本頁顯示的是關聯趨勢，不代表因果。若症狀明顯惡化，建議記錄後於回診時提供醫師參考。',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: HealingDesignSystem.deepText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  final Widget child;

  const _SoftCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HealingDesignSystem.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HealingDesignSystem.lineColor),
        boxShadow: [
          BoxShadow(
            color: HealingDesignSystem.primaryBlue.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}