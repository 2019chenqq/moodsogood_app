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
