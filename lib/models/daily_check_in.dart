import 'package:cloud_firestore/cloud_firestore.dart';

class DailyCheckIn {
  const DailyCheckIn({
    required this.date,
    required this.overallMood,
    required this.healthStatus,
    required this.noSpecialEvent,
    this.createdAt,
    this.updatedAt,
  });

  final DateTime date;
  final int overallMood;
  final int healthStatus;
  final bool noSpecialEvent;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toData() => {
        'date': Timestamp.fromDate(date),
        'overallMood': overallMood,
        'healthStatus': healthStatus,
        'noSpecialEvent': noSpecialEvent,
      };

  factory DailyCheckIn.fromData(Map<String, dynamic> data) {
    int score(String field) {
      final value = (data[field] as num?)?.toInt();
      if (value == null || value < 1 || value > 5) {
        throw FormatException('Invalid $field score.');
      }
      return value;
    }

    return DailyCheckIn(
      date: _asDate(data['date']) ?? DateTime.now(),
      overallMood: score('overallMood'),
      healthStatus: score('healthStatus'),
      noSpecialEvent: data['noSpecialEvent'] == true,
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
