import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/daily_record.dart';
import '../../models/period_cycle.dart';
import '../../utils/date_helper.dart';
import '../models/sleep_insight_models.dart';
import 'sleep_analysis_settings.dart';

class SleepAnalysisService {
  const SleepAnalysisService();

  SleepInsightResult analyze({
    required List<DailyRecord> records,
    required DateTime endDate,
    required SleepInsightPeriod period,
    List<PeriodCycle> periodCycles = const [],
    DateTime? startDate,
  }) {
    final end = _day(endDate);
    final sortedRecords = records
        .where((record) => !_day(record.date).isAfter(end))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final earliest =
        sortedRecords.isEmpty ? end : _day(sortedRecords.first.date);
    final days = period.days;
    final start = startDate == null
        ? (days == null
            ? earliest
            : end.subtract(Duration(days: math.max(0, days - 1))))
        : _day(startDate);
    final comparisonDays = end.difference(start).inDays + 1;

    final buildStart = days == null && startDate == null
        ? earliest
        : start.subtract(Duration(days: comparisonDays));
    final allPoints = _buildPoints(
      sortedRecords,
      buildStart,
      end,
      periodCycles,
    );
    final points = allPoints
        .where(
            (point) => !point.date.isBefore(start) && !point.date.isAfter(end))
        .toList();
    final summary = _summarize(points, end.difference(start).inDays + 1);

    SleepPeriodSummary? previousSummary;
    String? comparisonReason;
    if (days == null && startDate == null) {
      comparisonReason = '選擇「全部紀錄」時，沒有固定長度的上一個區間可比較。';
    } else {
      final previousEnd = start.subtract(const Duration(days: 1));
      final previousStart =
          previousEnd.subtract(Duration(days: comparisonDays - 1));
      final previousPoints = allPoints
          .where((point) =>
              !point.date.isBefore(previousStart) &&
              !point.date.isAfter(previousEnd))
          .toList();
      previousSummary = _summarize(previousPoints, comparisonDays);
      if (summary.validNightDays <
              SleepAnalysisSettings.minimumComparisonRecords ||
          previousSummary.validNightDays <
              SleepAnalysisSettings.minimumComparisonRecords) {
        comparisonReason = '目前有效紀錄不足，暫時無法進行可靠比較。';
      }
    }

    final comparison = SleepComparisonResult(
      isAvailable: comparisonReason == null,
      current: summary,
      previous: previousSummary,
      reason: comparisonReason,
    );
    final regularity = _regularity(points);
    final episodes = _episodes(points, allPoints);
    final association =
        _association(points, allPoints, summary.averageNightMinutes);
    final highlights = _highlights(points, summary, episodes);
    final narrative =
        _narrative(summary, comparison, regularity, episodes, association);

    return SleepInsightResult(
      startDate: start,
      endDate: end,
      points: points,
      summary: summary,
      comparison: comparison,
      regularity: regularity,
      episodes: episodes,
      association: association,
      highlights: highlights,
      narrative: narrative,
    );
  }

