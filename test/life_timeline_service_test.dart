import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/calendar_day_summary.dart';
import 'package:moodsogood_app/models/daily_check_in.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/models/life_timeline_item.dart';
import 'package:moodsogood_app/services/life_timeline_service.dart';
import 'package:moodsogood_app/meds/med_symptom_compare_models.dart';
import 'package:moodsogood_app/meds/medication_subjective_response.dart';

void main() {
  final day = DateTime(2026, 8, 12);

  test('keeps every Quick Record as a timestamped event in ascending order',
      () {
    final result = LifeTimelineService.buildDayItems(
      date: day,
      quickRecords: [
        HealthEvent(
          id: 'q3',
          timestamp: DateTime(2026, 8, 12, 18, 10),
          emotions: const [HealthEventEmotion(name: '焦慮', intensity: 4)],
        ),
        HealthEvent(
          id: 'q1',
          timestamp: DateTime(2026, 8, 12, 13, 20),
          symptoms: const [HealthEventSymptom(name: '心悸', severity: 4)],
        ),
        HealthEvent(
          id: 'q2',
          timestamp: DateTime(2026, 8, 12, 13, 35),
          symptoms: const [HealthEventSymptom(name: '反胃', severity: 3)],
        ),
      ],
    );

    expect(result, hasLength(3));
    expect(result.map((item) => item.sourceId), ['q1', 'q2', 'q3']);
    expect(result.every((item) => item.hasExplicitTime), isTrue);
    expect(result[0].summary, contains('心悸 4'));
    expect(result[1].summary, contains('反胃 3'));
    expect(result[2].summary, contains('焦慮 4'));
  });

  test('Daily Check-in remains a separate date-only baseline event', () {
    final result = LifeTimelineService.buildDayItems(
      date: day,
      dailyCheckIns: [
        DailyCheckIn(
          date: day,
          overallMood: 4,
          healthStatus: 3,
          noSpecialEvent: false,
        ),
      ],
      quickRecords: [
        HealthEvent(
          id: 'q1',
          timestamp: DateTime(2026, 8, 12, 10),
          emotions: const [HealthEventEmotion(name: '焦慮', intensity: 5)],
        ),
      ],
    );

    expect(result, hasLength(2));
    final checkIn = result.firstWhere(
      (item) => item.type == LifeTimelineType.dailyCheckIn,
    );
    expect(checkIn.hasExplicitTime, isFalse);
    expect(checkIn.summary, contains('4/5'));
  });

  test('suppresses overlapping legacy evidence without dropping other fields',
      () {
    final result = LifeTimelineService.buildDayItems(
      date: day,
      dailyRecords: [
        DailyRecord(
          id: 'daily-1',
          date: day,
          emotions: const [
            Emotion(name: '焦慮', value: 4),
            Emotion(name: '平靜', value: 3),
          ],
          symptoms: const ['心悸', '頭痛'],
        ),
      ],
      quickRecords: [
        HealthEvent(
          id: 'q1',
          timestamp: DateTime(2026, 8, 12, 13, 20),
          emotions: const [HealthEventEmotion(name: '焦慮', intensity: 4)],
          symptoms: const [HealthEventSymptom(name: '心悸', severity: 4)],
        ),
      ],
    );

    final emotion =
        result.singleWhere((item) => item.type == LifeTimelineType.emotion);
    final symptom =
        result.singleWhere((item) => item.type == LifeTimelineType.symptom);
    expect(emotion.summary, '平靜 3');
    expect(symptom.summary, '頭痛');
  });

  test('uses real sleep time and does not expose diary content', () {
    final result = LifeTimelineService.buildDayItems(
      date: day,
      dailyRecords: [
        DailyRecord(
          id: 'daily-1',
          date: day,
          sleep: const SleepData(
            sleepTime: TimeOfDay(hour: 23, minute: 40),
            wakeTime: TimeOfDay(hour: 7, minute: 10),
            quality: 4,
          ),
        ),
      ],
      calendarSummary: CalendarDaySummary(
        date: day,
        hasDiary: true,
        diaryDocId: '2026-08-12',
        diaryTitle: '今天的標題',
        diaryContent: '不應進入 timeline 的完整內容',
        diarySummary: '不應被複製的內容摘要',
      ),
    );

    final sleep =
        result.singleWhere((item) => item.type == LifeTimelineType.sleep);
    final diary =
        result.singleWhere((item) => item.type == LifeTimelineType.diary);
    expect(sleep.time, DateTime(2026, 8, 12, 23, 40));
    expect(sleep.hasExplicitTime, isTrue);
    expect(diary.title, '今天的標題');
    expect(diary.summary, '這一天有留下日記');
    expect(diary.summary, isNot(contains('完整內容')));
  });

  test(
      'date-only fallback order is stable and duplicate source events collapse',
      () {
    final input = [
      LifeTimelineItem(
        time: day,
        type: LifeTimelineType.diary,
        title: '日記',
        summary: '有日記',
        sourceId: 'd1',
        hasExplicitTime: false,
      ),
      LifeTimelineItem(
        time: day,
        type: LifeTimelineType.dailyCheckIn,
        title: 'Check-in',
        summary: '狀態',
        sourceId: 'c1',
        hasExplicitTime: false,
      ),
      LifeTimelineItem(
        time: day,
        type: LifeTimelineType.diary,
        title: '重複日記',
        summary: '不同顯示文字不應影響去重',
        sourceId: 'd1',
        hasExplicitTime: false,
      ),
    ];

    final result = LifeTimelineService.sortAndDeduplicate(input);
    expect(result, hasLength(2));
    expect(result.map((item) => item.type), [
      LifeTimelineType.dailyCheckIn,
      LifeTimelineType.diary,
    ]);
  });

  test('activity keeps HealthEvent time and DailyRecord date precision', () {
    final result = LifeTimelineService.buildDayItems(
      date: day,
      quickRecords: [
        HealthEvent(
          id: 'quick-activity',
          timestamp: DateTime(2026, 8, 12, 9, 20),
          stateChanges: const {'activity_change': 4},
        ),
      ],
      dailyRecords: [
        DailyRecord(
          id: 'daily-activity',
          date: day,
          stateChanges: const {'activity_change': 2},
        ),
      ],
    );

    final activity =
        result.where((item) => item.type == LifeTimelineType.activity).toList();
    expect(activity, hasLength(2));
    expect(activity[0].summary, '偏低');
    expect(activity[0].hasExplicitTime, isFalse);
    expect(activity[0].metadata?['sourceType'], 'dailyRecord');
    expect(activity[1].summary, '偏高');
    expect(activity[1].time, DateTime(2026, 8, 12, 9, 20));
    expect(activity[1].metadata?['sourceType'], 'healthEvent');
  });

  test('medication adjustments preserve type, identity, and time precision',
      () {
    final event = MedicationAdjustmentEvent(
      adjustmentId: 'adjustment-1',
      itemIndex: 0,
      medDocId: 'med-1',
      medName: 'Quetiapine',
      date: DateTime(2026, 8, 12, 22, 5),
      type: 'doseChanged',
      oldDose: 150,
      newDose: 200,
      oldUnit: 'mg',
      newUnit: 'mg',
    );

    final result = LifeTimelineService.buildDayItems(
      date: day,
      medicationAdjustments: [event, event],
    );
    final item = result.single;
    expect(item.type, LifeTimelineType.medication);
    expect(item.sourceId, 'adjustment-1#0');
    expect(item.hasExplicitTime, isTrue);
    expect(item.title, 'Quetiapine 劑量增加');
    expect(item.summary, '150 mg → 200 mg');
    expect(item.metadata?['adjustmentId'], 'adjustment-1');
  });

  test('subjective medication response uses existing structured report only',
      () {
    final response = MedicationSubjectiveResponse(
      id: 'response-1',
      medicationId: 'med-1',
      medicationName: 'Quetiapine',
      changeRecordId: 'adjustment-1',
      changeDate: DateTime(2026, 8, 9, 22),
      followUpDay: 3,
      recordedAt: DateTime(2026, 8, 12),
      overallResponse: MedicationOverallResponse.mixed,
      changedAreas: const ['白天嗜睡'],
      perceivedRelation: MedicationPerceivedRelation.unsure,
      otherFactors: const [],
      note: '情緒暫無明顯變化',
    );

    final result = LifeTimelineService.buildDayItems(
      date: day,
      subjectiveMedicationResponses: [response],
    );
    final item = result.single;
    expect(item.type, LifeTimelineType.subjectiveMedicationResponse);
    expect(item.title, '用藥反應｜第 3 天');
    expect(item.summary, contains('Quetiapine'));
    expect(item.summary, contains('白天嗜睡'));
    expect(item.hasExplicitTime, isFalse);
    expect(item.metadata?['timestampPrecision'], 'day');
  });
}
