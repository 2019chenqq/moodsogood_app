import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/med_symptom_compare_models.dart';

void main() {
  group('DailyRecordAggregator', () {
    test('Map 中的 0、false 與 null 不算症狀出現', () {
      final aggregate = DailyRecordAggregator.aggregate([
        {
          'symptoms': {'頭痛': 0, '噁心': 3, '心悸': false, '暈眩': null},
        },
      ]);

      expect(aggregate.symptoms.keys, {'噁心'});
      expect(aggregate.symptoms['噁心']!.presentDays, 1);
      expect(aggregate.symptoms['噁心']!.averageScore, 3);
    });

    test('症狀欄位缺少時保守視為未記錄', () {
      final aggregate = DailyRecordAggregator.aggregate([
        {
          'emotions': [
            {'name': '平靜', 'value': 4},
          ],
        },
      ]);

      expect(aggregate.symptomRecordedDays, 0);
      expect(aggregate.emotionRecordedDays, 1);
    });

    test('舊資料空症狀清單不直接推定為已完成', () {
      final aggregate = DailyRecordAggregator.aggregate([
        {'symptoms': <String>[]},
      ]);

      expect(aggregate.symptomRecordedDays, 0);
      expect(aggregate.symptoms, isEmpty);
    });

    test('明確 completed 的空症狀清單代表沒有症狀', () {
      final aggregate = DailyRecordAggregator.aggregate([
        {'symptomSectionCompleted': true, 'symptoms': <String>[]},
      ]);

      expect(aggregate.symptomRecordedDays, 1);
      expect(aggregate.symptoms, isEmpty);
      expect(aggregate.symptomRecordSummary.confirmedRecordedDays, 1);
      expect(aggregate.symptomRecordSummary.inferredRecordedDays, 0);
    });

    test('明確 false 的空症狀不列入分母', () {
      final aggregate = DailyRecordAggregator.aggregate([
        {'symptomSectionCompleted': false, 'symptoms': <String>[]},
      ]);

      expect(aggregate.symptomRecordedDays, 0);
      expect(aggregate.symptomRecordSummary.notRecordedDays, 1);
      expect(
        DailyRecordAggregator.resolveSymptomStatus({
          'symptomSectionCompleted': false,
          'symptoms': <String>[],
        }),
        SectionRecordStatus.notCompleted,
      );
    });

    test('舊資料有內容才視為 legacyInferred', () {
      expect(
        DailyRecordAggregator.resolveSymptomStatus({
          'symptoms': ['頭痛'],
        }),
        SectionRecordStatus.legacyInferred,
      );
      expect(
        DailyRecordAggregator.resolveSymptomStatus({
          'symptoms': <String>[],
        }),
        SectionRecordStatus.notCompleted,
      );
    });

    test('情緒、症狀與每日狀態各自統計完成狀態', () {
      final aggregate = DailyRecordAggregator.aggregate([
        {
          'emotionSectionCompleted': true,
          'emotions': [
            {'name': '平靜', 'value': 4},
          ],
          'symptomSectionCompleted': false,
          'stateSectionCompleted': false,
        },
      ]);

      expect(aggregate.emotionRecordSummary.confirmedRecordedDays, 1);
      expect(aggregate.symptomRecordSummary.notRecordedDays, 1);
      expect(aggregate.stateRecordSummary.notRecordedDays, 1);
    });

    test('單一情緒指標只保留實際有值的樣本天數', () {
      final aggregate = DailyRecordAggregator.aggregate([
        for (var day = 0; day < 7; day++)
          {
            'emotionSectionCompleted': true,
            'emotions': [
              if (day < 3) {'name': '焦慮', 'value': day + 1},
              {'name': '平靜', 'value': 4},
            ],
          },
      ]);

      expect(aggregate.emotionRecordedDays, 7);
      expect(aggregate.emotions['焦慮']!.recordedDays, 3);
      expect(aggregate.emotions['平靜']!.recordedDays, 7);
    });
  });

  group('CompareEngine', () {
    test('正向情緒增加是可能改善', () {
      final result = _emotionResult('平靜', 2, 4);
      expect(result.metricDirection, MetricDirection.higherIsBetter);
      expect(result.possiblyImproved, isTrue);
      expect(result.needsAttention, isFalse);
    });

    test('負向情緒增加是需要留意', () {
      final result = _emotionResult('焦慮', 2, 4);
      expect(result.metricDirection, MetricDirection.higherIsWorse);
      expect(result.needsAttention, isTrue);
      expect(result.possiblyImproved, isFalse);
    });

    test('中性狀態增加不直接判定改善或惡化', () {
      final before = DailyRecordAggregator.aggregate([
        {
          'stateChanges': {'energy_change': 2},
        },
      ]);
      final after = DailyRecordAggregator.aggregate([
        {
          'stateChanges': {'energy_change': 5},
        },
      ]);
      final result = CompareEngine.compare(before, after).single;

      expect(result.metricDirection, MetricDirection.neutralChange);
      expect(result.direction, ChangeDirection.increased);
      expect(result.possiblyImproved, isFalse);
      expect(result.needsAttention, isFalse);
    });

    test('前段明確沒有、後段一次即標為新出現', () {
      final before = DailyRecordAggregator.aggregate([
        {'symptomSectionCompleted': true, 'symptoms': <String>[]},
        {'symptomSectionCompleted': true, 'symptoms': <String>[]},
      ]);
      final after = DailyRecordAggregator.aggregate([
        {
          'symptoms': ['頭痛']
        },
        {'symptomSectionCompleted': true, 'symptoms': <String>[]},
      ]);
      final result = CompareEngine.compare(before, after).single;

      expect(result.newlyAppeared, isTrue);
      expect(result.afterPresentDays, 1);
      expect(result.afterOccurrenceRate, 50);
    });

    test('後段未填症狀頁時資料不足，不算消失或改善', () {
      final before = DailyRecordAggregator.aggregate([
        {
          'symptoms': ['頭痛']
        },
      ]);
      final after = DailyRecordAggregator.aggregate([
        {
          'emotions': [
            {'name': '平靜', 'value': 3},
          ],
        },
      ]);
      final result = CompareEngine.compare(before, after)
          .firstWhere((item) => item.name == '頭痛');

      expect(result.sufficientData, isFalse);
      expect(result.disappeared, isFalse);
      expect(result.possiblyImproved, isFalse);
    });

    test('頻率不變但強度增加會判定需要留意', () {
      final before = DailyRecordAggregator.aggregate(
        List.generate(
            5,
            (_) => {
                  'symptoms': {'頭痛': 1}
                }),
      );
      final after = DailyRecordAggregator.aggregate(
        List.generate(
            5,
            (_) => {
                  'symptoms': {'頭痛': 4}
                }),
      );
      final result = CompareEngine.compare(before, after).single;

      expect(result.occurrenceDirection, ChangeDirection.stable);
      expect(result.severityDirection, ChangeDirection.increased);
      expect(result.severityMagnitude, ChangeMagnitude.highAttention);
      expect(result.symptomPattern, SymptomChangePattern.worsened);
      expect(result.needsAttention, isTrue);
    });

    test('頻率下降但強度上升會判定變化不一致', () {
      final before = DailyRecordAggregator.aggregate([
        ...List.generate(
            8,
            (_) => {
                  'symptoms': {'頭痛': 2}
                }),
        ...List.generate(
            2,
            (_) => {
                  'symptomSectionCompleted': true,
                  'symptoms': <String>[],
                }),
      ]);
      final after = DailyRecordAggregator.aggregate([
        ...List.generate(
            3,
            (_) => {
                  'symptoms': {'頭痛': 4}
                }),
        ...List.generate(
            7,
            (_) => {
                  'symptomSectionCompleted': true,
                  'symptoms': <String>[],
                }),
      ]);
      final result = CompareEngine.compare(before, after).single;

      expect(result.occurrenceDirection, ChangeDirection.decreased);
      expect(result.severityDirection, ChangeDirection.increased);
      expect(result.symptomPattern, SymptomChangePattern.mixed);
      expect(result.possiblyImproved, isFalse);
      expect(result.needsAttention, isFalse);
    });

    test('前後各一筆情緒資料只能視為非常有限', () {
      final result = _emotionResult('焦慮', 2, 4, days: 1);

      expect(result.dataAdequacy, DataAdequacy.veryLimited);
      expect(result.canCalculate, isTrue);
      expect(result.canInterpret, isFalse);
      expect(result.needsAttention, isFalse);
    });

    test('新出現一次屬初步變化，不直接列為高度關注', () {
      final before = DailyRecordAggregator.aggregate(List.generate(
        3,
        (_) => {'symptomSectionCompleted': true, 'symptoms': <String>[]},
      ));
      final after = DailyRecordAggregator.aggregate([
        {
          'symptoms': ['頭痛']
        },
        ...List.generate(
          2,
          (_) => {'symptomSectionCompleted': true, 'symptoms': <String>[]},
        ),
      ]);
      final result = CompareEngine.compare(before, after).single;

      expect(result.newlyAppeared, isTrue);
      expect(result.occurrenceMagnitude, ChangeMagnitude.minor);
      expect(result.needsAttention, isFalse);
    });
  });

  test('30 天窗口只有前後各 5 天為低信心', () {
    expect(
      calculateCompareConfidence(
        beforeEffectiveDays: 5,
        afterEffectiveDays: 5,
        windowDays: 30,
        hasConcurrentAdjustments: false,
      ),
      CompareConfidence.low,
    );
  });

  test('推定天數超過明確完成天數時信心最高為低', () {
    expect(
      adjustConfidenceForLegacyData(
        original: CompareConfidence.high,
        confirmedDays: 2,
        inferredDays: 5,
      ),
      CompareConfidence.low,
    );
  });

  test('少量推定資料會將信心降低一級', () {
    expect(
      adjustConfidenceForLegacyData(
        original: CompareConfidence.high,
        confirmedDays: 6,
        inferredDays: 1,
      ),
      CompareConfidence.medium,
    );
    expect(
      adjustConfidenceForLegacyData(
        original: CompareConfidence.high,
        confirmedDays: 7,
        inferredDays: 0,
      ),
      CompareConfidence.high,
    );
  });

  test('分類信心會使用自己的 confirmed 與 inferred 比例', () {
    DailyRecordAggregate period() => DailyRecordAggregator.aggregate([
          ...List.generate(
            2,
            (_) => {
              'symptomSectionCompleted': true,
              'symptoms': ['頭痛'],
            },
          ),
          ...List.generate(
            5,
            (_) => {
              'symptoms': ['頭痛'],
            },
          ),
        ]);
    final confidence = CompareConfidenceSummary.calculate(
      before: period(),
      after: period(),
      beforeAvailableDays: 7,
      afterAvailableDays: 7,
      hasConcurrentAdjustments: false,
    );

    expect(confidence.symptom, CompareConfidence.low);
    expect(period().symptomRecordSummary.inferredRecordedDays, 5);
  });

  test('調藥事件解析會排除 unchanged', () {
    final events = MedicationAdjustmentEvent.fromRecord({
      'id': 'adjustment-1',
      'date': '2026/07/16',
      'items': [
        {'medDocId': 'med-1', 'name': 'A', 'type': 'unchanged'},
        {
          'medDocId': 'med-1',
          'name': 'A',
          'type': 'doseChanged',
          'oldDose': 100,
          'newDose': 200,
          'unit': 'mg',
        },
      ],
    });

    expect(events, hasLength(1));
    expect(events.single.type, 'doseChanged');
    expect(events.single.changeSummary, '100 mg → 200 mg');
  });

  test('僅有單位劑量與顆數時會解析總劑量增減', () {
    final event = MedicationAdjustmentEvent.fromRecord({
      'id': 'adjustment-dose',
      'date': '2026/07/16',
      'items': [
        {
          'name': 'A',
          'type': 'doseChanged',
          'oldDosePerUnit': 50,
          'oldPillCount': 1,
          'newDosePerUnit': 50,
          'newPillCount': 2,
          'unit': 'mg',
        },
      ],
    }).single;

    expect(event.resolvedOldTotalDose, 50);
    expect(event.resolvedNewTotalDose, 100);
    expect(event.typeLabel, '劑量增加');
  });

  test('同一天兩筆 daily record 只計為一天並安全合併區塊', () {
    final records = deduplicateDailyRecords([
      const LogicalDailyRecord(
        id: 'legacy-random',
        data: {
          'date': '2026-07-18',
          'emotions': [
            {'name': '平靜', 'value': 3},
          ],
        },
      ),
      const LogicalDailyRecord(
        id: '2026-07-18',
        data: {
          'date': '2026-07-18',
          'symptoms': ['頭痛'],
        },
      ),
    ]);

    expect(records, hasLength(1));
    expect(records.single.data['emotions'], isNotNull);
    expect(records.single.data['symptoms'], ['頭痛']);
  });

  test('尚未完成的觀察期只使用已經過的日曆天數', () {
    final status = ObservationWindowStatus.calculate(
      eventDate: DateTime(2026, 8, 1),
      requestedDays: 14,
      now: DateTime(2026, 8, 4),
    );

    expect(status.elapsedAfterDays, 3);
    expect(status.remainingDays, 11);
    expect(status.completed, isFalse);
    expect(status.expectedCompletionDate, DateTime(2026, 8, 15));
  });

  test('分類信心不會被其他類型的完整資料墊高', () {
    final before = DailyRecordAggregator.aggregate(List.generate(7, (index) {
      return {
        'emotionSectionCompleted': true,
        'emotions': [
          {'name': '平靜', 'value': 3},
        ],
        if (index == 0) 'symptoms': ['頭痛'],
      };
    }));
    final after = DailyRecordAggregator.aggregate(List.generate(7, (index) {
      return {
        'emotionSectionCompleted': true,
        'emotions': [
          {'name': '平靜', 'value': 4},
        ],
        if (index == 0) 'symptoms': ['頭痛'],
      };
    }));
    final confidence = CompareConfidenceSummary.calculate(
      before: before,
      after: after,
      beforeAvailableDays: 7,
      afterAvailableDays: 7,
      hasConcurrentAdjustments: false,
    );

    expect(confidence.emotion, CompareConfidence.high);
    expect(confidence.symptom, CompareConfidence.low);
  });

  test('主檔已刪除的藥物仍會由歷史事件加入選單', () {
    final events = MedicationAdjustmentEvent.fromRecord({
      'id': 'old-visit',
      'date': '2026-06-01',
      'items': [
        {'name': '  Olanzapine  ', 'type': 'stopped'},
      ],
    });
    final options = mergeMedicationCompareOptions(const [], events);

    expect(options, hasLength(1));
    expect(options.single.name, 'Olanzapine');
    expect(options.single.existsOnlyInHistory, isTrue);
    expect(options.single.statusLabel, '歷史紀錄');
  });

  test('同一 adjustmentId 的兩個事件會視為一筆兩項變動', () {
    final events = MedicationAdjustmentEvent.fromRecord({
      'id': 'same-visit',
      'date': '2026-07-18',
      'items': [
        {'name': 'A', 'type': 'stopped'},
        {'name': 'B', 'type': 'resumed'},
      ],
    });
    final groups = groupAdjustmentEvents(events);

    expect(groups, hasLength(1));
    expect(groups.values.single, hasLength(2));
  });
}

CompareMetricResult _emotionResult(
  String name,
  double before,
  double after, {
  int days = 5,
}) {
  final beforeAggregate = DailyRecordAggregator.aggregate(List.generate(
    days,
    (_) => {
      'emotions': [
        {'name': name, 'value': before},
      ],
    },
  ));
  final afterAggregate = DailyRecordAggregator.aggregate(List.generate(
    days,
    (_) => {
      'emotions': [
        {'name': name, 'value': after},
      ],
    },
  ));
  return CompareEngine.compare(beforeAggregate, afterAggregate).single;
}
