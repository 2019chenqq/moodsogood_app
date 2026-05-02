import 'dart:async';

import '../models/calendar_day_summary.dart';

enum AIFeedbackMode {
  diaryOnly,
  dailyIntegrated,
}

class AIFeedbackService {
  /// TODO: Wire this service to existing cloud AI function after API contracts are finalized.
  ///
  /// Current implementation is a safe mock version:
  /// - waits 1 second
  /// - returns gentle text based on available inputs
  Future<String> generateDiaryFeedback({
    required AIFeedbackMode mode,
    String? diaryTitle,
    String? diaryContent,
    CalendarDaySummary? daySummary,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));

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

        final hasOverlap = daySummary.hasEmotionData ||
            daySummary.hasSymptomData ||
            daySummary.hasSleepData ||
            daySummary.isPeriodDay ||
            daySummary.isPredictedPeriodDay;

        if (!hasOverlap && !daySummary.hasDiary && !daySummary.hasDailyRecord) {
          return '今天目前還沒有太多可交叉參考的資料。這也沒關係，你可以把它當作一個安靜的留白日。';
        }

        final lines = <String>[];
        final mood = daySummary.averageMood;

        if (mood != null) {
          if (mood <= 4) {
            lines.add('今天的情緒分數偏低，先把目標放在穩定自己，並回顧是否有特別耗能或壓力事件。');
          } else if (mood < 7) {
            lines.add('今天的情緒在中間區間，適合持續觀察睡眠、症狀與情緒是否有連動。');
          } else {
            lines.add('今天的情緒表現不錯，這是你有好好照顧自己的證據。');
          }
        }

        if (daySummary.hasSleepData) {
          lines.add('你有留下睡眠資料，接下來可以觀察睡眠品質是否影響白天的感受。');
        }

        if (daySummary.hasSymptomData) {
          lines.add('你也記錄了身體症狀，這會幫助你更快看見身心之間的關聯。');
        }

        if (daySummary.isPeriodDay) {
          lines.add('今天位在生理期，身體負荷可能較高，請把節奏放慢一些。');
        } else if (daySummary.isPredictedPeriodDay) {
          lines.add('目前接近預測生理期，這幾天的身心波動值得溫柔觀察。');
        }

        if (daySummary.hasDiary) {
          lines.add('你今天有寫日記，回頭看文字通常能更清楚理解情緒脈絡。');
        }

        if (lines.isEmpty) {
          lines.add('你已經開始留下紀錄，這會慢慢累積成理解自己的線索。');
        }

        final selected = lines.take(3).toList();
        return selected.join(' ');
    }
  }
}
