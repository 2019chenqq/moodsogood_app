import 'package:flutter/material.dart';

import '../models/calendar_day_summary.dart';
import 'ai_journal_reflection_http_client.dart';
import 'diary_ai_prompt_builder.dart';

enum AIFeedbackMode {
  diaryOnly,
  dailyIntegrated,
}

class AIFeedbackService {
  final AiJournalReflectionHttpClient _aiClient =
      AiJournalReflectionHttpClient();

  Future<String> generateDiaryFeedback({
    required AIFeedbackMode mode,
    String? diaryTitle,
    String? diaryContent,
    CalendarDaySummary? daySummary,
  }) async {
    switch (mode) {
      case AIFeedbackMode.diaryOnly:
        final hasTitle = (diaryTitle ?? '').trim().isNotEmpty;
        final hasContent = (diaryContent ?? '').trim().isNotEmpty;

        if (!hasTitle && !hasContent) {
          return '今天的日記內容還比較少，先給自己一點空間也很好。若願意，可以補上一句你最在意的感受。';
        }

        return '從你今天寫下的內容中，可以看見你正在努力整理自己的感受。先不用急著找到答案，能夠把心情寫下來，本身就是一種照顧自己的方式。';

      case AIFeedbackMode.dailyIntegrated:
        if (daySummary == null) {
          return '今天的資料還不完整，先保留這份紀錄就很好。等你補上更多內容後，我可以再幫你整理觀察重點。';
        }

        return _callGenerateAiJournalReflection(daySummary);
    }
  }

  Future<String> _callGenerateAiJournalReflection(
    CalendarDaySummary daySummary,
  ) async {
    try {
      final dateKey = _formatDateKey(daySummary.date);

      final diaryTitle = (daySummary.diaryTitle ?? '').trim();
      final diaryContent = (daySummary.diaryContent ?? '').trim();
      final diarySummary = (daySummary.diarySummary ?? '').trim();

      final diaryText = [diaryTitle, diaryContent, diarySummary]
          .where((s) => s.isNotEmpty)
          .join('\n');

      final emotionScores = <Map<String, dynamic>>[
        if (daySummary.averageMood != null)
          {
            'name': '整體情緒',
            'score': daySummary.averageMood,
          },
        ...daySummary.emotionNames.where((name) => name.trim().isNotEmpty).map(
              (name) => {
                'name': name.trim(),
                'score': null,
              },
            ),
      ];

      final promptPayload = buildDiaryAiPromptBasic(
        date: dateKey,
        diaryText: diaryText,
        emotions: emotionScores.where((e) => e['name'] == '整體情緒').toList(),
      );

      final payload = <String, dynamic>{
        'date': dateKey,
        'promptPayload': promptPayload,
        'aiInput': promptPayload,
      };

      debugPrint(
        'AI Feedback Service request payload: $payload',
      );

      final data = await _aiClient.generate(payload: payload);
      debugPrint('AI Feedback Service response body: $data');

      final summary = (data['summary'] ?? '').toString().trim();

      final emotionObservation =
          (data['emotionObservation'] ?? '').toString().trim();

      final possibleFactorsRaw = data['possibleFactors'];
      final possibleFactors = possibleFactorsRaw is List
          ? possibleFactorsRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[];

      final gentleFeedback =
          (data['gentleFeedback'] ?? data['positiveFeedback'] ?? '')
              .toString()
              .trim();

      final selfCareSuggestion =
          (data['selfCareSuggestion'] ?? data['tomorrowAction'] ?? '')
              .toString()
              .trim();

      final riskLevel = (data['riskLevel'] ?? 'low').toString().trim();

      final disclaimer = (data['disclaimer'] ?? '此回饋僅根據今日紀錄整理，不能取代專業醫療或心理諮詢。')
          .toString()
          .trim();

      final sections = <String>[];

      if (summary.isNotEmpty) {
        sections.add('今日摘要\n$summary');
      }

      if (emotionObservation.isNotEmpty) {
        sections.add('情緒觀察\n$emotionObservation');
      }

      if (possibleFactors.isNotEmpty) {
        sections.add(
          '可能影響因素\n${possibleFactors.map((e) => '• $e').join('\n')}',
        );
      }

      if (gentleFeedback.isNotEmpty) {
        sections.add('溫柔回饋\n$gentleFeedback');
      }

      if (selfCareSuggestion.isNotEmpty) {
        sections.add('照顧建議\n$selfCareSuggestion');
      }

      if (riskLevel == 'high') {
        sections.add(
          '安全提醒\n如果你現在有傷害自己的衝動，請先離開危險物品，並立刻聯絡身邊可信任的人、醫療院所或當地緊急資源。',
        );
      }

      if (disclaimer.isNotEmpty) {
        sections.add(disclaimer);
      }

      final combined = sections.join('\n\n');

      return combined.isNotEmpty ? combined : '暫時無法生成回饋，請稍後重試。';
    } catch (e, stack) {
      debugPrint('AI Feedback Service exception: $e');
      debugPrint('AI Feedback Service stackTrace: $stack');
      rethrow;
    }
  }

  String _formatDateKey(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
