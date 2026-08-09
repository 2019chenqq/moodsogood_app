import '../models/unified_health_data.dart';

class HealthCoOccurrenceResult {
  const HealthCoOccurrenceResult({
    required this.eventCoOccurrences,
    required this.legacySameDayRecords,
  });

  /// Emotion/symptom pairs observed inside one timestamp-precision event.
  final Map<String, int> eventCoOccurrences;

  /// Emotion/symptom pairs merely recorded on the same legacy calendar day.
  final Map<String, int> legacySameDayRecords;
}

class HealthCoOccurrenceService {
  const HealthCoOccurrenceService();

  HealthCoOccurrenceResult calculate(Iterable<UnifiedHealthData> data) {
    final eventPairs = <String, int>{};
    final legacyDayPairs = <String, int>{};

    for (final item in data) {
      if (item.emotions.isEmpty || item.symptoms.isEmpty) continue;
      final target = item.source == UnifiedHealthDataSource.healthEvent &&
              item.precision == UnifiedHealthDataPrecision.timestamp &&
              item.timestamp != null
          ? eventPairs
          : item.source == UnifiedHealthDataSource.legacyDailyRecord &&
                  item.precision == UnifiedHealthDataPrecision.day &&
                  item.timestamp == null
              ? legacyDayPairs
              : null;
      if (target == null) continue;

      for (final emotion in item.emotions.map((value) => value.name).toSet()) {
        for (final symptom
            in item.symptoms.map((value) => value.name).toSet()) {
          final key = '$emotion\u0000$symptom';
          target.update(key, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    }

    return HealthCoOccurrenceResult(
      eventCoOccurrences: Map.unmodifiable(eventPairs),
      legacySameDayRecords: Map.unmodifiable(legacyDayPairs),
    );
  }

  static String pairKey(String emotion, String symptom) =>
      '$emotion\u0000$symptom';
}
