import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/sleep_record.dart';
import '../utils/health_data_encryption_service.dart';

class SleepRecordService {
  SleepRecordService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> reference(
    String userId,
    DateTime date,
  ) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('sleepRecords')
          .doc(dateId(date));

  Future<void> save({
    required String userId,
    required SleepRecord record,
  }) async {
    final ref = reference(userId, record.date);
    await HealthDataEncryptionService.mutateEncrypted(
        ref,
        (current) => {
              ...current,
              ...record.toMap(),
              'createdAt': current['createdAt'] ?? FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
  }

  Future<SleepRecord?> get({
    required String userId,
    required DateTime date,
  }) async {
    final snapshot = await reference(userId, date).get();
    final raw = snapshot.data();
    if (raw == null) return null;
    return SleepRecord.fromMap(
      await HealthDataEncryptionService.decryptData(raw),
    );
  }

  static String dateId(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
