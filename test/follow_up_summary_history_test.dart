import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/follow_up/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/follow_up/pdf/follow_up_summary_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy summary without sleep and medication fields stays readable', () {
    final record = FollowUpSummaryRecord.fromMap('internal-id', {
      'createdAt': DateTime(2026, 8, 5),
      'periodStart': DateTime(2026, 7, 20),
      'periodEnd': DateTime(2026, 8, 5),
      'aiOutput': {
        'keyChanges': ['一', '二', '三'],
        'timelineRelations': [],
        'discussionPriorities': [],
        'userReportedConcerns': [],
        'dataLimitations': [],
        'generatedAt': '2026-08-05T00:00:00Z',
      },
    });

    expect(record.sleepSummary, isEmpty);
    expect(record.sleepTrend, isEmpty);
    expect(record.medicationTimeline, isEmpty);
  });

  test('PDF embeds a real sleep chart when trend data exists', () async {
    final now = DateTime(2026, 8, 5);
    final record = FollowUpSummaryRecord(
      id: 'never-export-this-id',
      createdAt: now,
      updatedAt: now,
      confirmedAt: now,
      appointmentDate: now,
      periodStart: DateTime(2026, 8, 1),
      periodEnd: now,
      validRecordDays: 3,
      selectedTopics: const [
        {'type': 'sleep', 'label': '睡眠品質'},
      ],
      discussionDetails: '想討論睡眠',
      additionalNotes: '',
      aiOutput: FollowUpAiOutput(
        keyChanges: const ['一', '二', '三'],
        timelineRelations: const [],
        discussionPriorities: const ['睡眠'],
        dataLimitations: const [],
        generatedAt: now,
      ),
      sleepSummary: const {
        'durationHours': {
          'recordedDays': 3,
          'average': 7.0,
          'minimum': 6.0,
          'maximum': 8.0,
        },
      },
      sleepTrend: const [
        {'date': '2026-08-01', 'value': 6.0},
        {'date': '2026-08-03', 'value': 7.0},
        {'date': '2026-08-05', 'value': 8.0},
      ],
      medicationTimeline: const [],
    );

    final bytes = await const FollowUpSummaryPdfService().buildPdf(
      record,
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
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final qaOutput = Platform.environment['FOLLOW_UP_PDF_QA_OUTPUT'];
    if (qaOutput != null && qaOutput.isNotEmpty) {
      await File(qaOutput).writeAsBytes(bytes, flush: true);
    }
  });

  test('PDF export filename is safe on every supported platform', () {
    final filename = FollowUpSummaryPdfService.exportFilename(
      DateTime(2026, 8, 5),
    );

    expect(filename, 'AI回診摘要_2026-08-05.pdf');
    expect(filename, isNot(contains('/')));
    expect(filename, isNot(contains(r'\')));
  });
}
