import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/medication_subjective_response.dart';
import 'package:moodsogood_app/meds/medication_subjective_summary_builder.dart';
import 'package:moodsogood_app/follow_up/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_ai_data_aggregator.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_ai_service.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_service.dart';

void main() {
  MedicationSubjectiveResponse response({
    required int day,
    MedicationOverallResponse overall = MedicationOverallResponse.mixed,
    List<String> areas = const ['睡眠'],
    MedicationPerceivedRelation relation = MedicationPerceivedRelation.unsure,
    List<String> factors = const [],
    String note = '',
  }) =>
      MedicationSubjectiveResponse(
        id: 'response-$day',
        medicationId: 'med-1',
        medicationName: '測試藥物',
        changeRecordId: 'change-1',
        changeDate: DateTime(2026, 8, 1),
        followUpDay: day,
        recordedAt: DateTime(2026, 8, 1 + day),
        overallResponse: overall,
        changedAreas: areas,
        perceivedRelation: relation,
        otherFactors: factors,
        note: note,
      );

  test('AI input groups by changeRecordId, sorts days, and uses whitelist', () {
    final input = MedicationSubjectiveSummaryBuilder.toAiInput([
      response(day: 14),
      response(day: 3),
      response(day: 7),
    ]);

    expect(input, hasLength(1));
    final reports = input.single['responses'] as List;
    expect(reports.map((item) => item['followUpDay']), [3, 7, 14]);
    expect((reports.first as Map).keys.toSet(), {
      'followUpDay',
      'overallResponse',
      'changedAreas',
      'perceivedRelation',
      'otherFactors',
      'note',
    });
  });

  test('single response fallback describes only that report without a trend',
      () {
    final groups = MedicationSubjectiveSummaryBuilder.toAiInput([
      response(
        day: 3,
        overall: MedicationOverallResponse.worse,
        factors: const ['睡眠改變'],
      ),
    ]);
    final summary =
        MedicationSubjectiveSummaryBuilder.fallbackSummaries(groups).single;

    expect(summary, contains('第3天主觀回報'));
    expect(summary, contains('使用者認為'));
    expect(summary, contains('同期紀錄顯示可能影響因素包括睡眠改變'));
    expect(summary, isNot(contains('趨勢')));
    expect(summary, isNot(contains('由第')));
  });

  test('multiple response fallback merges repeated areas and keeps uncertainty',
      () {
    final groups = MedicationSubjectiveSummaryBuilder.toAiInput([
      response(
        day: 3,
        overall: MedicationOverallResponse.worse,
        factors: const ['睡眠改變'],
      ),
      response(day: 7, overall: MedicationOverallResponse.mixed),
      response(day: 14, overall: MedicationOverallResponse.better),
    ]);
    final summary =
        MedicationSubjectiveSummaryBuilder.fallbackSummaries(groups).single;

    expect(summary, contains('第3、7、14天'));
    expect(summary, contains('整體感受由第3天的變差，至第14天為有改善'));
    expect(summary, contains('持續回報的變化包括睡眠'));
    expect(summary, contains('仍不確定'));
    expect(summary, isNot(contains('藥物有效')));
    expect(summary, isNot(contains('副作用')));
  });

  test('safe AI text is inserted into follow-up timeline relations', () {
    final groups = MedicationSubjectiveSummaryBuilder.toAiInput([
      response(day: 3),
      response(day: 7),
    ]);
    const aiText = '使用者主觀回報睡眠變化持續存在；使用者認為與此次調整的關聯仍不確定。';
    final parsed = FollowUpAiService.parseSummaryReplyForTesting(jsonEncode({
      'keyChanges': ['A', 'B', 'C'],
      'discussionPriorities': [],
      'timelineRelations': [],
      'userSharedNotes': [],
      'medicationSubjectiveSummaries': [aiText],
      'dataLimitations': [],
    }))!;
    final output = FollowUpAiService.applySelectionRulesForTesting(
      parsed,
      _input(groups),
    );

    expect(output.timelineRelations, contains(aiText));
    expect(output.usedFallback, isFalse);
  });

  test('follow-up aggregator includes completed subjective reports', () {
    final input = FollowUpAiDataAggregator().buildFromData(
      records: const [],
      medications: const [],
      adjustments: const [],
      subjectiveResponses: [response(day: 3), response(day: 7)],
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
      appointments: [
        FollowUpAppointment(
          id: 'previous',
          date: DateTime(2026, 7, 31),
          label: '前次回診',
        ),
      ],
      currentAppointmentDate: DateTime(2026, 8, 30),
      now: DateTime(2026, 8, 20),
    );

    expect(input.medicationSubjectiveReports, hasLength(1));
    expect(
      (input.toJson()['medicationSubjectiveReports'] as List).single,
      containsPair('changeRecordId', 'change-1'),
    );
  });

  test('unsafe AI text is replaced by deterministic fallback', () {
    final groups = MedicationSubjectiveSummaryBuilder.toAiInput([
      response(day: 3),
      response(day: 7),
    ]);
    final parsed = FollowUpAiService.parseSummaryReplyForTesting(jsonEncode({
      'keyChanges': ['A', 'B', 'C'],
      'discussionPriorities': [],
      'timelineRelations': [],
      'userSharedNotes': [],
      'medicationSubjectiveSummaries': ['藥物有效並造成副作用，建議停藥。'],
      'dataLimitations': [],
    }))!;
    final output = FollowUpAiService.applySelectionRulesForTesting(
      parsed,
      _input(groups),
    );

    expect(output.usedFallback, isTrue);
    expect(output.timelineRelations.join(), isNot(contains('副作用')));
    expect(output.timelineRelations.join(), contains('使用者'));
  });
}

FollowUpAiV1Input _input(List<Map<String, dynamic>> reports) {
  const trend = MetricTrendInput(dailyValues: []);
  return FollowUpAiV1Input(
    statistics: FollowUpStatistics(
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 29),
      validRecordDays: 0,
    ),
    discussionTopics: const [],
    discussionDetails: '',
    additionalNotes: '',
    wellbeingTrends: const WellbeingTrendsInput(
      mood: trend,
      anxiety: trend,
      energy: trend,
      appetite: trend,
      activity: trend,
    ),
    sleep: const {},
    highFrequencySymptoms: const [],
    bodyMeasurements: const [],
    currentMedications: const [],
    medicationTimeline: const [],
    medicationSubjectiveReports: reports,
    dataLimitations: const [],
  );
}
