import 'package:flutter/material.dart';

enum SleepInsightPeriod { sevenDays, thirtyDays, ninetyDays, all }

extension SleepInsightPeriodX on SleepInsightPeriod {
  int? get days => switch (this) {
        SleepInsightPeriod.sevenDays => 7,
        SleepInsightPeriod.thirtyDays => 30,
        SleepInsightPeriod.ninetyDays => 90,
        SleepInsightPeriod.all => null,
      };
}

class SleepTrendPoint {
  const SleepTrendPoint({
    required this.date,
    required this.napMinutes,
    required this.napCount,
    required this.flags,
    required this.symptoms,
    required this.emotions,
    required this.isPeriod,
    required this.usedEstimatedSleepTime,
    required this.hasSleepRecord,
    this.nightMinutes,
    this.sleepWindowMinutes,
    this.nightAwakeMinutes = 0,
    this.quality,
    this.bedTime,
    this.sleepStartTime,
    this.wakeTime,
    this.overallMood,
    this.tookHypnotic = false,
    this.hasNightWakeRecord = false,
  });

  final DateTime date;
  final int? nightMinutes;
  final int? sleepWindowMinutes;
  final int nightAwakeMinutes;
  final int napMinutes;
  final int napCount;
  final int? quality;
  final TimeOfDay? bedTime;
  final TimeOfDay? sleepStartTime;
  final TimeOfDay? wakeTime;
  final double? overallMood;
  final List<String> flags;
  final List<String> symptoms;
  final List<String> emotions;
  final bool isPeriod;
  final bool usedEstimatedSleepTime;
  final bool hasSleepRecord;
  final bool tookHypnotic;
  final bool hasNightWakeRecord;

  int? get totalMinutes => nightMinutes == null
      ? (napMinutes > 0 ? napMinutes : null)
      : nightMinutes! + napMinutes;
}

class SleepPeriodSummary {
  const SleepPeriodSummary({
    required this.periodDays,
    required this.recordDays,
    required this.validNightDays,
    required this.napDays,
    required this.napCount,
    required this.hypnoticDays,
    required this.qualityDays,
    required this.averageNightMinutes,
    required this.averageTotalMinutes,
    required this.averageQuality,
    required this.shortestNightMinutes,
    required this.longestNightMinutes,
    required this.averageNapMinutes,
    required this.averageBedtimeMinutes,
    required this.averageWakeMinutes,
    this.explicitBedtimeDays = 0,
    this.estimatedBedtimeDays = 0,
    this.usableBedtimeDays = 0,
    this.typicalBedtime,
    this.earliestBedtime,
    this.latestBedtime,
    this.sleepFlagCounts = const {},
  });

  final int periodDays;
  final int recordDays;
  final int validNightDays;
  final int napDays;
  final int napCount;
  final int hypnoticDays;
  final int qualityDays;
  final double? averageNightMinutes;
  final double? averageTotalMinutes;
  final double? averageQuality;
  final int? shortestNightMinutes;
  final int? longestNightMinutes;
  final double? averageNapMinutes;
  final double? averageBedtimeMinutes;
  final double? averageWakeMinutes;
  final int explicitBedtimeDays;
  final int estimatedBedtimeDays;
  final int usableBedtimeDays;
  final TimeOfDay? typicalBedtime;
  final TimeOfDay? earliestBedtime;
  final TimeOfDay? latestBedtime;
  final Map<String, int> sleepFlagCounts;

  double get completionRate => periodDays == 0 ? 0 : recordDays / periodDays;
}

class SleepComparisonResult {
  const SleepComparisonResult({
    required this.isAvailable,
    required this.current,
    this.previous,
    this.reason,
  });

  final bool isAvailable;
  final SleepPeriodSummary current;
  final SleepPeriodSummary? previous;
  final String? reason;
}

class SleepRegularityResult {
  const SleepRegularityResult({
    required this.isAvailable,
    required this.label,
    this.durationVariationMinutes,
    this.bedtimeVariationMinutes,
    this.wakeVariationMinutes,
  });

  final bool isAvailable;
  final String label;
  final double? durationVariationMinutes;
  final double? bedtimeVariationMinutes;
  final double? wakeVariationMinutes;
}

enum SleepChangeKind { decreasing, increasing, belowBaseline, largeChange }

class SleepChangeEpisode {
  const SleepChangeEpisode({
    required this.kind,
    required this.startDate,
    required this.endDate,
    required this.changeMinutes,
  });

  final SleepChangeKind kind;
  final DateTime startDate;
  final DateTime endDate;
  final int changeMinutes;
}

class SleepStateAssociation {
  const SleepStateAssociation({
    required this.lowSleepDays,
    required this.sameDayPairedDays,
    required this.nextDayPairedDays,
    required this.sameDayCounts,
    required this.nextDayCounts,
    required this.pairedDates,
  });

  final int lowSleepDays;
  final int sameDayPairedDays;
  final int nextDayPairedDays;
  final Map<String, int> sameDayCounts;
  final Map<String, int> nextDayCounts;
  final List<SleepStatePair> pairedDates;
}

class SleepStatePair {
  const SleepStatePair({
    required this.date,
    required this.nightMinutes,
    required this.sameDayLabels,
    required this.nextDayLabels,
    required this.isPeriod,
    this.overallMood,
  });

  final DateTime date;
  final int nightMinutes;
  final double? overallMood;
  final List<String> sameDayLabels;
  final List<String> nextDayLabels;
  final bool isPeriod;
}

class SleepHighlightDate {
  const SleepHighlightDate({
    required this.date,
    required this.nightMinutes,
    required this.reasons,
    required this.isPeriod,
  });

  final DateTime date;
  final int? nightMinutes;
  final List<String> reasons;
  final bool isPeriod;
}

class SleepInsightResult {
  const SleepInsightResult({
    required this.startDate,
    required this.endDate,
    required this.points,
    required this.summary,
    required this.comparison,
    required this.regularity,
    required this.episodes,
    required this.association,
    required this.highlights,
    required this.narrative,
  });

  final DateTime startDate;
  final DateTime endDate;
  final List<SleepTrendPoint> points;
  final SleepPeriodSummary summary;
  final SleepComparisonResult comparison;
  final SleepRegularityResult regularity;
  final List<SleepChangeEpisode> episodes;
  final SleepStateAssociation association;
  final List<SleepHighlightDate> highlights;
  final List<String> narrative;
}
