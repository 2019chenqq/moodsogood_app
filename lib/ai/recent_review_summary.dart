import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/daily_check_in.dart';
import '../models/daily_health_aggregate.dart';
import '../models/daily_record.dart';
import '../models/health_event.dart';
import '../models/period_cycle.dart';
import '../meds/med_symptom_compare_models.dart';
import '../services/daily_health_aggregation_service.dart';
import '../sleep_insights/models/sleep_insight_models.dart';
import '../sleep_insights/services/sleep_analysis_service.dart';
import '../utils/date_helper.dart';

class RecentReviewSummary {
  const RecentReviewSummary({
    required this.period,
    required this.sleep,
    required this.emotions,
    required this.symptoms,
    required this.states,
    required this.medications,
    required this.medicationChanges,
    required this.periodCycles,
    required this.evidence,
  });

  final RecentReviewPeriodSummary period;
  final RecentReviewSleepSummary sleep;
  final List<RecentReviewMetricSummary> emotions;
  final List<RecentReviewMetricSummary> symptoms;
  final RecentReviewStatesSummary states;
  final List<Map<String, dynamic>> medications;
  final List<Map<String, dynamic>> medicationChanges;
  final List<Map<String, dynamic>> periodCycles;
  final Map<String, List<Map<String, dynamic>>> evidence;

  Map<String, dynamic> toJson() => {
        'period': period.toJson(),
        'sleep': sleep.toJson(),
        'emotions': emotions.map((item) => item.toJson()).toList(),
        'symptoms': symptoms.map((item) => item.toJson()).toList(),
        'states': states.toJson(),
        'medications': medications,
        'medicationChanges': medicationChanges,
        'periodCycles': periodCycles,
      };

  Map<String, dynamic> evidenceToJson() => evidence;

  RecentReviewSummarySize get size => RecentReviewSummarySize.fromSummary(this);
}

class RecentReviewPeriodSummary {
  const RecentReviewPeriodSummary({
    required this.startDate,
    required this.endDate,
    required this.lookbackDays,
    required this.recordedDays,
  });

  final String startDate;
  final String endDate;
  final int lookbackDays;
  final int recordedDays;

  Map<String, dynamic> toJson() => {
        'startDate': startDate,
        'endDate': endDate,
        'lookbackDays': lookbackDays,
        'recordedDays': recordedDays,
      };
}

class RecentReviewSleepSummary {
  const RecentReviewSleepSummary({
    required this.recordedDays,
    required this.validNightSleepDays,
    required this.averageNightSleepMinutes,
    required this.averageAllDaySleepMinutes,
    required this.shortestNightSleepMinutes,
    required this.longestNightSleepMinutes,
    required this.sleepQualityRecordedDays,
    required this.averageSleepQuality,
    required this.napCount,
    required this.napDays,
    required this.averageNapMinutes,
    required this.sleepFlagCounts,
    required this.explicitBedtimeDays,
    required this.estimatedBedtimeDays,
    required this.usableBedtimeDays,
    required this.typicalBedtime,
    required this.earliestBedtime,
    required this.latestBedtime,
  });

  final int recordedDays;
  final int validNightSleepDays;
  final double? averageNightSleepMinutes;
  final double? averageAllDaySleepMinutes;
  final int? shortestNightSleepMinutes;
  final int? longestNightSleepMinutes;
  final int sleepQualityRecordedDays;
  final double? averageSleepQuality;
  final int napCount;
  final int napDays;
  final double? averageNapMinutes;
  final Map<String, int> sleepFlagCounts;
  final int explicitBedtimeDays;
  final int estimatedBedtimeDays;
  final int usableBedtimeDays;
  final String? typicalBedtime;
  final String? earliestBedtime;
  final String? latestBedtime;

  double? get averageNightSleepHours =>
      _minutesToHours(averageNightSleepMinutes);
  double? get averageAllDaySleepHours =>
      _minutesToHours(averageAllDaySleepMinutes);
  double? get averageNapHours => _minutesToHours(averageNapMinutes);
  double? get shortestNightSleepHours =>
      _minutesToHours(shortestNightSleepMinutes);
  double? get longestNightSleepHours =>
      _minutesToHours(longestNightSleepMinutes);

