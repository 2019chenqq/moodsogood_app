import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/weekly_record.dart';
import '../utils/health_data_encryption_service.dart';

class WeeklyRecordRepository {
  WeeklyRecordRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _records(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('weeklyRecords');
  }

  String weekId(DateTime weekStart) {
    final day = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  Future<WeeklyRecord?> getWeeklyRecord({
    required String userId,
    required DateTime weekStart,
  }) async {
    final doc = await _records(userId).doc(weekId(weekStart)).get();
    final raw = doc.data();
    if (!doc.exists || raw == null) return null;
    final data = await HealthDataEncryptionService.decryptData(raw);
    return WeeklyRecord.fromData(doc.id, data);
  }

  Future<void> saveWeeklyRecord({
    required String userId,
    required DateTime weekStart,
    required DateTime weekEnd,
    required int overallState,
    int? energyLevel,
    String? feeling,
    String? note,
    String? comparison,
    List<String> emotions = const [],
    String? primaryEmotion,
    int? primaryEmotionIntensity,
    int? sleepQuality,
    String? poorSleepDays,
    List<String> sleepIssues = const [],
    List<WeeklySymptom> symptoms = const [],
    Map<String, int> functionImpacts = const {},
    List<String> majorChanges = const [],
    String? eventNote,
    List<String> safetyFlags = const [],
    String? nextWeekFocus,
  }) async {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = DateTime(weekEnd.year, weekEnd.month, weekEnd.day);
    final ref = _records(userId).doc(weekId(start));
    final existing = await ref.get();

    await HealthDataEncryptionService.setEncrypted(ref, {
      'weekStart': Timestamp.fromDate(start),
      'weekEnd': Timestamp.fromDate(end),
      'overallState': overallState.clamp(1, 5),
      'energyLevel': energyLevel?.clamp(1, 5),
      'feeling': feeling?.trim(),
      'note': note?.trim(),
      'comparison': comparison,
      'emotions': emotions,
      'primaryEmotion': primaryEmotion,
      'primaryEmotionIntensity': primaryEmotionIntensity?.clamp(1, 5),
      'sleepQuality': sleepQuality?.clamp(1, 5),
      'poorSleepDays': poorSleepDays,
      'sleepIssues': sleepIssues,
      'symptoms': symptoms.map((item) => item.toMap()).toList(),
      'functionImpacts': functionImpacts,
      'majorChanges': majorChanges,
      'eventNote': eventNote?.trim(),
      'safetyFlags': safetyFlags,
      'nextWeekFocus': nextWeekFocus?.trim(),
      'source': 'three_minute_weekly_review',
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
