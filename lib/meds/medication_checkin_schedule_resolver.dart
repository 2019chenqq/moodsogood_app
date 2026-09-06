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

  static DateTime nextIntervalDateOnOrAfter({
    required DateTime anchorDate,
    required int intervalDays,
    required DateTime from,
  }) {
    final anchor = DateTime(anchorDate.year, anchorDate.month, anchorDate.day);
    final boundary = DateTime(from.year, from.month, from.day);
    if (!boundary.isAfter(anchor)) return anchor;
    final cycleDays = intervalDays <= 1 ? 1 : intervalDays;
    final elapsed = boundary.difference(anchor).inDays;
    final remainder = elapsed % cycleDays;
    return remainder == 0
        ? boundary
        : boundary.add(Duration(days: cycleDays - remainder));
  }

  static List<MedicationCheckinScheduleSnapshot> resolve({
    required Map<String, dynamic> medication,
    required Iterable<Map<String, dynamic>> adjustmentRecords,
    required DateTime selectedDate,
  }) =>
      _resolveAtEachSlot(
        medication: medication,
        adjustmentRecords: adjustmentRecords,
        selectedDate: selectedDate,
      );

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
        final anchor = _date(medication['scheduleAnchorDate']) ??
            _date(medication['lastChangeAt']) ??
            start;
        if (anchor == null || interval == null) return true;
        final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
        if (day.isBefore(anchorDay)) return false;
        // 產品規則：服用當天為第 0 天，隔天是第 1 天；「每 5 天」
        // 會在第 0、5、10 天服用，兩次日期相差 5 天。
        final cycleDays = interval <= 1 ? 1 : interval;
        return day.difference(anchorDay).inDays % cycleDays == 0;
      case 'weekdays':
        final weekdays = _ints(medication['weekdays']);
        return weekdays.isEmpty || weekdays.contains(day.weekday);
      default:
        return true;
    }
  }

  static List<MedicationCheckinScheduleSnapshot> _resolveAtEachSlot({
    required Map<String, dynamic> medication,
    required Iterable<Map<String, dynamic>> adjustmentRecords,
    required DateTime selectedDate,
  }) {
    final medicationId = (medication['id'] ?? '').toString();
    final events = <({DateTime date, Map<String, dynamic> item})>[];
    final candidateSlots = <String>{..._strings(medication['times'])};
    for (final record in adjustmentRecords) {
      final date = _date(record['effectiveDateTime']) ?? _date(record['date']);
      if (date == null) continue;
      final rawItems = record['items'] ?? record['changes'];
      if (rawItems is! Iterable) continue;
      for (final raw in rawItems.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        if (item['supersededAt'] != null) continue;
        if ((item['medDocId'] ?? '').toString() == medicationId) {
          events.add((date: date, item: item));
          candidateSlots.addAll(_strings(item['oldTimes']));
          candidateSlots.addAll(_strings(item['newTimes']));
        }
      }
    }
    events.sort((left, right) => right.date.compareTo(left.date));

    // 產品規則：停藥生效日不再產生任何待打卡項目。
    final sameDayActiveChanges = events
        .where((event) => _sameDay(event.date, selectedDate))
        .where((entry) =>
            entry.item['type'] == 'stopped' || entry.item['type'] == 'resumed')
        .toList()
      ..sort((left, right) => left.date.compareTo(right.date));
    if (sameDayActiveChanges.lastOrNull?.item['type'] == 'stopped') {
      return const [];
    }

    if (candidateSlots.isEmpty) candidateSlots.add('未設定');
    final result = <MedicationCheckinScheduleSnapshot>[];
    for (final slot in candidateSlots) {
      final state = Map<String, dynamic>.from(medication);
      final minutes = _slotMinutes[slot] ?? 23 * 60 + 59;
      final slotTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        minutes ~/ 60,
        minutes % 60,
      );
      for (final event
          in events.where((event) => event.date.isAfter(slotTime))) {
        _rollback(state, event.item);
      }
      final times = _strings(state['times']);
      final isPrn = slot == '需要時';
      final slotExists = slot == '未設定' ? times.isEmpty : times.contains(slot);
      if (state['isActive'] == false ||
          (!isPrn && !isScheduledOn(state, selectedDate)) ||
          !slotExists) {
        continue;
      }
      result.add(MedicationCheckinScheduleSnapshot(
        slot: slot,
        dose: state['dose'],
        dosePerUnit: state['dosePerUnit'],
        pillCount: state['pillCount'],
        unit: (state['unit'] ?? 'mg').toString(),
      ));
    }
    result.sort((left, right) => (_slotMinutes[left.slot] ?? 9999)
        .compareTo(_slotMinutes[right.slot] ?? 9999));
    return result;
  }

  static void _rollback(
    Map<String, dynamic> state,
    Map<String, dynamic> item,
  ) {
    final type = (item['type'] ?? '').toString();
    if (type == 'added') {
      state['isActive'] = false;
      state['times'] = item['oldTimes'] ?? const <String>[];
      return;
    }
    if (type == 'resumed') state['isActive'] = false;
    if (type == 'stopped') state['isActive'] = true;
    if (item.containsKey('oldDose') && item['oldDose'] != null) {
      state['dose'] = item['oldDose'];
    }
    if (item.containsKey('oldDosePerUnit') && item['oldDosePerUnit'] != null) {
      state['dosePerUnit'] = item['oldDosePerUnit'];
    }
    if (item.containsKey('oldPillCount') && item['oldPillCount'] != null) {
      state['pillCount'] = item['oldPillCount'];
    }
    if (item.containsKey('oldUnit') && item['oldUnit'] != null) {
      state['unit'] = item['oldUnit'];
    }
    if (item.containsKey('oldTimes') && item['oldTimes'] != null) {
      state['times'] = item['oldTimes'];
    }
    if (item.containsKey('oldScheduleType')) {
      state['scheduleType'] = item['oldScheduleType'] ?? 'daily';
      state['scheduleIntervalDays'] = item['oldScheduleIntervalDays'];
      state['scheduleAnchorDate'] = item['oldScheduleAnchorDate'];
      state['weekdays'] = item['oldWeekdays'] ?? const <int>[];
    }
  }

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
