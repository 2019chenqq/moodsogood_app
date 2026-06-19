import '../models/daily_record.dart';

enum EmotionFeelingType {
  positive,
  negative,
  unknown,
}

class DailyEmotionTrendPoint {
  const DailyEmotionTrendPoint({
    required this.date,
    required this.positiveAverage,
    required this.negativeAverage,
    required this.emotionBalance,
    required this.positiveCount,
    required this.negativeCount,
    required this.unknownCount,
  });

  final DateTime date;
  final double? positiveAverage;
  final double? negativeAverage;
  final double? emotionBalance;
  final int positiveCount;
  final int negativeCount;
  final int unknownCount;

  bool get hasClassifiedData =>
      positiveAverage != null || negativeAverage != null;
}

class EmotionTrendCalculator {
  EmotionTrendCalculator._();

  static const Set<String> positiveEmotionNames = {
    '開心',
    '快樂',
    '平靜',
    '安心',
    '放鬆',
    '期待',
    '興奮',
    '滿足',
    '有希望',
    '感謝',
    '幸福',
    '愉快',
    '穩定',
    '有動力',
    '被支持',
    '自信',
  };

  static const Set<String> negativeEmotionNames = {
    '焦慮',
    '憂鬱',
    '低落',
    '難過',
    '悲傷',
    '煩躁',
    '憤怒',
    '生氣',
    '恐懼',
    '害怕',
    '緊張',
    '壓力',
    '疲憊',
    '空虛',
    '無助',
    '崩潰',
    '孤單',
    '麻木',
    '內疚',
    '羞愧',
    '自責',
    '絕望',
    '不安',
  };

  static EmotionFeelingType classify(String rawName) {
    final name = rawName.trim();
    if (positiveEmotionNames.contains(name)) {
      return EmotionFeelingType.positive;
    }
    if (negativeEmotionNames.contains(name)) {
      return EmotionFeelingType.negative;
    }
    return EmotionFeelingType.unknown;
  }

  static DailyEmotionTrendPoint calculateForRecord(DailyRecord record) {
    var positiveTotal = 0.0;
    var negativeTotal = 0.0;
    var positiveCount = 0;
    var negativeCount = 0;
    var unknownCount = 0;

    for (final emotion in record.emotions) {
      final value = emotion.value;
      if (value == null || value <= 0 || emotion.name.trim().isEmpty) {
        continue;
      }

      switch (classify(emotion.name)) {
        case EmotionFeelingType.positive:
          positiveTotal += value;
          positiveCount++;
          break;
        case EmotionFeelingType.negative:
          negativeTotal += value;
          negativeCount++;
          break;
        case EmotionFeelingType.unknown:
          unknownCount++;
          break;
      }
    }

    final positiveAverage =
        positiveCount == 0 ? null : positiveTotal / positiveCount;
    final negativeAverage =
        negativeCount == 0 ? null : negativeTotal / negativeCount;
    final emotionBalance = positiveAverage == null && negativeAverage == null
        ? null
        : (positiveAverage ?? 0) - (negativeAverage ?? 0);

    return DailyEmotionTrendPoint(
      date: DateTime(record.date.year, record.date.month, record.date.day),
      positiveAverage: positiveAverage,
      negativeAverage: negativeAverage,
      emotionBalance: emotionBalance,
      positiveCount: positiveCount,
      negativeCount: negativeCount,
      unknownCount: unknownCount,
    );
  }

  static List<DailyEmotionTrendPoint> calculate(List<DailyRecord> records) {
    final points = records.map(calculateForRecord).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return points;
  }
}
