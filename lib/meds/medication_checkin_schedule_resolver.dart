import 'package:cloud_firestore/cloud_firestore.dart';

class MedicationCheckinScheduleSnapshot {
  const MedicationCheckinScheduleSnapshot({
    required this.slot,
    required this.dose,
    required this.dosePerUnit,
    required this.pillCount,
    required this.unit,
  });

  final String slot;
  final dynamic dose;
  final dynamic dosePerUnit;
  final dynamic pillCount;
  final String unit;
}

/// Resolves UI check-in slots from stored adjustment timestamps. It does not
/// calculate adherence; it only determines which prescription existed at a
/// particular scheduled time.
class MedicationCheckinScheduleResolver {
  const MedicationCheckinScheduleResolver._();

  static List<MedicationCheckinScheduleSnapshot> resolve({
    required Map<String, dynamic> medication,
    required Iterable<Map<String, dynamic>> adjustmentRecords,
    required DateTime selectedDate,
  }) {
    final schedules = _resolveUnfiltered(
      medication: medication,
      adjustmentRecords: adjustmentRecords,
      selectedDate: selectedDate,
    );
    final scheduleMedication = _scheduleForDate(
      medication,
      adjustmentRecords,
      selectedDate,
    );
    if (isScheduledOn(scheduleMedication, selectedDate)) return schedules;
    if (_oldScheduleAppliesOnSameDay(
      medication,
      adjustmentRecords,
      selectedDate,
    )) {
      return schedules;
    }
    // 「需要時」不是固定排程，不應因週期設定而消失。
    return schedules.where((item) => item.slot == '需要時').toList();
  }

  static bool _oldScheduleAppliesOnSameDay(
    Map<String, dynamic> medication,
    Iterable<Map<String, dynamic>> adjustmentRecords,
    DateTime selectedDate,
  ) {
    final medicationId = (medication['id'] ?? '').toString();
    for (final record in adjustmentRecords) {
      final date = _date(record['effectiveDateTime']) ?? _date(record['date']);
      if (date == null || !_sameDay(date, selectedDate)) continue;
      final rawItems = record['items'] ?? record['changes'];
      if (rawItems is! Iterable) continue;
      for (final raw in rawItems.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        if ((item['medDocId'] ?? '').toString() != medicationId ||
            !item.containsKey('oldScheduleType')) {
          continue;
        }
        if (isScheduledOn({
          ...medication,
          'scheduleType': item['oldScheduleType'] ?? 'daily',
          'scheduleIntervalDays': item['oldScheduleIntervalDays'],
          'weekdays': item['oldWeekdays'] ?? const <int>[],
        }, selectedDate)) {
          return true;
        }
      }
    }
    return false;
  }

