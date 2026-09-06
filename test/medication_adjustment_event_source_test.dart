import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/med_symptom_compare_models.dart';
import 'package:moodsogood_app/meds/medication_adjustment_service.dart';

void main() {
  group('MedicationChangeDetector', () {
    test('備註與名稱等非臨床欄位不建立事件', () {
      final events = MedicationChangeDetector.detect(
        medDocId: 'med-1',
        before: {
          'name': 'A',
          'dose': 10,
          'unit': 'mg',
          'times': ['晚上', '早上'],
          'isActive': true,
          'note': 'old',
        },
        after: {
          'name': 'B',
          'dose': 10.0,
          'unit': 'MG',
          'times': ['早上', '晚上'],
          'isActive': true,
          'note': 'new',
        },
      );

      expect(events, isEmpty);
    });

    test('舊資料缺少 dose 但可由單位劑量與顆數解析時不誤判', () {
      final events = MedicationChangeDetector.detect(
        medDocId: 'legacy-med',
        before: {'dosePerUnit': 25, 'pillCount': 2},
        after: {'dose': 50.0, 'dosePerUnit': 25.0, 'pillCount': 2.0},
      );

      expect(events, isEmpty);
    });

    test('劑量與時段同時改變會分別保存兩種調整', () {
      final events = MedicationChangeDetector.detect(
        medDocId: 'med-2',
        before: {
          'name': 'A',
          'dose': 10,
          'unit': 'mg',
          'times': ['早上'],
        },
        after: {
          'name': 'A',
          'dose': 20,
          'unit': 'mg',
          'times': ['晚上'],
        },
      );

      expect(events, hasLength(2));
      expect(events.map((event) => event['type']), [
        'doseChanged',
        'scheduleChanged',
      ]);
      expect(events.last['oldTimes'], ['早上']);
      expect(events.last['newTimes'], ['晚上']);
      expect(events.every((event) => event['medDocId'] == 'med-2'), isTrue);
    });

    test('啟用狀態改變建立 stopped 或 resumed', () {
      final stopped = MedicationChangeDetector.detect(
        medDocId: 'med-3',
        before: {'isActive': true},
        after: {'isActive': false},
      );
      final resumed = MedicationChangeDetector.detect(
        medDocId: 'med-3',
        before: {'isActive': false},
        after: {'isActive': true},
      );

      expect(stopped.single['type'], 'stopped');
      expect(resumed.single['type'], 'resumed');
    });

    test('新增事件帶完整識別、劑量、時段與狀態', () {
      final event = MedicationChangeDetector.addedItem(
        medDocId: 'med-4',
        medication: {
          'name': 'A',
          'dose': 15,
          'dosePerUnit': 10,
          'pillCount': 1.5,
          'unit': 'mg',
          'times': ['睡前'],
          'isActive': true,
        },
      );

      expect(event['medDocId'], 'med-4');
      expect(event['type'], 'added');
      expect(event['newDose'], 15);
      expect(event['newTimes'], ['睡前']);
      expect(event['newIsActive'], isTrue);
    });
  });

  group('synthetic added event fallback', () {
    test('僅依 startDate 推定，不使用 updatedAt', () {
      final events = buildSyntheticAddedEvents([
        {
          'id': 'with-start',
          'name': '有開始日',
          'startDate': '2026-01-02',
          'updatedAt': '2026-07-01',
          'dose': 5,
          'unit': 'mg',
        },
        {
          'id': 'updated-only',
          'name': '只有更新日',
          'updatedAt': '2026-07-01',
        },
      ], const []);

      expect(events, hasLength(1));
      expect(events.single.medDocId, 'with-start');
      expect(events.single.date, DateTime(2026, 1, 2));
      expect(events.single.isInferred, isTrue);
    });

    test('已有任何正式事件的藥物不再建立推定事件', () {
      final persisted = MedicationAdjustmentEvent(
        adjustmentId: 'adj-1',
        itemIndex: 0,
        medDocId: 'med-1',
        medName: 'A',
        date: DateTime(2026, 2, 1),
        type: 'doseChanged',
      );

      final events = buildSyntheticAddedEvents([
        {'id': 'med-1', 'name': 'A', 'startDate': '2026-01-01'},
      ], [
        persisted
      ]);

      expect(events, isEmpty);
    });
  });
}
