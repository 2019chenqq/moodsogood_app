import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/daily_record.dart';
import 'export_config.dart';
import 'export_metrics.dart';

/// ============================================================
/// STEP 2 + STEP 3: 原始資料擷取 + 轉換成中介指標
/// ============================================================
class ExportMetricsCalculator {
  /// 計算所有指標（主要入口）
  static Future<ExportMetrics> calculateMetrics({
    required List<DailyRecord> records,
    required ExportConfig config,
  }) async {
    debugPrint('📊 開始計算導出指標...');

    // 1. 計算情緒指標
    final emotionMetrics = _calculateEmotionMetrics(records);
    debugPrint('📊 情緒指標計算完成，共 ${emotionMetrics.length} 種情緒');

    // 2. 計算睡眠指標
    final sleepMetrics = _calculateSleepMetrics(records);
    debugPrint('📊 睡眠指標計算完成');

    // 3. 計算症狀指標
    final symptomMetrics = _calculateSymptomMetrics(records, emotionMetrics);
    debugPrint('📊 症狀指標計算完成，共 ${symptomMetrics.length} 項症狀');

    // 4. 計算文字分析指標
    final textMetrics = _calculateTextMetrics(records);
    debugPrint('📊 文字分析指標計算完成');

    // 5. 計算情緒×睡眠關聯
    final emotionSleepCorrelation =
        _calculateEmotionSleepCorrelation(emotionMetrics, sleepMetrics, records);
    debugPrint('📊 情緒×睡眠關聯計算完成');

    // 6. 選出 Top 3 核心情緒
    final topEmotions = _selectTopEmotions(emotionMetrics, count: 3);

    // 7. 判斷數據充分性
    final hasEmotionData = emotionMetrics.isNotEmpty;
    final hasSleepData = sleepMetrics != null;
    final hasSymptomData = symptomMetrics.isNotEmpty;
    final hasTextData = textMetrics != null;

    return ExportMetrics(
      emotions: emotionMetrics,
      topEmotions: topEmotions,
      sleepMetrics: sleepMetrics,
      symptoms: symptomMetrics.take(3).toList(),
      textMetrics: textMetrics,
      emotionSleepCorrelation: emotionSleepCorrelation,
      hasEmotionData: hasEmotionData,
      hasSleepData: hasSleepData,
      hasSymptomData: hasSymptomData,
      hasTextData: hasTextData,
    );
  }

  /// ============================================================
  /// 3-1. 計算情緒指標
  /// ============================================================
  static List<EmotionMetrics> _calculateEmotionMetrics(
    List<DailyRecord> records,
  ) {
    // 按情緒名稱分組
    final emotionMap = <String, List<int>>{};
    for (final record in records) {
      for (final emotion in record.emotions) {
        if (emotion.value != null && emotion.value! > 0) {
          emotionMap.putIfAbsent(emotion.name, () => []).add(emotion.value!);
        }
      }
    }

    if (emotionMap.isEmpty) {
      debugPrint('⚠️ 沒有情緒數據');
      return [];
    }

    // 計算每種情緒的指標
    final result = <EmotionMetrics>[];
    final recordsLength = records.length;
    final halfLength = (recordsLength / 2).ceil();

    for (final emotionName in emotionMap.keys) {
      final scores = emotionMap[emotionName]!;
      final appearanceDays = scores.length;
      final maxScore = scores.reduce((a, b) => a > b ? a : b);
      final avgScore = scores.isEmpty ? 0.0 : scores.reduce((a, b) => a + b) / scores.length;
      final highScoreCount = scores.where((s) => s >= 7).length;
      final veryHighScoreCount = scores.where((s) => s >= 8).length;

      // 前14天和後14天的平均
      final firstHalfScores = <int>[];
      final secondHalfScores = <int>[];
      int recordIndex = 0;

      for (int i = 0; i < records.length; i++) {
        final emotion =
            records[i].emotions.firstWhereOrNull((e) => e.name == emotionName);
        if (emotion != null && emotion.value != null && emotion.value! > 0) {
          if (i < halfLength) {
            firstHalfScores.add(emotion.value!);
          } else {
            secondHalfScores.add(emotion.value!);
          }
        }
      }

      final firstHalfAvg = firstHalfScores.isEmpty
          ? 0.0
          : firstHalfScores.reduce((a, b) => a + b) / firstHalfScores.length;
      final secondHalfAvg = secondHalfScores.isEmpty
          ? 0.0
          : secondHalfScores.reduce((a, b) => a + b) / secondHalfScores.length;

      final trend = secondHalfAvg - firstHalfAvg;

      result.add(EmotionMetrics(
        name: emotionName,
        averageScore: avgScore,
        maxScore: maxScore,
        highScoreCount: highScoreCount,
        veryHighScoreCount: veryHighScoreCount,
        firstHalfAverage: firstHalfAvg,
        secondHalfAverage: secondHalfAvg,
        trend: trend,
        appearanceDays: appearanceDays,
        allScores: scores,
      ));
    }

    // 按重要度排序
    result.sort((a, b) => b.importanceScore.compareTo(a.importanceScore));
    return result;
  }

