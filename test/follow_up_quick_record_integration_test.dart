import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/follow_up/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_ai_data_aggregator.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_ai_service.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_health_summary_builder.dart';
import 'package:moodsogood_app/meds/med_symptom_compare_models.dart';
import 'package:moodsogood_app/meds/medication_subjective_response.dart';
import 'package:moodsogood_app/models/daily_record.dart';
import 'package:moodsogood_app/models/health_event.dart';

void main() {
  test('QuickRecords use unique days while retaining events and severity', () {
    final summary = const FollowUpHealthSummaryBuilder().build(
      dailyRecords: [
        DailyRecord(
          id: 'legacy',
          date: DateTime(2026, 8, 1),
          symptoms: const ['心悸'],
        ),
      ],
      healthEvents: [
        _event('a', DateTime(2026, 8, 1, 9), 2),
        _event('b', DateTime(2026, 8, 1, 12), 4),
        _event('c', DateTime(2026, 8, 1, 18), 5),
        _event('d', DateTime(2026, 8, 2, 9), 3),
        _event('outside', DateTime(2026, 8, 15), 5),
      ],
      dailyCheckIns: const [],
      start: DateTime(2026, 8, 1),
      endExclusive: DateTime(2026, 8, 15),
    );

    expect(summary.recordedDays, 2);
    final symptom = summary.symptoms.single;
    expect(symptom['recordedDays'], 2);
    expect(symptom['occurrenceDays'], 2);
    expect(symptom['eventCount'], 4);
    expect(symptom['averageSeverity'], 3.5);
    expect(symptom['maxSeverity'], 5);
  });

  test('event and legacy evidence are merged into one descriptive cluster', () {
    final summary = const FollowUpHealthSummaryBuilder().build(
      dailyRecords: [
        DailyRecord(
          id: 'legacy',
          date: DateTime(2026, 8, 1),
          symptoms: const ['心悸', '噁心'],
        ),
      ],
      healthEvents: [
        HealthEvent(
          id: 'same-event',
          timestamp: DateTime(2026, 8, 2, 9),
          symptoms: const [
            HealthEventSymptom(name: '心悸', severity: 4),
            HealthEventSymptom(name: '噁心', severity: 3),
          ],
        ),
        HealthEvent(
          id: 'different-time-a',
          timestamp: DateTime(2026, 8, 3, 9),
          symptoms: const [HealthEventSymptom(name: '心悸', severity: 2)],
        ),
        HealthEvent(
          id: 'different-time-b',
          timestamp: DateTime(2026, 8, 3, 18),
          symptoms: const [HealthEventSymptom(name: '噁心', severity: 2)],
        ),
      ],
      dailyCheckIns: const [],
      start: DateTime(2026, 8, 1),
      endExclusive: DateTime(2026, 8, 4),
    );

    final cluster = (summary.coOccurrences['clusters'] as List).single as Map;
    expect(cluster['coreItems'], containsAll(['心悸', '噁心']));
    expect(cluster['occurrenceCount'], 3);
    expect(cluster['sameDayCount'], 3);
    expect(cluster['nearbyTimeCount'], 1);
  });

  test('subjective responses are period-filtered and isolated by medication',
      () {
    final input = FollowUpAiDataAggregator().buildFromData(
      now: DateTime(2026, 8, 14),
      currentAppointmentDate: DateTime(2026, 8, 14),
      records: const [],
      medications: const [],
      adjustments: [
        _adjustment('m1', '藥物甲'),
        _adjustment('m2', '藥物乙', itemIndex: 1),
      ],
      subjectiveResponses: [
        _response('m1', '藥物甲', 3, DateTime(2026, 8, 4)),
        _response('m1', '藥物甲', 7, DateTime(2026, 8, 8)),
        _response('m2', '藥物乙', 3, DateTime(2026, 8, 4)),
        _response('m2', '藥物乙', 28, DateTime(2026, 9, 1)),
      ],
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
    );

    expect(input.medicationSubjectiveReports, hasLength(2));
    final groups = {
      for (final item in input.medicationSubjectiveReports)
        item['medicationId']: item,
    };
    expect((groups['m1']!['responses'] as List), hasLength(2));
    expect((groups['m2']!['responses'] as List), hasLength(1));
    expect(groups['m1']!['concurrentMedicationAdjustments'], ['藥物乙']);
    expect(groups['m2']!['concurrentMedicationAdjustments'], ['藥物甲']);
  });

  test('fallback exposes the precomputed co-occurrence cluster', () {
    final input = _baseInput(
      symptoms: const [
        {
          'name': '心悸',
          'occurrenceDays': 1,
          'eventCount': 3,
          'maxSeverity': 5,
        },
      ],
      coOccurrences: const {
        'clusters': [
          {
            'coreItems': ['心悸', '噁心', '焦慮'],
            'companionItems': ['腸胃不適'],
            'occurrenceCount': 3,
            'sameDayCount': 3,
            'nearbyTimeCount': 2,
            'windowMinutes': 120,
          },
        ],
      },
    );
    final output = FollowUpAiService.fallbackSummaryForTesting(input);

    expect(output.recordEvidenceHighlights.join(), contains('1 個記錄日'));
    expect(output.recordEvidenceHighlights.join(), contains('3 次'));
    expect(output.recordEvidenceHighlights.join(), contains('重複共同出現 3 次'));
    expect(output.recordEvidenceHighlights.join(), contains('2 次發生於相近時間'));
    expect(output.recordEvidenceHighlights.join(), contains('常伴隨腸胃不適'));
    expect(output.usedFallback, isTrue);
  });

  test('old output JSON without new evidence field still parses', () {
    final output = FollowUpAiOutput.fromJson({
      'keyChanges': ['一', '二', '三'],
      'timelineRelations': <String>[],
      'discussionPriorities': <String>[],
      'dataLimitations': <String>[],
      'generatedAt': DateTime.utc(2026, 8, 14).toIso8601String(),
    });
    expect(output.recordEvidenceHighlights, isEmpty);
  });

  test('representative raw events are capped', () {
    final summary = const FollowUpHealthSummaryBuilder().build(
      dailyRecords: const [],
      healthEvents: [
        for (var i = 0; i < 30; i++)
          _event('e$i', DateTime(2026, 8, 1, 0, i), 3),
      ],
      dailyCheckIns: const [],
      start: DateTime(2026, 8, 1),
      endExclusive: DateTime(2026, 8, 2),
    );
    expect(summary.representativeEvents, hasLength(12));
    expect(summary.recordedDays, 1);
  });
}

