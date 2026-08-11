import '../models/unified_health_data.dart';

enum CoOccurrenceEvidence {
  preciseEvent,
  legacySameDay;

  String get countLabel => switch (this) {
        CoOccurrenceEvidence.preciseEvent => '次精確事件',
        CoOccurrenceEvidence.legacySameDay => '天同日出現',
      };
}

class HealthCoOccurrenceResult {
  const HealthCoOccurrenceResult({
    required this.eventCoOccurrences,
    required this.legacySameDayRecords,
    this.eventSymptomCoOccurrences = const {},
    this.legacySymptomSameDayRecords = const {},
    this.eventSymptomSeverity = const {},
  });

  /// Emotion/symptom pairs observed inside one timestamp-precision event.
  final Map<String, int> eventCoOccurrences;

  /// Emotion/symptom pairs merely recorded on the same legacy calendar day.
  final Map<String, int> legacySameDayRecords;

  /// Symptom pairs observed in the same timestamp-precision HealthEvent.
  final Map<String, int> eventSymptomCoOccurrences;

  /// Symptom pairs present on the same legacy DailyRecord date.
  final Map<String, int> legacySymptomSameDayRecords;

  /// Severity summary from precise co-occurrence events only.
  final Map<String, CoOccurrenceSeveritySummary> eventSymptomSeverity;
}

class CoOccurrenceSeveritySummary {
  const CoOccurrenceSeveritySummary({
    required this.itemAAverageSeverity,
    required this.itemAMaxSeverity,
    required this.itemBAverageSeverity,
    required this.itemBMaxSeverity,
  });

  final double itemAAverageSeverity;
  final int itemAMaxSeverity;
  final double itemBAverageSeverity;
  final int itemBMaxSeverity;
}

class HealthCoOccurrenceService {
  const HealthCoOccurrenceService();

  HealthCoOccurrenceResult calculate(Iterable<UnifiedHealthData> data) {
    final eventPairs = <String, int>{};
    final legacyDayPairs = <String, int>{};
    final eventSymptomPairs = <String, int>{};
    final legacySymptomDayPairs = <String, int>{};
    final eventSeverity = <String, _PairSeverityAccumulator>{};
    final seenLegacyEmotionSymptomDays = <String>{};
    final seenLegacySymptomDays = <String>{};

    for (final item in data) {
      final isPreciseEvent =
          item.source == UnifiedHealthDataSource.healthEvent &&
              item.precision == UnifiedHealthDataPrecision.timestamp &&
              item.timestamp != null;
      final isLegacyDay =
          item.source == UnifiedHealthDataSource.legacyDailyRecord &&
              item.precision == UnifiedHealthDataPrecision.day &&
              item.timestamp == null;
      if (!isPreciseEvent && !isLegacyDay) continue;

      final emotions = item.emotions.map((value) => value.name).toSet();
      final symptomsByName = <String, UnifiedScoredValue>{
        for (final symptom in item.symptoms) symptom.name: symptom,
      };
      final symptoms = symptomsByName.keys.toList()..sort();

      for (final emotion in emotions) {
        for (final symptom in symptoms) {
          final key = '$emotion\u0000$symptom';
          if (isPreciseEvent) {
            eventPairs.update(key, (count) => count + 1, ifAbsent: () => 1);
          } else if (seenLegacyEmotionSymptomDays
              .add('$key\u0000${item.dateKey}')) {
            legacyDayPairs.update(key, (count) => count + 1, ifAbsent: () => 1);
          }
        }
      }

      for (var left = 0; left < symptoms.length; left++) {
        for (var right = left + 1; right < symptoms.length; right++) {
          final key = symptomPairKey(symptoms[left], symptoms[right]);
          if (isPreciseEvent) {
            eventSymptomPairs.update(key, (count) => count + 1,
                ifAbsent: () => 1);
            final leftSeverity = symptomsByName[symptoms[left]]?.value;
            final rightSeverity = symptomsByName[symptoms[right]]?.value;
            if (leftSeverity != null && rightSeverity != null) {
              eventSeverity
                  .putIfAbsent(key, _PairSeverityAccumulator.new)
                  .add(leftSeverity, rightSeverity);
            }
          } else if (seenLegacySymptomDays.add('$key\u0000${item.dateKey}')) {
            legacySymptomDayPairs.update(key, (count) => count + 1,
                ifAbsent: () => 1);
          }
        }
      }
    }

    return HealthCoOccurrenceResult(
      eventCoOccurrences: Map.unmodifiable(eventPairs),
      legacySameDayRecords: Map.unmodifiable(legacyDayPairs),
      eventSymptomCoOccurrences: Map.unmodifiable(eventSymptomPairs),
      legacySymptomSameDayRecords: Map.unmodifiable(legacySymptomDayPairs),
      eventSymptomSeverity: Map.unmodifiable(
        eventSeverity.map((key, value) => MapEntry(key, value.summary)),
      ),
    );
  }

  static String pairKey(String emotion, String symptom) =>
      '$emotion\u0000$symptom';

  static String symptomPairKey(String symptomA, String symptomB) {
    final values = [symptomA, symptomB]..sort();
    return '${values[0]}\u0000${values[1]}';
  }
}

class _PairSeverityAccumulator {
  final List<int> _a = [];
  final List<int> _b = [];

  void add(int a, int b) {
    _a.add(a);
    _b.add(b);
  }

  CoOccurrenceSeveritySummary get summary => CoOccurrenceSeveritySummary(
        itemAAverageSeverity: _a.reduce((a, b) => a + b) / _a.length,
        itemAMaxSeverity: _a.reduce((a, b) => a > b ? a : b),
        itemBAverageSeverity: _b.reduce((a, b) => a + b) / _b.length,
        itemBMaxSeverity: _b.reduce((a, b) => a > b ? a : b),
      );
}