  /// ============================================================
  /// 3-2. 計算睡眠指標
  /// ============================================================
  static SleepMetrics? _calculateSleepMetrics(List<DailyRecord> records) {
    final durations = <double>[];
    for (final record in records) {
      final duration = record.sleep.durationHours;
      if (duration != null && duration > 0) {
        durations.add(duration);
      }
    }

    if (durations.isEmpty) {
      debugPrint('⚠️ 沒有睡眠數據');
      return null;
    }

    final average = durations.reduce((a, b) => a + b) / durations.length;
    final min = durations.reduce((a, b) => a < b ? a : b);
    final max = durations.reduce((a, b) => a > b ? a : b);
    final shortSleepDays = durations.where((d) => d < 5).length;

    // 計算標準差
    final variance = durations.map((d) => (d - average) * (d - average)).reduce((a, b) => a + b) /
        durations.length;
    final stdDev = math.sqrt(variance);

    // 判斷波動級別
    String volatilityLevel;
    if (stdDev < 1.0) {
      volatilityLevel = '小';
    } else if (stdDev < 2.0) {
      volatilityLevel = '中';
    } else {
      volatilityLevel = '大';
    }

    return SleepMetrics(
      averageDuration: average,
      minDuration: min,
      maxDuration: max,
      shortSleepDays: shortSleepDays,
      standardDeviation: stdDev,
      volatilityLevel: volatilityLevel,
      allDurations: durations,
      recordedDays: durations.length,
    );
  }

  /// ============================================================
  /// 3-3. 計算症狀指標
  /// ============================================================
  static List<SymptomMetrics> _calculateSymptomMetrics(
    List<DailyRecord> records,
    List<EmotionMetrics> emotionMetrics,
  ) {
    // 建立症狀評分映射
    final symptomScores = <String, List<int>>{};
    final symptomDates = <String, Set<int>>{};

    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      for (final symptom in record.symptoms) {
        // 假設症狀格式為 "symptomName:score" 或純 symptomName（分數為0）
        late String symptomName;
        late int score;

        if (symptom.contains(':')) {
          final parts = symptom.split(':');
          symptomName = parts[0];
          score = int.tryParse(parts[1]) ?? 0;
        } else {
          symptomName = symptom;
          score = 0;
        }

        symptomScores.putIfAbsent(symptomName, () => []).add(score);
        symptomDates.putIfAbsent(symptomName, () => {}).add(i);
      }
    }

    if (symptomScores.isEmpty) {
      debugPrint('⚠️ 沒有症狀數據');
      return [];
    }

    // 計算每個症狀的指標
    final result = <SymptomMetrics>[];

