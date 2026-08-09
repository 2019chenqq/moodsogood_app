import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/sleep_record_service.dart';
import 'package:moodsogood_app/daily/unified_sleep_repository.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/sleep_record.dart';
import 'package:moodsogood_app/sleep_insights/models/sleep_insight_models.dart';
import 'package:moodsogood_app/sleep_insights/services/sleep_analysis_service.dart';

void main() {
  group('SleepRecord', () {
    test('1. new sleep record preserves all current sleep values', () {
      final record = _sleepRecord(DateTime(2026, 8, 8), quality: 4);

      final decoded = SleepRecord.fromMap(record.toMap());

      expect(decoded.sleepStart, const TimeOfDay(hour: 23, minute: 30));
      expect(decoded.wakeTime, const TimeOfDay(hour: 7, minute: 0));
      expect(decoded.durationMinutes, 450);
      expect(decoded.quality, 4);
      expect(decoded.sleepConditions, ['dreams']);
      expect(decoded.sleepMedication.taken, isTrue);
      expect(decoded.naps, hasLength(1));
    });

    test('2. same date always resolves to the same document id', () {
      expect(
        SleepRecordService.dateId(DateTime(2026, 8, 8, 1)),
        SleepRecordService.dateId(DateTime(2026, 8, 8, 23, 59)),
      );
      expect(SleepRecordService.dateId(DateTime(2026, 8, 8)), '2026-08-08');
    });

    test('3. legacy DailyRecord sleep remains readable', () {
      final legacy = SleepRecord.fromSleepData(
        DateTime(2026, 8, 7),
        const SleepData(
          estimatedSleepTime: TimeOfDay(hour: 0, minute: 10),
          finalWakeTime: TimeOfDay(hour: 7, minute: 10),
          quality: 3,
          flags: ['earlyWake'],
        ),
      );

      final result = UnifiedSleepRepository.resolve(legacy: [legacy]);

      expect(result.single.source, SleepRecordSource.legacyDailyRecord);
      expect(result.single.record.quality, 3);
      expect(result.single.record.durationMinutes, 420);
    });

    test('4. current SleepRecord wins over legacy on the same date', () {
      final date = DateTime(2026, 8, 8);
      final legacy = _sleepRecord(date, quality: 2);
      final current = _sleepRecord(date, quality: 5);

      final result = UnifiedSleepRepository.resolve(
        current: [current],
        legacy: [legacy],
      );

      expect(result, hasLength(1));
      expect(result.single.source, SleepRecordSource.sleepRecord);
      expect(result.single.record.quality, 5);
    });

    test('5. insight overlay keeps old and new dates continuous', () {
      final legacyDate = DateTime(2026, 8, 7);
      final currentDate = DateTime(2026, 8, 8);
      final dailyRecords = [
        DailyRecord(
          id: '2026-08-07',
          date: legacyDate,
          sleep: const SleepData(
            estimatedSleepTime: TimeOfDay(hour: 23, minute: 0),
            finalWakeTime: TimeOfDay(hour: 7, minute: 0),
            quality: 2,
          ),
        ),
      ];
      final unified = UnifiedSleepRepository.resolve(
        current: [_sleepRecord(currentDate, quality: 4)],
        legacy: [
          SleepRecord.fromSleepData(legacyDate, dailyRecords.single.sleep),
        ],
      );

      final result = UnifiedSleepRepository.overlayForInsights(
        dailyRecords: dailyRecords,
        sleepRecords: unified,
      );

      expect(result.map((record) => record.date), [legacyDate, currentDate]);
      expect(result.map((record) => record.sleep.quality), [2, 4]);
      final insight = const SleepAnalysisService().analyze(
        records: result,
        endDate: currentDate,
        period: SleepInsightPeriod.sevenDays,
      );
      expect(
        insight.points.where((point) => point.hasSleepRecord),
        hasLength(2),
      );
    });

    test('6. populated quality is exposed through the actual quality field',
        () {
      final date = DateTime(2026, 8, 8);
      final record = DailyRecord(
        id: '2026-08-08',
        date: date,
        sleep: _sleepRecord(date, quality: 4).toSleepData(),
      );
      final insight = const SleepAnalysisService().analyze(
        records: [record],
        endDate: date,
        period: SleepInsightPeriod.sevenDays,
      );
      final point = insight.points.singleWhere(
        (item) => item.date == date,
      );

      expect(point.quality, 4);
      expect(insight.summary.qualityDays, 1);
    });
  });
}

SleepRecord _sleepRecord(DateTime date, {required int quality}) {
  return SleepRecord(
    date: date,
    bedTime: const TimeOfDay(hour: 23, minute: 0),
    sleepStart: const TimeOfDay(hour: 23, minute: 30),
    wakeTime: const TimeOfDay(hour: 7, minute: 0),
    activityWakeTime: const TimeOfDay(hour: 7, minute: 10),
    durationMinutes: 450,
    quality: quality,
    sleepConditions: const ['dreams'],
    naps: const [
      NapItem(
        start: TimeOfDay(hour: 13, minute: 0),
        end: TimeOfDay(hour: 13, minute: 30),
      ),
    ],
    sleepMedication: const SleepMedication(
      taken: true,
      name: 'existing medicine',
      dose: '0.5 mg',
    ),
  );
}
