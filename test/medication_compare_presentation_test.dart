import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/med_symptom_compare_models.dart';
import 'package:moodsogood_app/meds/medication_compare_presentation.dart';
import 'package:moodsogood_app/meds/medication_subjective_response.dart';
import 'package:moodsogood_app/meds/medication_subjective_summary_builder.dart';

void main() {
  test('occurrence days, rates, event counts, and severity keep their units',
      () {
    final presentation = MedicationCompareMetricPresentation(
      _result(
        beforePresentDays: 3,
        beforeRecordedDays: 7,
        afterPresentDays: 5,
        afterRecordedDays: 7,
        beforeRate: 42.9,
        afterRate: 71.4,
        beforeEvents: 2,
        afterEvents: 8,
        beforeAverage: 2.5,
        afterAverage: 3.6,
        beforeMax: 4,
        afterMax: 5,
      ),
    );

    expect(
      presentation.primaryOccurrenceLine,
      '調整前 3/7 天 → 調整後 5/7 天',
    );
    expect(presentation.symptomDetailLines, contains('快速記錄：2次 → 8次'));
    expect(presentation.symptomDetailLines, contains('平均強度：2.5/5 → 3.6/5'));
    expect(presentation.symptomDetailLines, contains('最高強度：4.0/5 → 5.0/5'));
    expect(presentation.symptomDetailLines.join(), isNot(contains('8天')));
  });

  test('legacy-only symptom does not display invented event or severity data',
      () {
    final presentation = MedicationCompareMetricPresentation(
      _result(beforePresentDays: 1, beforeRecordedDays: 3),
    );

    expect(
      presentation.symptomDetailLines
          .where((line) => line.contains('快速記錄') || line.contains('強度')),
      isEmpty,
    );
  });

  test('zero recorded days displays data insufficiency without division text',
      () {
    final presentation = MedicationCompareMetricPresentation(_result());

    expect(
      presentation.primaryOccurrenceLine,
      '調整前 資料不足 → 調整後 資料不足',
    );
    expect(presentation.primaryOccurrenceLine, isNot(contains('0/0')));
    expect(presentation.symptomDetailLines, contains('發生率：資料不足 → 資料不足'));
    expect(presentation.symptomDetailLines.join(), isNot(contains('NaN')));
    expect(presentation.symptomDetailLines.join(), isNot(contains('Infinity')));
  });

  test('only completed subjective follow-ups create presentation rows', () {
    final presentations = [_response(3)]
        .map(MedicationSubjectiveResponsePresentation.new)
        .toList();

    expect(presentations, hasLength(1));
    expect(presentations.single.title, 'Day 3｜感覺較差');
    expect(presentations.single.detailLines, contains('主觀變化：疲倦'));
  });

  test('two medications sharing a change remain separated for UI input', () {
    final responses = [
      _response(3, medicationId: 'a'),
      _response(7, medicationId: 'b')
    ];
    final forA = MedicationSubjectiveSummaryBuilder.forMedicationChange(
      responses,
      medicationId: 'a',
      changeRecordId: 'change-1',
      medicationIdsForChange: {'a', 'b'},
    );

    expect(forA.map((item) => item.medicationId), ['a']);
  });

  test('ambiguous legacy response is not assigned to either medication', () {
    final legacy = MedicationSubjectiveResponse.fromMap({
      ..._response(3).toMap(),
      'medicationId': '',
    });
    final matched = MedicationSubjectiveSummaryBuilder.forMedicationChange(
      [legacy],
      medicationId: 'a',
      changeRecordId: 'change-1',
      medicationIdsForChange: {'a', 'b'},
    );

    expect(matched, isEmpty);
  });
}

CompareMetricResult _result({
  int beforePresentDays = 0,
  int afterPresentDays = 0,
  int beforeRecordedDays = 0,
  int afterRecordedDays = 0,
  double? beforeRate,
  double? afterRate,
  int beforeEvents = 0,
  int afterEvents = 0,
  double? beforeAverage,
  double? afterAverage,
  double? beforeMax,
  double? afterMax,
}) =>
    CompareMetricResult(
      name: '疲倦',
      kind: CompareMetricKind.symptom,
      metricDirection: MetricDirection.higherIsWorse,
      newlyAppeared: false,
      disappeared: false,
      direction: ChangeDirection.stable,
      magnitude: ChangeMagnitude.stable,
      occurrenceDirection: ChangeDirection.stable,
      occurrenceMagnitude: ChangeMagnitude.stable,
      severityDirection: ChangeDirection.stable,
      severityMagnitude: ChangeMagnitude.stable,
      symptomPattern: SymptomChangePattern.stable,
      beforeOccurrenceRate: beforeRate,
      afterOccurrenceRate: afterRate,
      beforeAverageScore: beforeAverage,
      afterAverageScore: afterAverage,
      beforeMaximumScore: beforeMax,
      afterMaximumScore: afterMax,
      beforePresentDays: beforePresentDays,
      afterPresentDays: afterPresentDays,
      beforeRecordedDays: beforeRecordedDays,
      afterRecordedDays: afterRecordedDays,
      confidence: CompareConfidence.low,
      dataAdequacy: DataAdequacy.limited,
      beforeEventCount: beforeEvents,
      afterEventCount: afterEvents,
    );

MedicationSubjectiveResponse _response(
  int day, {
  String medicationId = 'a',
}) =>
    MedicationSubjectiveResponse(
      id: '$medicationId-$day',
      medicationId: medicationId,
      medicationName: '測試藥物',
      changeRecordId: 'change-1',
      changeDate: DateTime(2026, 8, 1),
      followUpDay: day,
      recordedAt: DateTime(2026, 8, 1 + day),
      overallResponse: MedicationOverallResponse.worse,
      changedAreas: const ['疲倦'],
      perceivedRelation: MedicationPerceivedRelation.unsure,
      otherFactors: const [],
    );
