import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/medication_adjustment_history_presentation.dart';

void main() {
  test('history sorts newest first and displays date without time', () {
    final entries = buildMedicationAdjustmentHistory([
      _record('jul-24', DateTime(2026, 7, 24, 9, 15)),
      _record('aug-10', DateTime(2026, 8, 10, 8)),
      _record('aug-7', DateTime(2026, 8, 7, 16, 30)),
    ]);

    expect(entries.map((entry) => entry.record['id']), [
      'aug-10',
      'aug-7',
      'jul-24',
    ]);
    expect(entries.map((entry) => entry.dateLabel), [
      '2026/08/10',
      '2026/08/07',
      '2026/07/24',
    ]);
    expect(
        entries.map((entry) => entry.dateLabel).join(), isNot(contains(':')));
  });

  test('same-day records retain timestamp order even though time is hidden',
      () {
    final entries = buildMedicationAdjustmentHistory([
      _record('morning', DateTime(2026, 8, 7, 9)),
      _record('afternoon', DateTime(2026, 8, 7, 15)),
    ]);

    expect(
        entries.map((entry) => entry.record['id']), ['afternoon', 'morning']);
    expect(entries.map((entry) => entry.dateLabel).toSet(), {'2026/08/07'});
  });

  test('adds an inferred timeline entry for a medication missing history', () {
    final entries = buildMedicationAdjustmentHistory(
      [_record('existing', DateTime(2026, 8, 7, 9))],
      medications: [
        {
          'id': 'med-1',
          'name': '已有紀錄的藥',
          'startDate': '2026-08-07',
        },
        {
          'id': 'med-2',
          'name': '驅異樂',
          'startDate': '2026-07-20',
          'dose': 10,
          'unit': 'mg',
        },
      ],
    );

    final inferred =
        entries.singleWhere((entry) => entry.events.first.isInferred);
    expect(inferred.events.first.medDocId, 'med-2');
    expect(inferred.events.first.medName, '驅異樂');
    expect(inferred.events.first.type, 'added');
    expect(inferred.dateLabel, '2026/07/20');
    expect(inferred.record['inferred'], isTrue);
  });

  test('does not infer an added event when that medication has any history',
      () {
    final entries = buildMedicationAdjustmentHistory(
      [_record('existing', DateTime(2026, 8, 7, 9))],
      medications: [
        {
          'id': 'med-1',
          'name': '測試藥物',
          'startDate': '2026-07-20',
        },
      ],
    );

    expect(entries, hasLength(1));
    expect(entries.single.events.single.isInferred, isFalse);
  });
}

Map<String, dynamic> _record(String id, DateTime date) => {
      'id': id,
      'date': date.toIso8601String(),
      'items': [
        {
          'medDocId': 'med-1',
          'name': '測試藥物',
          'type': 'doseChanged',
          'oldDose': 10,
          'newDose': 20,
          'unit': 'mg',
        },
      ],
    };
