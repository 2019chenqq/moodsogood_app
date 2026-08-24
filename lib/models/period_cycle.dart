import 'package:cloud_firestore/cloud_firestore.dart';

class PeriodCycle {
  final String id;
  final DateTime startDate;
  final DateTime? endDate; // 如果還沒結束，可以是 null

  const PeriodCycle({
    required this.id,
    required this.startDate,
    this.endDate,
  });

  // 計算持續天數 (如果沒結束，算到今天)
  int get durationDays {
    final end = endDate ?? DateTime.now();
    return end.difference(startDate).inDays + 1;
  }

  // 判斷某一天是否在這個經期內
  bool containsDate(DateTime date) {
    // 正規化日期 (只比對 yyyy-MM-dd)
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = endDate == null
        ? null
        : DateTime(endDate!.year, endDate!.month, endDate!.day);

    return !d.isBefore(s) && (e == null || !d.isAfter(e));
  }

  /// Calendar presentation range for an open cycle.
  ///
  /// An open cycle initially shows seven days. After that window has passed,
  /// it grows only through [asOf], one day at a time, until an end is recorded.
  bool isDisplayedOn(DateTime date, {DateTime? asOf}) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final recordedEnd = endDate == null
        ? null
        : DateTime(endDate!.year, endDate!.month, endDate!.day);
    if (recordedEnd != null) {
      return !d.isBefore(s) && !d.isAfter(recordedEnd);
    }

    final reference = asOf ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final initialWindowEnd = s.add(const Duration(days: 6));
    final displayEnd =
        today.isAfter(initialWindowEnd) ? today : initialWindowEnd;
    return !d.isBefore(s) && !d.isAfter(displayEnd);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
    };
  }

  factory PeriodCycle.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return PeriodCycle.fromData(doc.id, doc.data() ?? {});
  }

  factory PeriodCycle.fromData(String id, Map<String, dynamic> data) {
    return PeriodCycle(
      id: id,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
    );
  }
}
