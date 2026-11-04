import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/sleep_record_date.dart';
import 'package:moodsogood_app/models/sleep_record.dart';
import 'package:moodsogood_app/daily/unified_sleep_repository.dart';

void main() {
  test('supports explicit date types without losing timestamp precision', () {
    final date = DateTime(2026, 1, 31, 23, 59, 59, 999, 999);
    for (final value in [
      date,
      Timestamp.fromDate(date),
      date.toIso8601String()
    ]) {
      expect(parseSleepRecordDate(value), date);
    }
    expect(parseSleepRecordDate('2024-02-29'), DateTime(2024, 2, 29));
    expect(parseSleepRecordDate('2026-01-31T23:00:00+08:00'),
        DateTime.utc(2026, 1, 31, 15));
  });

  test('rejects malformed and overflowing dates instead of normalizing them',
      () {
    for (final value in [
      null,
      0,
      '',
      'bad',
      '2026-02-29',
      '2026-02-30',
      '2026-04-31',
      '2026-13-01',
      '2026-00-01',
      '2026-01-00',
      '2026-01-01T24:00:00',
      '2026-01-01T23:60:00',
      '2026-01-01T23:00:60',
      '2026-01-01T23:00:00+24:00',
      '2026-01-01T23:00:00+08:60',
      '2026-1-1',
      ' 2026-01-01',
      '0000-01-01'
    ]) {
      expect(parseSleepRecordDate(value), isNull, reason: '$value');
    }
  });

  test('valid field wins; strict ID fallback handles missing or invalid field',
      () {
    expect(sleepRecordDocumentDate('2026-02-01', '2026-01-31'),
        DateTime(2026, 2, 1));
    for (final value in [null, '', 'bad', '2026-02-30']) {
      expect(
          sleepRecordDocumentDate(value, '2026-01-31'), DateTime(2026, 1, 31));
    }
  });

  test('unreliable IDs cannot rescue a missing date', () {
    for (final id in [
      '',
      'auto-id',
      '2026-02-29',
      '2026-02-30',
      '2026-1-31',
      '2026-01-31-copy',
      '2026-01-31T00:00:00'
    ]) {
      expect(sleepRecordDocumentDate(null, id), isNull, reason: id);
    }
  });

  test('resolve excludes both empty sources and retains valid cross-month days',
      () {
    final output = UnifiedSleepRepository.resolve(
      current: [
        SleepRecord(date: DateTime(2026, 1, 31)),
        SleepRecord(date: DateTime(2026, 2, 1), quality: 5)
      ],
      legacy: [
        SleepRecord(date: DateTime(2026, 1, 31), quality: 3),
        SleepRecord(date: DateTime(2026, 2, 1), quality: 1),
        SleepRecord(date: DateTime(2026, 2, 2))
      ],
    );
    expect(output.map((item) => item.record.date),
        [DateTime(2026, 1, 31), DateTime(2026, 2, 1)]);
    expect(output.map((item) => item.record.quality), [3, 5]);
  });

  test('empty duplicate cannot hide valid record; duration-only stays limited',
      () {
    final date = DateTime(2026, 1, 31);
    final valid = SleepRecord(date: date, quality: 4);
    final empty = SleepRecord(date: date);
    expect(
        UnifiedSleepRepository.resolve(current: [valid, empty]).single.record,
        same(valid));
    expect(UnifiedSleepRepository.resolve(legacy: [valid, empty]).single.record,
        same(valid));
    expect(
        UnifiedSleepRepository.resolve(
          current: [SleepRecord(date: date, durationMinutes: 480)],
          legacy: [valid],
        ).single.record,
        same(valid));
  });
}