  List<SleepTrendPoint> _buildPoints(
    List<DailyRecord> records,
    DateTime start,
    DateTime end,
    List<PeriodCycle> cycles,
  ) {
    final grouped = <DateTime, List<DailyRecord>>{};
    for (final record in records) {
      (grouped[_day(record.date)] ??= []).add(record);
    }

    final points = <SleepTrendPoint>[];
    for (var date = start;
        !date.isAfter(end);
        date = date.add(const Duration(days: 1))) {
      final dayRecords = grouped[date] ?? const <DailyRecord>[];
      SleepData? primary;
      for (final record in dayRecords.reversed) {
        if (_hasSleepContent(record.sleep)) {
          primary = record.sleep;
          break;
        }
      }
      primary ??= dayRecords.isEmpty ? null : dayRecords.last.sleep;

      final naps = dayRecords.expand((record) => record.sleep.naps).toList();
      final validNaps = naps
          .where((nap) =>
              nap.durationMinutes > 0 &&
              nap.durationMinutes <=
                  SleepAnalysisSettings.maximumValidNapMinutes)
          .toList();
      final napMinutes =
          validNaps.fold<int>(0, (sum, nap) => sum + nap.durationMinutes);
      final sleepStart = primary?.effectiveSleepStart;
      final wake = primary?.finalWakeTime ?? primary?.wakeTime;
      final sleepWindowMinutes = _validNightMinutes(sleepStart, wake);
      final nightAwakeMinutes =
          primary == null || sleepStart == null || sleepWindowMinutes == null
              ? 0
              : _nightAwakeMinutes(
                  primary.nightAwakenings,
                  sleepStart,
                  sleepWindowMinutes,
                );
      final nightMinutes = sleepWindowMinutes == null
          ? null
          : math.max(0, sleepWindowMinutes - nightAwakeMinutes);
      final symptoms = dayRecords
          .expand((record) => record.symptoms)
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
      final emotions = dayRecords
          .expand((record) => record.emotions)
          .where((emotion) =>
              emotion.name.trim().isNotEmpty && emotion.value != null)
          .map((emotion) => emotion.name.trim())
          .toSet()
          .toList();
      final moodValues = dayRecords
          .map((record) => record.overallMood)
          .whereType<double>()
          .toList();

      points.add(SleepTrendPoint(
        date: date,
        nightMinutes: nightMinutes,
        sleepWindowMinutes: sleepWindowMinutes,
        nightAwakeMinutes: nightAwakeMinutes,
        napMinutes: napMinutes,
        napCount: validNaps.length,
        quality: primary?.quality,
        bedTime: primary?.sleepTime,
        sleepStartTime: sleepStart,
        wakeTime: wake,
        overallMood: moodValues.isEmpty ? null : _average(moodValues),
        flags:
            dayRecords.expand((record) => record.sleep.flags).toSet().toList(),
        symptoms: symptoms,
        emotions: emotions,
        isPeriod: cycles.any((cycle) => cycle.containsDate(date)) ||
            (cycles.isEmpty && dayRecords.any((record) => record.isPeriod)),
        usedEstimatedSleepTime: primary?.estimatedSleepTime != null,
        hasSleepRecord:
            dayRecords.any((record) => _hasSleepContent(record.sleep)),
        tookHypnotic: dayRecords.any((record) => record.sleep.tookHypnotic),
        hasNightWakeRecord: dayRecords.any(
          (record) =>
              record.sleep.nightAwakenings.isNotEmpty ||
              record.sleep.midWakeList?.trim().isNotEmpty == true,
        ),
      ));
    }
    return points;
  }

  SleepPeriodSummary _summarize(List<SleepTrendPoint> points, int periodDays) {
    final nights =
        points.map((point) => point.nightMinutes).whereType<int>().toList();
    final totals = points
        .where((point) => point.nightMinutes != null)
        .map((point) => point.totalMinutes)
        .whereType<int>()
        .where((value) => value > 0)
        .toList();
    final qualities =
        points.map((point) => point.quality).whereType<int>().toList();
    final napPoints = points.where((point) => point.napMinutes > 0).toList();
    final napCount = points.fold<int>(0, (sum, point) => sum + point.napCount);
    final bedtimes = points
        .map((point) => point.sleepStartTime)
        .whereType<TimeOfDay>()
        .map(_nightClockMinutes)
        .toList()
      ..sort();
    final wakes = points
        .map((point) => point.wakeTime)
        .whereType<TimeOfDay>()
        .map(_clockMinutes)
        .toList();
    final sleepFlagCounts = <String, int>{};
    for (final point in points) {
      for (final flag in point.flags.toSet()) {
        final normalized = flag.trim();
        if (normalized.isNotEmpty) {
          sleepFlagCounts[normalized] = (sleepFlagCounts[normalized] ?? 0) + 1;
        }
      }
    }

    return SleepPeriodSummary(
      periodDays: math.max(0, periodDays),
      recordDays: points.where((point) => point.hasSleepRecord).length,
      validNightDays: nights.length,
      napDays: napPoints.length,
      napCount: napCount,
      hypnoticDays: points.where((point) => point.tookHypnotic).length,
      qualityDays: qualities.length,
      averageNightMinutes: nights.isEmpty ? null : _averageInts(nights),
      averageTotalMinutes: totals.isEmpty ? null : _averageInts(totals),
      averageQuality: qualities.isEmpty ? null : _averageInts(qualities),
      shortestNightMinutes: nights.isEmpty ? null : nights.reduce(math.min),
      longestNightMinutes: nights.isEmpty ? null : nights.reduce(math.max),
      averageNapMinutes: napCount == 0
          ? null
          : napPoints.fold<int>(0, (sum, point) => sum + point.napMinutes) /
              napCount,
      averageBedtimeMinutes: bedtimes.isEmpty ? null : _average(bedtimes),
      averageWakeMinutes: wakes.isEmpty ? null : _average(wakes),
      explicitBedtimeDays: points
          .where((point) =>
              point.sleepStartTime != null && !point.usedEstimatedSleepTime)
          .length,
      estimatedBedtimeDays: points
          .where((point) =>
              point.sleepStartTime != null && point.usedEstimatedSleepTime)
          .length,
      usableBedtimeDays: bedtimes.length,
      typicalBedtime: _bedtimeFromMinutes(_median(bedtimes)),
      earliestBedtime:
          _bedtimeFromMinutes(bedtimes.isEmpty ? null : bedtimes.first),
      latestBedtime:
          _bedtimeFromMinutes(bedtimes.isEmpty ? null : bedtimes.last),
      sleepFlagCounts: Map.unmodifiable(sleepFlagCounts),
    );
  }

