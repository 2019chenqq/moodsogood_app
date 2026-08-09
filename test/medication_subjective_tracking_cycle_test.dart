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

    test('does not track schedule-only or indeterminate dose changes', () {
      expect(
          build([
            {'type': 'scheduleChanged', 'name': 'A'}
          ]),
          isNull);
      expect(
        build([
          {'type': 'doseChanged', 'name': 'A', 'newDose': 10}
        ]),
        isNull,
      );
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
  });
}
