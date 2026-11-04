import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/med_symptom_compare_models.dart';
import 'package:moodsogood_app/meds/sleep_comparison_contract.dart';
import 'package:moodsogood_app/models/sleep_record.dart';

void main() {
  for (final days in [3, 7, 14, 30]) {
    test('$days calendar dates on each side; D0 retained separately', () {
      final window = SleepComparisonDayWindow(
        effectiveDateTime: DateTime(2026, 1, 1, 18),
        days: days,
      );
      final records = List.generate(2 * days + 3, (index) {
        return SleepRecord(date: DateTime(2026, 1, 1 - days - 1 + index));
      });
      final grouped = window.partition(records, (item) => item.date);
      expect(grouped[SleepComparisonDayPosition.before], hasLength(days));
      expect(grouped[SleepComparisonDayPosition.after], hasLength(days));
      expect(grouped[SleepComparisonDayPosition.outside], hasLength(2));
      final d0 = grouped[SleepComparisonDayPosition.adjustmentDay]!.single;
      expect(identical(d0, records[days + 1]), isTrue);
      expect(d0.quality, isNull);
      expect(d0.durationMinutes, isNull);
      expect(records, hasLength(2 * days + 3));
      expect(() => grouped[SleepComparisonDayPosition.before]!.clear(),
          throwsUnsupportedError);
    });
  }

  test('default 7 crosses year with half-open boundaries', () {
    final window = SleepComparisonDayWindow(
        effectiveDateTime: DateTime(2026, 1, 1, 23, 59));
    expect(window.days, 7);
    expect(window.beforeStart, DateTime.utc(2025, 12, 25));
    expect(window.beforeEndExclusive, DateTime.utc(2026, 1, 1));
    expect(window.afterStart, DateTime.utc(2026, 1, 2));
    expect(window.afterEndExclusive, DateTime.utc(2026, 1, 9));
  });

  test('leap month and all D0 clock times use the same calendar window', () {
    for (final hour in [0, 8, 18, 23]) {
      final window = SleepComparisonDayWindow(
          effectiveDateTime: DateTime(2024, 3, 1, hour), days: 3);
      expect(window.beforeStart, DateTime.utc(2024, 2, 27));
      expect(window.afterEndExclusive, DateTime.utc(2024, 3, 5));
      for (final minute in [0, 720, 1439]) {
        expect(window.positionOf(DateTime(2024, 3, 1, 0, minute)),
            SleepComparisonDayPosition.adjustmentDay);
      }
    }
  });

  test('non-leap February and UTC dates preserve supplied calendar components',
      () {
    final window = SleepComparisonDayWindow(
        effectiveDateTime: DateTime.utc(2025, 3, 1, 23), days: 3);
    expect(window.beforeStart, DateTime.utc(2025, 2, 26));
    expect(window.positionOf(DateTime.utc(2025, 3, 4, 23, 59)),
        SleepComparisonDayPosition.after);
    expect(window.positionOf(DateTime.utc(2025, 3, 5)),
        SleepComparisonDayPosition.outside);
  });

  test('observation counts available dates, not valid records or full nights',
      () {
    final window = SleepComparisonDayWindow(
        effectiveDateTime: DateTime(2026, 12, 31, 18), days: 3);
    for (final offset in [-1, 0, 1, 2, 3, 10]) {
      final status = window.observationAt(DateTime(2026, 12, 31 + offset));
      final expected = offset.clamp(0, 3);
      expect(status.elapsedAfterDays, expected);
      expect(status.remainingDays, 3 - expected);
      expect(status.completed, expected == 3);
      expect(status.expectedCompletionDate, DateTime.utc(2027, 1, 3));
    }
  });

  test('unsupported windows are rejected, even without an effective date', () {
    for (final days in [-1, 0, 1, 5, 31]) {
      expect(
          () => SleepComparisonDayWindow(
              effectiveDateTime: DateTime(2026), days: days),
          throwsArgumentError);
      expect(() => const SleepComparisonTiming().dayWindow(days: days),
          throwsArgumentError);
    }
  });

  test('recording timestamps never replace missing effective time', () {
    final timing = SleepComparisonTiming(
      legacyDate: DateTime(2026, 8, 10, 20),
      adjustmentDateTime: DateTime(2026, 8, 10, 20),
      createdAt: DateTime(2026, 8, 11),
      effectivePrecision: SleepComparisonTimePrecision.exact,
    );
    expect(timing.source, SleepComparisonTimeSource.legacyDate);
    expect(timing.precision, SleepComparisonTimePrecision.unknown);
    expect(timing.dayWindow(), isNull);
    expect(timing.legacyDate, DateTime(2026, 8, 10, 20));
    expect(timing.createdAt, DateTime(2026, 8, 11));
    expect(const SleepComparisonTiming().source,
        SleepComparisonTimeSource.missing);
  });

  test('effective day wins over recording day without guessing precision', () {
    final timing = SleepComparisonTiming(
      effectiveDateTime: DateTime(2026, 8, 1, 18),
      legacyDate: DateTime(2026, 8, 10),
      createdAt: DateTime(2026, 8, 11),
    );
    expect(timing.source, SleepComparisonTimeSource.effectiveDateTime);
    expect(timing.precision, SleepComparisonTimePrecision.unknown);
    expect(timing.dayWindow()!.adjustmentDay, DateTime.utc(2026, 8, 1));
    final dayOnly = SleepComparisonTiming(
      effectiveDateTime: DateTime(2026, 8, 1),
      effectivePrecision: SleepComparisonTimePrecision.day,
    );
    expect(dayOnly.precision, SleepComparisonTimePrecision.day);
    expect(dayOnly.dayWindow()!.adjustmentDay, DateTime.utc(2026, 8, 1));
  });

  test('existing timestamp API retains exact split at effective instant', () {
    final effective = DateTime(2026, 3, 1, 18, 30);
    final window = MedicationComparisonWindow.timestampLevel(
        effectiveDateTime: effective, days: 7);
    expect(window.beforeStart, effective.subtract(const Duration(days: 7)));
    expect(window.beforeEndExclusive, effective);
    expect(window.afterStart, effective);
    expect(window.afterEndExclusive, effective.add(const Duration(days: 7)));
  });

  test('existing date API and observation keep their current semantics', () {
    final date = DateTime(2026, 3, 1, 18);
    final window =
        MedicationComparisonWindow.dateLevel(adjustmentDate: date, days: 3);
    expect(window.beforeStart, DateTime(2026, 2, 26));
    expect(window.beforeEndExclusive, DateTime(2026, 3, 1));
    expect(window.afterStart, DateTime(2026, 3, 2));
    expect(window.afterEndExclusive, DateTime(2026, 3, 5));
    expect(
        ObservationWindowStatus.calculate(
                eventDate: date, requestedDays: 3, now: DateTime(2026, 3, 2))
            .elapsedAfterDays,
        1);
  });
}
