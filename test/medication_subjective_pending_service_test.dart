import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/medication_subjective_pending_service.dart';
import 'package:moodsogood_app/meds/medication_subjective_response.dart';
import 'package:moodsogood_app/meds/medication_subjective_tracking_cycle.dart';

void main() {
  test('adjustment date is Day 0 and Day 3 becomes pending all day', () {
    final cycle = _cycle(changeDate: DateTime(2026, 8, 14, 16));

    expect(
      MedicationSubjectivePendingDetector.detect(
        cycles: [cycle],
        responses: const [],
        today: DateTime(2026, 8, 14, 23),
      ),
      isEmpty,
    );
    final pending = MedicationSubjectivePendingDetector.detect(
      cycles: [cycle],
      responses: const [],
      today: DateTime(2026, 8, 17, 23, 30),
    );
    expect(pending.map((item) => item.followUpDay), [3]);
    expect(pending.single.calculatedDay, 3);
  });

  test('at Day 7 a missed Day 3 is skipped instead of backfilled', () {
    final pending = MedicationSubjectivePendingDetector.detect(
      cycles: [_cycle(changeDate: DateTime(2026, 8, 10))],
      responses: const [],
      today: DateTime(2026, 8, 17),
    );

    expect(pending.map((item) => item.followUpDay), [7]);
  });

  test('completed follow-up day is not pending again', () {
    final cycle = _cycle(changeDate: DateTime(2026, 8, 10));
    final pending = MedicationSubjectivePendingDetector.detect(
      cycles: [cycle],
      responses: [_response(cycle, 3)],
      today: DateTime(2026, 8, 17),
    );

    expect(pending.map((item) => item.followUpDay), [7]);
  });

  test('inactive superseded or stopped cycle never creates pending UI', () {
    final cycle = _cycle(changeDate: DateTime(2026, 8, 10)).end(
      endedAt: DateTime(2026, 8, 12),
      reason: 'supersededByMedicationChange',
      supersededByChangeRecordId: 'change-2',
    );

    expect(
      MedicationSubjectivePendingDetector.detect(
        cycles: [cycle],
        responses: const [],
        today: DateTime(2026, 8, 17),
      ),
      isEmpty,
    );
  });

  test('multiple medications in one changeRecord create one questionnaire', () {
    final first = _cycle(changeDate: DateTime(2026, 8, 14));
    final second = MedicationSubjectiveTrackingCycle(
      id: 'cycle-2',
      medicationId: 'med-2',
      changeRecordId: 'change-1',
      changeDate: DateTime(2026, 8, 14, 16),
      medicationName: '測試藥物二',
      changeType: MedicationTrackingChangeType.scheduleChanged,
      active: true,
    );

    final pending = MedicationSubjectivePendingDetector.detect(
      cycles: [first, second],
      responses: const [],
      today: DateTime(2026, 8, 17),
    );

    expect(pending, hasLength(1));
    expect(pending.single.cycles, hasLength(2));
  });

  test('only latest active changeRecord is shown', () {
    final old = _cycle(changeDate: DateTime(2026, 8, 1));
    final latest = MedicationSubjectiveTrackingCycle(
      id: 'cycle-latest',
      medicationId: 'med-2',
      changeRecordId: 'change-latest',
      changeDate: DateTime(2026, 8, 10),
      medicationName: '新調整',
      changeType: MedicationTrackingChangeType.added,
      active: true,
    );
    final pending = MedicationSubjectivePendingDetector.detect(
      cycles: [old, latest],
      responses: const [],
      today: DateTime(2026, 8, 17),
    );

    expect(pending, hasLength(1));
    expect(pending.single.cycle.changeRecordId, 'change-latest');
    expect(pending.single.followUpDay, 7);
  });

  test('completed response on any changeRecord in episode completes milestone',
      () {
    final episode = MedicationSubjectiveTrackingCycle(
      id: 'episode-change-old',
      medicationId: 'med-2',
      changeRecordId: 'change-new',
      changeDate: DateTime(2026, 8, 14),
      medicationName: '本次調整',
      changeType: MedicationTrackingChangeType.scheduleChanged,
      active: true,
      episodeId: 'episode-change-old',
      episodeStartDate: DateTime(2026, 8, 13),
      changeRecordIds: const ['change-old', 'change-new'],
      medicationIds: const ['med-1', 'med-2'],
      adjustmentTypes: const ['doseChanged', 'scheduleChanged'],
    );
    final oldResponse = MedicationSubjectiveResponse(
      id: 'response-old',
      medicationId: 'med-1',
      medicationName: 'A',
      changeRecordId: 'change-old',
      changeDate: DateTime(2026, 8, 14),
      followUpDay: 3,
      recordedAt: DateTime(2026, 8, 17),
      overallResponse: MedicationOverallResponse.noChange,
      changedAreas: const [],
      perceivedRelation: MedicationPerceivedRelation.unsure,
      otherFactors: const [],
    );
    final pending = MedicationSubjectivePendingDetector.detect(
      cycles: [episode],
      responses: [oldResponse],
      today: DateTime(2026, 8, 17),
    );
    expect(pending, isEmpty);
  });

  test('latest repaired active cycle can produce the current milestone', () {
    final repaired = _cycle(changeDate: DateTime(2026, 8, 7));
    final pending = MedicationSubjectivePendingDetector.detect(
      cycles: [repaired],
      responses: const [],
      today: DateTime(2026, 8, 17),
    );

    expect(pending, hasLength(1));
    expect(pending.single.followUpDay, 7);
    expect(pending.single.calculatedDay, 10);
  });

  test('cycle serialization explicitly includes follow-up days and active', () {
    final map = _cycle(changeDate: DateTime(2026, 8, 14)).toMap();

    expect(map['followUpDays'], [3, 7, 14, 28]);
    expect(map['active'], isTrue);
    expect(map['medicationId'], 'med-1');
    expect(map['changeRecordId'], 'change-1');
  });
}

MedicationSubjectiveTrackingCycle _cycle({required DateTime changeDate}) =>
    MedicationSubjectiveTrackingCycle(
      id: 'cycle-1',
      medicationId: 'med-1',
      changeRecordId: 'change-1',
      changeDate: changeDate,
      medicationName: '測試藥物',
      changeType: MedicationTrackingChangeType.doseIncreased,
      oldDose: 10,
      newDose: 20,
      doseUnit: 'mg',
      active: true,
    );

MedicationSubjectiveResponse _response(
  MedicationSubjectiveTrackingCycle cycle,
  int day,
) =>
    MedicationSubjectiveResponse(
      id: 'response-$day',
      medicationId: cycle.medicationId,
      medicationName: cycle.medicationName,
      changeRecordId: cycle.changeRecordId,
      changeDate: cycle.changeDate,
      followUpDay: day,
      recordedAt: cycle.changeDate.add(Duration(days: day)),
      overallResponse: MedicationOverallResponse.noChange,
      changedAreas: const [],
      perceivedRelation: MedicationPerceivedRelation.unsure,
      otherFactors: const [],
    );