  Map<String, dynamic> toJson() => {
        'recordedDays': recordedDays,
        'validNightSleepDays': validNightSleepDays,
        'averageNightSleepHours': averageNightSleepHours,
        'averageAllDaySleepHours': averageAllDaySleepHours,
        'shortestNightSleepHours': shortestNightSleepHours,
        'longestNightSleepHours': longestNightSleepHours,
        'sleepQualityRecordedDays': sleepQualityRecordedDays,
        'averageSleepQuality': averageSleepQuality,
        'napCount': napCount,
        'napDays': napDays,
        'averageNapHours': averageNapHours,
        'sleepFlagCounts': sleepFlagCounts,
        'explicitBedtimeDays': explicitBedtimeDays,
        'estimatedBedtimeDays': estimatedBedtimeDays,
        'usableBedtimeDays': usableBedtimeDays,
        'typicalBedtime': typicalBedtime,
        'earliestBedtime': earliestBedtime,
        'latestBedtime': latestBedtime,
      };
}

double? _minutesToHours(num? minutes) =>
    minutes == null ? null : (minutes / 6).round() / 10;

class RecentReviewMetricSummary {
  const RecentReviewMetricSummary({
    required this.name,
    required this.occurrenceDays,
    required this.averageIntensity,
    required this.maxIntensity,
  });

  final String name;
  final int occurrenceDays;
  final double? averageIntensity;
  final double? maxIntensity;

  Map<String, dynamic> toJson() => {
        'name': name,
        'occurrenceDays': occurrenceDays,
        'averageIntensity': averageIntensity,
        'maxIntensity': maxIntensity,
      };
}

class RecentReviewStatesSummary {
  const RecentReviewStatesSummary({
    required this.energy,
    required this.appetite,
    required this.activity,
  });

  final double? energy;
  final double? appetite;
  final double? activity;

  Map<String, dynamic> toJson() => {
        'energy': energy,
        'appetite': appetite,
        'activity': activity,
      };
}

class RecentReviewSummarySize {
  const RecentReviewSummarySize({
    required this.totalCharacters,
    required this.sleepCharacters,
    required this.emotionCharacters,
    required this.symptomCharacters,
    required this.medicationCharacters,
    required this.medicationChangeCharacters,
    required this.periodCharacters,
  });

  factory RecentReviewSummarySize.fromSummary(RecentReviewSummary summary) {
    int sizeOf(Object? value) => jsonEncode(value).length;
    final json = summary.toJson();
    return RecentReviewSummarySize(
      totalCharacters: sizeOf(json),
      sleepCharacters: sizeOf(json['sleep']),
      emotionCharacters: sizeOf(json['emotions']),
      symptomCharacters: sizeOf(json['symptoms']),
      medicationCharacters: sizeOf(json['medications']),
      medicationChangeCharacters: sizeOf(json['medicationChanges']),
      periodCharacters: sizeOf({
        'period': json['period'],
        'periodCycles': json['periodCycles'],
      }),
    );
  }

  final int totalCharacters;
  final int sleepCharacters;
  final int emotionCharacters;
  final int symptomCharacters;
  final int medicationCharacters;
  final int medicationChangeCharacters;
  final int periodCharacters;

  Map<String, int> toJson() => {
        'totalCharacters': totalCharacters,
        'sleepCharacters': sleepCharacters,
        'emotionCharacters': emotionCharacters,
        'symptomCharacters': symptomCharacters,
        'medicationCharacters': medicationCharacters,
        'medicationChangeCharacters': medicationChangeCharacters,
        'periodCharacters': periodCharacters,
      };
}

class RecentReviewSummaryBuilder {
  const RecentReviewSummaryBuilder({
    this.aggregationService = const DailyHealthAggregationService(),
  });

  final DailyHealthAggregationService aggregationService;

