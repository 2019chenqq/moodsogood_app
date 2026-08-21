import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/follow_up/models/follow_up_ai_summary.dart';

void main() {
  FollowUpSummaryRecord record({
    String details = '最近工作壓力想請教',
    String notes = '最近完成一件開心的事',
    List<String> priorities = const ['最近工作壓力想請教。', '睡眠可否改善'],
    List<String> discussionItems = const [],
    List<String> shared = const [],
    List<String> legacy = const [],
  }) =>
      FollowUpSummaryRecord(
        id: 'private-id',
        createdAt: DateTime.utc(2026, 8, 5),
        updatedAt: DateTime.utc(2026, 8, 5),
        confirmedAt: DateTime.utc(2026, 8, 5),
        appointmentDate: DateTime.utc(2026, 8, 10),
        periodStart: DateTime.utc(2026, 7, 1),
        periodEnd: DateTime.utc(2026, 8, 5),
        validRecordDays: 12,
        selectedTopics: const [
          {'type': 'sleep', 'label': '睡眠品質'}
        ],
        discussionDetails: details,
        additionalNotes: notes,
        aiOutput: FollowUpAiOutput(
          keyChanges: const ['頭痛出現 3 天', '平均睡眠 7 小時。', '情緒較平穩'],
          timelineRelations: const ['8/1 後睡眠紀錄增加'],
          discussionPriorities: priorities,
          discussionItems: discussionItems,
          userSharedNotes: shared,
          userReportedConcerns: legacy,
          dataLimitations: const ['有效紀錄 12 天。。'],
          generatedAt: DateTime.utc(2026, 8, 5, 8),
        ),
        sleepSummary: const {
          'durationHours': {
            'recordedDays': 2,
            'average': 7,
            'minimum': 6,
            'maximum': 8,
          }
        },
        sleepTrend: const [
          {'date': '2026-08-04', 'value': 6},
          {'date': '2026-08-05', 'value': 8},
        ],
        medicationTimeline: const [],
      );

  test('preserves discussion details without using legacy priorities', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(record());
    expect(display.topicLabels, ['睡眠品質']);
    expect(display.discussionItems, ['最近工作壓力想請教']);
  });

  test('shows raw details before AI follow-up summaries and deduplicates', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(record(
      details: '最近工作壓力想請教',
      discussionItems: const [
        '最近工作壓力想請教。',
        '工作壓力通常在下午加重',
      ],
    ));

    expect(display.discussionItems, [
      '最近工作壓力想請教',
      '工作壓力通常在下午加重。',
    ]);
  });

  test('AI failure keeps details and never exposes raw follow-up Q/A', () {
    final source = record().copyWith(
      aiOutput: FollowUpAiOutput(
        keyChanges: const ['一', '二', '三'],
        timelineRelations: const [],
        discussionPriorities: const [],
        followUpResponses: const [
          {'question': '什麼時候加重？', 'answer': '下午'}
        ],
        generatedAt: DateTime.utc(2026, 8, 5),
        dataLimitations: const [],
        usedFallback: true,
      ),
    );
    final display = FollowUpSummaryDisplayModel.fromRecord(source);

    expect(display.discussionItems, ['最近工作壓力想請教']);
    expect(display.toJson().toString(), isNot(contains('什麼時候加重')));
    expect(display.toJson().toString(), isNot(contains('下午')));
  });

  test('health records never become user shared notes', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(record(
      notes: '',
      legacy: const ['頭痛出現 3 天', '平均睡眠 7 小時'],
    ));
    expect(display.userSharedNotes, isEmpty);
    expect(display.keyChanges, contains('頭痛出現 3 天。'));
  });

  test('normalizes sentence endings only in the display model', () {
    final source = record();
    final display = FollowUpSummaryDisplayModel.fromRecord(source);
    expect(display.dataLimitations, ['有效紀錄 12 天。']);
    expect(source.aiOutput.dataLimitations, ['有效紀錄 12 天。。']);
  });

  test('deidentified QR snapshot uses the same display model', () {
    final source = record();
    final snapshot = source.toDeidentifiedSnapshot();
    expect(snapshot, isNot(contains('id')));
    expect(snapshot['display'],
        FollowUpSummaryDisplayModel.fromRecord(source).toJson());
  });

  test('share snapshot contains only checked sections and no raw record', () {
    final snapshot = record().toDeidentifiedSnapshot(
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: true,
        emotionsAndSymptoms: false,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: false,
      ),
    );
    final display = Map<String, dynamic>.from(snapshot['display'] as Map);
    expect(snapshot.keys, containsAll(<String>['schemaVersion', 'display']));
    expect(snapshot['additionalNotes'], isEmpty);
    expect(snapshot['medicationTimeline'], isEmpty);
    expect(
      Map<String, dynamic>.from(snapshot['aiOutput'] as Map)['keyChanges'],
      isEmpty,
    );
    expect(snapshot.toString(), isNot(contains('最近完成一件開心的事')));
    expect(snapshot.toString(), isNot(contains('頭痛出現 3 天')));
    expect(display['includedSections'], ['sleep']);
    expect(display['keyChanges'], isEmpty);
    expect(display['userSharedNotes'], isEmpty);
    expect(display['sleepTrend'], isNotEmpty);
  });

  test('keeps verbose sleep metrics out of main changes', () {
    final source = record().copyWith(
      aiOutput: FollowUpAiOutput(
        keyChanges: const [
          '睡眠時間平均約8.37小時，期間從7月31日至8月5日，睡眠時間趨勢呈現增加，最低為6小時（8月2日），最高為11.1小時（8月3日）',
          '情緒較平穩',
          '頭痛出現 3 天',
        ],
        timelineRelations: const [],
        discussionPriorities: const [],
        userSharedNotes: const [],
        userReportedConcerns: const [],
        dataLimitations: const [],
        generatedAt: DateTime.utc(2026, 8, 5),
      ),
    );
    final custom = FollowUpSummaryRecord(
      id: source.id,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
      confirmedAt: source.confirmedAt,
      appointmentDate: source.appointmentDate,
      periodStart: source.periodStart,
      periodEnd: source.periodEnd,
      validRecordDays: source.validRecordDays,
      selectedTopics: source.selectedTopics,
      discussionDetails: source.discussionDetails,
      additionalNotes: source.additionalNotes,
      aiOutput: source.aiOutput,
      sleepSummary: const {
        'durationHours': {
          'recordedDays': 4,
          'average': 8.37,
          'minimum': 6,
          'maximum': 11.1,
        }
      },
      sleepTrend: source.sleepTrend,
      medicationTimeline: source.medicationTimeline,
    );

    expect(
      FollowUpSummaryDisplayModel.fromRecord(custom).keyChanges.take(3),
      ['情緒較平穩。', '頭痛出現 3 天。'],
    );
  });

  test('preserves multiline user-entered discussion details verbatim', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(record(
      details: '生活近況：登頂合歡主峰的相關影響\n睡眠品質與身體不適症狀',
      priorities: const [],
    ));

    expect(display.discussionItems, [
      '生活近況：登頂合歡主峰的相關影響\n睡眠品質與身體不適症狀',
    ]);
  });
}
