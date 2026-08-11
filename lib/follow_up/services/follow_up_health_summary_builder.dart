import '../../daily/emotion_trend_calculator.dart';
import '../../models/daily_check_in.dart';
import '../../models/daily_health_aggregate.dart';
import '../../models/daily_record.dart';
import '../../models/health_event.dart';
import '../../models/unified_health_data.dart';
import '../../repositories/unified_health_data_repository.dart';
import '../../services/daily_health_aggregation_service.dart';
import '../../services/health_co_occurrence_service.dart';

class FollowUpHealthSummary {
  const FollowUpHealthSummary({
    required this.aggregates,
    required this.recordedDays,
    required this.symptoms,
    required this.coOccurrences,
    required this.dailySummary,
    required this.representativeEvents,
  });

  final List<DailyHealthAggregate> aggregates;
  final int recordedDays;
  final List<Map<String, dynamic>> symptoms;
  final Map<String, dynamic> coOccurrences;
  final Map<String, dynamic> dailySummary;
  final List<Map<String, dynamic>> representativeEvents;
}

class FollowUpHealthSummaryBuilder {
  const FollowUpHealthSummaryBuilder();

  static const _aggregation = DailyHealthAggregationService();
  static const _coOccurrence = HealthCoOccurrenceService();

  FollowUpHealthSummary build({
    required Iterable<DailyRecord> dailyRecords,
    required Iterable<HealthEvent> healthEvents,
    required Iterable<DailyCheckIn> dailyCheckIns,
    required DateTime start,
    required DateTime endExclusive,
    int maxSymptoms = 5,
    int maxCoOccurrencePairs = 5,
    int maxRepresentativeEvents = 12,
  }) {
    final records = dailyRecords
        .where((item) => _inRange(item.date, start, endExclusive))
        .toList(growable: false);
    final events = healthEvents
        .where((item) => _inRange(item.timestamp, start, endExclusive))
        .toList(growable: false);
    final checkIns = dailyCheckIns
        .where((item) => _inRange(item.date, start, endExclusive))
        .toList(growable: false);

    final aggregates = _aggregation.aggregateRange(
      dailyRecords: records,
      healthEvents: events,
      dailyCheckIns: checkIns,
      start: start,
      endExclusive: endExclusive,
    );
    final recordedDays = _aggregation.recordedDayCount(aggregates);
    final symptoms = _aggregation
        .allSymptomStatistics(aggregates)
        .take(maxSymptoms)
        .map((item) => <String, dynamic>{
              'name': item.name,
              'recordedDays': item.recordedDays,
              'occurrenceDays': item.occurrenceDays,
              'occurrenceRate': _round(item.occurrenceRate),
              'eventCount': item.eventCount,
              if (item.averageSeverity != null)
                'averageSeverity': _round(item.averageSeverity!),
              if (item.maxSeverity != null) 'maxSeverity': item.maxSeverity,
              if (item.latestSeverity != null)
                'latestSeverity': item.latestSeverity,
            })
        .toList(growable: false);

    final evidence = <UnifiedHealthData>[
      ...records.map(UnifiedHealthDataRepository.fromLegacyDailyRecord),
      ...events.map(UnifiedHealthDataRepository.fromHealthEvent),
    ];
    final coOccurrences = _coOccurrence.calculate(evidence);

    return FollowUpHealthSummary(
      aggregates: aggregates,
      recordedDays: recordedDays,
      symptoms: symptoms,
      coOccurrences: {
        'eventLevel': _topPairs(
          coOccurrences.eventSymptomCoOccurrences,
          maxCoOccurrencePairs,
          countKey: 'coOccurrenceEventCount',
          evidenceLabel: 'same_quick_record_event',
        ),
        'legacySameDay': _topPairs(
          coOccurrences.legacySymptomSameDayRecords,
          maxCoOccurrencePairs,
          countKey: 'coOccurrenceDays',
          evidenceLabel: 'legacy_same_day_only',
        ),
      },
      dailySummary: _dailySummary(aggregates),
      representativeEvents:
          _representativeEvents(events, maxRepresentativeEvents),
    );
  }

