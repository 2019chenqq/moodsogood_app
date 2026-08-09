import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/daily_check_in.dart';
import '../utils/health_data_encryption_service.dart';

class DailyCheckInService {
  DailyCheckInService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in user is required.');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _reference(DateTime date) =>
      _firestore
          .collection('users')
          .doc(_uid)
          .collection('dailyCheckIns')
          .doc(dateId(date));

  Future<DailyCheckIn?> getForDate(DateTime date) async {
    final snapshot = await _reference(date).get();
    final raw = snapshot.data();
    if (raw == null) return null;
    return DailyCheckIn.fromData(
      await HealthDataEncryptionService.decryptData(raw),
    );
  }

  Future<void> save(DailyCheckIn checkIn) async {
    _validateScore(checkIn.overallMood, 'overallMood');
    _validateScore(checkIn.healthStatus, 'healthStatus');
    final reference = _reference(checkIn.date);
    await HealthDataEncryptionService.mutateEncrypted(reference, (current) {
      return {
        ...current,
        ...checkIn.toData(),
        'createdAt': current['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
    });
  }

  static String dateId(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static void _validateScore(int score, String field) {
    if (score < 1 || score > 5) {
      throw ArgumentError.value(score, field, 'must be between 1 and 5');
    }
  }
}
