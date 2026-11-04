import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/unified_sleep_repository.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/sleep_record.dart';
import 'package:moodsogood_app/sleep_insights/models/sleep_insight_models.dart';
import 'package:moodsogood_app/sleep_insights/services/sleep_analysis_service.dart';

// Pure source-selection tests. Remaining legacy limitations are explicit;
// no production data or Firestore writes are used.
void main() {
  final date = DateTime(2026, 8, 8);

  test('current record wins as a whole; missing quality is not backfilled', () {
    final current = SleepRecord(date: date, note: 'only a note');
    final legacy = SleepRecord(date: date, quality: 5);
    final resolved =
        UnifiedSleepRepository.resolve(current: [current], legacy: [legacy]);
    expect(resolved.single.record, same(current));
    expect(resolved.single.source, SleepRecordSource.sleepRecord);
    expect(resolved.single.record.quality, isNull);
  });

  test('empty current falls back to legacy with or without caller filtering',
      () {
    final current = SleepRecord(date: date);
    final legacy = SleepRecord(date: date, quality: 4);
    expect(current.hasData, isFalse);
    final direct =
        UnifiedSleepRepository.resolve(current: [current], legacy: [legacy]);
    expect(direct.single.record, same(legacy));
    final range = UnifiedSleepRepository.resolve(
        current: [current].where((record) => record.hasData), legacy: [legacy]);
    expect(range.single.source, SleepRecordSource.legacyDailyRecord);
    expect(range.single.record.quality, 4);
  });

  test('same-source duplicates currently use input order, not updatedAt', () {
    final older =
        SleepRecord(date: date, quality: 2, updatedAt: DateTime(2026, 8, 9));
    final newer =
        SleepRecord(date: date, quality: 5, updatedAt: DateTime(2026, 8, 10));
    expect(
        UnifiedSleepRepository.resolve(current: [newer, older]).single.record,
        same(older));
    expect(
        UnifiedSleepRepository.resolve(current: [older, newer]).single.record,
        same(newer));
    expect(UnifiedSleepRepository.resolve(legacy: [newer, older]).single.record,
        same(older));
  });

  test('missing or invalid date is rejected rather than assigned to today', () {
    for (final date in [null, 'invalid', '2026-02-30']) {
      expect(() => SleepRecord.fromMap({'date': date, 'quality': 4}),
          throwsFormatException);
    }
  });

  test(
      'duration-only records currently fail hasData and lose duration in overlay',
      () {
    final record = SleepRecord(date: date, durationMinutes: 480);
    expect(record.hasData, isFalse);
    expect(record.toSleepData().durationHours, isNull);
  });

  test('absent night-wake field and explicit empty list are indistinguishable',
      () {
    final missing = SleepData.fromMap({});
    final empty = SleepData.fromMap({'nightAwakenings': []});
    expect(missing.nightAwakenings, isEmpty);
    expect(empty.nightAwakenings, isEmpty);
    expect(missing.toMap(), empty.toMap());
    // No confirmed-zero state exists. Do not fabricate one from [] or null.
  });

  test(
      'unknown wake duration is not proof of zero wakes; missing night stays null',
      () {
    final result = const SleepAnalysisService().analyze(
      records: [
        DailyRecord(
            id: '2026-08-08',
            date: date,
            sleep: const SleepData(
              sleepTime: TimeOfDay(hour: 23, minute: 0),
              wakeTime: TimeOfDay(hour: 7, minute: 0),
              nightAwakenings: [
                NightAwakeningItem(start: TimeOfDay(hour: 3, minute: 0))
              ],
            )),
      ],
      startDate: date,
      endDate: DateTime(2026, 8, 9),
      period: SleepInsightPeriod.all,
    );
    expect(result.points.first.hasNightWakeRecord, isTrue);
    expect(result.points.first.nightAwakeMinutes, 0);
    expect(result.points.first.nightMinutes, 480);
    expect(result.points.last.nightMinutes, isNull);
    expect(result.points.last.quality, isNull);
    expect(result.summary.validNightDays, 1);
    expect(result.summary.qualityDays, 0);
    expect(result.summary.averageQuality, isNull);
  });
}