  static Map<String, dynamic> _scheduleForDate(
    Map<String, dynamic> medication,
    Iterable<Map<String, dynamic>> adjustmentRecords,
    DateTime selectedDate,
  ) {
    final medicationId = (medication['id'] ?? '').toString();
    final endOfDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      23,
      59,
      59,
      999,
    );
    final futureChanges = <({DateTime date, Map<String, dynamic> item})>[];
    for (final record in adjustmentRecords) {
      final date = _date(record['effectiveDateTime']) ?? _date(record['date']);
      if (date == null || !date.isAfter(endOfDay)) continue;
      final rawItems = record['items'] ?? record['changes'];
      if (rawItems is! Iterable) continue;
      for (final raw in rawItems.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        if ((item['medDocId'] ?? '').toString() == medicationId &&
            item.containsKey('oldScheduleType')) {
          futureChanges.add((date: date, item: item));
        }
      }
    }
    if (futureChanges.isEmpty) return medication;
    futureChanges.sort((a, b) => a.date.compareTo(b.date));
    final old = futureChanges.first.item;
    return {
      ...medication,
      'scheduleType': old['oldScheduleType'] ?? 'daily',
      'scheduleIntervalDays': old['oldScheduleIntervalDays'],
      'weekdays': old['oldWeekdays'] ?? const <int>[],
    };
  }

  static bool isScheduledOn(
    Map<String, dynamic> medication,
    DateTime date,
  ) {
    final day = DateTime(date.year, date.month, date.day);
    final start = _date(medication['startDate']);
    if (start != null) {
      final startDay = DateTime(start.year, start.month, start.day);
      if (day.isBefore(startDay)) return false;
    }

    switch ((medication['scheduleType'] ?? 'daily').toString()) {
      case 'intervalDays':
        final interval = _positiveInt(medication['scheduleIntervalDays']);
        if (start == null || interval == null) return true;
        final startDay = DateTime(start.year, start.month, start.day);
        return day.difference(startDay).inDays % interval == 0;
      case 'weekdays':
        final weekdays = _ints(medication['weekdays']);
        return weekdays.isEmpty || weekdays.contains(day.weekday);
      default:
        return true;
    }
  }

  static List<MedicationCheckinScheduleSnapshot> _resolveUnfiltered({
    required Map<String, dynamic> medication,
    required Iterable<Map<String, dynamic>> adjustmentRecords,
    required DateTime selectedDate,
  }) {
    final medicationId = (medication['id'] ?? '').toString();
    final sameDayItems = <({DateTime date, Map<String, dynamic> item})>[];
    final futureItems = <({DateTime date, Map<String, dynamic> item})>[];
    for (final record in adjustmentRecords) {
      final date = _date(record['effectiveDateTime']) ?? _date(record['date']);
      if (date == null) continue;
      final rawItems = record['items'] ?? record['changes'];
      if (rawItems is! Iterable) continue;
      for (final raw in rawItems.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        if ((item['medDocId'] ?? '').toString() == medicationId) {
          if (_sameDay(date, selectedDate)) {
            sameDayItems.add((date: date, item: item));
          } else if (date.isAfter(DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            23,
            59,
            59,
            999,
          ))) {
            futureItems.add((date: date, item: item));
          }
        }
      }
    }
    sameDayItems.sort((a, b) => a.date.compareTo(b.date));
    if (sameDayItems.isEmpty) {
      futureItems.sort((a, b) => a.date.compareTo(b.date));
      if (futureItems.isNotEmpty) {
        final future = futureItems.first.item;
        if ((future['type'] ?? '').toString() == 'added') return const [];
        final oldTimes = _strings(future['oldTimes']);
        return oldTimes
            .map((slot) => MedicationCheckinScheduleSnapshot(
                  slot: slot,
                  dose: future['oldDose'],
                  dosePerUnit: future['oldDosePerUnit'],
                  pillCount: future['oldPillCount'],
                  unit:
                      (future['oldUnit'] ?? future['unit'] ?? 'mg').toString(),
                ))
            .toList();
      }
      if (medication['isActive'] == false) return const [];
      return _currentSnapshots(medication);
    }

    final change = sameDayItems.last;
    final item = change.item;
    final oldTimes = _strings(item['oldTimes']);
    final newTimes = _strings(item['newTimes']).isEmpty
        ? _strings(medication['times'])
        : _strings(item['newTimes']);
    final action = (item['type'] ?? '').toString();
    final result = <MedicationCheckinScheduleSnapshot>[];
    if (action != 'added') {
      for (final slot
          in oldTimes.where((slot) => _isBefore(slot, change.date))) {
        result.add(MedicationCheckinScheduleSnapshot(
          slot: slot,
          dose: item['oldDose'],
          dosePerUnit: item['oldDosePerUnit'],
          pillCount: item['oldPillCount'],
          unit: (item['oldUnit'] ?? item['unit'] ?? 'mg').toString(),
        ));
      }
    }
    if (action != 'stopped') {
      for (final slot
          in newTimes.where((slot) => !_isBefore(slot, change.date))) {
        result.add(MedicationCheckinScheduleSnapshot(
          slot: slot,
          dose: medication['dose'],
          dosePerUnit: medication['dosePerUnit'],
          pillCount: medication['pillCount'],
          unit: (medication['unit'] ?? 'mg').toString(),
        ));
      }
    }
    return result;
  }

  static List<MedicationCheckinScheduleSnapshot> _currentSnapshots(
    Map<String, dynamic> medication,
  ) {
    final times = _strings(medication['times']);
    return (times.isEmpty ? const ['未設定'] : times)
        .map((slot) => MedicationCheckinScheduleSnapshot(
              slot: slot,
              dose: medication['dose'],
              dosePerUnit: medication['dosePerUnit'],
              pillCount: medication['pillCount'],
              unit: (medication['unit'] ?? 'mg').toString(),
            ))
        .toList();
  }

  static bool _isBefore(String slot, DateTime effectiveAt) =>
      (_slotMinutes[slot] ?? effectiveAt.hour * 60 + effectiveAt.minute) <
      effectiveAt.hour * 60 + effectiveAt.minute;

  static const _slotMinutes = <String, int>{
    '早上': 8 * 60,
    '中午': 12 * 60,
    '下午': 15 * 60,
    '晚上': 19 * 60,
    '睡前': 22 * 60,
  };

  static List<String> _strings(dynamic value) => value is Iterable
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];

  static int? _positiveInt(dynamic value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static Set<int> _ints(dynamic value) => value is Iterable
      ? value
          .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
          .whereType<int>()
          .where((item) => item >= 1 && item <= 7)
          .toSet()
      : const <int>{};

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
