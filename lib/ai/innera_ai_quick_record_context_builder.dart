import '../models/daily_health_aggregate.dart';
import '../models/health_event.dart';
import '../services/daily_health_aggregation_service.dart';
import '../utils/state_change_normalizer.dart';

class InneraAiQuickRecordContextBuilder {
  const InneraAiQuickRecordContextBuilder._();

  static List<Map<String, dynamic>> rawEvents(
    Iterable<HealthEvent> events, {
    required int maxEvents,
    bool symptomOnly = false,
  }) {
    final sorted = events
        .where((event) => !symptomOnly || event.symptoms.isNotEmpty)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(maxEvents).map((event) {
      final local =
          event.timestamp.isUtc ? event.timestamp.toLocal() : event.timestamp;
      final symptomNames = event.symptoms.map((item) => item.name).toList();
      return <String, dynamic>{
        'eventId': event.id,
        'date': _dateKey(local),
        'timestamp': local.toIso8601String(),
        'emotions': event.emotions
            .map((item) => {
                  'name': item.name,
                  'intensity': item.intensity,
                  'scale': 5,
                })
            .toList(),
        'symptoms': event.symptoms
            .map((item) => {
                  'name': item.name,
                  'severity': item.severity,
                })
            .toList(),
        'stateChanges': normalizeStateChanges(event.stateChanges),
        if (event.context?.trim().isNotEmpty == true)
          'context': _limit(event.context!, 120),
        if (event.note?.trim().isNotEmpty == true)
          'note': _limit(event.note!, 160),
        if (symptomNames.length >= 2) 'sameEventSymptoms': symptomNames,
      };
    }).toList();
  }

  static Map<String, dynamic> aggregateReview(
    Iterable<DailyHealthAggregate> source,
  ) {
    final aggregates = source.where((item) => item.recorded).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    const service = DailyHealthAggregationService();
    final symptomStats = service.allSymptomStatistics(aggregates).take(10);

    final states = <String, List<double>>{};
    final stateDays = <String, int>{};
    final emotions = <String, Map<int, List<double>>>{};
    for (final aggregate in aggregates) {
      for (final entry in aggregate.stateDailyValues.entries) {
        final value = entry.value.byScale[5]?.average;
        if (value == null) continue;
        states.putIfAbsent(entry.key, () => []).add(value);
        stateDays[entry.key] = (stateDays[entry.key] ?? 0) + 1;
      }
      for (final entry in aggregate.emotionDailyValues.entries) {
        for (final scaleEntry in entry.value.byScale.entries) {
          final value = scaleEntry.value.average;
          if (value == null) continue;
          emotions
              .putIfAbsent(entry.key, () => {})
              .putIfAbsent(scaleEntry.key, () => [])
              .add(value);
        }
      }
    }

    return {
      'recordedDays': service.recordedDayCount(aggregates),
      'quickRecordEventCount':
          aggregates.fold<int>(0, (sum, item) => sum + item.eventCount),
      'symptoms': symptomStats
          .map((item) => {
                'name': item.name,
                'occurrenceDays': item.occurrenceDays,
                'eventCount': item.eventCount,
                'averageSeverity': item.averageSeverity,
                'maxSeverity': item.maxSeverity,
                'latestSeverity': item.latestSeverity,
              })
          .toList(),
      'states': states.entries
          .map((entry) => {
                'key': entry.key,
                'recordedDays': stateDays[entry.key],
                'dailyAverage': _average(entry.value),
              })
          .toList(),
      'emotions': emotions.entries
          .expand((entry) => entry.value.entries.map((scaleEntry) => {
                'name': entry.key,
                'scale': scaleEntry.key,
                'recordedDays': scaleEntry.value.length,
                'dailyAverage': _average(scaleEntry.value),
              }))
          .take(12)
          .toList(),
    };
  }

  static List<String> legacySymptomsWithoutEventDuplicates(
    Iterable<String> legacySymptoms,
    Iterable<HealthEvent> sameDayEvents,
  ) {
    final eventNames = sameDayEvents
        .expand((event) => event.symptoms)
        .map((symptom) => symptom.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    return legacySymptoms
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && !eventNames.contains(name))
        .toSet()
        .toList();
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static double _average(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  static String _limit(String value, int maxChars) {
    final text = value.trim();
    return text.length <= maxChars ? text : '${text.substring(0, maxChars)}...';
  }
}
