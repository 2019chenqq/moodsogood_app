import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/models/follow_up_sleep_summary_view_model.dart';
import 'package:moodsogood_app/services/follow_up_ai_data_aggregator.dart';

void main() {
  test('2026-08-05 legacy sleep quality is parsed on the shared 1-5 scale', () {
    final legacy = DailyRecord.fromData('2026-08-05', {
      'date': '2026-08-05',
      'sleep': {'sleepQuality': '4'},
    });
    final topLevel = DailyRecord.fromData('2026-08-05', {
      'date': '2026-08-05',
      'sleepQuality': 8,
      'sleepQualityScale': 10,
    });

    expect(legacy.sleep.quality, 4);
    expect(topLevel.sleep.quality, 4);
  });

  test('follow-up reuses symptom aggregate formats and keeps top five', () {
    final records = List.generate(
      2,
      (index) => DailyRecord(
        id: '2026-08-0${index + 4}',
        date: DateTime(2026, 8, index + 4),
      ),
    );
    final input = FollowUpAiDataAggregator().buildFromData(
      now: DateTime(2026, 8, 5),
      records: records,
      rawRecords: [
        {
          '_documentId': '2026-08-04',
          'symptomSectionCompleted': true,
          'symptoms': [
            {'name': '嗜睡', 'intensity': 4},
            {'name': '頭痛', 'score': 2},
            '噁心',
          ],
        },
        {
          '_documentId': '2026-08-05',
          'symptomSectionCompleted': true,
          'symptoms': const [],
          'symptomScores': {
            '白天嗜睡': 2,
            '頭痛': 4,
            '腹痛': 1,
            '暈眩': 2,
            '心悸': 2,
            '耳鳴': 2,
          },
        },
      ],
      medications: const [],
      adjustments: const [],
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
    );

    expect(input.highFrequencySymptoms, hasLength(5));
    expect(input.highFrequencySymptoms.first['name'], '白天嗜睡');
    expect(input.highFrequencySymptoms.first['occurrenceDays'], 2);
    expect(input.highFrequencySymptoms.first['averageSeverity'], 3);
    expect(input.statistics.validRecordDays, 2);
    expect(input.bodyMeasurements, isEmpty);
  });

  test('shared sleep summary dynamically includes every recorded condition',
      () {
    final viewModel = FollowUpSleepSummaryViewModel.fromData(const {
      'durationHours': {
        'recordedDays': 1,
        'average': 7.5,
        'minimum': 7.5,
        'maximum': 7.5,
      },
      'quality': {'recordedDays': 1, 'average': 4},
      'conditions': [
        {'code': 'dreams', 'label': '多夢', 'occurrenceDays': 1},
        {'code': 'lightSleep', 'label': '淺眠', 'occurrenceDays': 2},
        {'code': 'fragmented', 'label': '睡睡醒醒', 'occurrenceDays': 1},
        {'code': 'nocturia', 'label': '夜尿', 'occurrenceDays': 1},
      ],
      'naps': {'days': 0},
    });

    expect(viewModel.metrics, hasLength(9));
    expect(viewModel.displayItems, contains('睡眠品質：4/5（1 天）'));
    expect(viewModel.displayItems, contains('多夢：1 天'));
    expect(viewModel.displayItems, contains('淺眠：2 天'));
    expect(viewModel.displayItems, contains('睡睡醒醒：1 天'));
    expect(viewModel.displayItems, contains('夜尿：1 天'));
    expect(viewModel.displayItems, isNot(contains('入睡困難：0 天')));
  });

  test('aggregator keeps every recorded sleep condition dynamically', () {
    final input = FollowUpAiDataAggregator().buildFromData(
      now: DateTime(2026, 8, 5),
      records: [
        DailyRecord(
          id: '2026-08-05',
          date: DateTime(2026, 8, 5),
          sleep: const SleepData(
            flags: [
              'good',
              'ok',
              'earlyWake',
              'dreams',
              'lightSleep',
              'fragmented',
              'insufficient',
              'initInsomnia',
              'interrupted',
              'nocturia',
            ],
          ),
        ),
      ],
      medications: const [],
      adjustments: const [],
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
    );

    final conditions = (input.sleep['conditions'] as List)
        .whereType<Map>()
        .map((item) => item['code'])
        .toSet();
    expect(conditions, {
      'good',
      'ok',
      'earlyWake',
      'dreams',
      'lightSleep',
      'fragmented',
      'insufficient',
      'initInsomnia',
      'interrupted',
      'nocturia',
    });
  });

  test('formal display keeps symptoms when body measurements are absent', () {
    final record = FollowUpSummaryRecord(
      id: 'private',
      createdAt: DateTime(2026, 8, 5),
      updatedAt: DateTime(2026, 8, 5),
      confirmedAt: DateTime(2026, 8, 5),
      appointmentDate: null,
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 5),
      validRecordDays: 2,
      selectedTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
      aiOutput: FollowUpAiOutput(
        keyChanges: const [],
        timelineRelations: const [],
        discussionPriorities: const [],
        dataLimitations: const [],
        generatedAt: DateTime(2026, 8, 5),
      ),
      sleepSummary: const {},
      sleepTrend: const [],
      medicationTimeline: const [],
      highFrequencySymptoms: const [
        {'name': '頭痛', 'occurrenceDays': 2, 'averageSeverity': 3},
      ],
    );

    final display = FollowUpSummaryDisplayModel.fromRecord(record);
    expect(display.symptomAndBodyChanges, hasLength(1));
    expect(display.symptomAndBodyChanges.single, contains('頭痛'));
    expect(display.symptomAndBodyChanges.single, contains('平均程度 3'));
  });
}
