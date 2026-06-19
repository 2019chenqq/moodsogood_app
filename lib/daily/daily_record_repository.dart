import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/home_widget_sync_service.dart';

class DailyRecordRepository {
  static final DailyRecordRepository _instance =
      DailyRecordRepository._internal();

  factory DailyRecordRepository() => _instance;

  DailyRecordRepository._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<void> init() async {}

  CollectionReference<Map<String, dynamic>> _records(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('dailyRecords');
  }

  String _dateId(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  Future<void> saveDailyRecord({
    required String id,
    required String userId,
    required DateTime date,
    Map<String, dynamic>? emotions,
    Map<String, dynamic>? sleep,
    List<String>? bodySymptoms,
    Map<String, dynamic>? dailyActivities,
    List<Map<String, dynamic>>? medicines,
    Map<String, dynamic>? periodData,
    int moodScale = 10,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    await _records(userId).doc(id).set({
      'date': Timestamp.fromDate(day),
      'emotions': emotions,
      'sleep': sleep,
      'bodySymptoms': bodySymptoms,
      'dailyActivities': dailyActivities,
      'medicines': medicines,
      'periodData': periodData,
      'moodScale': moodScale,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (!day.isAfter(todayOnly)) {
      final streakDays = await _getConsecutiveRecordDays(
        userId: userId,
        fromDate: todayOnly,
      );
      await HomeWidgetSyncService.updateDailyRecord(streakDays: streakDays);
    }
  }

  Future<int> _getConsecutiveRecordDays({
    required String userId,
    required DateTime fromDate,
  }) async {
    final end = DateTime(
      fromDate.year,
      fromDate.month,
      fromDate.day,
      23,
      59,
      59,
      999,
    );
    final snapshot = await _records(userId)
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .limit(366)
        .get();
    final recordedDays = snapshot.docs
        .map((doc) => _asDate(doc.data()['date']))
        .whereType<DateTime>()
        .map(_dateId)
        .toSet();

    var streak = 0;
    var cursor = DateTime(fromDate.year, fromDate.month, fromDate.day);
    while (recordedDays.contains(_dateId(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<Map<String, dynamic>?> getDailyRecord({
    required String userId,
    required DateTime date,
  }) async {
    final doc = await _records(userId).doc(_dateId(date)).get();
    if (!doc.exists || doc.data() == null) return null;
    return _normalize(doc.id, doc.data()!);
  }

  Future<List<Map<String, dynamic>>> getDailyRecordsByDateRange({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
      999,
    );
    final snapshot = await _records(userId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .get();
    return snapshot.docs.map((doc) => _normalize(doc.id, doc.data())).toList();
  }

  Future<void> deleteDailyRecord(String id) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw StateError('deleteDailyRecord requires a signed-in user');
    }
    await _records(userId).doc(id).delete();
  }

  Future<int> getRecordCount({required String userId}) async {
    final result = await _records(userId).count().get();
    return result.count ?? 0;
  }

  Future<void> clearAllRecords() async {
    throw UnsupportedError(
      'Cloud records must be deleted for an explicit user account.',
    );
  }

  Future<void> close() async {}

  Map<String, dynamic> _normalize(
    String id,
    Map<String, dynamic> data,
  ) {
    final date = _asDate(data['date']);
    return {
      ...data,
      'id': id,
      'date': date?.toIso8601String(),
      'createdAt': _asDate(data['createdAt'])?.toIso8601String(),
      'updatedAt': _asDate(data['updatedAt'])?.toIso8601String(),
    };
  }

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