  RecentReviewSummary build({
    required DateTime startDate,
    required DateTime endDate,
    Iterable<DailyRecord> dailyRecords = const [],
    Iterable<HealthEvent> healthEvents = const [],
    Iterable<DailyCheckIn> dailyCheckIns = const [],
    Iterable<Map<String, dynamic>> activeMedications = const [],
    Iterable<Map<String, dynamic>> medicationAdjustments = const [],
    Iterable<PeriodCycle> periodCycles = const [],
  }) {
    final start = _day(startDate);
    final end = _day(endDate);
    if (end.isBefore(start)) {
      throw ArgumentError.value(
          endDate, 'endDate', 'must not precede startDate');
    }
    final records = dailyRecords
        .where((record) => _within(record.date, start, end))
        .toList();
    final events = healthEvents
        .where((event) => _within(event.timestamp, start, end))
        .toList();
    final checkIns = dailyCheckIns
        .where((checkIn) => _within(checkIn.date, start, end))
        .toList();
    final aggregates = aggregationService.aggregateRange(
      dailyRecords: records,
      healthEvents: events,
      dailyCheckIns: checkIns,
      start: start,
      endExclusive: end.add(const Duration(days: 1)),
    );
    final cycles = periodCycles.toList();
    final sleepAnalysis = const SleepAnalysisService().analyze(
      records: records,
      endDate: end,
      startDate: start,
      period: SleepInsightPeriod.thirtyDays,
      periodCycles: cycles,
    );
    final medicationChanges =
        medicationAdjustments.expand(_medicationChanges).toList();
    final recentPeriodCycles = cycles
        .where((cycle) =>
            !cycle.startDate.isAfter(end) &&
            (cycle.endDate == null || !cycle.endDate!.isBefore(start)))
        .map(
          (cycle) => {
            'startDate': _date(cycle.startDate),
            'endDate': cycle.endDate == null ? null : _date(cycle.endDate!),
          },
        )
        .toList();

    final summary = RecentReviewSummary(
      period: RecentReviewPeriodSummary(
        startDate: _date(start),
        endDate: _date(end),
        lookbackDays: end.difference(start).inDays + 1,
        recordedDays: aggregationService.recordedDayCount(aggregates),
      ),
      sleep: _sleep(sleepAnalysis.summary),
      emotions: _emotions(aggregates),
      symptoms: aggregationService
          .allSymptomStatistics(aggregates)
          .map(
            (item) => RecentReviewMetricSummary(
              name: item.name,
              occurrenceDays: item.occurrenceDays,
              averageIntensity: _oneDecimal(item.averageSeverity),
              maxIntensity: item.maxSeverity?.toDouble(),
            ),
          )
          .toList(),
      states: RecentReviewStatesSummary(
        energy: _stateAverage(aggregates, 'energy_change'),
        appetite: _stateAverage(aggregates, 'appetite_change'),
        activity: _stateAverage(aggregates, 'activity_change'),
      ),
      medications: activeMedications.map(_medication).toList(),
      medicationChanges: medicationChanges,
      periodCycles: recentPeriodCycles,
      evidence: {
        'sleep': _sleepEvidence(sleepAnalysis.points),
        'emotion': _emotionEvidence(records, events),
        'symptom': _symptomEvidence(records, events),
        'medication': _recentMaps(medicationChanges, dateKey: 'date'),
        'period': _recentMaps(recentPeriodCycles, dateKey: 'startDate'),
      },
    );
    debugPrint('RecentReviewSummary size ${summary.size.toJson()}');
    debugPrint('RecentReviewEvidence size ${_evidenceSize(summary.evidence)}');
    return summary;
  }

  static RecentReviewSleepSummary _sleep(SleepPeriodSummary sleep) {
    return RecentReviewSleepSummary(
      recordedDays: sleep.recordDays,
      validNightSleepDays: sleep.validNightDays,
      averageNightSleepMinutes: _oneDecimal(sleep.averageNightMinutes),
      averageAllDaySleepMinutes: _oneDecimal(sleep.averageTotalMinutes),
      shortestNightSleepMinutes: sleep.shortestNightMinutes,
      longestNightSleepMinutes: sleep.longestNightMinutes,
      sleepQualityRecordedDays: sleep.qualityDays,
      averageSleepQuality: _oneDecimal(sleep.averageQuality),
      napCount: sleep.napCount,
      napDays: sleep.napDays,
      averageNapMinutes: _oneDecimal(sleep.averageNapMinutes),
      sleepFlagCounts: sleep.sleepFlagCounts,
      explicitBedtimeDays: sleep.explicitBedtimeDays,
      estimatedBedtimeDays: sleep.estimatedBedtimeDays,
      usableBedtimeDays: sleep.usableBedtimeDays,
      typicalBedtime: _formatTime(sleep.typicalBedtime),
      earliestBedtime: _formatTime(sleep.earliestBedtime),
      latestBedtime: _formatTime(sleep.latestBedtime),
    );
  }

