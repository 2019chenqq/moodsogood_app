import '../models/daily_check_in.dart';
import '../models/daily_health_aggregate.dart';
import '../models/daily_record.dart';
import '../models/health_event.dart';
import '../utils/state_change_normalizer.dart';

class DailyHealthAggregationService {
  const DailyHealthAggregationService();

  static const String overallMoodKey = 'overall_mood';

  DailyHealthAggregate aggregateDay({
    required DateTime date,
    Iterable<DailyRecord> dailyRecords = const [],
    Iterable<HealthEvent> healthEvents = const [],
    Iterable<DailyCheckIn> dailyCheckIns = const [],
  }) {
    final day = _localDay(date);
    return _build(
      day,
      dailyRecords.where((item) => _localDay(item.date) == day).toList(),
      healthEvents.where((item) => _localDay(item.timestamp) == day).toList(),
      dailyCheckIns.where((item) => _localDay(item.date) == day).toList(),
    );
  }

  List<DailyHealthAggregate> aggregateRange({
    Iterable<DailyRecord> dailyRecords = const [],
    Iterable<HealthEvent> healthEvents = const [],
    Iterable<DailyCheckIn> dailyCheckIns = const [],
    DateTime? start,
    DateTime? endExclusive,
  }) {
    final recordsByDay = <DateTime, List<DailyRecord>>{};
    final eventsByDay = <DateTime, List<HealthEvent>>{};
    final checkInsByDay = <DateTime, List<DailyCheckIn>>{};

    for (final record in dailyRecords) {
      final day = _localDay(record.date);
      if (_inRange(day, start, endExclusive)) {
        recordsByDay.putIfAbsent(day, () => []).add(record);
      }
    }
    for (final event in healthEvents) {
      final day = _localDay(event.timestamp);
      if (_inRange(day, start, endExclusive)) {
        eventsByDay.putIfAbsent(day, () => []).add(event);
      }
    }
    for (final checkIn in dailyCheckIns) {
      final day = _localDay(checkIn.date);
      if (_inRange(day, start, endExclusive)) {
        checkInsByDay.putIfAbsent(day, () => []).add(checkIn);
      }
    }

    final days = <DateTime>{
      ...recordsByDay.keys,
      ...eventsByDay.keys,
      ...checkInsByDay.keys,
    }.toList()
      ..sort();

    return List.unmodifiable(
      days.map(
        (day) => _build(
          day,
          recordsByDay[day] ?? const [],
          eventsByDay[day] ?? const [],
          checkInsByDay[day] ?? const [],
        ),
      ),
    );
  }

  int recordedDayCount(Iterable<DailyHealthAggregate> aggregates) =>
      aggregates.where((item) => item.recorded).length;

  int occurrenceDaysForSymptom(
    Iterable<DailyHealthAggregate> aggregates,
    String symptomName,
  ) =>
      aggregates
          .where(
              (item) => item.symptomDailyValues[symptomName]?.present == true)
          .length;

