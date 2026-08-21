import '../models/daily_record.dart';
import '../models/daily_health_aggregate.dart';
import '../services/daily_health_aggregation_service.dart';

enum DailyEmotionMainSource {
  dailyCheckIn,
  dailyRecord,
  quickRecordFallback,
}

List<DailyRecord> emotionTrendRecordsForScale(
  Iterable<DailyRecord> records,
  int scale,
) =>
    records.where((record) => record.moodScale == scale).toList();

List<String> newModeEmotionNames(
  Iterable<DailyHealthAggregate> aggregates,
) {
  final names = <String>{};
  for (final aggregate in aggregates) {
    for (final entry in aggregate.emotionDailyValues.entries) {
      if (entry.key == DailyHealthAggregationService.overallMoodKey) continue;
      if (entry.value.observations.any(
        (value) => value.source == DailyHealthValueSource.healthEvent,
      )) {
        names.add(entry.key);
      }
    }
  }
  return names.toList()..sort();
}

List<String> legacyEmotionNames(Iterable<DailyRecord> records) {
  final names = <String>{};
  for (final record in records) {
    for (final emotion in record.emotions) {
      if (emotion.name.trim().isNotEmpty && emotion.value != null) {
        names.add(emotion.name);
      }
    }
  }
  return names.toList()..sort();
}

bool hasLegacyTenPointEmotionData(
  Iterable<DailyRecord> records,
  String emotionName, {
  String overallMoodLabel = '整體情緒',
}) {
  return records.where((record) => record.moodScale == 10).any((record) {
    if (emotionName == overallMoodLabel) return record.overallMood != null;
    return record.emotions.any(
      (emotion) =>
          emotion.name == emotionName &&
          emotion.name.trim().isNotEmpty &&
          emotion.value != null,
    );
  });
}

class QuickRecordEmotionRange {
  const QuickRecordEmotionRange({
    required this.min,
    required this.max,
    required this.count,
  });

  final double min;
  final double max;
  final int count;

  bool get shouldDisplay => count >= 2;
}

class DailyEmotionValuePoint {
  const DailyEmotionValuePoint({
    required this.date,
    required this.emotionName,
    required this.mainValue,
    required this.scale,
    required this.source,
    this.quickRecordRange,
  });

  final DateTime date;
  final String emotionName;
  final double mainValue;
  final int scale;
  final DailyEmotionMainSource source;
  final QuickRecordEmotionRange? quickRecordRange;
}

class DailyEmotionAggregateCalculator {
  DailyEmotionAggregateCalculator._();

  static DailyEmotionValuePoint? calculateForEmotion(
    DailyHealthAggregate aggregate,
    String emotionName, {
    int scale = 5,
  }) {
    final summary = aggregate.emotionDailyValues[emotionName];
    if (summary == null) return null;

    List<DailyValueObservation> valuesFor(DailyHealthValueSource source) =>
        summary.observations
            .where((value) => value.source == source && value.scale == scale)
            .toList();

    final checkIns = valuesFor(DailyHealthValueSource.dailyCheckIn);
    final records = valuesFor(DailyHealthValueSource.dailyRecord);
    // QuickRecord is always a 1-5 value. It must never enter a 10-point trend.
    final events = scale == 5
        ? valuesFor(DailyHealthValueSource.healthEvent)
        : const <DailyValueObservation>[];

    final selected = checkIns.isNotEmpty
        ? checkIns
        : records.isNotEmpty
            ? records
            : events;
    if (selected.isEmpty) return null;

    final source = checkIns.isNotEmpty
        ? DailyEmotionMainSource.dailyCheckIn
        : records.isNotEmpty
            ? DailyEmotionMainSource.dailyRecord
            : DailyEmotionMainSource.quickRecordFallback;
    final mainValue = source == DailyEmotionMainSource.quickRecordFallback
        ? DailyValueSummary(events).median!
        : selected.fold<double>(0, (sum, value) => sum + value.value) /
            selected.length;

    QuickRecordEmotionRange? range;
    if (events.isNotEmpty) {
      final eventValues = events.map((value) => value.value).toList();
      range = QuickRecordEmotionRange(
        min: eventValues.reduce((a, b) => a < b ? a : b),
        max: eventValues.reduce((a, b) => a > b ? a : b),
        count: eventValues.length,
      );
    }

    return DailyEmotionValuePoint(
      date: aggregate.date,
      emotionName: emotionName,
      mainValue: mainValue,
      scale: scale,
      source: source,
      quickRecordRange: range,
    );
  }

