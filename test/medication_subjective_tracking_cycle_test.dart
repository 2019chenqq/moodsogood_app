import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/medication_adjustment_service.dart';
import 'package:moodsogood_app/meds/medication_subjective_tracking_cycle.dart';

void main() {
  group('MedicationSubjectiveTrackingCycle', () {
    test('creates Day 3, 7, 14, and 28 dates from Day 0', () {
      final cycle = MedicationSubjectiveTrackingCycle(
        id: 'cycle-1',
        medicationId: 'med-1',
        changeRecordId: 'change-1',
        changeDate: DateTime(2026, 8, 1),
        medicationName: 'A',
        changeType: MedicationTrackingChangeType.added,
        newDose: 10,
        active: true,
      );

      expect(cycle.followUpDates, {
        3: DateTime(2026, 8, 4),
        7: DateTime(2026, 8, 8),
        14: DateTime(2026, 8, 15),
        28: DateTime(2026, 8, 29),
      });
      final restored = MedicationSubjectiveTrackingCycle.fromMap(cycle.toMap());
      expect(restored.changeRecordId, 'change-1');
      expect(restored.newDose, 10);
      expect(restored.active, isTrue);
    });

    test('ending a cycle keeps its original tracking data', () {
      final cycle = MedicationSubjectiveTrackingCycle(
        id: 'cycle-1',
        medicationId: 'med-1',
        changeRecordId: 'change-1',
        changeDate: DateTime(2026, 8, 1),
        medicationName: 'A',
        changeType: MedicationTrackingChangeType.doseIncreased,
        oldDose: 10,
        newDose: 20,
        active: true,
      );
      final ended = cycle.end(
        endedAt: DateTime(2026, 8, 5),
        reason: 'supersededByMedicationChange',
        supersededByChangeRecordId: 'change-2',
      );

      expect(ended.active, isFalse);
      expect(ended.changeRecordId, 'change-1');
      expect(ended.followUpDates[7], DateTime(2026, 8, 8));
      expect(ended.supersededByChangeRecordId, 'change-2');
    });

    test('episode fields serialize while legacy cycle falls back safely', () {
      final episode = MedicationSubjectiveTrackingCycle(
        id: 'episode-change-1',
        medicationId: 'med-2',
        changeRecordId: 'change-2',
        changeDate: DateTime(2026, 8, 15),
        medicationName: 'B',
        changeType: MedicationTrackingChangeType.doseAdjusted,
        active: true,
        episodeId: 'episode-change-1',
        episodeStartDate: DateTime(2026, 8, 14),
        changeRecordIds: const ['change-1', 'change-2'],
        medicationIds: const ['med-1', 'med-2'],
        adjustmentTypes: const ['scheduleChanged', 'doseChanged'],
      );
      final restored = MedicationSubjectiveTrackingCycle.fromMap(
        episode.toMap(),
      );
      expect(restored.changeDate, DateTime(2026, 8, 15));
      expect(restored.episodeStartDate, DateTime(2026, 8, 14));
      expect(restored.changeRecordIds, ['change-1', 'change-2']);

      final legacyMap = episode.toMap()
        ..remove('episodeId')
        ..remove('episodeStartDate')
        ..remove('changeRecordIds')
        ..remove('medicationIds')
        ..remove('adjustmentTypes');
      final legacy = MedicationSubjectiveTrackingCycle.fromMap(legacyMap);
      expect(legacy.episodeId, legacy.changeRecordId);
      expect(legacy.changeRecordIds, [legacy.changeRecordId]);
      expect(legacy.medicationIds, [legacy.medicationId]);
    });
  });

  group('MedicationTrackingCycleFactory', () {
    MedicationSubjectiveTrackingCycle? build(
      List<Map<String, dynamic>> items,
    ) =>
        MedicationTrackingCycleFactory.fromAdjustmentItems(
          changeRecordId: 'change-1',
          changeDate: DateTime(2026, 8, 1),
          medicationId: 'med-1',
          items: items,
        );

    test('tracks added, increased, decreased, and resumed changes', () {
      expect(
        build([
          {'type': 'added', 'name': 'A', 'newDose': 10}
        ])!
            .changeType,
        MedicationTrackingChangeType.added,
      );
      expect(
        build([
          {
            'type': 'doseChanged',
            'name': 'A',
            'oldDose': 10,
            'newDose': 20,
          }
        ])!
            .changeType,
        MedicationTrackingChangeType.doseIncreased,
      );
      expect(
        build([
          {
            'type': 'doseChanged',
            'name': 'A',
            'oldDose': 20,
            'newDose': 5,
          }
        ])!
            .changeType,
        MedicationTrackingChangeType.doseDecreased,
      );
      expect(
        build([
          {'type': 'resumed', 'name': 'A', 'newDose': 5}
        ])!
            .changeType,
        MedicationTrackingChangeType.resumed,
      );
    });

    test('tracks schedule-only and indeterminate legacy dose changes', () {
      final schedule = build([
        {
          'type': 'scheduleChanged',
          'name': 'A',
          'oldTimes': ['早上'],
          'newTimes': ['睡前'],
        }
      ]);
      expect(
        schedule!.changeType,
        MedicationTrackingChangeType.scheduleChanged,
      );
      expect(schedule.oldTimes, ['早上']);
      expect(schedule.newTimes, ['睡前']);
      expect(schedule.adjustmentSummary, '服藥時間：早上 → 睡前');
      final dose = build([
        {'type': 'doseChanged', 'name': 'A', 'newDose': 10}
      ]);
      expect(dose, isNotNull);
      expect(dose!.changeType, MedicationTrackingChangeType.doseAdjusted);
    });

    test('dose and schedule changes share one cycle and one summary', () {
      final cycle = build([
        {
          'type': 'doseChanged',
          'name': 'A',
          'oldDose': 10,
          'newDose': 20,
          'unit': 'mg',
          'oldTimes': ['早上'],
          'newTimes': ['睡前'],
        }
      ]);

      expect(cycle!.changeType, MedicationTrackingChangeType.doseIncreased);
      expect(cycle.adjustmentSummary, '10mg → 20mg；服藥時間：早上 → 睡前');
      final restored = MedicationSubjectiveTrackingCycle.fromMap(cycle.toMap());
      expect(restored.oldTimes, ['早上']);
      expect(restored.newTimes, ['睡前']);
    });

    test('creates one cycle for a medication when resumed and dose changed',
        () {
      final cycle = build([
        {'type': 'doseChanged', 'name': 'A', 'oldDose': 10, 'newDose': 20},
        {'type': 'resumed', 'name': 'A', 'oldDose': 10, 'newDose': 20},
      ]);
      expect(cycle!.changeType, MedicationTrackingChangeType.resumed);
      expect(cycle.newDose, 20);
    });

    test('tracks doseChanged even when legacy dose direction is unavailable',
        () {
      final cycle = MedicationTrackingCycleFactory.fromAdjustmentItems(
        changeRecordId: 'change-compound',
        changeDate: DateTime(2026, 8, 14),
        medicationId: 'med-compound',
        items: const [
          {'type': 'doseChanged', 'name': '複方藥物'},
        ],
      );

      expect(cycle, isNotNull);
      expect(cycle!.changeType, MedicationTrackingChangeType.doseAdjusted);
      expect(cycle.adjustmentSummary, '調整劑量');
    });

    test('stopped is a valid episode adjustment', () {
      final cycle = MedicationTrackingCycleFactory.fromAdjustmentItems(
        changeRecordId: 'change-stop',
        changeDate: DateTime(2026, 8, 15),
        medicationId: 'med-stop',
        items: const [
          {'type': 'stopped', 'name': 'A'},
        ],
      );
      expect(cycle, isNotNull);
      expect(cycle!.changeType, MedicationTrackingChangeType.stopped);
    });
  });
}
