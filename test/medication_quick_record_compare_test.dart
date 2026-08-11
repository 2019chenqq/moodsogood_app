import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/med_symptom_compare_models.dart';
import 'package:moodsogood_app/meds/medication_adjustment_service.dart';
import 'package:moodsogood_app/meds/medication_subjective_response.dart';
import 'package:moodsogood_app/meds/medication_subjective_summary_builder.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';
import 'package:moodsogood_app/services/daily_health_aggregation_service.dart';

void main() {
  const aggregation = DailyHealthAggregationService();

  DailyRecordAggregate aggregate({
    List<DailyRecord> records = const [],
    List<HealthEvent> events = const [],
  }) {
    final base = DailyRecordAggregator.aggregate(records.map((record) => {
          'date': record.date,
          'bodySymptoms': record.symptoms,
        }));
    return DailyRecordAggregator.withAggregatedSymptoms(
      base,
      aggregation.aggregateRange(
        dailyRecords: records,
        healthEvents: events,
      ),
    );
  }

  test('five QuickRecords on one date add only one recorded day', () {
    final result = aggregate(events: _events([1, 2, 3, 4, 5]));

    expect(result.effectiveRecordDays, 1);
    expect(result.symptomRecordedDays, 1);
    expect(result.symptoms['心悸']?.eventCount, 5);
  });

  test('three same-day symptom events are one occurrence day', () {
    final metric = aggregate(events: _events([2, 4, 5])).symptoms['心悸']!;

    expect(metric.presentDays, 1);
    expect(metric.eventCount, 3);
  });

  test('before and after occurrence rates use unique recorded dates', () {
    final before = aggregate(events: [
      ..._events([2, 3, 4]),
      _event('other-day', DateTime(2026, 8, 10, 9), null),
    ]);
    final after = aggregate(events: [
      _event('after-present', DateTime(2026, 8, 13, 9), 3),
      _event('after-absent', DateTime(2026, 8, 14, 9), null),
    ]);

    expect(before.symptoms['心悸']?.occurrenceRate, 50);
    expect(after.symptoms['心悸']?.occurrenceRate, 50);
  });

  test('severity uses only HealthEvent values', () {
    final metric = aggregate(
      records: [
        _legacy(['心悸'])
      ],
      events: _events([2, 4]),
    ).symptoms['心悸']!;

    expect(metric.averageScore, 3);
    expect(metric.maximumScore, 4);
    expect(metric.scoredDays, 2);
  });

  test('DailyRecord and event on same day do not duplicate occurrence day', () {
    final metric = aggregate(
      records: [
        _legacy(['心悸'])
      ],
      events: [_event('same-day', DateTime(2026, 8, 11, 9), 3)],
    ).symptoms['心悸']!;

    expect(metric.recordedDays, 1);
    expect(metric.presentDays, 1);
  });

  test('Day 3 7 14 28 match medicationId and changeRecordId', () {
    final responses = [3, 7, 14, 28]
        .map((day) => _response('med-a', 'change-1', day))
        .toList();
    final matched = MedicationSubjectiveSummaryBuilder.forMedicationChange(
      responses,
      medicationId: 'med-a',
      changeRecordId: 'change-1',
      medicationIdsForChange: {'med-a'},
    );

    expect(matched.map((item) => item.followUpDay), [3, 7, 14, 28]);
  });

  test('two medications sharing one change record never mix responses', () {
    final responses = [
      _response('med-a', 'change-1', 3),
      _response('med-b', 'change-1', 3),
    ];
    final matched = MedicationSubjectiveSummaryBuilder.forMedicationChange(
      responses,
      medicationId: 'med-a',
      changeRecordId: 'change-1',
      medicationIdsForChange: {'med-a', 'med-b'},
    );

    expect(matched, hasLength(1));
    expect(matched.single.medicationId, 'med-a');
    expect(
      MedicationSubjectiveSummaryBuilder.toAiInput(responses),
      hasLength(2),
    );
  });

  test('missing subjective responses and legacy missing medicationId are safe',
      () {
    expect(
      MedicationSubjectiveSummaryBuilder.forMedicationChange(
        const [],
        medicationId: 'med-a',
        changeRecordId: 'change-1',
        medicationIdsForChange: {'med-a'},
      ),
      isEmpty,
    );
    final legacy = MedicationSubjectiveResponse.fromMap({
      ..._response('med-a', 'change-1', 3).toMap(),
      'medicationId': '',
    });
    expect(legacy.medicationId,
        MedicationSubjectiveResponse.legacyUnknownMedicationId);
  });

  test('concurrent medication adjustment cannot increase confidence', () {
    final withoutConcurrent = calculateCompareConfidence(
      beforeEffectiveDays: 7,
      afterEffectiveDays: 7,
      beforeAvailableDays: 7,
      afterAvailableDays: 7,
      hasConcurrentAdjustments: false,
      beforeConfirmedDays: 7,
      afterConfirmedDays: 7,
    );
    final withConcurrent = calculateCompareConfidence(
      beforeEffectiveDays: 7,
      afterEffectiveDays: 7,
      beforeAvailableDays: 7,
      afterAvailableDays: 7,
      hasConcurrentAdjustments: true,
      beforeConfirmedDays: 7,
      afterConfirmedDays: 7,
    );

    expect(withoutConcurrent, CompareConfidence.high);
    expect(withConcurrent, isNot(CompareConfidence.high));
  });

  test('synthetic adjustment source cannot create a tracking cycle', () {
    expect(
      MedicationAdjustmentService.shouldCreateSubjectiveTrackingCycle(
        'medicationStartDateFallback',
      ),
      isFalse,
    );
    expect(
      MedicationAdjustmentService.shouldCreateSubjectiveTrackingCycle(
        'synthetic-added',
      ),
      isFalse,
    );
  });

  test('legacy DailyRecord-only symptom comparison remains available', () {
    final metric = aggregate(records: [
      _legacy(['心悸'])
    ]).symptoms['心悸']!;

    expect(metric.presentDays, 1);
    expect(metric.eventCount, 0);
    expect(metric.averageScore, isNull);
  });

  test('adjustment day is excluded from before and after date-level windows',
      () {
    final window = MedicationComparisonWindow.dateLevel(
      adjustmentDate: DateTime(2026, 8, 12, 15, 30),
      days: 7,
    );

    expect(window.beforeEndExclusive, DateTime(2026, 8, 12));
    expect(window.afterStart, DateTime(2026, 8, 13));
  });

  test('subjective grouping exposes no medication causality conclusion', () {
    final groups = MedicationSubjectiveSummaryBuilder.toAiInput([
      _response('med-a', 'change-1', 3),
    ]);
    final serialized = groups.toString();

    expect(serialized, isNot(contains('造成症狀')));
    expect(serialized, isNot(contains('藥物造成')));
    expect(medicationCompareNonCausalNotice, contains('不代表'));
  });
}

