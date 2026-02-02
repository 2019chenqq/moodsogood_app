import 'package:collection/collection.dart';

/// ============================================================
/// STEP 3: 中介指標模型 (Intermediate Metrics)
/// 這是最關鍵的一步 - 轉換成標準化的指標供 Rule Engine 使用
/// ============================================================

/// 單一情緒的指標
class EmotionMetrics {
  /// 情緒名稱
  final String name;

  /// 28天平均分數
  final double averageScore;

  /// 最高分
  final int maxScore;

  /// 分數≥7的次數
  final int highScoreCount; // ≥7 次數

  /// 分數≥8的次數
  final int veryHighScoreCount; // ≥8 次數

  /// 前14天平均分數
  final double firstHalfAverage;

  /// 後14天平均分數
  final double secondHalfAverage;

  /// 變化量（後 − 前）
  final double trend;

  /// 出現天數
  final int appearanceDays;

  /// 所有記錄的分數
  final List<int> allScores;

  const EmotionMetrics({
    required this.name,
    required this.averageScore,
    required this.maxScore,
    required this.highScoreCount,
    required this.veryHighScoreCount,
    required this.firstHalfAverage,
    required this.secondHalfAverage,
    required this.trend,
    required this.appearanceDays,
    required this.allScores,
  });

  /// 計算「重要度分數」用於排序：平均分 × 出現天數
  double get importanceScore => averageScore * appearanceDays;

  /// 判斷是否是「高峰情緒」（連續≥2天分數≥8）
  bool get hasHighPeak {
    for (int i = 0; i < allScores.length - 1; i++) {
      if (allScores[i] >= 8 && allScores[i + 1] >= 8) {
        return true;
      }
    }
    return false;
  }

  /// 判斷趨勢
  String get trendDescription {
    if (trend >= 1.0) return '上升';
    if (trend <= -1.0) return '下降';
    return '穩定';
  }

  @override
  String toString() => 'EmotionMetrics('
      'name: $name, '
      'avgScore: ${averageScore.toStringAsFixed(1)}, '
      'trend: ${trend.toStringAsFixed(1)}, '
      'trendDesc: $trendDescription)';
}

/// 睡眠指標
class SleepMetrics {
  /// 平均睡眠時數
  final double averageDuration;

  /// 最短睡眠時數
  final double minDuration;

  /// 最長睡眠時數
  final double maxDuration;

  /// <5小時的天數
  final int shortSleepDays;

  /// 睡眠時數的標準差（波動程度）
  final double standardDeviation;

  /// 波動級別
  final String volatilityLevel; // "小" / "中" / "大"

  /// 所有睡眠記錄
  final List<double> allDurations;

  /// 有睡眠數據的天數
  final int recordedDays;

  const SleepMetrics({
    required this.averageDuration,
    required this.minDuration,
    required this.maxDuration,
    required this.shortSleepDays,
    required this.standardDeviation,
    required this.volatilityLevel,
    required this.allDurations,
    required this.recordedDays,
  });

  /// 判斷睡眠質量
  String get qualityDescription {
    if (averageDuration < 5) return '嚴重不足';
    if (averageDuration < 6) return '不足';
    if (averageDuration > 9) return '偏長';
    return '正常';
  }

  /// 判斷波動程度
  String get volatilityDescription {
    if (volatilityLevel == '小') return '穩定';
    if (volatilityLevel == '中') return '中等波動';
    return '波動較大';
  }

  @override
  String toString() => 'SleepMetrics('
      'avgDuration: ${averageDuration.toStringAsFixed(1)}h, '
      'quality: $qualityDescription, '
      'volatility: $volatilityDescription)';
}

/// 症狀指標
class SymptomMetrics {
  /// 症狀名稱
  final String name;

  /// 分數≥7的次數
  final int highScoreCount;

  /// 與情緒≥7同日或±1日重疊次數
  final int emotionOverlapCount;

  /// 重疊比例（百分比 0-100）
  final double overlapPercentage;

  /// 所有紀錄的分數
  final List<int> allScores;

  /// 出現天數
  final int appearanceDays;

  /// 平均分數
  final double averageScore;

