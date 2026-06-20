import '../models/daily_record.dart';

enum BasicEmotionCategory {
  joy,
  disgust,
  sadness,
  fear,
  anger,
  dangerSignal,
  custom,
  unknown,
}

enum AffectValence {
  positive,
  negative,
  neutral,
  unknown,
}

class EmotionClassification {
  const EmotionClassification({
    required this.category,
    required this.valence,
  });

  final BasicEmotionCategory category;
  final AffectValence valence;
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

  /// Positive average minus negative average. Unknown emotions are not included.
  final double? emotionBalance;

  final int positiveCount;
  final int negativeCount;
  final int unknownCount;

  bool get hasClassifiedData =>
      positiveAverage != null || negativeAverage != null;
}

class EmotionClassificationSystem {
  EmotionClassificationSystem._();

  static const Set<String> joyNames = {
    '快樂',
    '興奮',
    '愉悅',
    '滿足',
    '自在',
    '平靜',
    '放鬆',
    '安心',
    '期待',
    '自信',
    '感恩',
    '幸福',
    '有希望'
  };

  static const Set<String> disgustNames = {'厭倦', '無聊', '反感', '煩悶', '排斥', '討厭'};

  static const Set<String> sadnessNames = {
    '低落',
    '憂鬱',
    '孤單',
    '絕望',
    '沮喪',
    '難過',
    '失落',
    '空虛',
    '無助',
    '麻木'
  };

  static const Set<String> fearNames = {
    '緊張',
    '擔心',
    '惶恐',
    '焦慮',
    '害怕',
    '警覺',
    '恐懼',
    '忐忑不安'
  };

  static const Set<String> angerNames = {
    '生氣',
    '憤怒',
    '暴躁',
    '忌妒',
    '煩躁',
    '不耐煩',
    '惱羞成怒'
  };

  static const Set<String> dangerSignalNames = {
    '自殺意念',
  };

  static EmotionClassification classify(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) {
      return const EmotionClassification(
        category: BasicEmotionCategory.unknown,
        valence: AffectValence.unknown,
      );
    }

    if (joyNames.contains(name)) {
      return const EmotionClassification(
        category: BasicEmotionCategory.joy,
        valence: AffectValence.positive,
      );
    }
    if (disgustNames.contains(name)) {
      return const EmotionClassification(
        category: BasicEmotionCategory.disgust,
        valence: AffectValence.negative,
      );
    }
    if (sadnessNames.contains(name)) {
      return const EmotionClassification(
        category: BasicEmotionCategory.sadness,
        valence: AffectValence.negative,
      );
    }
    if (fearNames.contains(name)) {
      return const EmotionClassification(
        category: BasicEmotionCategory.fear,
        valence: AffectValence.negative,
      );
    }
    if (angerNames.contains(name)) {
      return const EmotionClassification(
        category: BasicEmotionCategory.anger,
        valence: AffectValence.negative,
      );
    }
    if (dangerSignalNames.contains(name)) {
      return const EmotionClassification(
        category: BasicEmotionCategory.dangerSignal,
        valence: AffectValence.negative,
      );
    }

    return const EmotionClassification(
      category: BasicEmotionCategory.custom,
      valence: AffectValence.unknown,
    );
  }
}

class EmotionTrendCalculator {
  EmotionTrendCalculator._();

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

      final classification = EmotionClassificationSystem.classify(emotion.name);
      switch (classification.valence) {
        case AffectValence.positive:
          positiveTotal += value;
          positiveCount++;
          break;
        case AffectValence.negative:
          negativeTotal += value;
          negativeCount++;
          break;
        case AffectValence.neutral:
        case AffectValence.unknown:
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