HealthEvent _event(String id, DateTime timestamp, int severity) => HealthEvent(
      id: id,
      timestamp: timestamp,
      symptoms: [HealthEventSymptom(name: '心悸', severity: severity)],
    );

MedicationAdjustmentEvent _adjustment(
  String medicationId,
  String name, {
  int itemIndex = 0,
}) =>
    MedicationAdjustmentEvent(
      adjustmentId: 'change-1',
      itemIndex: itemIndex,
      medDocId: medicationId,
      medName: name,
      date: DateTime(2026, 8, 1),
      type: 'doseChanged',
    );

MedicationSubjectiveResponse _response(
  String medicationId,
  String name,
  int day,
  DateTime recordedAt,
) =>
    MedicationSubjectiveResponse(
      id: '$medicationId-$day',
      medicationId: medicationId,
      medicationName: name,
      changeRecordId: 'change-1',
      changeDate: DateTime(2026, 8, 1),
      followUpDay: day,
      recordedAt: recordedAt,
      overallResponse: MedicationOverallResponse.mixed,
      changedAreas: const ['食慾'],
      perceivedRelation: MedicationPerceivedRelation.unsure,
      otherFactors: const [],
    );

FollowUpAiV1Input _baseInput({
  List<Map<String, dynamic>> symptoms = const [],
  Map<String, dynamic> coOccurrences = const {},
}) =>
    FollowUpAiV1Input(
      statistics: FollowUpStatistics(
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 8, 14),
        validRecordDays: 1,
        currentAppointmentDate: DateTime(2026, 8, 14),
        periodBasis: 'test',
      ),
      discussionTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
      wellbeingTrends: const WellbeingTrendsInput(
        mood: MetricTrendInput(
            dailyValues: [], direction: TrendDirection.insufficientData),
        anxiety: MetricTrendInput(
            dailyValues: [], direction: TrendDirection.insufficientData),
        energy: MetricTrendInput(
            dailyValues: [], direction: TrendDirection.insufficientData),
        appetite: MetricTrendInput(
            dailyValues: [], direction: TrendDirection.insufficientData),
        activity: MetricTrendInput(
            dailyValues: [], direction: TrendDirection.insufficientData),
      ),
      sleep: const {},
      highFrequencySymptoms: symptoms,
      bodyMeasurements: const [],
      currentMedications: const [],
      medicationTimeline: const [],
      coOccurrenceSummary: coOccurrences,
      dataLimitations: const [],
    );