  static List<Map<String, dynamic>> _sleepEvidence(
    List<SleepTrendPoint> points,
  ) {
    final candidates = points.where((point) => point.hasSleepRecord).toList()
      ..sort((left, right) {
        int score(SleepTrendPoint point) =>
            (point.flags.isNotEmpty ? 2 : 0) +
            (point.nightMinutes != null ? 1 : 0) +
            (point.quality != null ? 1 : 0);
        final representative = score(right).compareTo(score(left));
        return representative != 0
            ? representative
            : right.date.compareTo(left.date);
      });
    return candidates.take(5).map((point) {
      final bedtime = _formatTime(point.sleepStartTime);
      return <String, dynamic>{
        'date': _date(point.date),
        if (bedtime != null) 'bedtime': bedtime,
        if (point.nightMinutes != null)
          'nightSleepHours': _minutesToHours(point.nightMinutes),
        if (point.quality != null) 'sleepQuality': point.quality,
        if (point.flags.isNotEmpty) 'flags': point.flags,
      };
    }).toList();
  }

  static List<Map<String, dynamic>> _emotionEvidence(
    List<DailyRecord> records,
    List<HealthEvent> events,
  ) {
    final candidates = <_MetricEvidenceCandidate>[
      for (final record in records)
        for (final emotion in record.emotions)
          if (emotion.name.trim().isNotEmpty && emotion.value != null)
            _MetricEvidenceCandidate(
              at: record.date,
              name: emotion.name.trim(),
              value: emotion.value,
            ),
      for (final event in events)
        for (final emotion in event.emotions)
          if (emotion.name.trim().isNotEmpty)
            _MetricEvidenceCandidate(
              at: event.timestamp,
              name: emotion.name.trim(),
              value: emotion.intensity,
            ),
    ];
    return _selectMetricEvidence(candidates, valueKey: 'intensity');
  }

  static List<Map<String, dynamic>> _symptomEvidence(
    List<DailyRecord> records,
    List<HealthEvent> events,
  ) {
    final candidates = <_MetricEvidenceCandidate>[
      for (final record in records)
        for (final symptom in record.symptoms)
          if (symptom.trim().isNotEmpty)
            _MetricEvidenceCandidate(at: record.date, name: symptom.trim()),
      for (final event in events)
        for (final symptom in event.symptoms)
          if (symptom.name.trim().isNotEmpty)
            _MetricEvidenceCandidate(
              at: event.timestamp,
              name: symptom.name.trim(),
              value: symptom.severity,
              includeTime: true,
            ),
    ];
    return _selectMetricEvidence(candidates, valueKey: 'severity');
  }

  static List<Map<String, dynamic>> _selectMetricEvidence(
    List<_MetricEvidenceCandidate> candidates, {
    required String valueKey,
  }) {
    candidates.sort((left, right) {
      final intensity = (right.value ?? 0).compareTo(left.value ?? 0);
      return intensity != 0 ? intensity : right.at.compareTo(left.at);
    });
    final seen = <String>{};
    final selected = <Map<String, dynamic>>[];
    for (final item in candidates) {
      final key = '${_date(item.at)}\u0000${item.name}';
      if (!seen.add(key)) continue;
      selected.add({
        item.includeTime ? 'dateTime' : 'date':
            item.includeTime ? _dateTime(item.at) : _date(item.at),
        'name': item.name,
        if (item.value != null) valueKey: item.value,
      });
      if (selected.length == 5) break;
    }
    return selected;
  }

  static List<Map<String, dynamic>> _recentMaps(
    List<Map<String, dynamic>> values, {
    required String dateKey,
  }) {
    final result = values.map(Map<String, dynamic>.from).toList()
      ..sort((left, right) =>
          right[dateKey].toString().compareTo(left[dateKey].toString()));
    return result.take(5).toList();
  }

  static Map<String, int> _evidenceSize(
    Map<String, List<Map<String, dynamic>>> evidence,
  ) =>
      {
        'totalCharacters': jsonEncode(evidence).length,
        'sleepCount': evidence['sleep']?.length ?? 0,
        'emotionCount': evidence['emotion']?.length ?? 0,
        'symptomCount': evidence['symptom']?.length ?? 0,
        'medicationCount': evidence['medication']?.length ?? 0,
        'periodCount': evidence['period']?.length ?? 0,
      };

