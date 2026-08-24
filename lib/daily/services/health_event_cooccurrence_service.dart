import '../../models/health_event.dart';

/// 純計算用共現分析服務。
///
/// 規則：
/// - 「共現」定義為「同一筆 [HealthEvent] 中同時被記錄」。
/// - 不使用同一天或時間窗推論共現。
/// - 同一事件內同一症狀／情緒只計一次。
/// - 不同事件可重複累計。
/// - A+B 與 B+A 視為同一組（依字母順序或固定排序去重）。
/// - 空名稱忽略。
class HealthEventCooccurrenceService {
  HealthEventCooccurrenceService._();

  static HealthEventCooccurrenceService get _instance =>
      HealthEventCooccurrenceService._();

  static HealthEventCooccurrenceService get instance => _instance;

  /// 計算共現分析結果。
  HealthEventCooccurrenceResult analyze(List<HealthEvent> events) {
    final symptomCounts = <String, _ItemStats>{};
    final emotionCounts = <String, _ItemStats>{};
    final symptomPairs = <String, _PairData>{};
    final emotionSymptomPairs = <String, _PairData>{};
    final emotionPairs = <String, _PairData>{};

    for (final event in events) {
      final uniqueSymptoms = _uniqueNonEmpty(event.symptoms.map((s) => s.name));
      final uniqueEmotions = _uniqueNonEmpty(event.emotions.map((e) => e.name));

      for (final s in uniqueSymptoms) {
        final sev = event.symptoms.firstWhere((x) => x.name == s).severity;
        symptomCounts.putIfAbsent(s, () => _ItemStats()).add(value: sev);
      }

      for (final e in uniqueEmotions) {
        final inten = event.emotions.firstWhere((x) => x.name == e).intensity;
        emotionCounts.putIfAbsent(e, () => _ItemStats()).add(value: inten);
      }

      // symptom pairs
      for (var i = 0; i < uniqueSymptoms.length; i++) {
        for (var j = i + 1; j < uniqueSymptoms.length; j++) {
          final key = _pairKey(uniqueSymptoms[i], uniqueSymptoms[j]);
          symptomPairs
              .putIfAbsent(
                  key, () => _PairData(uniqueSymptoms[i], uniqueSymptoms[j]))
              .add(event.id);
        }
      }

      // emotion-symptom pairs
      for (final e in uniqueEmotions) {
        for (final s in uniqueSymptoms) {
          final key = _pairKey(e, s);
          emotionSymptomPairs
              .putIfAbsent(key, () => _PairData(e, s))
              .add(event.id);
        }
      }

      // emotion pairs
      for (var i = 0; i < uniqueEmotions.length; i++) {
        for (var j = i + 1; j < uniqueEmotions.length; j++) {
          final key = _pairKey(uniqueEmotions[i], uniqueEmotions[j]);
          emotionPairs
              .putIfAbsent(
                  key, () => _PairData(uniqueEmotions[i], uniqueEmotions[j]))
              .add(event.id);
        }
      }
    }

    return HealthEventCooccurrenceResult(
      symptomPairs: symptomPairs.values.map(_toPair).toList()
        ..sort((a, b) => b.coOccurrenceCount.compareTo(a.coOccurrenceCount)),
      emotionSymptomPairs: emotionSymptomPairs.values.map(_toPair).toList()
        ..sort((a, b) => b.coOccurrenceCount.compareTo(a.coOccurrenceCount)),
      emotionPairs: emotionPairs.values.map(_toPair).toList()
        ..sort((a, b) => b.coOccurrenceCount.compareTo(a.coOccurrenceCount)),
      symptomEventCounts: symptomCounts.map((k, v) => MapEntry(k, v.count)),
      emotionEventCounts: emotionCounts.map((k, v) => MapEntry(k, v.count)),
      symptomAvgSeverity: Map.fromEntries(
        symptomCounts.entries
            .where((entry) => entry.value.average() != null)
            .map((entry) => MapEntry(entry.key, entry.value.average()!)),
      ),
      emotionAvgIntensity:
          emotionCounts.map((k, v) => MapEntry(k, v.average()!)),
    );
  }

  static List<String> _uniqueNonEmpty(Iterable<String> source) {
    return source.where((s) => s.trim().isNotEmpty).toSet().toList();
  }

  static String _pairKey(String a, String b) {
    // 去重：A+B 與 B+A 視為同一組，依字母順序固定 key
    if (a.compareTo(b) <= 0) return '$a|||$b';
    return '$b|||$a';
  }

  static CooccurrencePair _toPair(_PairData data) {
    return CooccurrencePair(
      itemA: data.a,
      itemB: data.b,
      coOccurrenceCount: data.count,
      eventIds: List<String>.from(data.ids),
    );
  }
}

class HealthEventCooccurrenceResult {
  HealthEventCooccurrenceResult({
    required this.symptomPairs,
    required this.emotionSymptomPairs,
    required this.emotionPairs,
    required this.symptomEventCounts,
    required this.emotionEventCounts,
    required this.symptomAvgSeverity,
    required this.emotionAvgIntensity,
  });

  final List<CooccurrencePair> symptomPairs;
  final List<CooccurrencePair> emotionSymptomPairs;
  final List<CooccurrencePair> emotionPairs;
  final Map<String, int> symptomEventCounts;
  final Map<String, int> emotionEventCounts;
  final Map<String, double> symptomAvgSeverity;
  final Map<String, double> emotionAvgIntensity;
}

class CooccurrencePair {
  CooccurrencePair({
    required this.itemA,
    required this.itemB,
    required this.coOccurrenceCount,
    required this.eventIds,
  });

  final String itemA;
  final String itemB;
  final int coOccurrenceCount;
  final List<String> eventIds;
}

class _PairData {
  _PairData(this.a, this.b);

  final String a;
  final String b;
  final Set<String> ids = <String>{};

  int get count => ids.length;

  void add(String eventId) {
    ids.add(eventId);
  }
}

class _ItemStats {
  _ItemStats();

  int count = 0;
  int scoredCount = 0;
  int valueSum = 0;

  void add({required int? value}) {
    count++;
    if (value == null) return;
    scoredCount++;
    valueSum += value;
  }

  double? average() {
    if (scoredCount == 0) return null;
    return valueSum / scoredCount;
  }
}
