import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/recent_review_summary.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/models/period_cycle.dart';
import 'package:moodsogood_app/sleep_insights/models/sleep_insight_models.dart';
import 'package:moodsogood_app/sleep_insights/services/sleep_analysis_service.dart';

void main() {
  const builder = RecentReviewSummaryBuilder();

  test('builds deterministic facts for a complete 30-day period', () {
    final records = List.generate(30, (index) {
      final date = DateTime(2026, 7, index + 1);
      return DailyRecord(
        id: _date(date),
        date: date,
        emotions: [Emotion(name: index.isEven ? '焦慮' : '平靜', value: 3)],
        symptoms: const ['疲倦'],
        stateChanges: const {
          'energy_change': 3,
          'appetite_change': 4,
          'activity_change': 2,
        },
        sleep: SleepData(
          sleepTime: const TimeOfDay(hour: 23, minute: 0),
          estimatedSleepTime:
              index % 3 == 0 ? const TimeOfDay(hour: 23, minute: 30) : null,
          finalWakeTime: const TimeOfDay(hour: 7, minute: 0),
          quality: index.isEven ? 3 : null,
          flags: index % 10 == 0 ? const ['insufficient'] : const [],
          naps: index % 5 == 0
              ? const [
                  NapItem(
                    start: TimeOfDay(hour: 13, minute: 0),
                    end: TimeOfDay(hour: 13, minute: 30),
                  ),
                ]
              : const [],
        ),
      );
    });

    final summary = builder.build(
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 30),
      dailyRecords: records,
    );

    expect(summary.period.lookbackDays, 30);
    expect(summary.period.recordedDays, 30);
    expect(summary.sleep.recordedDays, 30);
    expect(summary.sleep.validNightSleepDays, 30);
    expect(summary.sleep.averageNightSleepMinutes, 470);
    expect(summary.sleep.averageAllDaySleepMinutes, 476);
    expect(summary.sleep.sleepQualityRecordedDays, 15);
    expect(summary.sleep.averageSleepQuality, 3);
    expect(summary.sleep.napCount, 6);
    expect(summary.sleep.napDays, 6);
    expect(summary.sleep.averageNapMinutes, 30);
    expect(summary.sleep.sleepFlagCounts, {'insufficient': 3});
    expect(summary.sleep.explicitBedtimeDays, 20);
    expect(summary.sleep.estimatedBedtimeDays, 10);
    expect(summary.sleep.usableBedtimeDays, 30);
    expect(summary.sleep.typicalBedtime, '23:00');
    expect(summary.states.toJson(), {
      'energy': 3,
      'appetite': 4,
      'activity': 2,
    });
    expect(summary.size.totalCharacters, greaterThan(0));

    final canonical = const SleepAnalysisService().analyze(
      records: records,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 30),
      period: SleepInsightPeriod.thirtyDays,
    );
    expect(summary.sleep.recordedDays, canonical.summary.recordDays);
    expect(
      summary.sleep.validNightSleepDays,
      canonical.summary.validNightDays,
    );
    expect(
      summary.sleep.averageNightSleepMinutes,
      canonical.summary.averageNightMinutes,
    );
    expect(
      summary.sleep.averageAllDaySleepMinutes,
      canonical.summary.averageTotalMinutes,
    );
    expect(
      summary.sleep.sleepQualityRecordedDays,
      canonical.summary.qualityDays,
    );
    expect(summary.sleep.napCount, canonical.summary.napCount);
    expect(summary.sleep.napDays, canonical.summary.napDays);
  });

  test('missing sleep dates do not become valid bedtime days', () {
    final summary = builder.build(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 10),
      dailyRecords: [
        DailyRecord(
          id: '1',
          date: DateTime(2026, 8, 1),
          sleep: const SleepData(
            sleepTime: TimeOfDay(hour: 0, minute: 30),
            finalWakeTime: TimeOfDay(hour: 8, minute: 0),
            quality: 2,
          ),
        ),
        DailyRecord(
          id: '2',
          date: DateTime(2026, 8, 2),
          sleep: const SleepData(quality: 4),
        ),
        DailyRecord(id: '3', date: DateTime(2026, 8, 3)),
      ],
    );

    expect(summary.period.lookbackDays, 10);
    expect(summary.sleep.recordedDays, 2);
    expect(summary.sleep.validNightSleepDays, 1);
    expect(summary.sleep.sleepQualityRecordedDays, 2);
    expect(summary.sleep.usableBedtimeDays, 1);
    expect(summary.sleep.explicitBedtimeDays, 1);
    expect(summary.sleep.estimatedBedtimeDays, 0);
  });

  test('30 recorded days reuse estimated starts for 29 valid nights', () {
    final records = List.generate(30, (index) {
      final day = index + 1;
      return DailyRecord(
        id: '2026-08-${day.toString().padLeft(2, '0')}',
        date: DateTime(2026, 8, day),
        sleep: day <= 13
            ? const SleepData(
                sleepTime: TimeOfDay(hour: 23, minute: 0),
                finalWakeTime: TimeOfDay(hour: 7, minute: 0),
              )
            : day <= 29
                ? const SleepData(
                    estimatedSleepTime: TimeOfDay(hour: 23, minute: 0),
                    finalWakeTime: TimeOfDay(hour: 7, minute: 0),
                  )
                : const SleepData(quality: 3),
      );
    });

    final summary = builder.build(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 30),
      dailyRecords: records,
    );

    expect(summary.sleep.recordedDays, 30);
    expect(summary.sleep.validNightSleepDays, 29);
    expect(summary.sleep.explicitBedtimeDays, 13);
    expect(summary.sleep.estimatedBedtimeDays, 16);
    expect(summary.sleep.usableBedtimeDays, 29);
    expect(summary.sleep.averageNightSleepMinutes, 480);
  });

  test('aggregates multiple emotions and symptoms without causal inference',
      () {
    final summary = builder.build(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 3),
      dailyRecords: [
        DailyRecord(
          id: '1',
          date: DateTime(2026, 8, 1),
          emotions: const [
            Emotion(name: '焦慮', value: 2),
            Emotion(name: '平靜', value: 4),
          ],
          symptoms: const ['頭痛'],
        ),
        DailyRecord(
          id: '2',
          date: DateTime(2026, 8, 2),
          emotions: const [Emotion(name: '焦慮', value: 4)],
          symptoms: const ['頭痛', '反胃'],
        ),
      ],
      healthEvents: [
        HealthEvent(
          id: 'event',
          timestamp: DateTime(2026, 8, 2, 15),
          emotions: const [HealthEventEmotion(name: '焦慮', intensity: 5)],
          symptoms: const [HealthEventSymptom(name: '頭痛', severity: 4)],
        ),
      ],
    );

    final anxiety = summary.emotions.firstWhere((item) => item.name == '焦慮');
    expect(anxiety.occurrenceDays, 2);
    expect(anxiety.averageIntensity, 3.5);
    expect(anxiety.maxIntensity, 5);
    final headache = summary.symptoms.firstWhere((item) => item.name == '頭痛');
    expect(headache.occurrenceDays, 2);
    expect(headache.averageIntensity, 4);
    expect(headache.maxIntensity, 4);
  });

  test('keeps all active medications with only review fields', () {
    final summary = builder.build(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 30),
      activeMedications: List.generate(
          5,
          (index) => {
                'id': 'private-$index',
                'name': '藥物 $index',
                'dosePerUnit': 25,
                'pillCount': index + 0.5,
                'dose': 25 * (index + 0.5),
                'unit': 'mg',
                'times': ['睡前'],
                'type': 'oral',
                'purposes': ['不應輸出'],
              }),
    );

    expect(summary.medications, hasLength(5));
    expect(summary.medications.first.keys, [
      'name',
      'dosePerUnit',
      'pillCount',
      'dose',
      'unit',
      'times',
      'type',
    ]);
  });

  test('uses the existing deterministic medication adjustment formatter', () {
    final summary = builder.build(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 30),
      medicationAdjustments: [
        {
          'id': 'adjustment-1',
          'date': '2026-08-20',
          'items': [
            {
              'name': '藥物 A',
              'type': 'doseChanged',
              'oldDose': 25,
              'newDose': 50,
              'oldUnit': 'mg',
              'newUnit': 'mg',
            },
            {
              'name': '藥物 B',
              'type': 'scheduleChanged',
              'oldTimes': ['早上'],
              'newTimes': ['睡前'],
            },
            {'name': '藥物 C', 'type': 'stopped'},
          ],
        },
        {
          'id': 'adjustment-2',
          'date': '2026-08-21',
          'items': [
            {
              'name': '藥物 D',
              'type': 'added',
              'newDosePerUnit': 25,
              'newPillCount': 1,
              'newUnit': 'mg',
            },
            {'name': '藥物 E', 'type': 'resumed'},
            {'name': '藥物 F', 'type': 'injected'},
          ],
        },
      ],
    );

    expect(summary.medicationChanges, [
      {
        'date': '2026/08/20',
        'name': '藥物 A',
        'type': 'doseChanged',
        'changeSummary': '25 mg → 50 mg',
      },
      {
        'date': '2026/08/20',
        'name': '藥物 B',
        'type': 'scheduleChanged',
        'changeSummary': '早上 → 睡前',
      },
      {
        'date': '2026/08/20',
        'name': '藥物 C',
        'type': 'stopped',
        'changeSummary': '停藥',
      },
      {
        'date': '2026/08/21',
        'name': '藥物 D',
        'type': 'added',
        'changeSummary': '25 mg × 1 顆',
      },
      {
        'date': '2026/08/21',
        'name': '藥物 E',
        'type': 'resumed',
        'changeSummary': '恢復使用',
      },
      {
        'date': '2026/08/21',
        'name': '藥物 F',
        'type': 'injected',
        'changeSummary': '已施打',
      },
    ]);
  });

  test('empty periods and legacy missing fields do not crash', () {
    final summary = builder.build(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 30),
      activeMedications: const [
        {'nameZh': '舊藥', 'dose': 10},
      ],
      medicationAdjustments: const [
        {'date': 'invalid', 'items': []},
        {'id': 'missing-date', 'items': []},
      ],
    );

    expect(summary.periodCycles, isEmpty);
    expect(summary.medications.single['name'], '舊藥');
    expect(summary.medicationChanges, isEmpty);
    expect(summary.states.toJson().values, everyElement(isNull));
  });

  test('accepts the existing compact medication adjustment as V2 input', () {
    final summary = builder.build(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 30),
      medicationAdjustments: const [
        {
          'date': '2026/08/22',
          'items': [
            {
              'name': '藥物 G',
              'type': 'doseChanged',
              'changeSummary': '50 mg → 100 mg',
            },
          ],
        },
      ],
    );

    expect(summary.medicationChanges, [
      {
        'date': '2026/08/22',
        'name': '藥物 G',
        'type': 'doseChanged',
        'changeSummary': '50 mg → 100 mg',
      },
    ]);
  });

  test('period cycles keep only overlapping start and end dates', () {
    final summary = builder.build(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 30),
      periodCycles: [
        PeriodCycle(
          id: 'inside',
          startDate: DateTime(2026, 8, 5),
          endDate: DateTime(2026, 8, 9),
        ),
        PeriodCycle(
          id: 'outside',
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 7, 5),
        ),
      ],
    );

    expect(summary.periodCycles, [
      {'startDate': '2026-08-05', 'endDate': '2026-08-09'},
    ]);
  });
}

String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
