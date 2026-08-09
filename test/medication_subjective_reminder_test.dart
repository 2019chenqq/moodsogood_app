import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/medication_subjective_reminder_payload.dart';
import 'package:moodsogood_app/meds/medication_subjective_reminder_service.dart';
import 'package:moodsogood_app/meds/medication_subjective_response.dart';
import 'package:moodsogood_app/meds/medication_subjective_tracking_cycle.dart';

void main() {
  MedicationSubjectiveTrackingCycle cycle({
    String id = 'cycle-1',
    String medicationId = 'med-1',
    String changeRecordId = 'change-1',
    bool active = true,
  }) =>
      MedicationSubjectiveTrackingCycle(
        id: id,
        medicationId: medicationId,
        changeRecordId: changeRecordId,
        changeDate: DateTime(2026, 8, 1),
        medicationName: 'A',
        changeType: MedicationTrackingChangeType.doseIncreased,
        oldDose: 10,
        newDose: 20,
        active: active,
      );

  MedicationSubjectiveResponse response(int day) =>
      MedicationSubjectiveResponse(
        id: 'response-$day',
        medicationId: 'med-1',
        medicationName: 'A',
        changeRecordId: 'change-1',
        changeDate: DateTime(2026, 8, 1),
        followUpDay: day,
        recordedAt: DateTime(2026, 8, 2),
        overallResponse: MedicationOverallResponse.unsure,
        changedAreas: const [],
        perceivedRelation: MedicationPerceivedRelation.unsure,
        otherFactors: const [],
      );

  test('plans future Day 3, 7, 14, and 28 reminders at 20:00', () {
    final reminders = MedicationSubjectiveReminderPlanner.build(
      cycles: [cycle()],
      responses: const [],
      now: DateTime(2026, 8, 1, 12),
    );

    expect(reminders.map((item) => item.followUpDay), [3, 7, 14, 28]);
    expect(reminders.first.scheduledAt, DateTime(2026, 8, 4, 20));
    expect(reminders.map((item) => item.notificationId).toSet(), hasLength(4));
  });

  test('skips inactive, completed, and expired reminders', () {
    final reminders = MedicationSubjectiveReminderPlanner.build(
      cycles: [cycle(), cycle(id: 'inactive', active: false)],
      responses: [response(7)],
      now: DateTime(2026, 8, 5),
    );

    expect(reminders.map((item) => item.followUpDay), [14, 28]);
  });

  test('different medication cycles receive different notification ids', () {
    final reminders = MedicationSubjectiveReminderPlanner.build(
      cycles: [
        cycle(),
        cycle(
          id: 'cycle-2',
          medicationId: 'med-2',
          changeRecordId: 'change-2',
        ),
      ],
      responses: const [],
      now: DateTime(2026, 8, 1),
    );
    expect(reminders.map((item) => item.notificationId).toSet(), hasLength(8));
  });

  test('payload round-trips questionnaire routing fields', () {
    const original = MedicationSubjectiveReminderPayload(
      cycleId: 'cycle-1',
      medicationId: 'med-1',
      changeRecordId: 'change-1',
      followUpDay: 14,
    );
    final restored =
        MedicationSubjectiveReminderPayload.tryDecode(original.encode());
    expect(restored?.cycleId, 'cycle-1');
    expect(restored?.medicationId, 'med-1');
    expect(restored?.changeRecordId, 'change-1');
    expect(restored?.followUpDay, 14);
  });
}
