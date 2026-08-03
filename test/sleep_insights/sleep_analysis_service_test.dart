import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/period_cycle.dart';
import 'package:moodsogood_app/sleep_insights/models/sleep_insight_models.dart';
import 'package:moodsogood_app/sleep_insights/services/sleep_analysis_service.dart';
import 'package:moodsogood_app/utils/date_helper.dart';

void main() {
  const service = SleepAnalysisService();

  DailyRecord record(
    int day, {
    int month = 1,
    TimeOfDay? bed,
    TimeOfDay? estimated,
    TimeOfDay? wake,
    List<NapItem> naps = const [],
    List<NightAwakeningItem> nightAwakenings = const [],
    int? quality,
    List<String> symptoms = const [],
    List<Emotion> emotions = const [],
    bool isPeriod = false,
  }) {
    return DailyRecord(
      id: '2026-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
      date: DateTime(2026, month, day),
      symptoms: symptoms,
      emotions: emotions,
      isPeriod: isPeriod,
      sleep: SleepData(
        sleepTime: bed,
        estimatedSleepTime: estimated,
        finalWakeTime: wake,
        naps: naps,
        nightAwakenings: nightAwakenings,
        quality: quality,
      ),
    );
  }

  SleepInsightResult analyze(
    List<DailyRecord> records, {
    DateTime? end,
    SleepInsightPeriod period = SleepInsightPeriod.sevenDays,
  }) {
    return service.analyze(
      records: records,
      endDate: end ?? DateTime(2026, 1, 7),
      period: period,
    );
  }

  group('時間與欄位相容', () {
    test('跨午夜 23:30 至 07:30 為 8 小時', () {
      expect(
        DateHelper.calcDurationMinutes(
          const TimeOfDay(hour: 23, minute: 30),
          const TimeOfDay(hour: 7, minute: 30),
        ),
        480,
      );
    });

    test('推估入睡時間優先，舊資料 fallback 至準備睡覺時間', () {
      const modern = SleepData(
        sleepTime: TimeOfDay(hour: 23, minute: 0),
        estimatedSleepTime: TimeOfDay(hour: 23, minute: 45),
        finalWakeTime: TimeOfDay(hour: 7, minute: 0),
      );
      const legacy = SleepData(
        sleepTime: TimeOfDay(hour: 23, minute: 0),
        finalWakeTime: TimeOfDay(hour: 7, minute: 0),
      );
      expect(modern.durationHours, 7.3);
      expect(legacy.durationHours, 8.0);
    });

    test('bodySymptoms 與 periodData 舊儲存格式可讀取', () {
      final parsed = DailyRecord.fromData('2026-01-01', {
        'date': '2026-01-01',
        'bodySymptoms': ['疲倦'],
        'periodData': {'isPeriod': true, 'periodStartId': '2026-01-01'},
      });
      expect(parsed.symptoms, ['疲倦']);
      expect(parsed.isPeriod, isTrue);
      expect(parsed.periodStartId, '2026-01-01');
    });

    test('結構化夜間醒來可序列化，舊欄位仍保留', () {
      const original = SleepData(
        midWakeList: '舊資料 03:10',
        nightAwakenings: [
          NightAwakeningItem(
            start: TimeOfDay(hour: 3, minute: 20),
            end: TimeOfDay(hour: 3, minute: 45),
            note: '做夢',
          ),
        ],
      );
      final parsed = SleepData.fromMap(original.toMap());
      expect(parsed.midWakeList, '舊資料 03:10');
      expect(parsed.nightAwakenings, hasLength(1));
      expect(parsed.nightAwakenings.single.effectiveDurationMinutes, 25);
      expect(parsed.nightAwakenings.single.note, '做夢');
    });
  });

  group('摘要統計', () {
    test('夜間醒來時段會從跨午夜睡眠區間扣除', () {
      final result = analyze([
        record(
          7,
          bed: const TimeOfDay(hour: 23, minute: 30),
          wake: const TimeOfDay(hour: 7, minute: 30),
          nightAwakenings: const [
            NightAwakeningItem(
              start: TimeOfDay(hour: 3, minute: 0),
              end: TimeOfDay(hour: 3, minute: 30),
            ),
          ],
        ),
      ]);
      final point = result.points.last;
      expect(point.sleepWindowMinutes, 480);
      expect(point.nightAwakeMinutes, 30);
      expect(point.nightMinutes, 450);
    });

    test('重疊夜間醒來只扣除合併後時長', () {
      final result = analyze([
        record(
          7,
          bed: const TimeOfDay(hour: 23, minute: 0),
          wake: const TimeOfDay(hour: 7, minute: 0),
          nightAwakenings: const [
            NightAwakeningItem(
              start: TimeOfDay(hour: 3, minute: 0),
              end: TimeOfDay(hour: 3, minute: 30),
            ),
            NightAwakeningItem(
              start: TimeOfDay(hour: 3, minute: 20),
              end: TimeOfDay(hour: 3, minute: 50),
            ),
          ],
        ),
      ]);
      expect(result.points.last.nightAwakeMinutes, 50);
      expect(result.points.last.nightMinutes, 430);
    });

    test('只有醒來時間不扣除，推估分鐘數則會扣除', () {
      final startOnly = analyze([
        record(
          7,
          bed: const TimeOfDay(hour: 23, minute: 0),
          wake: const TimeOfDay(hour: 7, minute: 0),
          nightAwakenings: const [
            NightAwakeningItem(start: TimeOfDay(hour: 3, minute: 0)),
          ],
        ),
      ]);
      expect(startOnly.points.last.nightMinutes, 480);

      final estimated = analyze([
        record(
          7,
          bed: const TimeOfDay(hour: 23, minute: 0),
          wake: const TimeOfDay(hour: 7, minute: 0),
          nightAwakenings: const [
            NightAwakeningItem(
              start: TimeOfDay(hour: 3, minute: 0),
              estimatedDurationMinutes: 20,
            ),
          ],
        ),
      ]);
      expect(estimated.points.last.nightAwakeMinutes, 20);
      expect(estimated.points.last.nightMinutes, 460);
    });

    test('同日多筆小睡正確加總', () {
      final result = analyze([
        record(
          7,
          bed: const TimeOfDay(hour: 23, minute: 0),
          wake: const TimeOfDay(hour: 7, minute: 0),
          naps: const [
            NapItem(
              start: TimeOfDay(hour: 12, minute: 0),
              end: TimeOfDay(hour: 12, minute: 30),
            ),
            NapItem(
              start: TimeOfDay(hour: 15, minute: 0),
              end: TimeOfDay(hour: 15, minute: 45),
            ),
          ],
        ),
      ]);
      final point = result.points.last;
      expect(point.napMinutes, 75);
      expect(result.summary.napCount, 2);
      expect(point.totalMinutes, 555);
    });

    test('缺少開始或醒來時間不納入平均夜眠', () {
      final result = analyze([
        record(5, bed: const TimeOfDay(hour: 23, minute: 0)),
        record(6, wake: const TimeOfDay(hour: 7, minute: 0)),
        record(
          7,
          bed: const TimeOfDay(hour: 23, minute: 0),
          wake: const TimeOfDay(hour: 7, minute: 0),
        ),
      ]);
      expect(result.summary.recordDays, 3);
      expect(result.summary.validNightDays, 1);
      expect(result.summary.averageNightMinutes, 480);
    });

    test('同一天多筆資料合併情緒、症狀與小睡', () {
      final result = analyze([
        record(7, symptoms: ['頭痛']),
        DailyRecord(
          id: 'duplicate',
          date: DateTime(2026, 1, 7, 12),
          emotions: const [Emotion(name: '焦躁', value: 4)],
          sleep: const SleepData(
            naps: [
              NapItem(
                start: TimeOfDay(hour: 13, minute: 0),
                end: TimeOfDay(hour: 13, minute: 30),
              ),
            ],
          ),
        ),
      ]);
      expect(result.points.last.symptoms, contains('頭痛'));
      expect(result.points.last.emotions, contains('焦躁'));
      expect(result.points.last.napMinutes, 30);
      expect(result.summary.recordDays, 1);
    });

    test('平均、最短、最長及品質分母正確', () {
      final result = analyze([
        record(5,
            bed: const TimeOfDay(hour: 0, minute: 0),
            wake: const TimeOfDay(hour: 6, minute: 0),
            quality: 2),
        record(6,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 7, minute: 0)),
        record(7,
            bed: const TimeOfDay(hour: 22, minute: 0),
            wake: const TimeOfDay(hour: 8, minute: 0),
            quality: 4),
      ]);
      expect(result.summary.averageNightMinutes, 480);
      expect(result.summary.shortestNightMinutes, 360);
      expect(result.summary.longestNightMinutes, 600);
      expect(result.summary.averageQuality, 3);
      expect(result.summary.qualityDays, 2);
    });

    test('空資料與只有 1 筆資料不拋出錯誤', () {
      expect(analyze([]).summary.validNightDays, 0);
      final one = analyze([
        record(7,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 7, minute: 0)),
      ]);
      expect(one.regularity.isAvailable, isFalse);
      expect(one.narrative, isNotEmpty);
    });
  });

  group('比較、規律度與連續變化', () {
    test('前 7 天與後 7 天比較', () {
      final records = <DailyRecord>[];
      for (var day = 1; day <= 7; day++) {
        records.add(record(day,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 6, minute: 0)));
      }
      for (var day = 8; day <= 14; day++) {
        records.add(record(day,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 7, minute: 0)));
      }
      final result = analyze(records, end: DateTime(2026, 1, 14));
      expect(result.comparison.isAvailable, isTrue);
      expect(result.summary.averageNightMinutes, 480);
      expect(result.comparison.previous!.averageNightMinutes, 420);
    });

    test('凌晨入睡 23:30、00:00、00:30 視為相近', () {
      final result = analyze([
        record(5,
            estimated: const TimeOfDay(hour: 23, minute: 30),
            wake: const TimeOfDay(hour: 7, minute: 0)),
        record(6,
            estimated: const TimeOfDay(hour: 0, minute: 0),
            wake: const TimeOfDay(hour: 7, minute: 0)),
        record(7,
            estimated: const TimeOfDay(hour: 0, minute: 30),
            wake: const TimeOfDay(hour: 7, minute: 0)),
      ]);
      expect(result.regularity.bedtimeVariationMinutes, lessThan(25));
    });

    test('連續 3 天睡眠縮短可偵測', () {
      final result = analyze([
        record(5,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 8, minute: 0)),
        record(6,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 7, minute: 0)),
        record(7,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 6, minute: 0)),
      ]);
      final episode = result.episodes.firstWhere(
        (item) => item.kind == SleepChangeKind.decreasing,
      );
      expect(episode.changeMinutes, -120);
    });

    test('中間缺少日期不視為連續', () {
      final result = analyze([
        record(4,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 8, minute: 0)),
        record(5,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 7, minute: 0)),
        record(7,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 6, minute: 0)),
      ]);
      expect(
        result.episodes
            .where((item) => item.kind == SleepChangeKind.decreasing),
        isEmpty,
      );
    });
  });

  test('睡眠與情緒、症狀依同日及隔日配對', () {
    final result = analyze([
      record(4,
          bed: const TimeOfDay(hour: 23, minute: 0),
          wake: const TimeOfDay(hour: 8, minute: 0)),
      record(5,
          bed: const TimeOfDay(hour: 1, minute: 0),
          wake: const TimeOfDay(hour: 6, minute: 0),
          symptoms: ['疲倦'],
          emotions: const [Emotion(name: '焦躁', value: 4)],
          isPeriod: true),
      record(6, symptoms: ['頭痛']),
      record(7,
          bed: const TimeOfDay(hour: 23, minute: 0),
          wake: const TimeOfDay(hour: 8, minute: 0)),
    ]);
    expect(result.association.lowSleepDays, 1);
    expect(result.association.sameDayCounts['疲倦'], 1);
    expect(result.association.sameDayCounts['焦躁'], 1);
    expect(result.association.nextDayCounts['頭痛'], 1);
    expect(result.association.pairedDates.single.isPeriod, isTrue);
    expect(result.points.firstWhere((point) => point.date.day == 5).isPeriod,
        isTrue);
  });

  test('缺少睡眠紀錄的日期仍會保留生理期標示', () {
    final result = service.analyze(
      records: [
        record(7,
            bed: const TimeOfDay(hour: 23, minute: 0),
            wake: const TimeOfDay(hour: 7, minute: 0)),
      ],
      endDate: DateTime(2026, 1, 7),
      period: SleepInsightPeriod.sevenDays,
      periodCycles: [
        PeriodCycle(
          id: 'cycle',
          startDate: DateTime(2026, 1, 3),
          endDate: DateTime(2026, 1, 5),
        ),
      ],
    );
    expect(
      result.points
          .where((point) => point.isPeriod)
          .map((point) => point.date.day),
      [3, 4, 5],
    );
  });
}
