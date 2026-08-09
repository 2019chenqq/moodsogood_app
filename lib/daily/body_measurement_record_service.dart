import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/body_measurement_record.dart';
import '../utils/health_data_encryption_service.dart';

class BodyMeasurementRecordService {
  BodyMeasurementRecordService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _records(String userId) =>
      _firestore.collection('users').doc(userId).collection('bodyMeasurements');

  Future<String> save({
    required String userId,
    required BodyMeasurementRecord record,
  }) async {
    if (!record.hasMeasurements || !record.isValid) {
      throw ArgumentError('Body measurement values are missing or invalid.');
    }
    final ref = record.id.isEmpty
        ? _records(userId).doc()
        : _records(userId).doc(record.id);
    await HealthDataEncryptionService.mutateEncrypted(
        ref,
        (current) => {
              ...current,
              ...record.toMap(),
              'createdAt': current['createdAt'] ?? FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
    return ref.id;
  }

  Future<void> delete({required String userId, required String recordId}) =>
      _records(userId).doc(recordId).delete();

  Future<List<BodyMeasurementRecord>> getByDate({
    required String userId,
    required DateTime date,
  }) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final docs = await HealthDataEncryptionService.getEncrypted(
      _records(userId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThan: Timestamp.fromDate(end))
          .orderBy('timestamp'),
    );
    return docs
        .map((doc) => BodyMeasurementRecord.fromMap(doc.id, doc.data))
        .toList(growable: false);
  }
}