    for (final symptomName in symptomScores.keys) {
      final scores = symptomScores[symptomName]!;
      final highScoreCount = scores.where((s) => s >= 7).length;
      final appearanceDays = scores.length;
      final avgScore = scores.isEmpty ? 0.0 : scores.reduce((a, b) => a + b) / scores.length;

      // 計算與情緒≥7的重疊天數
      int overlapCount = 0;
      final symptomDaySet = symptomDates[symptomName] ?? {};

      for (final emotionMetric in emotionMetrics) {
        if (emotionMetric.highScoreCount > 0) {
          // 找出該情緒出現在第幾天
          for (int i = 0; i < records.length; i++) {
            final emotion = records[i].emotions
                .firstWhereOrNull((e) => e.name == emotionMetric.name);
            if (emotion != null && emotion.value! >= 7) {
              // 檢查是否在症狀日期的 ±1 日內
              if (symptomDaySet.contains(i) ||
                  symptomDaySet.contains(i - 1) ||
                  symptomDaySet.contains(i + 1)) {
                overlapCount++;
              }
            }
          }
        }
      }

      final overlapPercentage = highScoreCount > 0 ? (overlapCount / highScoreCount) * 100 : 0.0;

      result.add(SymptomMetrics(
        name: symptomName,
        highScoreCount: highScoreCount,
        emotionOverlapCount: overlapCount,
        overlapPercentage: overlapPercentage,
        allScores: scores,
        appearanceDays: appearanceDays,
        averageScore: avgScore,
      ));
    }

