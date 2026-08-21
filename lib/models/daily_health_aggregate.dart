import 'daily_check_in.dart';
import 'daily_record.dart';
import 'health_event.dart';

enum DailyHealthValueSource { dailyRecord, dailyCheckIn, healthEvent }

class DailyValueObservation {
  const DailyValueObservation({
    required this.value,
    required this.source,
    required this.scale,
    this.timestamp,
  });

  final double value;
  final DailyHealthValueSource source;
  final int scale;
  final DateTime? timestamp;
}

class DailyValueSummary {
  DailyValueSummary(Iterable<DailyValueObservation> observations)
      : observations = List.unmodifiable(observations);

  final List<DailyValueObservation> observations;

  int get count => observations.length;

  Set<int> get scales => Set.unmodifiable(
        observations.map((item) => item.scale).toSet(),
      );

  Map<int, DailyValueSummary> get byScale {
    final grouped = <int, List<DailyValueObservation>>{};
    for (final observation in observations) {
      grouped.putIfAbsent(observation.scale, () => []).add(observation);
    }
    return Map.unmodifiable(
      grouped
          .map((scale, values) => MapEntry(scale, DailyValueSummary(values))),
    );
  }

  bool get hasCompatibleScale => scales.length <= 1;

  double? get average => hasCompatibleScale && observations.isNotEmpty
      ? observations.fold<double>(0, (sum, item) => sum + item.value) /
          observations.length
      : null;

  double? get median {
    if (!hasCompatibleScale || observations.isEmpty) return null;
    final values = observations.map((item) => item.value).toList()..sort();
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }

  double? get min => hasCompatibleScale && observations.isNotEmpty
      ? observations
          .map((item) => item.value)
          .reduce((left, right) => left < right ? left : right)
      : null;

  double? get max => hasCompatibleScale && observations.isNotEmpty
      ? observations
          .map((item) => item.value)
          .reduce((left, right) => left > right ? left : right)
      : null;

  DailyValueObservation? get latest {
    if (observations.isEmpty) return null;
    final timestamped = observations
        .where((item) => item.timestamp != null)
        .toList(growable: false);
    if (timestamped.isEmpty) return observations.last;
    return timestamped.reduce(
      (left, right) => left.timestamp!.isAfter(right.timestamp!) ? left : right,
    );
  }
}

class DailySymptomObservation {
  const DailySymptomObservation({
    required this.source,
    this.severity,
    this.timestamp,
  });

  final DailyHealthValueSource source;
  final int? severity;
  final DateTime? timestamp;
}

class DailySymptomSummary {
  DailySymptomSummary(Iterable<DailySymptomObservation> observations)
      : observations = List.unmodifiable(observations);

  final List<DailySymptomObservation> observations;

  bool get present => observations.isNotEmpty;

  int get eventCount => observations
      .where((item) => item.source == DailyHealthValueSource.healthEvent)
      .length;

  Iterable<DailySymptomObservation> get _scored =>
      observations.where((item) => item.severity != null);

  double? get averageSeverity {
    final values = _scored.map((item) => item.severity!).toList();
    return values.isEmpty
        ? null
        : values.reduce((left, right) => left + right) / values.length;
  }

  int? get maxSeverity {
    final values = _scored.map((item) => item.severity!).toList();
    return values.isEmpty
        ? null
        : values.reduce((left, right) => left > right ? left : right);
  }

  int? get latestSeverity {
    final values = _scored.toList();
    if (values.isEmpty) return null;
    final timestamped =
        values.where((item) => item.timestamp != null).toList(growable: false);
    if (timestamped.isEmpty) return values.last.severity;
    return timestamped
        .reduce(
          (left, right) =>
              left.timestamp!.isAfter(right.timestamp!) ? left : right,
        )
        .severity;
  }
}

class SymptomRangeStatistics {
  const SymptomRangeStatistics({
    required this.name,
    required this.recordedDays,
    required this.occurrenceDays,
    required this.eventCount,
    required this.averageSeverity,
    required this.maxSeverity,
    required this.latestSeverity,
  });

  final String name;
  final int recordedDays;
  final int occurrenceDays;
  final int eventCount;
  final double? averageSeverity;
  final int? maxSeverity;
  final int? latestSeverity;

  double get occurrenceRate =>
      recordedDays == 0 ? 0 : occurrenceDays / recordedDays;
}

class DailyHealthAggregate {
  DailyHealthAggregate({
    required this.date,
    required this.hasDailyRecord,
    required this.hasDailyCheckIn,
    required this.eventCount,
    required Map<String, DailyValueSummary> emotionDailyValues,
    required Map<String, DailySymptomSummary> symptomDailyValues,
    required Map<String, DailyValueSummary> stateDailyValues,
    required List<DailyRecord> dailyRecords,
    required List<DailyCheckIn> dailyCheckIns,
    required List<HealthEvent> healthEvents,
  })  : emotionDailyValues = Map.unmodifiable(emotionDailyValues),
        symptomDailyValues = Map.unmodifiable(symptomDailyValues),
        stateDailyValues = Map.unmodifiable(stateDailyValues),
        dailyRecords = List.unmodifiable(dailyRecords),
        dailyCheckIns = List.unmodifiable(dailyCheckIns),
        healthEvents = List.unmodifiable(healthEvents);

  final DateTime date;
  final bool hasDailyRecord;
  final bool hasDailyCheckIn;
  final int eventCount;
  final Map<String, DailyValueSummary> emotionDailyValues;
  final Map<String, DailySymptomSummary> symptomDailyValues;
  final Map<String, DailyValueSummary> stateDailyValues;

  /// Original source records are retained without changing their precision.
  final List<DailyRecord> dailyRecords;
  final List<DailyCheckIn> dailyCheckIns;
  final List<HealthEvent> healthEvents;

  bool get recorded => hasDailyRecord || hasDailyCheckIn || eventCount > 0;

  String get dateKey => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
