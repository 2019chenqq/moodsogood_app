import 'med_symptom_compare_models.dart';

/// In-memory provenance only; these values are not Firestore schema fields.
enum SleepComparisonTimeSource { effectiveDateTime, legacyDate, missing }

enum SleepComparisonTimePrecision { day, exact, unknown }

/// Pass the original fields, NOT MedicationAdjustmentEvent.effectiveDateTime:
/// that model already falls back to `date` and loses the provenance.
/// A legacy `date` may be a recording date; it must not silently become D0.
class SleepComparisonTiming {
  const SleepComparisonTiming({
    this.effectiveDateTime,
    this.legacyDate,
    this.adjustmentDateTime,
    this.createdAt,
    this.effectivePrecision = SleepComparisonTimePrecision.unknown,
  });

  final DateTime? effectiveDateTime;
  final DateTime? legacyDate;
  final DateTime? adjustmentDateTime;
  final DateTime? createdAt;

  /// Precision must come from source evidence, never from a non-midnight clock.
  final SleepComparisonTimePrecision effectivePrecision;

  SleepComparisonTimeSource get source => effectiveDateTime != null
      ? SleepComparisonTimeSource.effectiveDateTime
      : legacyDate != null
          ? SleepComparisonTimeSource.legacyDate
          : SleepComparisonTimeSource.missing;

  SleepComparisonTimePrecision get precision => effectiveDateTime == null
      ? SleepComparisonTimePrecision.unknown
      : effectivePrecision;

  SleepComparisonDayWindow? dayWindow({int days = 7}) {
    SleepComparisonDayWindow.validateDays(days);
    final effective = effectiveDateTime;
    if (effective == null) return null;
    return SleepComparisonDayWindow(effectiveDateTime: effective, days: days);
  }
}

enum SleepComparisonDayPosition { before, adjustmentDay, after, outside }

/// Calendar comparison only: no averages, imputation or causal interpretation.
/// Callers must supply dates in the same intended calendar/time zone. This
/// class uses their year/month/day components and never converts an instant to
/// the host time zone. UTC midnights below are calendar labels, not instants.
class SleepComparisonDayWindow {
  SleepComparisonDayWindow({required DateTime effectiveDateTime, this.days = 7})
      : adjustmentDay = _day(effectiveDateTime) {
    validateDays(days);
  }

  static const supportedDays = {3, 7, 14, 30};
  final int days;
  final DateTime adjustmentDay;

  static void validateDays(int days) {
    if (!supportedDays.contains(days)) {
      throw ArgumentError.value(days, 'days', 'Expected 3, 7, 14 or 30');
    }
  }

  DateTime get beforeStart => adjustmentDay.subtract(Duration(days: days));
  DateTime get beforeEndExclusive => adjustmentDay;
  DateTime get afterStart => adjustmentDay.add(const Duration(days: 1));
  DateTime get afterEndExclusive => afterStart.add(Duration(days: days));

  SleepComparisonDayPosition positionOf(DateTime date) {
    final day = _day(date);
    if (day == adjustmentDay) return SleepComparisonDayPosition.adjustmentDay;
    if (!day.isBefore(beforeStart) && day.isBefore(beforeEndExclusive)) {
      return SleepComparisonDayPosition.before;
    }
    if (!day.isBefore(afterStart) && day.isBefore(afterEndExclusive)) {
      return SleepComparisonDayPosition.after;
    }
    return SleepComparisonDayPosition.outside;
  }

  /// Available calendar dates, including today; NOT completed nights or valid
  /// records. Kept separate from per-metric data completeness.
  ObservationWindowStatus observationAt(DateTime now) {
    final elapsed =
        (_day(now).difference(afterStart).inDays + 1).clamp(0, days);
    return ObservationWindowStatus(
      requestedDays: days,
      elapsedAfterDays: elapsed,
      remainingDays: days - elapsed,
      completed: elapsed == days,
      expectedCompletionDate: adjustmentDay.add(Duration(days: days)),
    );
  }

  /// D0 remains separately accessible for P1. Items are neither copied with
  /// defaults nor mutated; missing values and original timestamps survive.
  Map<SleepComparisonDayPosition, List<T>> partition<T>(
    Iterable<T> records,
    DateTime Function(T) dateOf,
  ) {
    final grouped = {
      for (final position in SleepComparisonDayPosition.values) position: <T>[],
    };
    for (final record in records) {
      grouped[positionOf(dateOf(record))]!.add(record);
    }
    return Map.unmodifiable(grouped.map(
      (key, value) => MapEntry(key, List<T>.unmodifiable(value)),
    ));
  }

  static DateTime _day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
