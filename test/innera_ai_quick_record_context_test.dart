import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_quick_record_context_builder.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/services/daily_health_aggregation_service.dart';

void main() {
  const aggregation = DailyHealthAggregationService();

  test('three today QuickRecords retain all timestamps in AI context', () {
    final context = InneraAiQuickRecordContextBuilder.rawEvents(
      _events(3),
      maxEvents: 12,
    );

    expect(context, hasLength(3));
    expect(context.every((item) => item['timestamp'] != null), isTrue);
  });

  test('QuickRecord-only data remains available without DailyRecord', () {
    final context = InneraAiQuickRecordContextBuilder.rawEvents(
      [
        _event('only', DateTime(2026, 8, 11, 9), symptoms: {'疲倦': 3})
      ],
      maxEvents: 12,
    );

    expect(context.single['symptoms'], isNotEmpty);
  });

  test('legacy and event duplicate symptom does not create wrong day count',
      () {
    final aggregates = aggregation.aggregateRange(
      dailyRecords: [
        _legacy(['心悸'])
      ],
      healthEvents: [
        _event('event', DateTime(2026, 8, 11, 9), symptoms: {'心悸': 3}),
      ],
    );
    final review =
        InneraAiQuickRecordContextBuilder.aggregateReview(aggregates);
    final symptom = (review['symptoms'] as List).single as Map;

    expect(symptom['occurrenceDays'], 1);
    expect(symptom['eventCount'], 1);
  });

  test('five same-day events still produce one recorded day', () {
    final review = InneraAiQuickRecordContextBuilder.aggregateReview(
      aggregation.aggregateRange(healthEvents: _events(5)),
    );

    expect(review['recordedDays'], 1);
    expect(review['quickRecordEventCount'], 5);
  });

  test('different timestamps never receive same-event co-occurrence marker',
      () {
    final context = InneraAiQuickRecordContextBuilder.rawEvents(
      [
        _event('a', DateTime(2026, 8, 11, 9), symptoms: {'心悸': 3}),
        _event('b', DateTime(2026, 8, 11, 18), symptoms: {'噁心': 2}),
      ],
      maxEvents: 12,
    );

    expect(context.every((item) => !item.containsKey('sameEventSymptoms')),
        isTrue);
  });

  test('symptoms in one HealthEvent expose event-level co-occurrence', () {
    final context = InneraAiQuickRecordContextBuilder.rawEvents(
      [
        _event(
          'a',
          DateTime(2026, 8, 11, 9),
          symptoms: {'心悸': 3, '噁心': 2},
        ),
      ],
      maxEvents: 12,
    );

    expect(context.single['sameEventSymptoms'], containsAll(['心悸', '噁心']));
  });

  test('review keeps occurrenceDays and eventCount separate', () {
    final review = InneraAiQuickRecordContextBuilder.aggregateReview(
      aggregation.aggregateRange(healthEvents: [
        _event('a', DateTime(2026, 8, 11, 9), symptoms: {'疲倦': 2}),
        _event('b', DateTime(2026, 8, 11, 12), symptoms: {'疲倦': 4}),
        _event('c', DateTime(2026, 8, 12, 9), symptoms: {'疲倦': 5}),
      ]),
    );
    final symptom = (review['symptoms'] as List).single as Map;

    expect(symptom['occurrenceDays'], 2);
    expect(symptom['eventCount'], 3);
  });

  test('legacy state key is exposed only as canonical state key', () {
    final review = InneraAiQuickRecordContextBuilder.aggregateReview(
      aggregation.aggregateRange(healthEvents: [
        HealthEvent(
          id: 'a',
          timestamp: DateTime(2026, 8, 11, 9),
          stateChanges: const {'energy': 2},
        ),
      ]),
    );
    final serialized = review.toString();

    expect(serialized, contains('energy_change'));
    expect(RegExp(r'(?<!_)energy[:}]').hasMatch(serialized), isFalse);
  });

  test('large event history is capped to recent raw events', () {
    final events = List.generate(
      100,
      (index) => _event(
        '$index',
        DateTime(2026, 8, 1).add(Duration(hours: index)),
        symptoms: {'疲倦': 3},
      ),
    );
    final context = InneraAiQuickRecordContextBuilder.rawEvents(
      events,
      maxEvents: 12,
    );

    expect(context, hasLength(12));
    expect(context.first['eventId'], '99');
  });

  test('QuickRecord context contains no recordDraft write instruction', () {
    final context = InneraAiQuickRecordContextBuilder.rawEvents(
      _events(1),
      maxEvents: 12,
    );
    final serialized = context.toString();

    expect(serialized, isNot(contains('recordDraft')));
    expect(serialized, isNot(contains('confirm')));
  });

  test('DailyRecord-only legacy account still produces aggregate review', () {
    final review = InneraAiQuickRecordContextBuilder.aggregateReview(
      aggregation.aggregateRange(dailyRecords: [
        _legacy(['疲倦'])
      ]),
    );

    expect(review['recordedDays'], 1);
    expect(review['quickRecordEventCount'], 0);
  });

  test('empty HealthEvent input is safe', () {
    expect(
      InneraAiQuickRecordContextBuilder.rawEvents(const [], maxEvents: 12),
      isEmpty,
    );
    final review = InneraAiQuickRecordContextBuilder.aggregateReview(const []);
    expect(review['recordedDays'], 0);
  });

  test('old 10-point DailyRecord remains a separate scale in review', () {
    final review = InneraAiQuickRecordContextBuilder.aggregateReview(
      aggregation.aggregateRange(dailyRecords: [
        DailyRecord(
          id: 'legacy-10',
          date: DateTime(2026, 8, 11),
          moodScale: 10,
          emotions: const [Emotion(name: '焦慮', value: 8)],
        ),
      ]),
    );
    final emotion = (review['emotions'] as List).single as Map;

    expect(emotion['scale'], 10);
    expect(emotion['dailyAverage'], 8);
  });
}

DailyRecord _legacy(List<String> symptoms) => DailyRecord(
      id: 'legacy',
      date: DateTime(2026, 8, 11),
      symptoms: symptoms,
    );

List<HealthEvent> _events(int count) => List.generate(
      count,
      (index) => _event(
        '$index',
        DateTime(2026, 8, 11, 8 + index),
        symptoms: {'疲倦': 3},
      ),
    );

HealthEvent _event(
  String id,
  DateTime timestamp, {
  Map<String, int> symptoms = const {},
}) =>
    HealthEvent(
      id: id,
      timestamp: timestamp,
      symptoms: symptoms.entries
          .map((entry) =>
              HealthEventSymptom(name: entry.key, severity: entry.value))
          .toList(),
      emotions: const [HealthEventEmotion(name: '焦慮', intensity: 3)],
      context: '工作後',
      note: '測試紀錄',
    );
