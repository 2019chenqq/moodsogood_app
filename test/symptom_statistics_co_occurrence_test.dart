import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/repositories/unified_health_data_repository.dart';
import 'package:moodsogood_app/services/daily_health_aggregation_service.dart';
import 'package:moodsogood_app/services/health_co_occurrence_service.dart';

void main() {
  const aggregation = DailyHealthAggregationService();
  const coOccurrence = HealthCoOccurrenceService();

  test('three same-day symptom events are one day and three events', () {
    final aggregates = aggregation.aggregateRange(
      healthEvents: _symptomEvents([2, 4, 5]),
    );
    final stats = aggregation.symptomStatistics(aggregates, '心悸');

    expect(stats.occurrenceDays, 1);
    expect(stats.eventCount, 3);
  });

  test('symptom on two dates has two occurrence days', () {
    final aggregates = aggregation.aggregateRange(
      healthEvents: [
        _event('a', DateTime(2026, 8, 11, 9), {'心悸': 2}),
        _event('b', DateTime(2026, 8, 12, 9), {'心悸': 4}),
      ],
    );

    expect(aggregation.symptomStatistics(aggregates, '心悸').occurrenceDays, 2);
  });

  test('severity average max and latest use HealthEvent values', () {
    final stats = aggregation.symptomStatistics(
      aggregation.aggregateRange(healthEvents: _symptomEvents([2, 4, 5])),
      '心悸',
    );

    expect(stats.averageSeverity, closeTo(11 / 3, 0.000001));
    expect(stats.maxSeverity, 5);
    expect(stats.latestSeverity, 5);
  });

  test('DailyRecord and event on same day do not duplicate occurrence day', () {
    final stats = aggregation.symptomStatistics(
      aggregation.aggregateRange(
        dailyRecords: [
          _legacy(['心悸'])
        ],
        healthEvents: [
          _event('a', DateTime(2026, 8, 11, 9), {'心悸': 3})
        ],
      ),
      '心悸',
    );

    expect(stats.occurrenceDays, 1);
    expect(stats.eventCount, 1);
  });

  test('legacy symptoms never contribute a fabricated severity', () {
    final legacyOnly = aggregation.symptomStatistics(
      aggregation.aggregateRange(dailyRecords: [
        _legacy(['心悸'])
      ]),
      '心悸',
    );
    final mixed = aggregation.symptomStatistics(
      aggregation.aggregateRange(
        dailyRecords: [
          _legacy(['心悸'])
        ],
        healthEvents: [
          _event('a', DateTime(2026, 8, 11, 9), {'心悸': 4})
        ],
      ),
      '心悸',
    );

    expect(legacyOnly.averageSeverity, isNull);
    expect(mixed.averageSeverity, 4);
  });

  test('two symptoms in one HealthEvent are one precise co-occurrence', () {
    final result = coOccurrence.calculate([
      UnifiedHealthDataRepository.fromHealthEvent(
        _event('a', DateTime(2026, 8, 11, 9), {'心悸': 2, '噁心': 4}),
      ),
    ]);
    final key = HealthCoOccurrenceService.symptomPairKey('心悸', '噁心');

    expect(result.eventSymptomCoOccurrences[key], 1);
    expect(result.legacySymptomSameDayRecords[key], isNull);
    expect(result.eventSymptomSeverity[key]?.itemAAverageSeverity, isNotNull);
    expect(result.eventSymptomSeverity[key]?.itemBMaxSeverity, isNotNull);
  });

  test('legacy symptom pair is counted only as unique same-day evidence', () {
    final legacy = UnifiedHealthDataRepository.fromLegacyDailyRecord(
      _legacy(['心悸', '噁心']),
    );
    final result = coOccurrence.calculate([legacy, legacy]);
    final key = HealthCoOccurrenceService.symptomPairKey('心悸', '噁心');

    expect(result.legacySymptomSameDayRecords[key], 1);
    expect(result.eventSymptomCoOccurrences[key], isNull);
  });

  test('precise event label is a count and is never labelled as days', () {
    expect(CoOccurrenceEvidence.preciseEvent.countLabel, contains('次'));
    expect(CoOccurrenceEvidence.preciseEvent.countLabel, isNot(contains('天')));
  });

  test('legacy label is days and never claims precise event count', () {
    expect(CoOccurrenceEvidence.legacySameDay.countLabel, contains('天'));
    expect(
      CoOccurrenceEvidence.legacySameDay.countLabel,
      isNot(contains('精確事件')),
    );
  });

  test('recordedDays remains unique when one date has many events', () {
    final stats = aggregation.symptomStatistics(
      aggregation.aggregateRange(
        healthEvents: _symptomEvents([1, 2, 3, 4, 5]),
      ),
      '心悸',
    );

    expect(stats.recordedDays, 1);
    expect(stats.occurrenceRate, 1);
    expect(stats.eventCount, 5);
  });
}

DailyRecord _legacy(List<String> symptoms) => DailyRecord(
      id: 'legacy',
      date: DateTime(2026, 8, 11),
      symptoms: symptoms,
    );

List<HealthEvent> _symptomEvents(List<int> severities) => List.generate(
      severities.length,
      (index) => _event(
        '$index',
        DateTime(2026, 8, 11, 8 + index),
        {'心悸': severities[index]},
      ),
    );

HealthEvent _event(
  String id,
  DateTime timestamp,
  Map<String, int> symptoms,
) =>
    HealthEvent(
      id: id,
      timestamp: timestamp,
      symptoms: symptoms.entries
          .map((entry) =>
              HealthEventSymptom(name: entry.key, severity: entry.value))
          .toList(),
    );