    // 按頻率排序
    result.sort((a, b) => b.highScoreCount.compareTo(a.highScoreCount));
    return result;
  }

  /// ============================================================
  /// 3-4. 計算文字分析指標（統計+分類）
  /// ============================================================
  static DiaryTextMetrics? _calculateTextMetrics(List<DailyRecord> records) {
    // 蒐集所有日記文本
    final allTexts = <String>[];
    for (final record in records) {
      // 假設有日記內容在某處（需要根據實際模型調整）
      // 這裡為示例，實際需要從日記模型中獲取
    }

    if (allTexts.isEmpty) {
      debugPrint('⚠️ 沒有日記數據');
      return null;
    }

    // 簡單的詞頻統計（實際應使用更複雜的分詞）
    final sleepRelated = _extractKeywords(allTexts, _sleepKeywords);
    final physicalDiscomfort = _extractKeywords(allTexts, _physicalKeywords);
    final rumination = _extractKeywords(allTexts, _ruminationKeywords);
    final emotionDescription = _extractKeywords(allTexts, _emotionKeywords);

    // 判斷是否有集中主題
    final allCounts = <String, int>{};
    allCounts.addAll(sleepRelated);
    allCounts.addAll(physicalDiscomfort);
    allCounts.addAll(rumination);
    allCounts.addAll(emotionDescription);

    String? primaryTheme;
    int maxCount = 0;

    if (sleepRelated.isNotEmpty) {
      final max = sleepRelated.values.reduce((a, b) => a > b ? a : b);
      if (max > maxCount) {
        maxCount = max;
        primaryTheme = 'sleep';
      }
    }
    if (physicalDiscomfort.isNotEmpty) {
      final max = physicalDiscomfort.values.reduce((a, b) => a > b ? a : b);
      if (max > maxCount) {
        maxCount = max;
        primaryTheme = 'physical';
      }
    }
    if (rumination.isNotEmpty) {
      final max = rumination.values.reduce((a, b) => a > b ? a : b);
      if (max > maxCount) {
        maxCount = max;
        primaryTheme = 'rumination';
      }
    }

    final topKeywordEntry =
        allCounts.entries.reduce((a, b) => a.value > b.value ? a : b);

    return DiaryTextMetrics(
      categorizedKeywords: {
        'sleep': sleepRelated,
        'physical': physicalDiscomfort,
        'rumination': rumination,
        'emotion': emotionDescription,
      },
      sleepRelated: sleepRelated,
      physicalDiscomfort: physicalDiscomfort,
      rumination: rumination,
      emotionDescription: emotionDescription,
      hasConcentratedTheme: maxCount >= 5,
      primaryTheme: primaryTheme,
      topKeyword: topKeywordEntry.key,
      topKeywordCount: topKeywordEntry.value,
    );
  }

  /// 提取關鍵詞
  static Map<String, int> _extractKeywords(
    List<String> texts,
    List<String> keywords,
  ) {
    final result = <String, int>{};

    for (final text in texts) {
      final lowerText = text.toLowerCase();
      for (final keyword in keywords) {
        if (lowerText.contains(keyword)) {
          result[keyword] = (result[keyword] ?? 0) + 1;
        }
      }
    }

    return result;
  }

  /// ============================================================
  /// 3-5. 計算情緒×睡眠關聯
  /// ============================================================
  static EmotionSleepCorrelation? _calculateEmotionSleepCorrelation(
    List<EmotionMetrics> emotionMetrics,
    SleepMetrics? sleepMetrics,
    List<DailyRecord> records,
  ) {
    if (sleepMetrics == null || emotionMetrics.isEmpty) {
      return null;
    }

    // 計算短睡眠後隔日情緒變化
    double emotionChangeAfterShortSleep = 0.0;
    int countAfterShortSleep = 0;

    for (int i = 0; i < records.length - 1; i++) {
      final currentDuration = records[i].sleep.durationHours;
      final nextDuration = records[i + 1].sleep.durationHours;

      if (currentDuration != null && currentDuration < 5 && nextDuration != null) {
        // 計算隔日情緒變化
        double currentEmotionAvg = 0.0;
        double nextEmotionAvg = 0.0;

        if (records[i].emotions.isNotEmpty) {
          final values =
              records[i].emotions.where((e) => e.value != null && e.value! > 0).map((e) => e.value!);
          if (values.isNotEmpty) {
            currentEmotionAvg = values.reduce((a, b) => a + b) / values.length;
          }
        }

        if (records[i + 1].emotions.isNotEmpty) {
          final values = records[i + 1]
              .emotions
              .where((e) => e.value != null && e.value! > 0)
              .map((e) => e.value!);
          if (values.isNotEmpty) {
            nextEmotionAvg = values.reduce((a, b) => a + b) / values.length;
          }
        }

        emotionChangeAfterShortSleep += (nextEmotionAvg - currentEmotionAvg);
        countAfterShortSleep++;
      }
    }

    if (countAfterShortSleep > 0) {
      emotionChangeAfterShortSleep /= countAfterShortSleep;
    }

    final hasSignificant = sleepMetrics.shortSleepDays >= 6 &&
        emotionChangeAfterShortSleep >= 0.8;

    return EmotionSleepCorrelation(
      hasSignificantCorrelation: hasSignificant,
      emotionChangeAfterShortSleep: emotionChangeAfterShortSleep,
      shortSleepDays: sleepMetrics.shortSleepDays,
    );
  }

  /// ============================================================
  /// 選出 Top N 核心情緒
  /// ============================================================
  static List<EmotionMetrics> _selectTopEmotions(
    List<EmotionMetrics> emotions, {
    required int count,
  }) {
    if (emotions.length <= count) {
      return emotions;
    }
    return emotions.take(count).toList();
  }

  /// ============================================================
  /// 關鍵詞列表
  /// ============================================================
  static const List<String> _sleepKeywords = [
    '睡眠',
    '睡覺',
    '入睡',
    '失眠',
    '夜裡',
    '早醒',
    '半夜',
    '床上',
    '睡眠時間',
    '睡眠品質'
  ];

  static const List<String> _physicalKeywords = [
    '頭痛',
    '疼痛',
    '不適',
    '疲勞',
    '身體',
    '腸胃',
    '消化',
    '食慾',
    '虛弱',
    '乏力'
  ];

  static const List<String> _ruminationKeywords = [
    '反覆',
    '思考',
    '想到',
    '擔心',
    '緊張',
    '焦慮',
    '不安',
    '心煩',
    '腦子',
    '無法停止'
  ];

  static const List<String> _emotionKeywords = [
    '開心',
    '高興',
    '難過',
    '悲傷',
    '生氣',
    '憤怒',
    '沮喪',
    '失望',
    '害怕',
    '緊張',
    '放鬆',
    '平靜'
  ];
}

extension _FirstWhereOrNullExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
