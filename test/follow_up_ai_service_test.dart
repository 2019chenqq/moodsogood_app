import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/services/follow_up_ai_service.dart';

FollowUpAiV1Input _buildInput() => FollowUpAiV1Input(
      statistics: FollowUpStatistics(
        periodStart: DateTime(2024, 1, 1),
        periodEnd: DateTime(2024, 1, 31),
        validRecordDays: 20,
      ),
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
      wellbeingTrends: const WellbeingTrendsInput(
        mood: MetricTrendInput(dailyValues: []),
        anxiety: MetricTrendInput(dailyValues: []),
        energy: MetricTrendInput(dailyValues: []),
        appetite: MetricTrendInput(dailyValues: []),
        activity: MetricTrendInput(dailyValues: []),
      ),
      sleep: const {
        'averageHours': 6,
        'range': {'minimumHours': 4, 'maximumHours': 8},
        'abnormalFlags': [],
        'dailyTrend': [],
      },
      highFrequencySymptoms: const [],
      bodyMeasurements: const [],
      currentMedications: const [],
      medicationTimeline: const [],
      dataLimitations: const [],
    );

void main() {
  group('FollowUpAiService follow-up answer preservation', () {
    test(
        'keeps discussionItems/keyChanges derived from the answer, only '
        'blocks items that merely echo the question', () {
      final input = _buildInput();
      final followUpAnswers = {
        '最近睡眠品質如何？': '最近常常凌晨兩點才睡著，白天很累',
      };

      final output = FollowUpAiOutput(
        keyChanges: const [
          '最近常常凌晨兩點才睡著，白天很累',
          '情緒起伏較上次穩定',
          '食慾大致正常',
        ],
        timelineRelations: const [],
        discussionPriorities: const [],
        discussionItems: const [
          '最近睡眠品質如何？', // literal echo of the question -> must be blocked
          '最近常常凌晨兩點才睡著，白天很累', // reflects the answer -> must be kept
        ],
        dataLimitations: const [],
        generatedAt: DateTime(2024, 2, 1),
      );

      final result = FollowUpAiService.applySelectionRulesForTesting(
        output,
        input,
        followUpAnswers: followUpAnswers,
      );

      expect(
        result.discussionItems,
        contains('最近常常凌晨兩點才睡著，白天很累。'),
        reason: 'Answer-derived content must not disappear from the summary.',
      );
      expect(
        result.discussionItems,
        isNot(contains('最近睡眠品質如何？')),
        reason: 'A literal echo of the question conveys no information.',
      );
      expect(
        result.keyChanges,
        contains('最近常常凌晨兩點才睡著，白天很累'),
        reason: 'Answer-derived keyChanges must also be preserved.',
      );
    });

    test(
        'fallback summary surfaces answered follow-up questions in '
        'discussionItems, not only in the private followUpResponses field', () {
      final input = _buildInput();
      final followUpAnswers = {
        '最近有沒有漏服藥物？': '上週漏了兩次早上的藥',
      };

      final fallback = FollowUpAiService.fallbackSummaryForTesting(
        input,
        followUpAnswers: followUpAnswers,
      );

      expect(fallback.discussionItems, contains('上週漏了兩次早上的藥。'));
      expect(
        fallback.followUpResponses.any((entry) =>
            entry['question'] == '最近有沒有漏服藥物？' &&
            entry['answer'] == '上週漏了兩次早上的藥'),
        isTrue,
      );
    });
  });
}