  static Map<String, dynamic> _dailySummary(
    List<DailyHealthAggregate> aggregates,
  ) {
    final mood = DailyEmotionAggregateCalculator.calculate(
      aggregates,
      DailyHealthAggregationService.overallMoodKey,
      scale: 5,
    );
    final tenPointMood = DailyEmotionAggregateCalculator.calculate(
      aggregates,
      DailyHealthAggregationService.overallMoodKey,
      scale: 10,
    );
    final emotionNames = aggregates
        .expand((day) => day.emotionDailyValues.keys)
        .where((name) => name != DailyHealthAggregationService.overallMoodKey)
        .toSet()
        .toList()
      ..sort();
    return {
      'recordedDays': aggregates.where((item) => item.recorded).length,
      'eventCount':
          aggregates.fold<int>(0, (sum, item) => sum + item.eventCount),
      'mood5Point': mood
          .map((point) => {
                'date': _date(point.date),
                'mainValue': _round(point.mainValue),
                'source': point.source.name,
                if (point.quickRecordRange?.count != null)
                  'quickRecordCount': point.quickRecordRange!.count,
                if (point.quickRecordRange?.shouldDisplay == true)
                  'quickRecordRange': {
                    'min': point.quickRecordRange!.min,
                    'max': point.quickRecordRange!.max,
                  },
              })
          .toList(),
      // Kept separate: no unsupported 10 -> 5 conversion or mixed average.
      'mood10Point': tenPointMood
          .map((point) => {
                'date': _date(point.date),
                'mainValue': _round(point.mainValue),
                'source': point.source.name,
              })
          .toList(),
      'emotion5Point': {
        for (final name in emotionNames)
          name: DailyEmotionAggregateCalculator.calculate(
            aggregates,
            name,
            scale: 5,
          )
              .map((point) => {
                    'date': _date(point.date),
                    'mainValue': _round(point.mainValue),
                    'source': point.source.name,
                    if (point.quickRecordRange?.count != null)
                      'quickRecordCount': point.quickRecordRange!.count,
                    if (point.quickRecordRange?.shouldDisplay == true)
                      'quickRecordRange': {
                        'min': point.quickRecordRange!.min,
                        'max': point.quickRecordRange!.max,
                      },
                  })
              .toList(),
      },
      'stateDailyValues': {
        for (final key in const [
          'energy_change',
          'appetite_change',
          'activity_change',
        ])
          key: aggregates
              .where((day) => day.stateDailyValues[key]?.average != null)
              .map((day) => {
                    'date': day.dateKey,
                    'value': _round(day.stateDailyValues[key]!.average!),
                  })
              .toList(),
      },
    };
  }

  static List<Map<String, dynamic>> _topPairs(
    Map<String, int> values,
    int limit, {
    required String countKey,
    required String evidenceLabel,
  }) {
    final entries = values.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count != 0 ? count : a.key.compareTo(b.key);
      });
    return entries.take(limit).map((entry) {
      final pair = entry.key.split('\u0000');
      return <String, dynamic>{
        'symptoms': pair,
        countKey: entry.value,
        'evidence': evidenceLabel,
      };
    }).toList(growable: false);
  }

  static List<Map<String, dynamic>> _representativeEvents(
    List<HealthEvent> events,
    int limit,
  ) {
    final ranked = List<HealthEvent>.from(events)
      ..sort((a, b) {
        final aScore = a.symptoms.length * 10 +
            a.symptoms.fold<int>(0, (sum, item) => sum + item.severity);
        final bScore = b.symptoms.length * 10 +
            b.symptoms.fold<int>(0, (sum, item) => sum + item.severity);
        final score = bScore.compareTo(aScore);
        return score != 0 ? score : b.timestamp.compareTo(a.timestamp);
      });
    final selected = ranked.take(limit).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return selected
        .map((event) => <String, dynamic>{
              'timestamp': event.timestamp.toLocal().toIso8601String(),
              'symptoms': event.symptoms
                  .map((item) => {'name': item.name, 'severity': item.severity})
                  .toList(),
              'emotions': event.emotions
                  .map((item) =>
                      {'name': item.name, 'intensity': item.intensity})
                  .toList(),
              if (event.context?.trim().isNotEmpty == true)
                'context': _limit(event.context!.trim(), 100),
              if (event.note?.trim().isNotEmpty == true)
                'note': _limit(event.note!.trim(), 100),
            })
        .toList(growable: false);
  }

  static bool _inRange(DateTime value, DateTime start, DateTime endExclusive) =>
      !value.isBefore(start) && value.isBefore(endExclusive);

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _limit(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';

  static double _round(double value) => (value * 100).round() / 100;
}