  SymptomRangeStatistics symptomStatistics(
    Iterable<DailyHealthAggregate> aggregates,
    String symptomName,
  ) {
    final daysByKey = <String, DailyHealthAggregate>{
      for (final aggregate in aggregates)
        if (aggregate.recorded) aggregate.dateKey: aggregate,
    };
    final presentDays = daysByKey.values
        .where((aggregate) =>
            aggregate.symptomDailyValues[symptomName]?.present == true)
        .toList();
    final eventObservations = presentDays
        .expand((aggregate) =>
            aggregate.symptomDailyValues[symptomName]!.observations)
        .where((observation) =>
            observation.source == DailyHealthValueSource.healthEvent)
        .toList();
    final scored = eventObservations
        .where((observation) => observation.severity != null)
        .toList();
    final severityValues = scored.map((item) => item.severity!).toList();
    final timestamped =
        scored.where((observation) => observation.timestamp != null).toList();
    timestamped.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));

    return SymptomRangeStatistics(
      name: symptomName,
      recordedDays: daysByKey.length,
      occurrenceDays: presentDays.length,
      eventCount: eventObservations.length,
      averageSeverity: severityValues.isEmpty
          ? null
          : severityValues.reduce((a, b) => a + b) / severityValues.length,
      maxSeverity: severityValues.isEmpty
          ? null
          : severityValues.reduce((a, b) => a > b ? a : b),
      latestSeverity: timestamped.isEmpty ? null : timestamped.last.severity,
    );
  }

  List<SymptomRangeStatistics> allSymptomStatistics(
    Iterable<DailyHealthAggregate> aggregates,
  ) {
    final values = aggregates.toList();
    final names =
        values.expand((aggregate) => aggregate.symptomDailyValues.keys).toSet();
    final result = names.map((name) => symptomStatistics(values, name)).toList()
      ..sort((a, b) {
        final dayOrder = b.occurrenceDays.compareTo(a.occurrenceDays);
        return dayOrder != 0 ? dayOrder : a.name.compareTo(b.name);
      });
    return result;
  }

  DailyHealthAggregate _build(
    DateTime day,
    List<DailyRecord> records,
    List<HealthEvent> events,
    List<DailyCheckIn> checkIns,
  ) {
    final emotionValues = <String, List<DailyValueObservation>>{};
    final symptomValues = <String, List<DailySymptomObservation>>{};
    final stateValues = <String, List<DailyValueObservation>>{};

    void addValue(
      Map<String, List<DailyValueObservation>> target,
      String rawName,
      double value,
      DailyHealthValueSource source,
      int scale, {
      DateTime? timestamp,
    }) {
      final name = rawName.trim();
      if (name.isEmpty) return;
      target.putIfAbsent(name, () => []).add(
            DailyValueObservation(
              value: value,
              source: source,
              scale: scale,
              timestamp: timestamp,
            ),
          );
    }

    for (final record in records) {
      for (final emotion in record.emotions) {
        final value = emotion.value;
        if (value != null) {
          addValue(
            emotionValues,
            emotion.name,
            value.toDouble(),
            DailyHealthValueSource.dailyRecord,
            record.moodScale,
          );
        }
      }
      if (record.overallMood != null) {
        addValue(
          emotionValues,
          overallMoodKey,
          record.overallMood!,
          DailyHealthValueSource.dailyRecord,
          record.moodScale,
        );
      }
      for (final symptom in record.symptoms) {
        final name = symptom.trim();
        if (name.isNotEmpty) {
          symptomValues.putIfAbsent(name, () => []).add(
                const DailySymptomObservation(
                  source: DailyHealthValueSource.dailyRecord,
                ),
              );
        }
      }
      for (final entry in normalizeStateChanges(record.stateChanges).entries) {
        addValue(
          stateValues,
          entry.key,
          entry.value.toDouble(),
          DailyHealthValueSource.dailyRecord,
          5,
        );
      }
    }

    for (final checkIn in checkIns) {
      addValue(
        emotionValues,
        overallMoodKey,
        checkIn.overallMood.toDouble(),
        DailyHealthValueSource.dailyCheckIn,
        5,
      );
    }

    final sortedEvents = List<HealthEvent>.from(events)
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    for (final event in sortedEvents) {
      for (final emotion in event.emotions) {
        addValue(
          emotionValues,
          emotion.name,
          emotion.intensity.toDouble(),
          DailyHealthValueSource.healthEvent,
          5,
          timestamp: event.timestamp,
        );
      }
      for (final symptom in event.symptoms) {
        final name = symptom.name.trim();
        if (name.isNotEmpty) {
          symptomValues.putIfAbsent(name, () => []).add(
                DailySymptomObservation(
                  source: DailyHealthValueSource.healthEvent,
                  severity: symptom.severity,
                  timestamp: event.timestamp,
                ),
              );
        }
      }
      for (final entry in normalizeStateChanges(event.stateChanges).entries) {
        addValue(
          stateValues,
          entry.key,
          entry.value.toDouble(),
          DailyHealthValueSource.healthEvent,
          5,
          timestamp: event.timestamp,
        );
      }
    }

    return DailyHealthAggregate(
      date: day,
      hasDailyRecord: records.isNotEmpty,
      hasDailyCheckIn: checkIns.isNotEmpty,
      eventCount: events.length,
      emotionDailyValues: emotionValues.map(
        (name, values) => MapEntry(name, DailyValueSummary(values)),
      ),
      symptomDailyValues: symptomValues.map(
        (name, values) => MapEntry(name, DailySymptomSummary(values)),
      ),
      stateDailyValues: stateValues.map(
        (name, values) => MapEntry(name, DailyValueSummary(values)),
      ),
      dailyRecords: records,
      dailyCheckIns: checkIns,
      healthEvents: sortedEvents,
    );
  }

  static DateTime _localDay(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    return DateTime(local.year, local.month, local.day);
  }

  static bool _inRange(
    DateTime day,
    DateTime? start,
    DateTime? endExclusive,
  ) {
    final startDay = start == null ? null : _localDay(start);
    final endDay = endExclusive == null ? null : _localDay(endExclusive);
    return (startDay == null || !day.isBefore(startDay)) &&
        (endDay == null || day.isBefore(endDay));
  }
}
