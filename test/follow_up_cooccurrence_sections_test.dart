import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/follow_up/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_ai_data_aggregator.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_summary_section_builder.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';

void main() {
  test('same HealthEvent pair is counted four times without same-day mixing',
      () {
    final events = [
      for (var index = 0; index < 4; index++)
        HealthEvent(
          id: 'pair-$index',
          timestamp: DateTime(2026, 8, 1 + index, 9),
          emotions: const [HealthEventEmotion(name: '焦慮', intensity: 4)],
          symptoms: const [HealthEventSymptom(name: '心悸', severity: 3)],
        ),
      HealthEvent(
        id: 'separate-emotion',
        timestamp: DateTime(2026, 8, 5, 9),
        emotions: const [HealthEventEmotion(name: '焦慮', intensity: 2)],
      ),
      HealthEvent(
        id: 'separate-symptom',
        timestamp: DateTime(2026, 8, 5, 18),
        symptoms: const [HealthEventSymptom(name: '心悸', severity: 5)],
      ),
    ];
    final input = FollowUpAiDataAggregator().buildFromData(
      records: [
        DailyRecord(
          id: 'legacy',
          date: DateTime(2026, 8, 6),
          symptoms: const ['心悸'],
          emotions: const [Emotion(name: '焦慮', value: 5)],
        ),
      ],
      medications: const [],
      adjustments: const [],
      healthEvents: events,
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
      now: DateTime(2026, 8, 6),
    );

    final pair = input.highFrequencySymptoms.single;
    expect(pair['items'], ['焦慮', '心悸']);
    expect(pair['coOccurrenceCount'], 4);
  });

  test('canonical sections deduplicate discussion and keep fixed order', () {
    final record = _record();
    final display = FollowUpSummaryDisplayModel.fromRecord(record);
    final sections = FollowUpSummarySectionBuilder.fromDisplay(display);

    expect(display.discussionItems, [
      '原始討論內容',
      'AI 整理後的討論內容。',
    ]);
    expect(display.discussionItems, isNot(contains('原始討論內容。')));
    expect(display.timelineRelations, isEmpty);
    expect(
      sections.map((section) => section.title),
      [
        '基本資訊',
        '想跟醫師討論的事',
        '主要變化',
        '睡眠趨勢',
        '症狀與情緒共現模式',
        '身體測量',
        '藥物調整時間軸',
        '其他想跟醫師說的內容',
        '資料限制',
      ],
    );
    expect(sections.expand((section) => section.items).join(),
        isNot(contains('重要時間關聯')));
    expect(
      sections
          .singleWhere(
            (section) => section.id == FollowUpSummarySectionId.cooccurrence,
          )
          .items
          .first,
      contains('共同記錄 4 次'),
    );
  });
}

FollowUpSummaryRecord _record() => FollowUpSummaryRecord(
      id: 'summary',
      createdAt: DateTime(2026, 8, 6),
      updatedAt: DateTime(2026, 8, 6),
      confirmedAt: DateTime(2026, 8, 6),
      appointmentDate: null,
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 6),
      validRecordDays: 6,
      selectedTopics: const [],
      discussionDetails: '原始討論內容',
      additionalNotes: '補充內容',
      aiOutput: FollowUpAiOutput(
        keyChanges: const ['主要變化'],
        discussionPriorities: const ['舊討論優先項目'],
        discussionItems: const ['AI 整理後的討論內容'],
        timelineRelations: const ['重要時間關聯'],
        userSharedNotes: const [],
        dataLimitations: const ['資料限制'],
        generatedAt: DateTime(2026, 8, 6),
      ),
      sleepSummary: const {
        'durationHours': {
          'recordedDays': 1,
          'average': 7,
          'minimum': 7,
          'maximum': 7,
        },
      },
      sleepTrend: const [
        {'date': '2026-08-01', 'value': 7},
      ],
      medicationTimeline: const [
        {'date': '2026-08-02', 'medicationName': '測試藥物', 'type': 'started'},
      ],
      highFrequencySymptoms: const [
        {
          'items': ['焦慮', '心悸'],
          'coOccurrenceCount': 4,
          'averageValues': {'焦慮': 4, '心悸': 3},
        },
      ],
      bodyMeasurements: const [
        {'name': '體重', 'unit': 'kg', 'change': -0.6},
      ],
    );