  static List<RecentReviewMetricSummary> _emotions(
    List<DailyHealthAggregate> aggregates,
  ) {
    final values = <String, List<double>>{};
    final occurrenceDays = <String, int>{};
    for (final aggregate in aggregates) {
      for (final entry in aggregate.emotionDailyValues.entries) {
        if (entry.key == DailyHealthAggregationService.overallMoodKey) continue;
        final dailyValues = entry.value.observations
            .map((item) => item.value)
            .where((value) => value >= 1 && value <= 5)
            .toList();
        if (dailyValues.isEmpty) continue;
        occurrenceDays[entry.key] = (occurrenceDays[entry.key] ?? 0) + 1;
        values.putIfAbsent(entry.key, () => []).add(
              dailyValues.reduce((left, right) => left > right ? left : right),
            );
      }
    }
    final result = values.entries
        .map(
          (entry) => RecentReviewMetricSummary(
            name: entry.key,
            occurrenceDays: occurrenceDays[entry.key] ?? 0,
            averageIntensity: _average(entry.value),
            maxIntensity: entry.value.reduce((a, b) => a > b ? a : b),
          ),
        )
        .toList()
      ..sort((left, right) {
        final count = right.occurrenceDays.compareTo(left.occurrenceDays);
        if (count != 0) return count;
        final intensity =
            (right.averageIntensity ?? 0).compareTo(left.averageIntensity ?? 0);
        return intensity != 0 ? intensity : left.name.compareTo(right.name);
      });
    return result;
  }

  static double? _stateAverage(
    List<DailyHealthAggregate> aggregates,
    String key,
  ) {
    final values = aggregates
        .expand((aggregate) =>
            aggregate.stateDailyValues[key]?.observations ??
            const <DailyValueObservation>[])
        .map((item) => item.value)
        .where((value) => value >= 1 && value <= 5)
        .toList();
    return _average(values);
  }

  static Map<String, dynamic> _medication(Map<String, dynamic> medication) => {
        'name': (medication['name'] ??
                medication['nameZh'] ??
                medication['nameEn'] ??
                '')
            .toString()
            .trim(),
        'dosePerUnit': medication['dosePerUnit'],
        'pillCount': medication['pillCount'],
        'dose': medication['dose'],
        'unit': medication['unit'],
        'times': medication['times'] is Iterable
            ? (medication['times'] as Iterable)
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
            : const <String>[],
        'type': medication['type'],
      };

  static Iterable<Map<String, dynamic>> _medicationChanges(
    Map<String, dynamic> adjustment,
  ) {
    final events = MedicationAdjustmentEvent.fromRecord(adjustment);
    if (events.isNotEmpty) {
      return events.map(
        (event) => {
          'date': event.dateLabel,
          'name': event.medName,
          'type': event.type,
          'changeSummary': MedicationAdjustmentFormatter.shortSummary(event),
        },
      );
    }
    final date = adjustment['date']?.toString().trim() ?? '';
    final rawItems = adjustment['items'];
    if (date.isEmpty || rawItems is! List) return const [];
    return rawItems.whereType<Map>().map((rawItem) {
      final item = Map<String, dynamic>.from(rawItem);
      return {
        'date': date,
        'name': (item['name'] ?? '').toString().trim(),
        'type': (item['type'] ?? '').toString().trim(),
        'changeSummary': (item['changeSummary'] ?? '').toString().trim(),
      };
    }).where(
      (item) =>
          item['name'].toString().isNotEmpty &&
          item['type'].toString().isNotEmpty &&
          item['changeSummary'].toString().isNotEmpty,
    );
  }

  static double? _average(List<double> values) => values.isEmpty
      ? null
      : _oneDecimal(values.reduce((a, b) => a + b) / values.length);

  static double? _oneDecimal(double? value) =>
      value == null ? null : double.parse(value.toStringAsFixed(1));

  static String? _formatTime(TimeOfDay? value) =>
      value == null ? null : DateHelper.formatTime(value);

  static DateTime _day(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    return DateTime(local.year, local.month, local.day);
  }

  static bool _within(DateTime value, DateTime start, DateTime end) {
    final day = _day(value);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _dateTime(DateTime value) => '${_date(value)} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _MetricEvidenceCandidate {
  const _MetricEvidenceCandidate({
    required this.at,
    required this.name,
    this.value,
    this.includeTime = false,
  });

  final DateTime at;
  final String name;
  final int? value;
  final bool includeTime;
}