  SleepRegularityResult _regularity(List<SleepTrendPoint> points) {
    final nights = points
        .map((point) => point.nightMinutes)
        .whereType<int>()
        .map((value) => value.toDouble())
        .toList();
    final bedtimes = points
        .map((point) => point.sleepStartTime)
        .whereType<TimeOfDay>()
        .map(_nightClockMinutes)
        .toList();
    final wakes = points
        .map((point) => point.wakeTime)
        .whereType<TimeOfDay>()
        .map(_clockMinutes)
        .toList();
    if (nights.length < SleepAnalysisSettings.minimumRegularityRecords) {
      return const SleepRegularityResult(
        isAvailable: false,
        label: '資料不足',
      );
    }
    final durationMad = _meanAbsoluteDeviation(nights);
    final bedtimeMad =
        bedtimes.length < 2 ? null : _meanAbsoluteDeviation(_unwrap(bedtimes));
    final wakeMad =
        wakes.length < 2 ? null : _meanAbsoluteDeviation(_unwrap(wakes));
    final large = durationMad >=
            SleepAnalysisSettings.largeDurationVariationMinutes ||
        (bedtimeMad ?? 0) >= SleepAnalysisSettings.largeClockVariationMinutes ||
        (wakeMad ?? 0) >= SleepAnalysisSettings.largeClockVariationMinutes;
    final stable = durationMad <=
            SleepAnalysisSettings.stableDurationVariationMinutes &&
        (bedtimeMad == null ||
            bedtimeMad <= SleepAnalysisSettings.stableClockVariationMinutes) &&
        (wakeMad == null ||
            wakeMad <= SleepAnalysisSettings.stableClockVariationMinutes);
    return SleepRegularityResult(
      isAvailable: true,
      label: large ? '波動較大' : (stable ? '相對穩定' : '略有波動'),
      durationVariationMinutes: durationMad,
      bedtimeVariationMinutes: bedtimeMad,
      wakeVariationMinutes: wakeMad,
    );
  }

  List<SleepChangeEpisode> _episodes(
    List<SleepTrendPoint> selected,
    List<SleepTrendPoint> all,
  ) {
    final valid =
        selected.where((point) => point.nightMinutes != null).toList();
    final result = <SleepChangeEpisode>[];
    _appendMonotonicEpisodes(valid, result, increasing: false);
    _appendMonotonicEpisodes(valid, result, increasing: true);

    var belowRun = <SleepTrendPoint>[];
    for (final point in valid) {
      final baseline = all
          .where((candidate) =>
              candidate.nightMinutes != null &&
              candidate.date.isBefore(point.date) &&
              !candidate.date
                  .isBefore(point.date.subtract(const Duration(days: 30))))
          .map((candidate) => candidate.nightMinutes!)
          .toList();
      final below = baseline.length >= 3 &&
          point.nightMinutes! <=
              _averageInts(baseline) -
                  SleepAnalysisSettings.belowBaselineMinutes;
      if (below && (_isNextDay(belowRun.lastOrNull?.date, point.date))) {
        belowRun.add(point);
      } else {
        _appendBelowEpisode(belowRun, result, baseline);
        belowRun = below ? <SleepTrendPoint>[point] : <SleepTrendPoint>[];
      }
    }
    _appendBelowEpisode(belowRun, result, const []);

    for (var index = 1; index < valid.length; index++) {
      final previous = valid[index - 1];
      final current = valid[index];
      if (!_isNextDay(previous.date, current.date)) continue;
      final difference = current.nightMinutes! - previous.nightMinutes!;
      if (difference.abs() >= SleepAnalysisSettings.largeChangeMinutes) {
        result.add(SleepChangeEpisode(
          kind: SleepChangeKind.largeChange,
          startDate: previous.date,
          endDate: current.date,
          changeMinutes: difference,
        ));
      }
    }
    result.sort((a, b) => a.startDate.compareTo(b.startDate));
    return result;
  }

