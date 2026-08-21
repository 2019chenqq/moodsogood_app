import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/unified_body_measurement_repository.dart';
import 'package:moodsogood_app/daily/unified_sleep_repository.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_ai_data_aggregator.dart';
import 'package:moodsogood_app/models/body_measurement_record.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/models/sleep_record.dart';
import 'package:moodsogood_app/sleep_insights/models/sleep_insight_models.dart';
import 'package:moodsogood_app/sleep_insights/services/sleep_analysis_service.dart';

void main() {
  test('follow-up sleep uses the same normalized records and values as insight',
      () {
    final legacyRecords = [
      _daily(DateTime(2026, 8, 1), hours: 8, quality: 2),
      _daily(DateTime(2026, 8, 2), hours: 4, quality: 1),
    ];
    final unified = UnifiedSleepRepository.resolve(
      legacy: legacyRecords.map(
        (record) => SleepRecord.fromSleepData(record.date, record.sleep),
      ),
      current: [
        _sleep(DateTime(2026, 8, 2), hours: 7, quality: 4),
        _sleep(DateTime(2026, 8, 3), hours: 6, quality: 5),
      ],
    );
    final input = _build(records: legacyRecords, sleepRecords: unified);
    final insight = const SleepAnalysisService().analyze(
      records: UnifiedSleepRepository.overlayForInsights(
        dailyRecords: legacyRecords,
        sleepRecords: unified,
      ),
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 3),
      period: SleepInsightPeriod.all,
    );
    final duration = input.sleep['durationHours'] as Map<String, dynamic>;

    expect(unified, hasLength(3));
    expect(duration['recordedDays'], insight.summary.validNightDays);
    expect(duration['average'], insight.summary.averageNightMinutes! / 60);
    expect(duration['minimum'], insight.summary.shortestNightMinutes! / 60);
    expect(duration['maximum'], insight.summary.longestNightMinutes! / 60);
    expect(
      (duration['dailyTrend'] as List).map((item) => item['value']),
      [8, 7, 6],
    );
    expect((input.sleep['quality'] as Map)['recordedDays'], 3);
    expect((input.sleep['quality'] as Map)['average'], 3.67);
  });

  test('body trend uses latest current measurement per day and correct sign',
      () {
    final records = [
      DailyRecord(
        id: 'legacy',
        date: DateTime(2026, 8, 1),
        bodyMeasurement: const BodyMeasurement(weightKg: 80),
      ),
    ];
    final measurements = [
      UnifiedBodyMeasurementRepository.fromLegacy(records.single),
      UnifiedBodyMeasurementRepository.fromCurrent(
        _body('morning', DateTime(2026, 8, 1, 8), 76),
      ),
      UnifiedBodyMeasurementRepository.fromCurrent(
        _body('evening', DateTime(2026, 8, 1, 20), 75.8),
      ),
      UnifiedBodyMeasurementRepository.fromCurrent(
        _body('latest', DateTime(2026, 8, 3, 8), 75.2),
      ),
    ];
    final input = _build(
      records: records,
      bodyMeasurementRecords: measurements,
    );
    final weight = input.bodyMeasurements.single;

    expect(weight['startValue'], 75.8);
    expect(weight['latestValue'], 75.2);
    expect(weight['change'], -0.6);
    expect(weight['startDate'], '2026-08-01');
    expect(weight['latestDate'], '2026-08-03');
  });

  test(
      'HealthEvent timestamp, emotion intensity and symptom severity enter input',
      () {
    final timestamp = DateTime(2026, 8, 2, 14, 35);
    final input = _build(
      healthEvents: [
        HealthEvent(
          id: 'event',
          timestamp: timestamp,
          emotions: const [HealthEventEmotion(name: '焦慮', intensity: 4)],
          symptoms: const [HealthEventSymptom(name: '心悸', severity: 3)],
        ),
      ],
    );
    final event = input.representativeHealthEvents.single;

    expect(event['timestamp'], timestamp.toLocal().toIso8601String());
    expect((event['emotions'] as List).single, {
      'name': '焦慮',
      'intensity': 4,
    });
    expect((event['symptoms'] as List).single, {
      'name': '心悸',
      'severity': 3,
    });
  });
}

dynamic _build({
  List<DailyRecord> records = const [],
  List<UnifiedSleepRecord>? sleepRecords,
  List<UnifiedBodyMeasurement>? bodyMeasurementRecords,
  List<HealthEvent> healthEvents = const [],
}) =>
    FollowUpAiDataAggregator().buildFromData(
      records: records,
      medications: const [],
      adjustments: const [],
      healthEvents: healthEvents,
      sleepRecords: sleepRecords,
      bodyMeasurementRecords: bodyMeasurementRecords,
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
      now: DateTime(2026, 8, 3),
    );

DailyRecord _daily(DateTime date, {required int hours, required int quality}) =>
    DailyRecord(
      id: date.toIso8601String(),
      date: date,
      sleep: SleepData(
        estimatedSleepTime: const TimeOfDay(hour: 23, minute: 0),
        finalWakeTime: TimeOfDay(hour: (23 + hours) % 24, minute: 0),
        quality: quality,
      ),
    );

SleepRecord _sleep(
  DateTime date, {
  required int hours,
  required int quality,
}) =>
    SleepRecord(
      date: date,
      sleepStart: const TimeOfDay(hour: 23, minute: 0),
      wakeTime: TimeOfDay(hour: (23 + hours) % 24, minute: 0),
      durationMinutes: hours * 60,
      quality: quality,
      sleepConditions: const ['dreams', 'earlyWake', 'initInsomnia'],
    );

BodyMeasurementRecord _body(String id, DateTime timestamp, double weight) =>
    BodyMeasurementRecord(id: id, timestamp: timestamp, weightKg: weight);
