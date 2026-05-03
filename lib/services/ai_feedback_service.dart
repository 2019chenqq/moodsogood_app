import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../models/calendar_day_summary.dart';

enum AIFeedbackMode {
  diaryOnly,
  dailyIntegrated,
}

class AIFeedbackService {
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

  Future<String> _callGenerateAiJournalReflection(CalendarDaySummary daySummary) async {
    try {
      final dateKey = _formatDateKey(daySummary.date);

      final diaryTitle = (daySummary.diaryTitle ?? '').trim();
      final diaryContent = (daySummary.diaryContent ?? '').trim();
      final diarySummary = (daySummary.diarySummary ?? '').trim();

      final diaryText = [diaryTitle, diaryContent, diarySummary]
          .where((s) => s.isNotEmpty)
          .join('\n');

      final emotions = <Map<String, dynamic>>[
        if (daySummary.averageMood != null)
          {'name': '整體情緒', 'score': daySummary.averageMood}
      ];
      for (final emotionName in daySummary.emotionNames) {
        if (emotionName.isNotEmpty) {
          emotions.add({
            'name': emotionName,
            'score': daySummary.averageMood,
          });
        }
      }

      final symptoms = <Map<String, dynamic>>[];
      for (final symptomName in daySummary.symptomNames) {
        if (symptomName.isNotEmpty) {
          symptoms.add({'name': symptomName});
        }
      }

      final aiInput = <String, dynamic>{
        'date': dateKey,
        'diaryText': diaryText,
        'emotions': emotions,
        'sleep': {
          'hours': daySummary.sleepHours,
          'quality': daySummary.sleepQuality ?? '',
        },
        'symptoms': symptoms,
        'period': {
          'isPeriodDay': daySummary.isPeriodDay,
          'isPredictedPeriodDay': daySummary.isPredictedPeriodDay,
        },
      };

      final diaryFields = <String, dynamic>{
        'title': diaryTitle,
        'content': diaryContent.isNotEmpty ? diaryContent : diarySummary ?? '',
        'overallMood': daySummary.averageMood,
        'overallSleepQuality': daySummary.sleepQuality,
      };

      final dailyRecord = <String, dynamic>{
        'overallMood': daySummary.averageMood,
        'emotions': daySummary.emotionNames
            .map((name) => {
              'name': name,
              'value': daySummary.averageMood,
            })
            .toList(),
        'symptoms': daySummary.symptomNames,
        'sleep': {
          'hours': daySummary.sleepHours,
          'quality': daySummary.sleepQuality,
        },
        'isPeriodDay': daySummary.isPeriodDay,
        'isPredictedPeriodDay': daySummary.isPredictedPeriodDay,
      };

      final payload = <String, dynamic>{
        'date': dateKey,
        'aiInput': aiInput,
        'diaryContent': diaryText,
        'diaryFields': diaryFields,
        'dailyRecord': dailyRecord,
      };

      debugPrint('🧪 AI Feedback Service: Calling generateAiJournalReflection with payload: $payload');

      final callable =
          FirebaseFunctions.instance.httpsCallable('generateAiJournalReflection');
      final response = await callable.call(payload);

      debugPrint('🧪 AI Feedback Service: Response received: ${response.data}');

      if (response.data is! Map) {
        throw Exception('AI 回應格式錯誤');
      }

      final data = Map<String, dynamic>.from(response.data as Map);

      final summary = (data['summary'] ?? '').toString().trim();
      final emotionObservation = (data['emotionObservation'] ?? '').toString().trim();
      final positiveFeedback = (data['positiveFeedback'] ?? '').toString().trim();
      final tomorrowAction = (data['tomorrowAction'] ?? '').toString().trim();

      final combined = [summary, emotionObservation, positiveFeedback, tomorrowAction]
          .where((s) => s.isNotEmpty)
          .join('\n\n');

      return combined.isNotEmpty
          ? combined
          : '暫時無法生成回饋，請稍後重試。';
    } catch (e) {
      debugPrint('❌ AI Feedback Service error: $e');
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