  void _appendMonotonicEpisodes(
    List<SleepTrendPoint> valid,
    List<SleepChangeEpisode> output, {
    required bool increasing,
  }) {
    var run = <SleepTrendPoint>[];
    for (final point in valid) {
      final continues = run.isNotEmpty &&
          _isNextDay(run.last.date, point.date) &&
          (increasing
              ? point.nightMinutes! > run.last.nightMinutes!
              : point.nightMinutes! < run.last.nightMinutes!);
      if (continues) {
        run.add(point);
      } else {
        _appendMonotonicRun(run, output, increasing);
        run = <SleepTrendPoint>[point];
      }
    }
    _appendMonotonicRun(run, output, increasing);
  }

  void _appendMonotonicRun(
    List<SleepTrendPoint> run,
    List<SleepChangeEpisode> output,
    bool increasing,
  ) {
    if (run.length < SleepAnalysisSettings.consecutiveDays) return;
    output.add(SleepChangeEpisode(
      kind:
          increasing ? SleepChangeKind.increasing : SleepChangeKind.decreasing,
      startDate: run.first.date,
      endDate: run.last.date,
      changeMinutes: run.last.nightMinutes! - run.first.nightMinutes!,
    ));
  }

  void _appendBelowEpisode(
    List<SleepTrendPoint> run,
    List<SleepChangeEpisode> output,
    List<int> baseline,
  ) {
    if (run.length < SleepAnalysisSettings.consecutiveDays) return;
    output.add(SleepChangeEpisode(
      kind: SleepChangeKind.belowBaseline,
      startDate: run.first.date,
      endDate: run.last.date,
      changeMinutes: baseline.isEmpty
          ? 0
          : (run.map((point) => point.nightMinutes!).reduce(math.min) -
                  _averageInts(baseline))
              .round(),
    ));
  }

  SleepStateAssociation _association(
    List<SleepTrendPoint> selected,
    List<SleepTrendPoint> all,
    double? averageNight,
  ) {
    if (averageNight == null) {
      return const SleepStateAssociation(
        lowSleepDays: 0,
        sameDayPairedDays: 0,
        nextDayPairedDays: 0,
        sameDayCounts: {},
        nextDayCounts: {},
        pairedDates: [],
      );
    }
    final byDate = {for (final point in all) point.date: point};
    final low = selected
        .where((point) =>
            point.nightMinutes != null && point.nightMinutes! < averageNight)
        .toList();
    final sameCounts = <String, int>{};
    final nextCounts = <String, int>{};
    var sameDays = 0;
    var nextDays = 0;
    final pairs = <SleepStatePair>[];
    for (final point in low) {
      final sameLabels = <String>{...point.symptoms, ...point.emotions};
      if (sameLabels.isNotEmpty) sameDays++;
      for (final label in sameLabels) {
        sameCounts[label] = (sameCounts[label] ?? 0) + 1;
      }
      final next = byDate[point.date.add(const Duration(days: 1))];
      final nextLabels = <String>{...?(next?.symptoms), ...?(next?.emotions)};
      if (nextLabels.isNotEmpty) nextDays++;
      for (final label in nextLabels) {
        nextCounts[label] = (nextCounts[label] ?? 0) + 1;
      }
      if (sameLabels.isNotEmpty || nextLabels.isNotEmpty) {
        pairs.add(SleepStatePair(
          date: point.date,
          nightMinutes: point.nightMinutes!,
          overallMood: point.overallMood,
          sameDayLabels: sameLabels.toList(),
          nextDayLabels: nextLabels.toList(),
          isPeriod: point.isPeriod,
        ));
      }
    }
    return SleepStateAssociation(
      lowSleepDays: low.length,
      sameDayPairedDays: sameDays,
      nextDayPairedDays: nextDays,
      sameDayCounts: _sortedCounts(sameCounts),
      nextDayCounts: _sortedCounts(nextCounts),
      pairedDates: pairs,
    );
  }