  static DailyEmotionValuePoint? calculateNewModeForEmotion(
    DailyHealthAggregate aggregate,
    String emotionName,
  ) {
    final summary = aggregate.emotionDailyValues[emotionName];
    if (summary == null) return null;
    final isOverallMood =
        emotionName == DailyHealthAggregationService.overallMoodKey;
    final observations = summary.observations.where((value) {
      if (value.scale != 5) return false;
      return isOverallMood
          ? value.source == DailyHealthValueSource.dailyCheckIn
          : value.source == DailyHealthValueSource.healthEvent;
    }).toList();
    if (observations.isEmpty) return null;

    final source = isOverallMood
        ? DailyEmotionMainSource.dailyCheckIn
        : DailyEmotionMainSource.quickRecordFallback;
    final mainValue = isOverallMood
        ? observations.fold<double>(0, (sum, value) => sum + value.value) /
            observations.length
        : DailyValueSummary(observations).median!;
    final range = isOverallMood
        ? null
        : QuickRecordEmotionRange(
            min: observations.map((value) => value.value).reduce(
                  (left, right) => left < right ? left : right,
                ),
            max: observations.map((value) => value.value).reduce(
                  (left, right) => left > right ? left : right,
                ),
            count: observations.length,
          );
    return DailyEmotionValuePoint(
      date: aggregate.date,
      emotionName: emotionName,
      mainValue: mainValue,
      scale: 5,
      source: source,
      quickRecordRange: range,
    );
  }

  static List<DailyEmotionValuePoint> calculateNewMode(
    Iterable<DailyHealthAggregate> aggregates,
    String emotionName,
  ) {
    final points = aggregates
        .map((aggregate) => calculateNewModeForEmotion(aggregate, emotionName))
        .whereType<DailyEmotionValuePoint>()
        .toList()
      ..sort((left, right) => left.date.compareTo(right.date));
    return points;
  }

  static List<DailyEmotionValuePoint> calculate(
    Iterable<DailyHealthAggregate> aggregates,
    String emotionName, {
    int scale = 5,
  }) {
    final points = aggregates
        .map((aggregate) => calculateForEmotion(
              aggregate,
              emotionName,
              scale: scale,
            ))
        .whereType<DailyEmotionValuePoint>()
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  static double? averageMainValue(Iterable<DailyEmotionValuePoint> points) {
    final values = points.map((point) => point.mainValue).toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double? movingAverage(
    Iterable<DailyEmotionValuePoint> points,
    DateTime targetDate, {
    int windowDays = 7,
  }) {
    final day = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final start = day.subtract(Duration(days: windowDays - 1));
    return averageMainValue(points.where((point) {
      final pointDay =
          DateTime(point.date.year, point.date.month, point.date.day);
      return !pointDay.isBefore(start) && !pointDay.isAfter(day);
    }));
  }

  static int filledDaysInWindow(
    Iterable<DailyEmotionValuePoint> points,
    DateTime targetDate, {
    int windowDays = 7,
  }) {
    final day = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final start = day.subtract(Duration(days: windowDays - 1));
    return points.where((point) {
      final pointDay =
          DateTime(point.date.year, point.date.month, point.date.day);
      return !pointDay.isBefore(start) && !pointDay.isAfter(day);
    }).length;
  }
}

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

  static List<DailyEmotionTrendPoint> calculateAggregates(
    Iterable<DailyHealthAggregate> aggregates, {
    int scale = 5,
    bool newModeOnly = false,
  }) {
    final points = <DailyEmotionTrendPoint>[];
    for (final aggregate in aggregates) {
      var positiveTotal = 0.0;
      var negativeTotal = 0.0;
      var positiveCount = 0;
      var negativeCount = 0;
      var unknownCount = 0;

      for (final emotionName in aggregate.emotionDailyValues.keys) {
        if (emotionName == DailyHealthAggregationService.overallMoodKey) {
          continue;
        }
        final point = newModeOnly
            ? DailyEmotionAggregateCalculator.calculateNewModeForEmotion(
                aggregate,
                emotionName,
              )
            : DailyEmotionAggregateCalculator.calculateForEmotion(
                aggregate,
                emotionName,
                scale: scale,
              );
        if (point == null) continue;
        switch (EmotionClassificationSystem.classify(emotionName).valence) {
          case AffectValence.positive:
            positiveTotal += point.mainValue;
            positiveCount++;
            break;
          case AffectValence.negative:
            negativeTotal += point.mainValue;
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
      if (positiveAverage == null && negativeAverage == null) continue;
      points.add(DailyEmotionTrendPoint(
        date: aggregate.date,
        positiveAverage: positiveAverage,
        negativeAverage: negativeAverage,
        emotionBalance: (positiveAverage ?? 0) - (negativeAverage ?? 0),
        positiveCount: positiveCount,
        negativeCount: negativeCount,
        unknownCount: unknownCount,
      ));
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }
}
