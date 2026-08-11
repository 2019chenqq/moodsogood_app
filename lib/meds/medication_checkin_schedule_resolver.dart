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
    final medicationId = (medication['id'] ?? '').toString();
    final sameDayItems = <({DateTime date, Map<String, dynamic> item})>[];
    for (final record in adjustmentRecords) {
      final date = _date(record['date']);
      if (date == null || !_sameDay(date, selectedDate)) continue;
      final rawItems = record['items'] ?? record['changes'];
      if (rawItems is! Iterable) continue;
      for (final raw in rawItems.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        if ((item['medDocId'] ?? '').toString() == medicationId) {
          sameDayItems.add((date: date, item: item));
        }
      }
    }
    sameDayItems.sort((a, b) => a.date.compareTo(b.date));
    if (sameDayItems.isEmpty) {
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

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
