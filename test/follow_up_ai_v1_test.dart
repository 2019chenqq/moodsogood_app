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
    });

    expect(workspace.aiDiscussionTopics, hasLength(2));
    expect(workspace.aiDiscussionTopics.first.note, '最近常提早醒來');
    expect(workspace.aiDiscussionTopics.last.selected, isFalse);
    expect(workspace.aiDiscussionTopics.last.note, '取消後仍需保留');
    expect(workspace.aiAdditionalNotes, '補充背景');
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
            flags: const ['earlyWake', 'initInsomnia'],
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
    expect(input.highFrequencySymptoms.single['occurrenceDays'], 2);
    expect(input.highFrequencySymptoms.single['averageSeverity'], isNull);
    expect(input.bodyMeasurements.first['change'], 1.5);
    expect(input.currentMedications.single['dose'], 20.0);
    expect(input.medicationTimeline.single['beforeDose'], 10);
    expect(input.discussionTopics.single.note, '最近常提早醒來');
    expect(input.discussionDetails, '想討論睡眠與生活近況');
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
    expect(normalized.discussionPriorities, ['生活近況更新及身體不適狀況']);
    expect(normalized.userSharedNotes, ['我完成了期待很久的旅行']);
    expect(normalized.userSharedNotes, isNot(contains('每天都有頭痛')));
    expect(normalized.userReportedConcerns, isEmpty);
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
    await tester.enterText(find.byKey(const ValueKey('keyChanges-0')), '修改後項目');
    await tester.enterText(
      find.byKey(const ValueKey('preview-additional-notes')),
      '更新後的補充背景',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keyChanges-delete-1')));
    await tester.pump();
    await tester.tap(find.text('確認摘要'));
    await tester.pumpAndSettle();

    expect(confirmed, isNotNull);
    expect(confirmed!.summary.keyChanges, ['修改後項目', '項目 C']);
    expect(confirmed!.additionalNotes, '更新後的補充背景');
  });
}
