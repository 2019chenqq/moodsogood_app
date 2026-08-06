import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/med_symptom_compare_models.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/pages/follow_up_ai_preview_page.dart';
import 'package:moodsogood_app/services/follow_up_ai_data_aggregator.dart';
import 'package:moodsogood_app/services/follow_up_ai_service.dart';
import 'package:moodsogood_app/services/follow_up_service.dart';

void main() {
  test('saved AI preparation restores independent topic notes', () {
    final workspace = FollowUpWorkspace.fromMap({
      'aiDiscussionTopics': [
        {
          'type': 'sleep',
          'label': '睡眠品質',
          'selected': true,
          'note': '最近常提早醒來',
        },
        {
          'type': 'mood',
          'label': '情緒狀況',
          'selected': false,
          'note': '取消後仍需保留',
        },
      ],
      'aiAdditionalNotes': '補充背景',
      'aiAllowDiaryReference': true,
    });

    expect(workspace.aiDiscussionTopics, hasLength(2));
    expect(workspace.aiDiscussionTopics.first.note, '最近常提早醒來');
    expect(workspace.aiDiscussionTopics.last.selected, isFalse);
    expect(workspace.aiDiscussionTopics.last.note, '取消後仍需保留');
    expect(workspace.aiAdditionalNotes, '補充背景');
    expect(workspace.aiAllowDiaryReference, isTrue);
  });

  test('diary context and AI highlights use structured candidate fields', () {
    final input = FollowUpAiDataAggregator()
        .buildFromData(
      now: DateTime(2026, 8, 5),
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
      records: const [],
      medications: const [],
      adjustments: const [],
    )
        .copyWith(diaryContext: const [
      {
        'date': '2026-08-02',
        'title': '登山',
        'content': '完成合歡主峰，覺得很有成就感',
      }
    ]);

    expect((input.toJson()['diaryContext'] as List).single,
        containsPair('date', '2026-08-02'));

    final output = FollowUpAiOutput.fromJson({
      'keyChanges': ['變化一', '變化二', '變化三'],
      'timelineRelations': [],
      'discussionPriorities': [],
      'userSharedNotes': [],
      'dataLimitations': [],
      'diaryHighlights': [
        {
          'date': '2026-08-02',
          'category': 'life_event',
          'summary': '完成合歡主峰，覺得很有成就感',
          'source': 'diary',
        }
      ],
      'generatedAt': '2026-08-05T00:00:00.000Z',
    });
    expect(output.diaryHighlights.single.source, 'diary');
    expect(output.diaryHighlights.single.category, 'life_event');
  });

  test('V1 aggregator computes 28-day evidence before AI receives it', () {
    final input = FollowUpAiDataAggregator().buildFromData(
      now: DateTime(2026, 8, 5),
      discussionTopics: const [
        FollowUpDiscussionTopicInput(
          type: 'sleep',
          label: '睡眠品質',
          selected: true,
          note: '最近常提早醒來',
        ),
      ],
      discussionDetails: '想討論睡眠與生活近況',
      additionalNotes: '想確認近期變化',
      currentAppointmentDate: DateTime(2026, 8, 10),
      appointments: [
        FollowUpAppointment(
          id: 'previous',
          date: DateTime(2026, 7, 20),
          label: '上次回診',
        ),
        FollowUpAppointment(
          id: 'current',
          date: DateTime(2026, 8, 10),
          label: '本次回診',
        ),
      ],
      records: [
        DailyRecord(
          id: '2026-08-01',
          date: DateTime(2026, 8, 1),
          overallMood: 3,
          stateChanges: const {
            'energy_change': 2,
            'appetite_change': 3,
            'activity_change': 2,
          },
          symptoms: const ['頭痛'],
          sleep: SleepData(
            sleepTime: const TimeOfDay(hour: 0, minute: 0),
            finalWakeTime: const TimeOfDay(hour: 6, minute: 0),
            quality: 2,
            flags: const ['earlyWake', 'initInsomnia', 'dreams'],
          ),
          bodyMeasurement: const BodyMeasurement(
            weightKg: 60,
            bodyFatPercent: 25,
            waistCm: 80,
          ),
        ),
        DailyRecord(
          id: '2026-08-05',
          date: DateTime(2026, 8, 5),
          overallMood: 4,
          stateChanges: const {
            'energy_change': 4,
            'appetite_change': 4,
            'activity_change': 3,
          },
          symptoms: const ['頭痛'],
          sleep: SleepData(
            sleepTime: const TimeOfDay(hour: 23, minute: 0),
            finalWakeTime: const TimeOfDay(hour: 7, minute: 0),
            quality: 4,
          ),
          bodyMeasurement: const BodyMeasurement(
            weightKg: 61.5,
            bodyFatPercent: 24.5,
            waistCm: 79,
          ),
        ),
      ],
      medications: const [
        {
          'name': '測試藥物',
          'dose': 20,
          'unit': 'mg',
          'times': ['睡前'],
          'isActive': true,
        },
      ],
      adjustments: [
        MedicationAdjustmentEvent(
          adjustmentId: 'a1',
          itemIndex: 0,
          medDocId: 'm1',
          medName: '測試藥物',
          date: DateTime(2026, 8, 3),
          type: 'doseChanged',
          oldDose: 10,
          newDose: 20,
          oldUnit: 'mg',
          newUnit: 'mg',
        ),
      ],
    );

    final json = input.toJson();
    expect(json['statistics'], containsPair('validRecordDays', 2));
    expect(json['statistics'], containsPair('periodStart', '2026-07-20'));
    expect(
      json['statistics'],
      containsPair('previousAppointmentDate', '2026-07-20'),
    );
    expect(
      json['statistics'],
      containsPair('currentAppointmentDate', '2026-08-10'),
    );
    expect(
      (json['sleep'] as Map)['durationHours'],
      containsPair('average', 7.0),
    );
    expect(
      (json['sleep'] as Map)['earlyAwakening'],
      containsPair('occurrenceDays', 1),
    );
    final sleepConditions = ((json['sleep'] as Map)['conditions'] as List)
        .whereType<Map>()
        .toList();
    expect(
      sleepConditions,
      contains(predicate<Map>((item) =>
          item['code'] == 'dreams' &&
          item['label'] == '多夢' &&
          item['occurrenceDays'] == 1)),
    );
    expect(input.highFrequencySymptoms.single['occurrenceDays'], 2);
    expect(input.highFrequencySymptoms.single['averageSeverity'], isNull);
    expect(input.bodyMeasurements.first['change'], 1.5);
    expect(input.currentMedications.single['dose'], 20.0);
    expect(input.medicationTimeline.single['beforeDose'], 10);
    expect(input.discussionTopics.single.note, '最近常提早醒來');
    expect(input.discussionDetails, '想討論睡眠與生活近況');
  });

  test('sleep input compares the earlier and recent halves', () {
    final input = FollowUpAiDataAggregator().buildFromData(
      now: DateTime(2026, 8, 5),
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
      records: [
        for (var day = 1; day <= 4; day++)
          DailyRecord(
            id: '2026-08-0$day',
            date: DateTime(2026, 8, day),
            sleep: SleepData(
              sleepTime: const TimeOfDay(hour: 23, minute: 0),
              finalWakeTime: TimeOfDay(hour: day <= 2 ? 6 : 8, minute: 0),
            ),
          ),
      ],
      medications: const [],
      adjustments: const [],
    );

    final duration = input.sleep['durationHours'] as Map;
    expect(duration['comparison'], containsPair('earlierAverage', 7.0));
    expect(duration['comparison'], containsPair('recentAverage', 9.0));
    expect(duration['comparison'], containsPair('change', 2.0));
    expect(duration['comparison'], containsPair('direction', 'increasing'));

    final output = FollowUpAiService.applySelectionRulesForTesting(
      FollowUpAiOutput(
        keyChanges: const [
          '睡眠平均 8 小時，最低 7 小時，最高 9 小時',
          '情緒較穩定',
          '活動量增加',
        ],
        discussionPriorities: const [],
        timelineRelations: const [],
        dataLimitations: const [],
        generatedAt: DateTime.utc(2026, 8, 5),
      ),
      input,
    );
    expect(output.keyChanges, [
      '情緒較穩定',
      '活動量增加',
      '睡眠時間較前期增加：2小時',
    ]);
  });

  test('unselected topics do not filter basic health data from AI input', () {
    final input = FollowUpAiDataAggregator().buildFromData(
      now: DateTime(2026, 8, 5),
      discussionTopics: const [
        FollowUpDiscussionTopicInput(
          type: 'lifeUpdates',
          label: '生活近況',
          selected: true,
        ),
        FollowUpDiscussionTopicInput(
          type: 'physicalDiscomfort',
          label: '身體不適',
          selected: false,
        ),
      ],
      discussionDetails: '近期生活更新',
      additionalNotes: '',
      records: [
        DailyRecord(
          id: '2026-08-05',
          date: DateTime(2026, 8, 5),
          overallMood: 2,
          stateChanges: const {
            'energy_change': 4,
            'appetite_change': 3,
            'activity_change': 2,
          },
          symptoms: const ['頭痛'],
          sleep: SleepData(
            sleepTime: const TimeOfDay(hour: 23, minute: 0),
            finalWakeTime: const TimeOfDay(hour: 7, minute: 0),
            quality: 3,
          ),
          bodyMeasurement: const BodyMeasurement(weightKg: 60),
        ),
      ],
      medications: const [
        {'name': '測試藥物', 'isActive': true},
      ],
      adjustments: const [],
    );

    expect(input.highFrequencySymptoms, isNotEmpty);
    expect(input.bodyMeasurements, isNotEmpty);
    expect(input.sleep, isNotEmpty);
    expect(input.currentMedications, isNotEmpty);
    expect(input.medicationTimeline, isEmpty);
    expect(input.wellbeingTrends.mood.dailyValues, isNotEmpty);
    expect(input.wellbeingTrends.energy.dailyValues, isNotEmpty);
    expect(input.dataLimitations.join(), contains('症狀紀錄'));

    final normalized = FollowUpAiService.applySelectionRulesForTesting(
      FollowUpAiOutput(
        keyChanges: const ['期間有頭痛紀錄', '睡眠有所變化', '藥物時間軸已更新'],
        discussionPriorities: const ['生活近況更新及身體不適狀況'],
        timelineRelations: const [],
        userReportedConcerns: const ['頭痛'],
        dataLimitations: const [],
        generatedAt: DateTime.utc(2026, 8, 5),
      ),
      input,
      followUpAnswers: const {
        '最近頭痛程度如何？': '每天都有頭痛',
        '還有什麼想讓醫師知道？': '我完成了期待很久的旅行',
      },
    );

    expect(normalized.keyChanges, contains('期間有頭痛紀錄'));
    expect(normalized.discussionItems, ['生活近況更新及身體不適狀況。']);
    expect(normalized.userSharedNotes, isEmpty);
    expect(normalized.userSharedNotes, isNot(contains('每天都有頭痛')));
    expect(normalized.userReportedConcerns, isEmpty);
    expect(normalized.followUpResponses, [
      {'question': '最近頭痛程度如何？', 'answer': '每天都有頭痛'},
      {'question': '還有什麼想讓醫師知道？', 'answer': '我完成了期待很久的旅行'},
    ]);
  });

  testWidgets('preview supports editing, deleting, and confirming',
      (tester) async {
    FollowUpAiPreviewResult? confirmed;
    final summary = FollowUpAiOutput(
      keyChanges: const ['項目 A', '項目 B', '項目 C'],
      discussionPriorities: const ['優先事項'],
      timelineRelations: const ['時間關聯'],
      userReportedConcerns: const ['使用者困擾'],
      dataLimitations: const ['資料限制'],
      generatedAt: DateTime.utc(2026, 8, 5),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            confirmed = await Navigator.push<FollowUpAiPreviewResult>(
              context,
              MaterialPageRoute(
                builder: (_) => FollowUpAiPreviewPage(
                  initialSummary: summary,
                  initialAdditionalNotes: '原本的補充背景',
                  onRegenerate: (_) async => summary,
                ),
              ),
            );
          },
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('keyChanges-0')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const ValueKey('keyChanges-0')), '修改後項目');
    await tester.drag(find.byType(ListView), const Offset(0, 150));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keyChanges-delete-1')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('preview-additional-notes')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('preview-additional-notes')),
      '更新後的補充背景',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.text('確認摘要'));
    await tester.pumpAndSettle();

    expect(confirmed, isNotNull);
    expect(confirmed!.summary.keyChanges, ['修改後項目', '項目 C']);
    expect(confirmed!.additionalNotes, '更新後的補充背景');
  });

  testWidgets('preview hides raw follow-up responses and edits discussionItems',
      (tester) async {
    final summary = FollowUpAiOutput(
      keyChanges: const ['項目 A', '項目 B', '項目 C'],
      discussionPriorities: const [],
      discussionItems: const ['下午嗜睡會影響日常活動意願。'],
      followUpResponses: const [
        {'question': '最近最想先討論什麼？', 'answer': '頭痛對工作的影響'}
      ],
      timelineRelations: const [],
      dataLimitations: const [],
      generatedAt: DateTime.utc(2026, 8, 5),
    );
    await tester.pumpWidget(MaterialApp(
      home: FollowUpAiPreviewPage(
        initialSummary: summary,
        initialAdditionalNotes: '',
        onRegenerate: (_) async => summary,
      ),
    ));

    expect(find.text('AI 補問與回答'), findsNothing);
    expect(find.textContaining('最近最想先討論什麼'), findsNothing);
    expect(find.textContaining('頭痛對工作的影響'), findsNothing);
    expect(find.text('下午嗜睡會影響日常活動意願。'), findsOneWidget);
    await tester.tap(find.text('確認摘要'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('AI discussionItems formalize and merge colloquial answers', () {
    final output = FollowUpAiService.parseSummaryReplyForTesting('''
{"keyChanges":["變化一","變化二","變化三"],"discussionItems":["白天嗜睡主要出現在下午，並影響日常活動意願。"],"userSharedNotes":[],"dataLimitations":[]}
''');

    expect(output, isNotNull);
    expect(output!.discussionItems, [
      '白天嗜睡主要出現在下午，並影響日常活動意願。',
    ]);
  });

  test('similar follow-up answers can become one discussion item', () {
    final output = FollowUpAiService.parseSummaryReplyForTesting('''
{"keyChanges":["變化一","變化二","變化三"],"discussionItems":["下午嗜睡會降低工作專注力。"],"userSharedNotes":[],"dataLimitations":[]}
''');

    expect(output!.discussionItems, hasLength(1));
  });

  test('fallback never copies follow-up questions or answers', () {
    final input = FollowUpAiDataAggregator().buildFromData(
      now: DateTime(2026, 8, 5),
      discussionTopics: const [
        FollowUpDiscussionTopicInput(
          type: 'sleep',
          label: '睡眠品質',
          selected: true,
        ),
      ],
      discussionDetails: '想討論最近白天精神狀況',
      additionalNotes: '',
      records: const [],
      medications: const [],
      adjustments: const [],
    );
    final output = FollowUpAiService.fallbackSummaryForTesting(
      input,
      followUpAnswers: const {
        '最近白天嗜睡最嚴重的時段是什麼時候？': '就下午超想睡啊，整個人廢掉',
        '空白題目？': '   ',
      },
    );

    expect(output.discussionItems, ['想討論最近白天精神狀況。']);
    expect(output.userSharedNotes, isEmpty);
    expect(output.toJson().toString(), contains('就下午超想睡啊，整個人廢掉'));
    expect(
      FollowUpSummaryTextFormatter.safeDiscussionItems([
        ...output.discussionItems,
        ...output.keyChanges,
      ]).join(),
      isNot(contains('就下午超想睡啊')),
    );
    expect(output.followUpResponses, hasLength(1));
  });

  testWidgets('preview uses fixed sections without timeline relations',
      (tester) async {
    final summary = FollowUpAiOutput(
      keyChanges: const ['變化一', '變化二', '變化三'],
      discussionPriorities: const [],
      timelineRelations: const ['舊版時間關聯'],
      dataLimitations: const [],
      generatedAt: DateTime.utc(2026, 8, 5),
    );
    await tester.pumpWidget(MaterialApp(
      home: FollowUpAiPreviewPage(
        initialSummary: summary,
        initialAdditionalNotes: '',
        onRegenerate: (_) async => summary,
      ),
    ));

    expect(find.text('主要變化'), findsOneWidget);
    expect(find.text('重要時間關聯'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('藥物調整時間軸'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('藥物調整時間軸'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview only confirms selected diary highlights',
      (tester) async {
    FollowUpAiPreviewResult? confirmed;
    final summary = FollowUpAiOutput(
      keyChanges: const ['變化一', '變化二', '變化三'],
      discussionPriorities: const [],
      timelineRelations: const [],
      diaryHighlights: const [
        FollowUpDiaryHighlight(
          date: '2026-08-02',
          category: 'life_event',
          summary: '完成合歡主峰',
        ),
        FollowUpDiaryHighlight(
          date: '2026-08-03',
          category: 'subjective_feeling',
          summary: '對完成目標感到開心',
        ),
      ],
      dataLimitations: const [],
      generatedAt: DateTime.utc(2026, 8, 5),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            confirmed = await Navigator.push<FollowUpAiPreviewResult>(
              context,
              MaterialPageRoute(
                builder: (_) => FollowUpAiPreviewPage(
                  initialSummary: summary,
                  initialAdditionalNotes: '',
                  onRegenerate: (_) async => summary,
                ),
              ),
            );
          },
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('完成合歡主峰'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final candidateTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '完成合歡主峰'),
    );
    candidateTile.onChanged!(true);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('確認摘要'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('確認摘要'));
    await tester.pumpAndSettle();

    expect(confirmed, isNotNull);
    expect(confirmed!.summary.diaryHighlights, hasLength(1));
    expect(confirmed!.summary.diaryHighlights.single.summary, '完成合歡主峰');
  });
}
