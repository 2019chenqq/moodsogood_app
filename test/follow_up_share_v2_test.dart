import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/follow_up/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/follow_up/pdf/follow_up_summary_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('V2 display keeps symptom days events severity and evidence semantics',
      () {
    final display = FollowUpSummaryDisplayModel.fromRecord(_record());

    expect(display.symptoms.single, contains('出現 4 天'));
    expect(display.symptoms.single, contains('快速記錄共 7 次'));
    expect(display.symptoms.single, contains('最高強度 4/5'));
    expect(
        display.recordEvidenceHighlights,
        contains(
          '心悸與噁心曾於 4 次快速記錄事件中共同出現。',
        ));
    expect(
        display.recordEvidenceHighlights,
        contains(
          '頭痛與疲倦曾於 3 個記錄日同日出現。',
        ));
    expect(display.medicationSubjectiveSummaries.single, contains('使用者主觀回報'));
  });

  test('missing severity never creates a fabricated value', () {
    final source = _record(symptoms: const [
      {
        'name': '頭痛',
        'occurrenceDays': 2,
        'eventCount': 0,
      },
    ]);
    final text = FollowUpSummaryDisplayModel.fromRecord(source).symptoms.single;

    expect(text, contains('出現 2 天'));
    expect(text, isNot(contains('強度')));
    expect(text, isNot(contains('程度')));
    expect(text, isNot(contains('次')));
  });

  test('deidentified V2 snapshot contains summaries but no raw events', () {
    final snapshot = _record().toDeidentifiedSnapshot();
    final display = Map<String, dynamic>.from(snapshot['display'] as Map);

    expect(snapshot['schemaVersion'], 2);
    expect(display['schemaVersion'], 2);
    expect(display['recordEvidenceHighlights'], isNotEmpty);
    expect(display['medicationSubjectiveSummaries'], isNotEmpty);
    expect(snapshot.toString(), isNot(contains('representativeHealthEvents')));
    expect(snapshot.toString(), isNot(contains('timestamp')));
    expect(snapshot.toString(), isNot(contains('healthEvents')));
  });

  test('share options remove unselected health and medication summaries', () {
    final snapshot = _record().toDeidentifiedSnapshot(
      options: const FollowUpSummaryShareOptions(
        discussionTopics: false,
        sleep: true,
        emotionsAndSymptoms: false,
        medicationAdjustments: false,
        lifeUpdates: false,
        dataLimitations: false,
        bodyMeasurements: false,
      ),
    );
    final display = Map<String, dynamic>.from(snapshot['display'] as Map);

    expect(display['recordEvidenceHighlights'], isEmpty);
    expect(display['symptoms'], isEmpty);
    expect(display['medicationSubjectiveSummaries'], isEmpty);
  });

  test('V2 and fallback summaries both produce a PDF', () async {
    final service = const FollowUpSummaryPdfService();
    final normal = await service.buildPdf(_record());
    final fallback = await service.buildPdf(_record(usedFallback: true));

    expect(String.fromCharCodes(normal.take(4)), '%PDF');
    expect(String.fromCharCodes(fallback.take(4)), '%PDF');
    expect(normal.length, greaterThan(1000));
    expect(fallback.length, greaterThan(1000));
  });

  test('old summary missing V2 fields remains readable', () {
    final record = FollowUpSummaryRecord.fromMap('legacy', {
      'periodStart': DateTime(2026, 8, 1),
      'periodEnd': DateTime(2026, 8, 14),
      'aiOutput': {
        'keyChanges': ['一', '二', '三'],
        'generatedAt': '2026-08-14T00:00:00Z',
      },
    });
    final display = FollowUpSummaryDisplayModel.fromRecord(record);

    expect(display.recordEvidenceHighlights, isEmpty);
    expect(display.medicationSubjectiveSummaries, isEmpty);
  });
}

FollowUpSummaryRecord _record({
  List<Map<String, dynamic>>? symptoms,
  bool usedFallback = false,
}) {
  final now = DateTime.utc(2026, 8, 14);
  return FollowUpSummaryRecord(
    id: 'private-id',
    createdAt: now,
    updatedAt: now,
    confirmedAt: now,
    appointmentDate: now,
    periodStart: DateTime.utc(2026, 8, 1),
    periodEnd: now,
    validRecordDays: 7,
    selectedTopics: const [],
    discussionDetails: '',
    additionalNotes: '',
    aiOutput: FollowUpAiOutput(
      keyChanges: const ['情緒趨勢已整理', '狀態變化已整理', '症狀紀錄已整理'],
      timelineRelations: const [],
      discussionPriorities: const [],
      recordEvidenceHighlights: const [
        '心悸與噁心曾於 4 次快速記錄事件中共同出現。',
        '頭痛與疲倦曾於 3 個記錄日同日出現。',
      ],
      medicationSubjectiveSummaries: const [
        '藥物甲（使用者主觀回報）：調藥後第3、7、14、28天均有回報。',
      ],
      dataLimitations: const [],
      generatedAt: now,
      usedFallback: usedFallback,
    ),
    sleepSummary: const {},
    sleepTrend: const [],
    medicationTimeline: const [],
    highFrequencySymptoms: symptoms ??
        const [
          {
            'name': '疲倦',
            'recordedDays': 7,
            'occurrenceDays': 4,
            'eventCount': 7,
            'averageSeverity': 3.2,
            'maxSeverity': 4,
          },
        ],
    schemaVersion: 2,
  );
}