  List<SleepHighlightDate> _highlights(
    List<SleepTrendPoint> points,
    SleepPeriodSummary summary,
    List<SleepChangeEpisode> episodes,
  ) {
    final reasons = <DateTime, Set<String>>{};
    void add(DateTime date, String reason) =>
        (reasons[date] ??= <String>{}).add(reason);
    final valid = points.where((point) => point.nightMinutes != null).toList();
    if (valid.isNotEmpty) {
      final shortest =
          valid.reduce((a, b) => a.nightMinutes! <= b.nightMinutes! ? a : b);
      final longest =
          valid.reduce((a, b) => a.nightMinutes! >= b.nightMinutes! ? a : b);
      add(shortest.date, '本期最短夜眠');
      add(longest.date, '本期最長夜眠');
      if (summary.averageNightMinutes != null) {
        final furthest = valid.reduce((a, b) =>
            (a.nightMinutes! - summary.averageNightMinutes!).abs() >=
                    (b.nightMinutes! - summary.averageNightMinutes!).abs()
                ? a
                : b);
        add(furthest.date, '與個人平均差異較大');
      }
    }
    for (final point in points) {
      if (point.quality != null && point.quality! <= 2) {
        add(point.date, '睡眠品質較低');
      }
      if (point.tookHypnotic) add(point.date, '有安眠藥紀錄');
      if (point.symptoms.length >= 3) add(point.date, '同期症狀紀錄較多');
      if (point.hasNightWakeRecord ||
          point.flags
              .any((flag) => flag == 'fragmented' || flag == 'interrupted')) {
        add(point.date, '有夜間醒來或中斷紀錄');
      }
    }
    for (final episode
        in episodes.where((item) => item.kind != SleepChangeKind.largeChange)) {
      add(episode.startDate, '連續變化期間');
      add(episode.endDate, '連續變化期間');
    }
    final byDate = {for (final point in points) point.date: point};
    final result = reasons.entries.map((entry) {
      final point = byDate[entry.key];
      return SleepHighlightDate(
        date: entry.key,
        nightMinutes: point?.nightMinutes,
        reasons: entry.value.toList(),
        isPeriod: point?.isPeriod ?? false,
      );
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result.take(8).toList();
  }

  List<String> _narrative(
    SleepPeriodSummary summary,
    SleepComparisonResult comparison,
    SleepRegularityResult regularity,
    List<SleepChangeEpisode> episodes,
    SleepStateAssociation association,
  ) {
    if (summary.validNightDays < 3) {
      return [
        '目前共有 ${summary.validNightDays} 天有效夜間睡眠紀錄。',
        '持續紀錄後，系統才能提供較完整的趨勢與比較。',
      ];
    }
    final lines = <String>[
      '本期共記錄 ${summary.recordDays} 天睡眠，平均夜眠為 ${_duration(summary.averageNightMinutes)}。',
    ];
    if (comparison.isAvailable &&
        comparison.previous?.averageNightMinutes != null) {
      final delta = summary.averageNightMinutes! -
          comparison.previous!.averageNightMinutes!;
      lines.add(
          '與上一個等長區間相比，平均夜眠${delta.abs() < 10 ? '相近' : '${delta > 0 ? '增加' : '減少'} ${_duration(delta.abs())}'}。');
    }
    if (regularity.isAvailable) {
      lines.add('本期睡眠規律度呈現「${regularity.label}」。');
    } else if (episodes.isNotEmpty) {
      lines.add('本期有 ${episodes.length} 段值得一起回顧的連續變化。');
    }
    if (association.sameDayPairedDays >= 2 &&
        association.sameDayCounts.isNotEmpty) {
      lines.add(
          '夜眠低於本期平均的日期中，較常同日記錄${association.sameDayCounts.keys.take(2).join('與')}。');
    }
    lines.add('以上僅為個人紀錄整理，不代表診斷或醫療判斷。');
    return lines.take(4).toList();
  }

  bool _hasSleepContent(SleepData sleep) =>
      sleep.sleepTime != null ||
      sleep.estimatedSleepTime != null ||
      sleep.wakeTime != null ||
      sleep.finalWakeTime != null ||
      sleep.quality != null ||
      sleep.flags.isNotEmpty ||
      sleep.naps.isNotEmpty ||
      sleep.nightAwakenings.isNotEmpty ||
      sleep.tookHypnotic ||
      sleep.midWakeList?.trim().isNotEmpty == true ||
      sleep.note?.trim().isNotEmpty == true;

  int? _validNightMinutes(TimeOfDay? start, TimeOfDay? end) {
    if (start == null || end == null) return null;
    final minutes = DateHelper.calcDurationMinutes(start, end);
    if (minutes <= 0 ||
        minutes > SleepAnalysisSettings.maximumValidNightMinutes) {
      return null;
    }
    return minutes;
  }

  int _nightAwakeMinutes(
    List<NightAwakeningItem> awakenings,
    TimeOfDay sleepStart,
    int sleepWindowMinutes,
  ) {
    final intervals = <(int, int)>[];
    final anchor = sleepStart.hour * 60 + sleepStart.minute;

    int offset(TimeOfDay time) {
      var value = time.hour * 60 + time.minute - anchor;
      if (value < 0) value += 24 * 60;
      return value;
    }

    for (final awakening in awakenings) {
      final start = offset(awakening.start);
      int? end;
      if (awakening.end != null) {
        end = offset(awakening.end!);
        if (end <= start) end += 24 * 60;
      } else if (awakening.estimatedDurationMinutes != null &&
          awakening.estimatedDurationMinutes! > 0) {
        end = start + awakening.estimatedDurationMinutes!;
      }
      if (end != null &&
          end - start >
              SleepAnalysisSettings.maximumValidNightAwakeningMinutes) {
        continue;
      }
      if (end == null || start >= sleepWindowMinutes || end <= 0) continue;
      final clampedStart = start.clamp(0, sleepWindowMinutes).toInt();
      final clampedEnd = end.clamp(0, sleepWindowMinutes).toInt();
      if (clampedEnd > clampedStart) {
        intervals.add((clampedStart, clampedEnd));
      }
    }

    intervals.sort((a, b) => a.$1.compareTo(b.$1));
    var total = 0;
    int? mergedStart;
    int? mergedEnd;
    for (final interval in intervals) {
      if (mergedStart == null) {
        mergedStart = interval.$1;
        mergedEnd = interval.$2;
      } else if (interval.$1 <= mergedEnd!) {
        mergedEnd = math.max(mergedEnd, interval.$2);
      } else {
        total += mergedEnd - mergedStart;
        mergedStart = interval.$1;
        mergedEnd = interval.$2;
      }
    }
    if (mergedStart != null) total += mergedEnd! - mergedStart;
    return total;
  }

  DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
  bool _isNextDay(DateTime? previous, DateTime current) =>
      previous != null && current.difference(previous).inDays == 1;
  double _clockMinutes(TimeOfDay time) =>
      (time.hour * 60 + time.minute).toDouble();
  double _nightClockMinutes(TimeOfDay time) {
    final minutes = _clockMinutes(time);
    return minutes < 12 * 60 ? minutes + 24 * 60 : minutes;
  }

  double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  TimeOfDay? _bedtimeFromMinutes(double? adjustedMinutes) {
    if (adjustedMinutes == null || !adjustedMinutes.isFinite) return null;
    final rounded = adjustedMinutes.round() % (24 * 60);
    return TimeOfDay(hour: rounded ~/ 60, minute: rounded % 60);
  }

  List<double> _unwrap(List<double> values) {
    if (values.isEmpty) return const [];
    final anchor = values.first;
    return values.map((value) {
      var adjusted = value;
      while (adjusted - anchor > 720) {
        adjusted -= 1440;
      }
      while (adjusted - anchor < -720) {
        adjusted += 1440;
      }
      return adjusted;
    }).toList();
  }

  double _average(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;
  double _averageInts(List<int> values) =>
      values.reduce((a, b) => a + b) / values.length;
  double _meanAbsoluteDeviation(List<double> values) {
    final average = _average(values);
    return values
            .map((value) => (value - average).abs())
            .reduce((a, b) => a + b) /
        values.length;
  }

  Map<String, int> _sortedCounts(Map<String, int> counts) {
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount == 0 ? a.key.compareTo(b.key) : byCount;
      });
    return {for (final entry in entries) entry.key: entry.value};
  }

  String _duration(double? minutes) {
    if (minutes == null) return '資料不足';
    return DateHelper.formatDurationText(minutes.round());
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
