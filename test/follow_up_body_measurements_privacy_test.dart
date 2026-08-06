import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/follow_up_ai_summary.dart';

void main() {
  FollowUpSummaryRecord recordWithMeasurements() =>
      FollowUpSummaryRecord(
        id: 'test-id',
        createdAt: DateTime.utc(2026, 8, 5),
        updatedAt: DateTime.utc(2026, 8, 5),
        confirmedAt: DateTime.utc(2026, 8, 5),
        appointmentDate: DateTime.utc(2026, 8, 10),
        periodStart: DateTime.utc(2026, 7, 1),
        periodEnd: DateTime.utc(2026, 8, 5),
        validRecordDays: 12,
        selectedTopics: const [],
        discussionDetails: '',
        additionalNotes: '',
        aiOutput: FollowUpAiOutput(
          keyChanges: const [
            '情緒較平穩',
            '體重從 75kg 變化到 74.5kg',
            '睡眠時間較前期增加：1.5小時',
          ],
          timelineRelations: const [],
          discussionPriorities: const [],
          dataLimitations: const [],
          generatedAt: DateTime.utc(2026, 8, 5, 8),
        ),
        sleepSummary: const {},
        sleepTrend: const [],
        medicationTimeline: const [],
        highFrequencySymptoms: const [
          {'name': '頭痛', 'occurrenceDays': 3, 'averageSeverity': 2.5},
        ],
        bodyMeasurements: const [
          {
            'name': '體重',
            'unit': 'kg',
            'startValue': 60.0,
            'latestValue': 58.5,
            'change': -1.5,
          },
        ],
      );

  test('includes body measurements when bodyMeasurements option is true', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(
      recordWithMeasurements(),
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: true,
      ),
    );

    expect(display.bodyMeasurements, isNotEmpty);
    expect(
      display.bodyMeasurements.any(
        (item) => item.contains('體重：減少 1.5kg'),
      ),
      isTrue,
    );
  });

  test('excludes body measurements when bodyMeasurements option is false', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(
      recordWithMeasurements(),
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: false,
      ),
    );

    expect(display.symptoms, isNotEmpty);
    expect(
      display.symptoms.any(
        (item) => item.contains('體重'),
      ),
      isFalse,
    );
    // Symptoms should still be included
    expect(
      display.symptoms.any(
        (item) => item.contains('頭痛'),
      ),
      isTrue,
    );
  });

  test('filters body measurements from keyChanges when disabled', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(
      recordWithMeasurements(),
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: false,
      ),
    );

    // Key changes should not contain body measurement values
    expect(
      display.keyChanges.any(
        (item) => item.contains('75kg') || item.contains('74.5kg'),
      ),
      isFalse,
    );
    // But should still contain other key changes
    expect(
      display.keyChanges.any(
        (item) => item.contains('情緒較平穩'),
      ),
      isTrue,
    );
  });

  test('never shows actual body measurement values in keyChanges', () {
    // When bodyMeasurements is enabled
    final displayEnabled = FollowUpSummaryDisplayModel.fromRecord(
      recordWithMeasurements(),
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: true,
      ),
    );

    // Key changes should never contain actual body measurement values
    expect(
      displayEnabled.keyChanges.any(
        (item) => item.contains('75kg') || item.contains('74.5kg'),
      ),
      isFalse,
    );

    // When bodyMeasurements is disabled
    final displayDisabled = FollowUpSummaryDisplayModel.fromRecord(
      recordWithMeasurements(),
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: false,
      ),
    );

    // Key changes should also not contain actual body measurement values
    expect(
      displayDisabled.keyChanges.any(
        (item) => item.contains('75kg') || item.contains('74.5kg'),
      ),
      isFalse,
    );
  });

  test('includes body measurements in deidentified snapshot when enabled', () {
    final record = recordWithMeasurements();
    final snapshot = record.toDeidentifiedSnapshot(
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: true,
      ),
    );

    final bodyMeasurements = snapshot['bodyMeasurements'] as List;
    expect(bodyMeasurements, isNotEmpty);
    expect(bodyMeasurements.length, 1);
  });

  test('excludes body measurements from deidentified snapshot when disabled', () {
    final record = recordWithMeasurements();
    final snapshot = record.toDeidentifiedSnapshot(
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: false,
      ),
    );

    final bodyMeasurements = snapshot['bodyMeasurements'] as List;
    expect(bodyMeasurements, isEmpty);
  });

  test('bodyMeasurements option is included in includedSections when true', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(
      recordWithMeasurements(),
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: true,
      ),
    );

    expect(display.includedSections, contains('bodyMeasurements'));
  });

  test('bodyMeasurements option is not in includedSections when false', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(
      recordWithMeasurements(),
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: false,
      ),
    );

    expect(display.includedSections, isNot(contains('bodyMeasurements')));
  });

  test('shows no change when body measurement change is zero', () {
    final record = FollowUpSummaryRecord(
      id: 'test-id',
      createdAt: DateTime.utc(2026, 8, 5),
      updatedAt: DateTime.utc(2026, 8, 5),
      confirmedAt: DateTime.utc(2026, 8, 5),
      appointmentDate: DateTime.utc(2026, 8, 10),
      periodStart: DateTime.utc(2026, 7, 1),
      periodEnd: DateTime.utc(2026, 8, 5),
      validRecordDays: 12,
      selectedTopics: const [],
      discussionDetails: '',
      additionalNotes: '',
      aiOutput: FollowUpAiOutput(
        keyChanges: const ['情緒較平穩'],
        timelineRelations: const [],
        discussionPriorities: const [],
        dataLimitations: const [],
        generatedAt: DateTime.utc(2026, 8, 5, 8),
      ),
      sleepSummary: const {},
      sleepTrend: const [],
      medicationTimeline: const [],
      highFrequencySymptoms: const [],
      bodyMeasurements: const [
        {
          'name': '體重',
          'unit': 'kg',
          'startValue': 60.0,
          'latestValue': 60.0,
          'change': 0.0,
        },
      ],
    );

    final display = FollowUpSummaryDisplayModel.fromRecord(
      record,
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: false,
        emotionsAndSymptoms: true,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: true,
      ),
    );

    expect(
      display.bodyMeasurements.any(
        (item) => item.contains('體重：無明顯變化'),
      ),
      isTrue,
    );
  });
}