DailyRecord _legacy(List<String> symptoms) => DailyRecord(
      id: 'legacy',
      date: DateTime(2026, 8, 11),
      symptoms: symptoms,
    );

List<HealthEvent> _events(List<int> severities) => List.generate(
      severities.length,
      (index) => _event(
        '$index',
        DateTime(2026, 8, 11, 8 + index),
        severities[index],
      ),
    );

HealthEvent _event(String id, DateTime timestamp, int? severity) => HealthEvent(
      id: id,
      timestamp: timestamp,
      symptoms: severity == null
          ? const []
          : [HealthEventSymptom(name: '心悸', severity: severity)],
      emotions: severity == null
          ? const [HealthEventEmotion(name: '平靜', intensity: 3)]
          : const [],
    );

MedicationSubjectiveResponse _response(
  String medicationId,
  String changeRecordId,
  int day,
) =>
    MedicationSubjectiveResponse(
      id: '$medicationId-$changeRecordId-$day',
      medicationId: medicationId,
      medicationName: medicationId,
      changeRecordId: changeRecordId,
      changeDate: DateTime(2026, 8, 12),
      followUpDay: day,
      recordedAt: DateTime(2026, 8, 12 + day),
      overallResponse: MedicationOverallResponse.unsure,
      changedAreas: const ['症狀'],
      perceivedRelation: MedicationPerceivedRelation.unsure,
      otherFactors: const [],
    );
