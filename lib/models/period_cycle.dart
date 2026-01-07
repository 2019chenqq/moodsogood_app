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
    final e = endDate != null 
        ? DateTime(endDate!.year, endDate!.month, endDate!.day)
        : DateTime.now(); // 若未結束，預設包含到今天

    return !d.isBefore(s) && !d.isAfter(e);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
    };
  }

  factory PeriodCycle.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return PeriodCycle(
      id: doc.id,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
    );
  }
}