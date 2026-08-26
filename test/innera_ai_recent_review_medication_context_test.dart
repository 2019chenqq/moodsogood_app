import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/ai/innera_ai_context_service.dart';

void main() {
  test('recent review keeps every active medication with only compact fields',
      () {
    final medications = List.generate(
      6,
      (index) => <String, dynamic>{
        'id': 'med-$index',
        'name': '藥物 $index',
        'nameZh': '中文名 $index',
        'nameEn': 'English $index',
        'ingredientLines': ['成分 $index'],
        'compoundType': '複方',
        'dose': index + 1,
        'dosePerUnit': 2,
        'pillCount': [1, 2, 0.5, 1, 2, 0.5][index],
        'unit': 'mg',
        'times': ['早餐後', '睡前'],
        'type': 'oral',
        'purposes': ['測試用途'],
        'startDate': '2026-08-01',
        'lastChangeAt': index.isEven ? '2026-08-20' : null,
      },
    );

    final compact = medications
        .map(InneraAiContextService.compactMedicationForRecentReview)
        .toList();

    expect(compact, hasLength(medications.length));
    for (var index = 0; index < compact.length; index++) {
      expect(
        compact[index].keys,
        index.isEven
            ? [
                'name',
                'dosePerUnit',
                'pillCount',
                'dose',
                'unit',
                'times',
                'type',
                'lastChangeAt',
              ]
            : [
                'name',
                'dosePerUnit',
                'pillCount',
                'dose',
                'unit',
                'times',
                'type',
              ],
      );
      expect(compact[index]['name'], '藥物 $index');
      expect(compact[index]['dose'], index + 1);
      expect(compact[index]['dosePerUnit'], 2);
      expect(compact[index]['pillCount'], [1, 2, 0.5, 1, 2, 0.5][index]);
      expect(compact[index]['unit'], 'mg');
      expect(compact[index]['times'], ['早餐後', '睡前']);
      expect(compact[index]['type'], 'oral');
    }
  });

  test('recent review adjustment keeps ordered readable dose changes', () {
    final compact = InneraAiContextService.compactAdjustmentForRecentReview({
      'id': 'adjustment-1',
      'date': '2026-08-25',
      'type': 'ignored-envelope-type',
      'itemsCount': 2,
      'items': [
        {
          'name': '藥物 A',
          'type': 'doseChanged',
          'oldDosePerUnit': 25,
          'oldPillCount': 1,
          'newDosePerUnit': 50,
          'newPillCount': 2,
          'oldDose': 25,
          'newDose': 100,
          'oldTimes': ['睡前'],
          'newTimes': ['早餐後', '睡前'],
          'oldUnit': 'mg',
          'newUnit': 'mg',
          'source': 'not sent',
        },
        {
          'name': '藥物 B',
          'type': 'scheduleChanged',
          'oldTimes': ['早餐後'],
          'newTimes': ['睡前'],
          'oldDose': null,
        },
      ],
    });

    expect(compact.keys, ['date', 'items']);
    final items = compact['items'] as List<Map<String, dynamic>>;
    expect(items.map((item) => item['name']), ['藥物 A', '藥物 B']);
    expect(items.first.containsKey('source'), isFalse);
    expect(items.first, {
      'name': '藥物 A',
      'type': 'doseChanged',
      'changeSummary': '25 mg → 100 mg',
    });
    expect(items.last, {
      'name': '藥物 B',
      'type': 'scheduleChanged',
      'changeSummary': '早餐後 → 睡前',
    });
  });

  test('recent review adjustment summarizes added stopped and resumed items',
      () {
    final compact = InneraAiContextService.compactAdjustmentForRecentReview({
      'id': 'adjustment-2',
      'date': '2026-08-26',
      'items': [
        {
          'name': '藥物 C',
          'type': 'added',
          'newDosePerUnit': 25,
          'newPillCount': 1,
          'newUnit': 'mg',
        },
        {'name': '藥物 D', 'type': 'stopped'},
        {'name': '藥物 E', 'type': 'resumed'},
      ],
    });

    expect(compact['items'], [
      {
        'name': '藥物 C',
        'type': 'added',
        'changeSummary': '25 mg × 1 顆',
      },
      {'name': '藥物 D', 'type': 'stopped', 'changeSummary': '停藥'},
      {'name': '藥物 E', 'type': 'resumed', 'changeSummary': '恢復使用'},
    ]);
  });

  test('recent review adjustment limits an optional note to 80 characters', () {
    final compact = InneraAiContextService.compactAdjustmentForRecentReview({
      'id': 'adjustment-3',
      'date': '2026-08-26',
      'note': List.filled(90, '備').join(),
      'items': [
        {'name': '藥物 F', 'type': 'stopped'},
      ],
    });

    expect((compact['note'] as String).length, 80);
  });
}
