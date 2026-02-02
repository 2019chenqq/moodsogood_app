import 'export_metrics.dart';

/// ============================================================
/// STEP 4: 套用摘要規則 (Rule Engine)
/// 這一步只做「選句」，不做「生成句」
/// ============================================================
class SummaryRuleEngine {
  /// 整體情緒趨勢判斷
  static String analyzeEmotionTrend(ExportMetrics metrics) {
    if (metrics.topEmotions.isEmpty) {
      return '';
    }

    // 使用第一個核心情緒的變化量
    final primaryEmotion = metrics.topEmotions.first;
    if (primaryEmotion.trend >= 1.0) {
      return '情緒呈現上升趨勢';
    } else if (primaryEmotion.trend <= -1.0) {
      return '情緒呈現下降趨勢';
    } else {
      return '情緒保持相對穩定';
    }
  }

  /// 4-2. 高峰與波動判斷
  static List<String> analyzeHighPeaks(ExportMetrics metrics) {
    final summaries = <String>[];

    // 檢查是否出現≥8
    for (final emotion in metrics.topEmotions) {
      if (emotion.veryHighScoreCount > 0) {
        summaries.add('${emotion.name}情緒達到高峰水平（≥8分）${emotion.veryHighScoreCount}次');
      }
    }

    // 檢查是否連續≥2天
    for (final emotion in metrics.topEmotions) {
      if (emotion.hasHighPeak) {
        summaries.add('${emotion.name}出現連續高分（≥8分）情況');
      }
    }

    // 檢查波動程度
    if (metrics.sleepMetrics != null) {
      if (metrics.sleepMetrics!.volatilityLevel == '大') {
        summaries.add('睡眠波動較大，呈現不穩定狀態');
      }
    }

    return summaries;
  }

  /// 4-3. 睡眠 × 情緒關聯
  static String analyzeSleepEmotionLink(ExportMetrics metrics) {
    if (metrics.emotionSleepCorrelation == null) {
      return '';
    }

    final correlation = metrics.emotionSleepCorrelation!;

    if (correlation.hasSignificantCorrelation) {
      return '短睡眠期間與隔日情緒水平具有時間關聯性'
          '（短睡眠${correlation.shortSleepDays}晚，隔日情緒變化${correlation.emotionChangeAfterShortSleep.toStringAsFixed(1)}）';
    } else {
      return '';
    }
  }

  /// 4-4. 症狀 × 情緒同時出現
  static List<String> analyzeSymptomEmotionLink(ExportMetrics metrics) {
    final summaries = <String>[];

    for (final symptom in metrics.symptoms) {
      if (symptom.overlapPercentage >= 50) {
        summaries.add('${symptom.name}常於相近日期與高峰情緒同時出現'
            '（重疊比例${symptom.overlapPercentage.toStringAsFixed(0)}%）');
      } else if (symptom.highScoreCount > 0) {
        summaries.add('${symptom.name}未見與情緒明顯同步');
      }
    }

    return summaries;
  }

  /// 4-5. 文字摘要選擇
  static String analyzeTextTheme(ExportMetrics metrics) {
    if (metrics.textMetrics == null) {
      return '';
    }

    final text = metrics.textMetrics!;

    if (text.hasConcentratedTheme && text.primaryTheme != null) {
      final themeLabel = _getThemeLabel(text.primaryTheme!);
      return '日記中呈現明顯的$themeLabel主題，'
          '高頻詞為「${text.topKeyword}」（${text.topKeywordCount}次）';
    } else {
      return '日記內容未見特別集中的主題';
    }
  }

  /// 生成「AI關鍵變化摘要」
  static String generateAISummary(ExportMetrics metrics) {
    final parts = <String>[];

    // 1. 情緒趨勢
    final emotionTrend = analyzeEmotionTrend(metrics);
    if (emotionTrend.isNotEmpty) {
      parts.add(emotionTrend);
    }

    // 2. 高峰判斷
    final peaks = analyzeHighPeaks(metrics);
    parts.addAll(peaks);

    // 3. 睡眠×情緒
    final sleepLink = analyzeSleepEmotionLink(metrics);
    if (sleepLink.isNotEmpty) {
      parts.add(sleepLink);
    }

    // 4. 症狀×情緒
    final symptomLink = analyzeSymptomEmotionLink(metrics);
    parts.addAll(symptomLink);

    // 5. 文字主題
    final textTheme = analyzeTextTheme(metrics);
    if (textTheme.isNotEmpty) {
      parts.add(textTheme);
    }

    return parts.join('\n');
  }

  /// 主題標籤
  static String _getThemeLabel(String theme) {
    switch (theme) {
      case 'sleep':
        return '睡眠相關';
      case 'physical':
        return '身體不適';
      case 'rumination':
        return '反覆思考';
      case 'emotion':
        return '情緒描述';
      default:
        return '其他';
    }
  }

  /// 檢查頁面是否應該被跳過
  static bool shouldSkipPage(String pageType, ExportMetrics metrics) {
    switch (pageType) {
      case 'emotion_trend':
        return !metrics.hasEmotionData;
      case 'sleep':
        return !metrics.hasSleepData;
      case 'symptoms':
        return !metrics.hasSymptomData;
      case 'daily_detail':
        return !metrics.hasEmotionData && !metrics.hasSleepData;
      default:
        return false;
    }
  }

  /// 獲取頁面「無數據」提示文本
  static String getNoDataMessage(String pageType) {
    switch (pageType) {
      case 'emotion_trend':
        return '此期間無情緒紀錄';
      case 'sleep':
        return '此期間無睡眠數據';
      case 'symptoms':
        return '此期間無症狀紀錄';
      case 'daily_detail':
        return '此期間無足夠的詳細數據';
      default:
        return '此期間無相關數據';
    }
  }
}
