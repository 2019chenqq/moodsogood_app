import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/meds/medication_checkin_schedule_resolver.dart';

void main() {
  final medication = <String, dynamic>{
    'id': 'med-1',
    'isActive': true,
    'dose': 20,
    'dosePerUnit': 20,
    'pillCount': 1,
    'unit': 'mg',
    'times': ['早上', '下午', '晚上'],
  };

  test('afternoon adjustment preserves old morning and applies new later dose',
      () {
    final schedules = MedicationCheckinScheduleResolver.resolve(
      medication: medication,
      adjustmentRecords: [
        {
          'date': DateTime(2026, 8, 11, 14, 30),
          'items': [
            {
              'medDocId': 'med-1',
              'type': 'doseChanged',
              'oldDose': 10,
              'newDose': 20,
              'oldDosePerUnit': 10,
              'newDosePerUnit': 20,
              'oldPillCount': 1,
              'newPillCount': 1,
              'oldTimes': ['早上', '下午', '晚上'],
              'newTimes': ['早上', '下午', '晚上'],
              'oldUnit': 'mg',
              'newUnit': 'mg',
            },
          ],
        },
      ],
      selectedDate: DateTime(2026, 8, 11),
    );

    expect(schedules.map((item) => item.slot), ['早上', '下午', '晚上']);
    expect(schedules.first.dose, 10);
    expect(schedules[1].dose, 20);
  });

  test('stopping in afternoon still keeps the morning check-in target', () {
    final schedules = MedicationCheckinScheduleResolver.resolve(
      medication: {...medication, 'isActive': false},
      adjustmentRecords: [
        {
          'date': DateTime(2026, 8, 11, 14),
          'items': [
            {
              'medDocId': 'med-1',
              'type': 'stopped',
              'oldDose': 10,
              'oldTimes': ['早上', '晚上'],
              'oldUnit': 'mg',
            },
          ],
        },
      ],
      selectedDate: DateTime(2026, 8, 11),
    );

    expect(schedules.map((item) => item.slot), ['早上']);
  });

  test('an added afternoon prescription does not create a morning target', () {
    final schedules = MedicationCheckinScheduleResolver.resolve(
      medication: medication,
      adjustmentRecords: [
        {
          'date': DateTime(2026, 8, 11, 14),
          'items': [
            {
              'medDocId': 'med-1',
              'type': 'added',
              'newTimes': ['早上', '下午', '晚上'],
            },
          ],
        },
      ],
      selectedDate: DateTime(2026, 8, 11),
    );

    expect(schedules.map((item) => item.slot), ['下午', '晚上']);
  });

  test('effectiveDateTime overrides adjustment time on the same day', () {
    final schedules = MedicationCheckinScheduleResolver.resolve(
      medication: medication,
      adjustmentRecords: [
        {
          'date': DateTime(2026, 8, 17, 15),
          'adjustmentDateTime': DateTime(2026, 8, 17, 15),
          'effectiveDateTime': DateTime(2026, 8, 17, 21),
          'items': [
            {
              'medDocId': 'med-1',
              'type': 'doseChanged',
              'oldDose': 10,
              'newDose': 20,
              'oldTimes': ['早上', '晚上', '睡前'],
              'newTimes': ['早上', '晚上', '睡前'],
              'oldUnit': 'mg',
            },
          ],
        },
      ],
      selectedDate: DateTime(2026, 8, 17),
    );

    expect(schedules.map((item) => item.slot), ['早上', '晚上', '睡前']);
    expect(schedules[0].dose, 10);
    expect(schedules[1].dose, 10);
    expect(schedules[2].dose, 20);
  });

  test('future effective prescription keeps the old schedule today', () {
    final schedules = MedicationCheckinScheduleResolver.resolve(
      medication: medication,
      adjustmentRecords: [
        {
          'date': DateTime(2026, 8, 17, 15),
          'effectiveDateTime': DateTime(2026, 8, 18, 8),
          'items': [
            {
              'medDocId': 'med-1',
              'type': 'doseChanged',
              'oldDose': 10,
              'oldTimes': ['早上', '晚上'],
              'oldUnit': 'mg',
            },
          ],
        },
      ],
      selectedDate: DateTime(2026, 8, 17),
    );

    expect(schedules.map((item) => item.slot), ['早上', '晚上']);
    expect(schedules.every((item) => item.dose == 10), isTrue);
  });
}
