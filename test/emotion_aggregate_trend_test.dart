import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/emotion_trend_calculator.dart';
import 'package:moodsogood_app/models/daily_check_in.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/services/daily_health_aggregation_service.dart';

void main() {
  const aggregation = DailyHealthAggregationService();
  const moodKey = DailyHealthAggregationService.overallMoodKey;

  test('DailyCheckIn wins while QuickRecord range remains available', () {
    final aggregate = aggregation.aggregateDay(
      date: DateTime(2026, 8, 11),
      dailyCheckIns: [
        DailyCheckIn(
          date: DateTime(2026, 8, 11),
          overallMood: 3,
          healthStatus: 3,
          noSpecialEvent: false,
        ),
      ],
      healthEvents: _events([2, 4, 5]),
    );
    final point = DailyEmotionAggregateCalculator.calculateForEmotion(
      aggregate,
      moodKey,
    )!;

    expect(point.mainValue, 3);
    expect(point.source, DailyEmotionMainSource.dailyCheckIn);
    expect(point.quickRecordRange?.min, 2);
    expect(point.quickRecordRange?.max, 5);
    expect(point.quickRecordRange?.count, 3);
  });

  test('DailyRecord wins over QuickRecord for the same named emotion', () {
    final aggregate = aggregation.aggregateDay(
      date: DateTime(2026, 8, 11),
      dailyRecords: [_record(4)],
      healthEvents: _events([1, 3], name: 'calm'),
    );
    final point = DailyEmotionAggregateCalculator.calculateForEmotion(
      aggregate,
      'calm',
    )!;

    expect(point.mainValue, 4);
    expect(point.source, DailyEmotionMainSource.dailyRecord);
    expect(point.quickRecordRange?.min, 1);
    expect(point.quickRecordRange?.max, 3);
  });

  test('QuickRecord average is fallback when no day-level value exists', () {
    final aggregate = aggregation.aggregateDay(
      date: DateTime(2026, 8, 11),
      healthEvents: _events([2, 4], name: 'calm'),
    );
    final point = DailyEmotionAggregateCalculator.calculateForEmotion(
      aggregate,
      'calm',
    )!;

    expect(point.mainValue, 3);
    expect(point.source, DailyEmotionMainSource.quickRecordFallback);
  });

  test('five same-day events still produce one trend point', () {
    final aggregates = aggregation.aggregateRange(
      healthEvents: _events([1, 2, 3, 4, 5], name: 'calm'),
    );
    final points = DailyEmotionAggregateCalculator.calculate(
      aggregates,
      'calm',
    );

    expect(points, hasLength(1));
    expect(points.single.quickRecordRange?.count, 5);
  });

  test('long-term average gives each day equal weight', () {
    final events = <HealthEvent>[
      ..._events(List.filled(10, 5), name: 'calm'),
      HealthEvent(
        id: 'next-day',
        timestamp: DateTime(2026, 8, 12, 9),
        emotions: const [HealthEventEmotion(name: 'calm', intensity: 1)],
      ),
    ];
    final points = DailyEmotionAggregateCalculator.calculate(
      aggregation.aggregateRange(healthEvents: events),
      'calm',
    );

    expect(points, hasLength(2));
    expect(DailyEmotionAggregateCalculator.averageMainValue(points), 3);
  });

  test('single QuickRecord does not request a visible min-max range', () {
    final point = DailyEmotionAggregateCalculator.calculateForEmotion(
      aggregation.aggregateDay(
        date: DateTime(2026, 8, 11),
        healthEvents: _events([4], name: 'calm'),
      ),
      'calm',
    )!;

    expect(point.quickRecordRange?.count, 1);
    expect(point.quickRecordRange?.shouldDisplay, isFalse);
  });

  test('10-point DailyRecord is isolated from 5-point QuickRecord', () {
    final aggregate = aggregation.aggregateDay(
      date: DateTime(2026, 8, 11),
      dailyRecords: [_record(8, scale: 10)],
      healthEvents: _events([2, 4], name: 'calm'),
    );
    final oldPoint = DailyEmotionAggregateCalculator.calculateForEmotion(
      aggregate,
      'calm',
      scale: 10,
    )!;
    final newPoint = DailyEmotionAggregateCalculator.calculateForEmotion(
      aggregate,
      'calm',
      scale: 5,
    )!;

    expect(oldPoint.mainValue, 8);
    expect(oldPoint.quickRecordRange, isNull);
    expect(newPoint.mainValue, 3);
  });

  test('7 30 90 and all ranges retain one point per included date', () {
    final now = DateTime(2026, 8, 11);
    final events = List.generate(
      100,
      (index) => HealthEvent(
        id: '$index',
        timestamp: now.subtract(Duration(days: index)),
        emotions: const [HealthEventEmotion(name: 'calm', intensity: 3)],
      ),
    );
    int countFor(int? days) {
      final start =
          days == null ? null : now.subtract(Duration(days: days - 1));
      final aggregates = aggregation.aggregateRange(
        healthEvents: events,
        start: start,
        endExclusive: now.add(const Duration(days: 1)),
      );
      return DailyEmotionAggregateCalculator.calculate(aggregates, 'calm')
          .length;
    }

    expect(countFor(7), 7);
    expect(countFor(30), 30);
    expect(countFor(90), 90);
    expect(countFor(null), 100);
  });

  test('MA7 consumes daily representative values', () {
    final points = DailyEmotionAggregateCalculator.calculate(
      aggregation.aggregateRange(
        healthEvents: [
          ..._events(List.filled(10, 5), name: 'calm'),
          HealthEvent(
            id: 'next-day',
            timestamp: DateTime(2026, 8, 12, 9),
            emotions: const [HealthEventEmotion(name: 'calm', intensity: 1)],
          ),
        ],
      ),
      'calm',
    );

    expect(
      DailyEmotionAggregateCalculator.movingAverage(
        points,
        DateTime(2026, 8, 12),
      ),
      3,
    );
  });

  test('without QuickRecord DailyRecord result stays unchanged', () {
    final record = _record(4);
    final aggregatePoint = DailyEmotionAggregateCalculator.calculateForEmotion(
      aggregation.aggregateDay(
        date: record.date,
        dailyRecords: [record],
      ),
      'calm',
    )!;

    expect(aggregatePoint.mainValue, record.emotions.single.value);
    expect(aggregatePoint.source, DailyEmotionMainSource.dailyRecord);
    expect(aggregatePoint.quickRecordRange, isNull);
  });
}

DailyRecord _record(int value, {int scale = 5}) => DailyRecord(
      id: 'record-$scale',
      date: DateTime(2026, 8, 11),
      emotions: [Emotion(name: 'calm', value: value)],
      moodScale: scale,
    );

List<HealthEvent> _events(List<int> values, {String name = 'overall_mood'}) =>
    List.generate(
      values.length,
      (index) => HealthEvent(
        id: 'event-$index',
        timestamp: DateTime(2026, 8, 11, 8 + index),
        emotions: [HealthEventEmotion(name: name, intensity: values[index])],
      ),
    );