  const SymptomMetrics({
    required this.name,
    required this.highScoreCount,
    required this.emotionOverlapCount,
    required this.overlapPercentage,
    required this.allScores,
    required this.appearanceDays,
    required this.averageScore,
  });

  /// 判斷與情緒是否有明顯同步
  bool get hasSignificantOverlap => overlapPercentage >= 50;

  @override
  String toString() => 'SymptomMetrics('
      'name: $name, '
      'overlap: ${overlapPercentage.toStringAsFixed(1)}%, '
      'isSignificant: $hasSignificantOverlap)';
}

/// 文字分析指標
class DiaryTextMetrics {
  /// 每個類別的高頻詞及其計數
  final Map<String, Map<String, int>> categorizedKeywords;

  /// 睡眠相關詞頻
  final Map<String, int> sleepRelated;

  /// 身體不適相關詞頻
  final Map<String, int> physicalDiscomfort;

  /// 反覆思考相關詞頻
  final Map<String, int> rumination;

  /// 情緒描述相關詞頻（可選）
  final Map<String, int> emotionDescription;

  /// 是否有明顯集中的主題
  final bool hasConcentratedTheme;

  /// 最集中的主題類別
  final String? primaryTheme; // "sleep" / "physical" / "rumination" / "none"

  /// 詞頻最高的詞
  final String? topKeyword;

  /// 詞頻最高的計數
  final int topKeywordCount;

  const DiaryTextMetrics({
    required this.categorizedKeywords,
    required this.sleepRelated,
    required this.physicalDiscomfort,
    required this.rumination,
    required this.emotionDescription,
    required this.hasConcentratedTheme,
    required this.primaryTheme,
    required this.topKeyword,
    required this.topKeywordCount,
  });

  @override
  String toString() => 'DiaryTextMetrics('
      'primaryTheme: $primaryTheme, '
      'topKeyword: $topKeyword ($topKeywordCount times))';
}

/// 情緒 × 睡眠關聯指標
class EmotionSleepCorrelation {
  /// 是否有明顯時間關聯
  /// IF <5小時天數 ≥ 6 AND 隔日情緒平均 ↑ ≥ 0.8
  final bool hasSignificantCorrelation;

  /// 短睡眠後隔日情緒變化量
  final double emotionChangeAfterShortSleep;

  /// 短睡眠天數
  final int shortSleepDays;

  const EmotionSleepCorrelation({
    required this.hasSignificantCorrelation,
    required this.emotionChangeAfterShortSleep,
    required this.shortSleepDays,
  });

  @override
  String toString() => 'EmotionSleepCorrelation('
      'correlation: $hasSignificantCorrelation, '
      'emotionChange: ${emotionChangeAfterShortSleep.toStringAsFixed(2)})';
}

/// ============================================================
/// 完整的指標彙總容器
/// ============================================================
class ExportMetrics {
  /// 情緒指標（已排序）
  final List<EmotionMetrics> emotions;

  /// Top3 核心情緒
  final List<EmotionMetrics> topEmotions;

  /// 睡眠指標
  final SleepMetrics? sleepMetrics;

  /// 症狀指標（已排序，取前3）
  final List<SymptomMetrics> symptoms;

  /// 文字分析指標
  final DiaryTextMetrics? textMetrics;

  /// 情緒 × 睡眠關聯
  final EmotionSleepCorrelation? emotionSleepCorrelation;

  /// 是否有足夠的數據
  final bool hasEmotionData;
  final bool hasSleepData;
  final bool hasSymptomData;
  final bool hasTextData;

  const ExportMetrics({
    required this.emotions,
    required this.topEmotions,
    this.sleepMetrics,
    required this.symptoms,
    this.textMetrics,
    this.emotionSleepCorrelation,
    this.hasEmotionData = false,
    this.hasSleepData = false,
    this.hasSymptomData = false,
    this.hasTextData = false,
  });

  @override
  String toString() => 'ExportMetrics('
      'emotions: ${emotions.length}, '
      'topEmotions: ${topEmotions.length}, '
      'symptoms: ${symptoms.length}, '
      'hasSleepData: $hasSleepData)';
}
