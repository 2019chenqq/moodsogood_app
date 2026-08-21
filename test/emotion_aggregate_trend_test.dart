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

  test('QuickRecord even-count median is fallback without day-level value', () {
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

  test('QuickRecord skewed odd-count median is used instead of average', () {
    final aggregate = aggregation.aggregateDay(
      date: DateTime(2026, 8, 11),
      healthEvents: _events([2, 2, 2, 2, 5], name: 'calm'),
    );
    final summary = aggregate.emotionDailyValues['calm']!;
    final point = DailyEmotionAggregateCalculator.calculateForEmotion(
      aggregate,
      'calm',
    )!;

    expect(summary.median, 2);
    expect(summary.average, 2.6);
    expect(point.mainValue, 2);
    expect(point.quickRecordRange?.min, 2);
    expect(point.quickRecordRange?.max, 5);
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
    expect(newPoint.source, DailyEmotionMainSource.quickRecordFallback);
  });

  test('5-point and legacy 10-point records stay in separate chart inputs', () {
    final records = [_record(4), _record(8, scale: 10)];

    expect(
      emotionTrendRecordsForScale(records, 5).map((record) => record.moodScale),
      [5],
    );
    expect(
      emotionTrendRecordsForScale(records, 10)
          .map((record) => record.moodScale),
      [10],
    );
  });

  test('new mode options exclude legacy DailyRecord emotions at every scale',
      () {
    final aggregates = aggregation.aggregateRange(
      dailyRecords: [
        DailyRecord(
          id: 'legacy-5',
          date: DateTime(2026, 8, 11),
          emotions: const [
            Emotion(name: '幸福', value: 4),
            Emotion(name: '感恩', value: 5),
          ],
          moodScale: 5,
        ),
        DailyRecord(
          id: 'legacy-10',
          date: DateTime(2026, 8, 12),
          emotions: const [Emotion(name: '憤怒', value: 8)],
          moodScale: 10,
        ),
      ],
      dailyCheckIns: [
        DailyCheckIn(
          date: DateTime(2026, 8, 11),
          overallMood: 3,
          healthStatus: 3,
          noSpecialEvent: false,
        ),
      ],
      healthEvents: _events([2], name: '焦慮'),
    );

    expect(newModeEmotionNames(aggregates), ['焦慮']);
    expect(newModeEmotionNames(aggregates), isNot(contains('幸福')));
    expect(newModeEmotionNames(aggregates), isNot(contains('感恩')));
    expect(newModeEmotionNames(aggregates), isNot(contains('憤怒')));
    expect(
      legacyEmotionNames(aggregates.expand((day) => day.dailyRecords)),
      containsAll(['幸福', '感恩', '憤怒']),
    );
  });

  test('new individual chart excludes same-name legacy DailyRecord value', () {
    final aggregate = aggregation.aggregateDay(
      date: DateTime(2026, 8, 11),
      dailyRecords: [_record(5)],
      healthEvents: _events([1, 3], name: 'calm'),
    );
    final point = DailyEmotionAggregateCalculator.calculateNewModeForEmotion(
      aggregate,
      'calm',
    )!;

    expect(point.mainValue, 2);
    expect(point.source, DailyEmotionMainSource.quickRecordFallback);
    expect(point.quickRecordRange?.min, 1);
    expect(point.quickRecordRange?.max, 3);
  });

  test('legacy chart visibility requires actual 10-point DailyRecord data', () {
    expect(
        hasLegacyTenPointEmotionData([_record(8, scale: 10)], 'calm'), isTrue);
    expect(hasLegacyTenPointEmotionData([_record(4)], 'calm'), isFalse);
    expect(
      hasLegacyTenPointEmotionData(
        [
          DailyRecord(
            id: 'empty-legacy',
            date: DateTime(2026, 8, 11),
            emotions: const [Emotion(name: 'calm', value: null)],
            moodScale: 10,
          ),
        ],
        'calm',
      ),
      isFalse,
    );
  });

  test('legacy balance trend uses only 10-point DailyRecord values', () {
    final legacyRecords = emotionTrendRecordsForScale(
      [
        DailyRecord(
          id: 'new',
          date: DateTime(2026, 8, 11),
          emotions: const [Emotion(name: '快樂', value: 4)],
          moodScale: 5,
        ),
        DailyRecord(
          id: 'legacy',
          date: DateTime(2026, 8, 11),
          emotions: const [Emotion(name: '快樂', value: 8)],
          moodScale: 10,
        ),
      ],
      10,
    );
    final legacyPoints = EmotionTrendCalculator.calculate(legacyRecords);
    final newPoints = EmotionTrendCalculator.calculateAggregates(
      aggregation.aggregateRange(
        dailyRecords: legacyRecords,
        healthEvents: _events([1, 5], name: '快樂'),
      ),
      scale: 5,
    );

    expect(legacyPoints, hasLength(1));
    expect(legacyPoints.single.positiveAverage, 8);
    expect(newPoints, hasLength(1));
    expect(newPoints.single.positiveAverage, 3);
  });

  test('balance trend uses per-emotion daily medians for QuickRecords', () {
    final points = EmotionTrendCalculator.calculateAggregates(
      aggregation.aggregateRange(
        healthEvents: [
          ..._events([2, 2, 2, 2, 5], name: '快樂'),
          ..._events([4], name: '焦慮'),
        ],
      ),
      scale: 5,
    );

    expect(points, hasLength(1));
    expect(points.single.positiveAverage, 2);
    expect(points.single.negativeAverage, 4);
    expect(points.single.emotionBalance, -2);
  });

  test('balance MA7 gives each day equal weight regardless of event count', () {
    final aggregates = aggregation.aggregateRange(
      healthEvents: [
        ..._events(List.filled(10, 5), name: '快樂'),
        HealthEvent(
          id: 'next-day-positive',
          timestamp: DateTime(2026, 8, 12, 9),
          emotions: const [HealthEventEmotion(name: '快樂', intensity: 1)],
        ),
      ],
    );
    final dailyEmotionPoints = DailyEmotionAggregateCalculator.calculate(
      aggregates,
      '快樂',
    );

    expect(dailyEmotionPoints, hasLength(2));
    expect(
      DailyEmotionAggregateCalculator.movingAverage(
        dailyEmotionPoints,
        DateTime(2026, 8, 12),
      ),
      3,
    );
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
