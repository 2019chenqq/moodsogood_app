import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/medication_subjective_response.dart';

void main() {
  MedicationSubjectiveResponse response({int followUpDay = 7}) =>
      MedicationSubjectiveResponse(
        id: 'response-1',
        medicationId: 'med-1',
        medicationName: 'Medication A',
        changeRecordId: 'change-1',
        changeDate: DateTime(2026, 8, 1),
        followUpDay: followUpDay,
        recordedAt: DateTime(2026, 8, 8, 9, 30),
        overallResponse: MedicationOverallResponse.mixed,
        changedAreas: const ['sleep', 'mood'],
        perceivedRelation: MedicationPerceivedRelation.likely,
        otherFactors: const ['stress'],
        note: 'Subjective report only',
      );

  test('round-trips all subjective response fields', () {
    final original = response();
    final restored = MedicationSubjectiveResponse.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.medicationId, original.medicationId);
    expect(restored.changeRecordId, original.changeRecordId);
    expect(restored.followUpDay, 7);
    expect(restored.overallResponse, MedicationOverallResponse.mixed);
    expect(restored.changedAreas, ['sleep', 'mood']);
    expect(restored.perceivedRelation, MedicationPerceivedRelation.likely);
    expect(restored.otherFactors, ['stress']);
    expect(restored.note, 'Subjective report only');
  });

  test('accepts only Day 3, 7, 14, and 28', () {
    for (final day in MedicationSubjectiveResponse.allowedFollowUpDays) {
      expect(response(followUpDay: day).followUpDay, day);
    }
    expect(() => response(followUpDay: 10), throwsArgumentError);
  });

  test('requires medication and adjustment traceability ids', () {
    final map = response().toMap()..['changeRecordId'] = '';
    expect(
      () => MedicationSubjectiveResponse.fromMap(map),
      throwsFormatException,
    );
  });
}
