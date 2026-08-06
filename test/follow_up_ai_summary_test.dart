import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/pages/follow_up_summary_page.dart';

void main() {
  test('AI input serializes every V0 follow-up data group', () {
    final input = FollowUpAiInput(
      statistics: FollowUpStatistics(
        periodStart: DateTime(2026, 7, 1),
        periodEnd: DateTime(2026, 7, 14),
        validRecordDays: 11,
      ),
      sleep: SleepSummaryInput(
        averageHours: 6.8,
        minimumHours: 4.5,
        maximumHours: 9,
        abnormalFlags: [
          SleepAbnormalFlagInput(
            code: 'short_sleep',
            label: '睡眠時間偏短',
            dates: [DateTime(2026, 7, 3)],
          ),
        ],
        dailyTrend: [
          DatedMetricValue(date: DateTime(2026, 7, 1), value: 7.2),
        ],
      ),
      wellbeingTrends: WellbeingTrendsInput(
        mood: _trend(3),
        anxiety: _trend(4),
        energy: _trend(2),
        appetite: _trend(3),
        activity: _trend(2),
      ),
      commonSymptoms: const [
        SymptomSummaryInput(
          name: '頭痛',
          occurrenceDays: 4,
          averageSeverity: 2.5,
        ),
      ],
      bodyMeasurements: const [
        BodyMeasurementChangeInput(
          name: '體重',
          unit: 'kg',
          startValue: 60,
          latestValue: 61.2,
          change: 1.2,
        ),
      ],
      medicationAdjustments: [
        MedicationDoseChangeInput(
          medicationName: '測試藥物',
          adjustedAt: DateTime.utc(2026, 7, 8),
          beforeDose: const DoseInput(value: 10, unit: 'mg'),
          afterDose: const DoseInput(value: 20, unit: 'mg'),
        ),
      ],
      discussionSelection: const DiscussionSelectionInput(
        topics: ['睡眠品質'],
        details: '想討論夜間醒來',
      ),
    );

    final json = input.toJson();

    expect(json['schemaVersion'], 1);
    expect(json['statistics'], containsPair('validRecordDays', 11));
    expect(json['sleep'], contains('dailyTrend'));
    expect(json['wellbeingTrends'], contains('anxiety'));
    expect(json['commonSymptoms'], isNotEmpty);
    expect(json['bodyMeasurements'], isNotEmpty);
    expect(json['medicationAdjustments'], isNotEmpty);
    expect(json['discussionSelection'], containsPair('topics', ['睡眠品質']));
  });

  test('AI output keeps the reserved response fields', () {
    final generatedAt = DateTime.utc(2026, 8, 5, 9, 30);
    final output = FollowUpAiOutput(
      keyChanges: const ['睡眠時間較前期增加', '焦慮紀錄波動', '活動量維持穩定'],
      timelineRelations: const ['7/8 調整用藥後有連續睡眠紀錄'],
      discussionPriorities: const ['夜間醒來'],
      userReportedConcerns: const ['最近常提早醒來'],
      dataLimitations: const ['有效紀錄僅 5 天'],
      generatedAt: generatedAt,
    );

    final parsed = FollowUpAiOutput.fromJson(output.toJson());

    expect(parsed.keyChanges, output.keyChanges);
    expect(parsed.timelineRelations, output.timelineRelations);
    expect(parsed.discussionPriorities, output.discussionPriorities);
    expect(parsed.userReportedConcerns, output.userReportedConcerns);
    expect(parsed.dataLimitations, output.dataLimitations);
    expect(parsed.generatedAt, generatedAt);
  });

  testWidgets('V0 AI card shows the unavailable message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FollowUpAiHighlightsCard()),
      ),
    );

    expect(find.text('AI 回診重點'), findsOneWidget);
    expect(
        find.text(FollowUpAiHighlightsCard.unavailableMessage), findsOneWidget);
    expect(find.text('準備中'), findsOneWidget);
  });

  testWidgets('AI card exposes a tappable detail entry', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowUpAiHighlightsCard(
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.text('開始準備 AI 回診摘要'), findsOneWidget);
    await tester.tap(find.text('開始準備 AI 回診摘要'));
    expect(tapped, isTrue);
  });
}

MetricTrendInput _trend(double value) => MetricTrendInput(
      direction: TrendDirection.stable,
      dailyValues: [
        DatedMetricValue(date: DateTime(2026, 7, 1), value: value),
      ],
    );
