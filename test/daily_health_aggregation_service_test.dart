import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/daily_check_in.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/services/daily_health_aggregation_service.dart';

void main() {
  const service = DailyHealthAggregationService();

  test('three same-day events produce one aggregate with eventCount three', () {
    final result = service.aggregateRange(
      healthEvents: [
        _event('a', DateTime(2026, 8, 11, 8)),
        _event('b', DateTime(2026, 8, 11, 12)),
        _event('c', DateTime(2026, 8, 11, 20)),
      ],
    );

    expect(result, hasLength(1));
    expect(result.single.eventCount, 3);
    expect(result.single.recorded, isTrue);
  });

  test('three symptom events remain one occurrence day', () {
    final result = service.aggregateRange(
      healthEvents: [
        _event('a', DateTime(2026, 8, 11, 8), symptomSeverity: 2),
        _event('b', DateTime(2026, 8, 11, 12), symptomSeverity: 4),
        _event('c', DateTime(2026, 8, 11, 20), symptomSeverity: 5),
      ],
    );

    expect(service.occurrenceDaysForSymptom(result, '頭痛'), 1);
    expect(result.single.symptomDailyValues['頭痛']!.eventCount, 3);
  });

  test('symptom severity summary keeps average max and latest', () {
    final summary = service
        .aggregateRange(
          healthEvents: [
            _event('a', DateTime(2026, 8, 11, 8), symptomSeverity: 2),
            _event('b', DateTime(2026, 8, 11, 12), symptomSeverity: 4),
            _event('c', DateTime(2026, 8, 11, 20), symptomSeverity: 5),
          ],
        )
        .single
        .symptomDailyValues['頭痛']!;

    expect(summary.averageSeverity, closeTo(11 / 3, 0.000001));
    expect(summary.maxSeverity, 5);
    expect(summary.latestSeverity, 5);
    expect(summary.present, isTrue);
  });

  test('same emotion keeps every timestamped value and daily summary', () {
    final summary = service
        .aggregateRange(
          healthEvents: [
            _event('a', DateTime(2026, 8, 11, 8), emotionValue: 2),
            _event('b', DateTime(2026, 8, 11, 12), emotionValue: 5),
            _event('c', DateTime(2026, 8, 11, 20), emotionValue: 3),
          ],
        )
        .single
        .emotionDailyValues['焦慮']!;

    expect(summary.count, 3);
    expect(summary.min, 2);
    expect(summary.max, 5);
    expect(summary.average, closeTo(10 / 3, 0.000001));
    expect(summary.latest!.value, 3);
    expect(summary.observations.map((item) => item.timestamp), hasLength(3));
  });

  test('DailyRecord and HealthEvent on one day produce one aggregate', () {
    final result = service.aggregateRange(
      dailyRecords: [
        DailyRecord(id: '2026-08-11', date: DateTime(2026, 8, 11)),
      ],
      healthEvents: [_event('a', DateTime(2026, 8, 11, 8))],
    );

    expect(result, hasLength(1));
    expect(result.single.hasDailyRecord, isTrue);
    expect(result.single.eventCount, 1);
  });

  test('DailyCheckIn-only day is recorded', () {
    final result = service.aggregateRange(
      dailyCheckIns: [
        DailyCheckIn(
          date: DateTime(2026, 8, 11),
          overallMood: 4,
          healthStatus: 3,
          noSpecialEvent: true,
        ),
      ],
    );

    expect(result.single.hasDailyCheckIn, isTrue);
    expect(result.single.recorded, isTrue);
    expect(
      result
          .single
          .emotionDailyValues[DailyHealthAggregationService.overallMoodKey]!
          .observations
          .single
          .source
          .name,
      'dailyCheckIn',
    );
  });

  test('multiple events over two days count as two recorded days', () {
    final result = service.aggregateRange(
      healthEvents: [
        _event('a', DateTime(2026, 8, 11, 8)),
        _event('b', DateTime(2026, 8, 11, 12)),
        _event('c', DateTime(2026, 8, 12, 8)),
        _event('d', DateTime(2026, 8, 12, 12)),
      ],
    );

    expect(result, hasLength(2));
    expect(service.recordedDayCount(result), 2);
  });

  test('23:59 and next-day midnight use different local date keys', () {
    final result = service.aggregateRange(
      healthEvents: [
        _event('a', DateTime(2026, 8, 11, 23, 59)),
        _event('b', DateTime(2026, 8, 12)),
      ],
    );

    expect(result.map((item) => item.dateKey), [
      '2026-08-11',
      '2026-08-12',
    ]);
  });

  test('legacy state key is normalized before aggregation', () {
    final aggregate = service.aggregateDay(
      date: DateTime(2026, 8, 11),
      healthEvents: [
        HealthEvent(
          id: 'a',
          timestamp: DateTime(2026, 8, 11, 9),
          stateChanges: const {'energy': 2},
        ),
      ],
    );

    expect(aggregate.stateDailyValues.keys, ['energy_change']);
    expect(aggregate.stateDailyValues['energy_change']!.average, 2);
  });

  test('mixed mood scales retain source and scale without averaging', () {
    final aggregate = service.aggregateDay(
      date: DateTime(2026, 8, 11),
      dailyRecords: [
        DailyRecord(
          id: '2026-08-11',
          date: DateTime(2026, 8, 11),
          emotions: const [Emotion(name: '焦慮', value: 8)],
          moodScale: 10,
        ),
      ],
      healthEvents: [
        _event('a', DateTime(2026, 8, 11, 9), emotionValue: 4),
      ],
    );
    final summary = aggregate.emotionDailyValues['焦慮']!;

    expect(summary.count, 2);
    expect(summary.scales, {5, 10});
    expect(summary.average, isNull);
    expect(summary.min, isNull);
    expect(summary.max, isNull);
    expect(summary.byScale[10]!.average, 8);
    expect(summary.byScale[5]!.average, 4);
    expect(summary.observations.first.source.name, 'dailyRecord');
    expect(summary.observations.first.scale, 10);
  });
}

HealthEvent _event(
  String id,
  DateTime timestamp, {
  int? symptomSeverity,
  int? emotionValue,
}) {
  return HealthEvent(
    id: id,
    timestamp: timestamp,
    symptoms: symptomSeverity == null
        ? const []
        : [HealthEventSymptom(name: '頭痛', severity: symptomSeverity)],
    emotions: emotionValue == null
        ? const []
        : [HealthEventEmotion(name: '焦慮', intensity: emotionValue)],
  );
}
