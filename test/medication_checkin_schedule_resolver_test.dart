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

  test('stopping on a date removes all pending check-in targets that date', () {
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

    expect(schedules, isEmpty);
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

  test('precise added event overrides an earlier day-only added event', () {
    final schedules = MedicationCheckinScheduleResolver.resolve(
      medication: {
        ...medication,
        'times': ['早上', '晚上'],
      },
      adjustmentRecords: [
        {
          'effectiveDateTime': DateTime(2026, 8, 28),
          'items': [
            {
              'medDocId': 'med-1',
              'type': 'added',
              'newTimes': ['早上', '晚上'],
            },
          ],
        },
        {
          'effectiveDateTime': DateTime(2026, 8, 28, 20),
          'items': [
            {
              'medDocId': 'med-1',
              'type': 'added',
              'newTimes': ['早上', '晚上'],
            },
          ],
        },
      ],
      selectedDate: DateTime(2026, 8, 28),
    );

    expect(schedules, isEmpty);
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

  test('dose and schedule changes at the same time are both resolved', () {
    final changedMedication = {
      ...medication,
      'dose': 20,
      'dosePerUnit': 20,
      'times': ['晚上'],
    };
    final sharedFields = <String, dynamic>{
      'medDocId': 'med-1',
      'oldDose': 10,
      'newDose': 20,
      'oldDosePerUnit': 10,
      'newDosePerUnit': 20,
      'oldPillCount': 1,
      'newPillCount': 1,
      'oldTimes': ['早上'],
      'newTimes': ['晚上'],
      'oldUnit': 'mg',
      'newUnit': 'mg',
    };
    final schedules = MedicationCheckinScheduleResolver.resolve(
      medication: changedMedication,
      adjustmentRecords: [
        {
          'effectiveDateTime': DateTime(2026, 8, 29, 12),
          'items': [
            {...sharedFields, 'type': 'doseChanged'},
            {...sharedFields, 'type': 'scheduleChanged'},
          ],
        },
      ],
      selectedDate: DateTime(2026, 8, 29),
    );

    expect(schedules.map((item) => item.slot), ['早上', '晚上']);
    expect(schedules.first.dose, 10);
    expect(schedules.last.dose, 20);
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

  test('interval schedule counts the anchor day as day zero', () {
    final intervalMedication = {
      ...medication,
      'scheduleType': 'intervalDays',
      'scheduleIntervalDays': 3,
      'startDate': DateTime(2026, 8, 1),
      'scheduleAnchorDate': DateTime(2026, 8, 31),
    };

    expect(
      MedicationCheckinScheduleResolver.resolve(
        medication: intervalMedication,
        adjustmentRecords: const [],
        selectedDate: DateTime(2026, 9, 3),
      ),
      isNotEmpty,
    );
    expect(
      MedicationCheckinScheduleResolver.resolve(
        medication: intervalMedication,
        adjustmentRecords: const [],
        selectedDate: DateTime(2026, 9, 2),
      ),
      isEmpty,
    );
  });

  test('every five days waits five full days after the dose day', () {
    final intervalMedication = {
      ...medication,
      'scheduleType': 'intervalDays',
      'scheduleIntervalDays': 5,
      'startDate': DateTime(2026, 3, 31),
      'scheduleAnchorDate': DateTime(2026, 8, 31),
    };

    expect(
      MedicationCheckinScheduleResolver.isScheduledOn(
        intervalMedication,
        DateTime(2026, 8, 31),
      ),
      isTrue,
    );
    expect(
      MedicationCheckinScheduleResolver.isScheduledOn(
        intervalMedication,
        DateTime(2026, 9, 5),
      ),
      isTrue,
    );
    expect(
      MedicationCheckinScheduleResolver.isScheduledOn(
        intervalMedication,
        DateTime(2026, 9, 4),
      ),
      isFalse,
    );
  });

  test('legacy interval schedule uses the latest adjustment as its anchor', () {
    final intervalMedication = {
      ...medication,
      'scheduleType': 'intervalDays',
      'scheduleIntervalDays': 5,
      'startDate': DateTime(2026, 3, 31),
      'lastChangeAt': DateTime(2026, 8, 31),
    };

    expect(
      MedicationCheckinScheduleResolver.isScheduledOn(
        intervalMedication,
        DateTime(2026, 9, 5),
      ),
      isTrue,
    );
    expect(
      MedicationCheckinScheduleResolver.isScheduledOn(
        intervalMedication,
        DateTime(2026, 9, 2),
      ),
      isFalse,
    );
  });

  test('next interval date skips past occurrences', () {
    final next = MedicationCheckinScheduleResolver.nextIntervalDateOnOrAfter(
      anchorDate: DateTime(2026, 8, 23),
      intervalDays: 5,
      from: DateTime(2026, 9, 6),
    );

    expect(next, DateTime(2026, 9, 7));
  });

  test('superseded schedule adjustments no longer affect check-in', () {
    final intervalMedication = {
      ...medication,
      'scheduleType': 'intervalDays',
      'scheduleIntervalDays': 5,
      'scheduleAnchorDate': DateTime(2026, 8, 23),
    };
    final schedules = MedicationCheckinScheduleResolver.resolve(
      medication: intervalMedication,
      adjustmentRecords: [
        {
          'effectiveDateTime': DateTime(2026, 9, 3, 12),
          'items': [
            {
              'medDocId': 'med-1',
              'type': 'scheduleChanged',
              'oldScheduleType': 'daily',
              'newScheduleType': 'intervalDays',
              'oldTimes': ['早上'],
              'newTimes': ['早上'],
              'supersededAt': DateTime(2026, 9, 3, 13),
            },
          ],
        },
      ],
      selectedDate: DateTime(2026, 9, 3),
    );

    expect(schedules, isEmpty);
  });

  test('weekday schedule creates targets only on selected weekdays', () {
    final weeklyMedication = {
      ...medication,
      'scheduleType': 'weekdays',
      'weekdays': [DateTime.monday, DateTime.thursday],
    };

    expect(
      MedicationCheckinScheduleResolver.resolve(
        medication: weeklyMedication,
        adjustmentRecords: const [],
        selectedDate: DateTime(2026, 8, 24),
      ),
      isNotEmpty,
    );
    expect(
      MedicationCheckinScheduleResolver.resolve(
        medication: weeklyMedication,
        adjustmentRecords: const [],
        selectedDate: DateTime(2026, 8, 25),
      ),
      isEmpty,
    );
  });

  test('as-needed slot remains available outside a scheduled day', () {
    final mixedMedication = {
      ...medication,
      'times': ['中午', '需要時'],
      'scheduleType': 'weekdays',
      'weekdays': [DateTime.monday],
    };
    final schedules = MedicationCheckinScheduleResolver.resolve(
      medication: mixedMedication,
      adjustmentRecords: const [],
      selectedDate: DateTime(2026, 8, 25),
    );
    expect(schedules.map((item) => item.slot), ['需要時']);
  });
}
