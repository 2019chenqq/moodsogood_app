import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/health_data_encryption_service.dart';
import 'medication_subjective_response.dart';
import 'medication_subjective_tracking_cycle.dart';

class MedicationLocalDB {
  static final MedicationLocalDB _instance = MedicationLocalDB._internal();

  factory MedicationLocalDB() => _instance;

  MedicationLocalDB._internal();

  CollectionReference<Map<String, dynamic>> _medications(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications');

  CollectionReference<Map<String, dynamic>> _adjustments(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medAdjustments');

  CollectionReference<Map<String, dynamic>> _subjectiveResponses(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medicationSubjectiveResponses');

  CollectionReference<Map<String, dynamic>> _subjectiveTrackingCycles(
    String uid,
  ) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medicationSubjectiveTrackingCycles');

  Future<void> addMedication(String uid, Map<String, dynamic> data) async {
    final id = data['id']?.toString();
    if (id == null || id.isEmpty) {
      throw ArgumentError('Medication id is required.');
    }
    await HealthDataEncryptionService.setEncrypted(
      _medications(uid).doc(id),
      _toCloudMedication(data),
    );
  }

  Future<void> updateMedication(
    String uid,
    String docId,
    Map<String, dynamic> data,
  ) async {
    await HealthDataEncryptionService.setEncrypted(
      _medications(uid).doc(docId),
      _toCloudMedication(data),
    );
  }

  Future<void> updateMedicationStatus(
    String uid,
    String docId, {
    required bool isActive,
    String? updatedAt,
    String? lastChangeAt,
  }) async {
    await HealthDataEncryptionService.setEncrypted(
        _medications(uid).doc(docId), {
      'isActive': isActive,
      'updatedAt': _asTimestamp(updatedAt) ?? FieldValue.serverTimestamp(),
      if (lastChangeAt != null) 'lastChangeAt': _asTimestamp(lastChangeAt),
    });
  }

  Future<void> deleteMedication(String uid, String docId) async {
    await _medications(uid).doc(docId).delete();
  }

  Future<List<Map<String, dynamic>>> getMedications(String uid) async {
    final documents =
        await HealthDataEncryptionService.getEncrypted(_medications(uid));
    final records =
        documents.map((doc) => _fromCloud(doc.id, doc.data)).toList();
    records.sort((a, b) {
      final activeCompare = (b['isActive'] == true ? 1 : 0)
          .compareTo(a['isActive'] == true ? 1 : 0);
      if (activeCompare != 0) return activeCompare;
      return (b['updatedAt'] ?? '').toString().compareTo(
            (a['updatedAt'] ?? '').toString(),
          );
    });
    return records;
  }

  Future<Map<String, dynamic>?> getMedication(
    String uid,
    String docId,
  ) async {
    final doc = await _medications(uid).doc(docId).get();
    final raw = doc.data();
    if (raw == null) return null;
    final data = await HealthDataEncryptionService.decryptData(raw);
    return _fromCloud(doc.id, data);
  }

  Future<List<Map<String, dynamic>>> getMedicationsForDisplay(String uid) {
    return getMedications(uid);
  }

  Future<void> clearAll() async {
    throw UnsupportedError(
      'Cloud medications must be deleted for an explicit user account.',
    );
  }

  Future<void> addAdjustmentRecord(
    String uid,
    String docId,
    Map<String, dynamic> data,
  ) async {
    await HealthDataEncryptionService.setEncrypted(
        _adjustments(uid).doc(docId), {
      ...data,
      'date': _asTimestamp(data['date']) ?? data['date'],
      'createdAt':
          _asTimestamp(data['createdAt']) ?? FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getAdjustmentRecords(String uid) async {
    final documents = await HealthDataEncryptionService.getEncrypted(
      _adjustments(uid).orderBy('date', descending: true),
    );
    return documents
        .map((doc) => {
              'id': doc.id,
              ..._normalizeMap(doc.data),
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAdjustmentRecordsForDisplay(
    String uid,
  ) {
    return getAdjustmentRecords(uid);
  }

  /// Creates or replaces the response with the same id. The encrypted storage
  /// path matches the existing medication and adjustment-record architecture.
  Future<void> saveSubjectiveResponse(
    String uid,
    MedicationSubjectiveResponse response,
  ) async {
    final data = response.toMap()..remove('id');
    data['changeDate'] = Timestamp.fromDate(response.changeDate);
    data['recordedAt'] = Timestamp.fromDate(response.recordedAt);
    await HealthDataEncryptionService.setEncrypted(
      _subjectiveResponses(uid).doc(response.id),
      data,
    );
  }

  Future<MedicationSubjectiveResponse?> getSubjectiveResponse(
    String uid,
    String responseId,
  ) async {
    final doc = await _subjectiveResponses(uid).doc(responseId).get();
    final raw = doc.data();
    if (raw == null) return null;
    final data = await HealthDataEncryptionService.decryptData(raw);
    return MedicationSubjectiveResponse.fromMap({
      'id': doc.id,
      ..._normalizeMap(data),
    });
  }

  Future<List<MedicationSubjectiveResponse>> getAllSubjectiveResponses(
    String uid,
  ) async {
    final documents = await HealthDataEncryptionService.getEncrypted(
      _subjectiveResponses(uid),
    );
    final responses = documents
        .map(
          (doc) => MedicationSubjectiveResponse.fromMap({
            'id': doc.id,
            ..._normalizeMap(doc.data),
          }),
        )
        .toList();
    responses.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return responses;
  }

  /// Reads reports for a specific adjustment. Optional filters support the
  /// later Day 3/7/14/28 questionnaire without requiring a Firestore index.
  Future<List<MedicationSubjectiveResponse>> getSubjectiveResponses({
    required String uid,
    required String changeRecordId,
    String? medicationId,
    int? followUpDay,
  }) async {
    if (changeRecordId.trim().isEmpty) {
      throw ArgumentError('changeRecordId is required.');
    }
    if (followUpDay != null &&
        !MedicationSubjectiveResponse.allowedFollowUpDays.contains(
          followUpDay,
        )) {
      throw ArgumentError.value(
        followUpDay,
        'followUpDay',
        'must be 3, 7, 14, or 28',
      );
    }

    final responses = (await getAllSubjectiveResponses(uid))
        .where(
          (response) =>
              response.changeRecordId == changeRecordId &&
              (medicationId == null || response.medicationId == medicationId) &&
              (followUpDay == null || response.followUpDay == followUpDay),
        )
        .toList();
    responses.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return responses;
  }

  Future<MedicationSubjectiveTrackingCycle?> getSubjectiveTrackingCycle(
    String uid,
    String cycleId,
  ) async {
    final doc = await _subjectiveTrackingCycles(uid).doc(cycleId).get();
    final raw = doc.data();
    if (raw == null) return null;
    final data = await HealthDataEncryptionService.decryptData(raw);
    return MedicationSubjectiveTrackingCycle.fromMap({
      'id': doc.id,
      ..._normalizeMap(data),
    });
  }

  Future<void> deleteSubjectiveResponse(String uid, String responseId) async {
    await _subjectiveResponses(uid).doc(responseId).delete();
  }

  Future<void> saveSubjectiveTrackingCycle(
    String uid,
    MedicationSubjectiveTrackingCycle cycle,
  ) async {
    final data = cycle.toMap()..remove('id');
    data['changeDate'] = Timestamp.fromDate(cycle.changeDate);
    if (cycle.endedAt != null) {
      data['endedAt'] = Timestamp.fromDate(cycle.endedAt!);
    }
    data['followUpDates'] = {
      for (final entry in cycle.followUpDates.entries)
        entry.key.toString(): Timestamp.fromDate(entry.value),
    };
    await HealthDataEncryptionService.setEncrypted(
      _subjectiveTrackingCycles(uid).doc(cycle.id),
      data,
    );
  }

  Future<List<MedicationSubjectiveTrackingCycle>>
      getSubjectiveTrackingCycles({
    required String uid,
    String? medicationId,
    bool? active,
  }) async {
    final documents = await HealthDataEncryptionService.getEncrypted(
      _subjectiveTrackingCycles(uid),
    );
    final cycles = documents
        .map(
          (doc) => MedicationSubjectiveTrackingCycle.fromMap({
            'id': doc.id,
            ..._normalizeMap(doc.data),
          }),
        )
        .where(
          (cycle) =>
              (medicationId == null || cycle.medicationId == medicationId) &&
              (active == null || cycle.active == active),
        )
        .toList();
    cycles.sort((a, b) => b.changeDate.compareTo(a.changeDate));
    return cycles;
  }

  Future<void> endActiveSubjectiveTrackingCycles({
    required String uid,
    required String medicationId,
    required DateTime endedAt,
    required String reason,
    String? supersededByChangeRecordId,
  }) async {
    final activeCycles = await getSubjectiveTrackingCycles(
      uid: uid,
      medicationId: medicationId,
      active: true,
    );
    for (final cycle in activeCycles) {
      await saveSubjectiveTrackingCycle(
        uid,
        cycle.end(
          endedAt: endedAt,
          reason: reason,
          supersededByChangeRecordId: supersededByChangeRecordId,
        ),
      );
    }
  }

  Future<void> applyAdjustmentToMedication(
    String uid,
    String medId, {
    required double dosePerUnit,
    required double pillCount,
    required String unit,
  }) async {
    final totalDose = _roundDose(dosePerUnit * pillCount);
    await HealthDataEncryptionService.setEncrypted(
        _medications(uid).doc(medId), {
      'dose': totalDose,
      'dosePerUnit': dosePerUnit,
      'pillCount': pillCount,
      'unit': unit,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastChangeAt': FieldValue.serverTimestamp(),
    });
  }

  Map<String, dynamic> _toCloudMedication(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data)..remove('id');
    for (final field in [
      'startDate',
      'createdAt',
      'updatedAt',
      'lastChangeAt',
      'lastChangedAt',
      'resumedAt',
    ]) {
      if (copy[field] != null) {
        copy[field] = _asTimestamp(copy[field]) ?? copy[field];
      }
    }
    copy['updatedAt'] ??= FieldValue.serverTimestamp();
    copy['createdAt'] ??= FieldValue.serverTimestamp();
    return copy;
  }

  Map<String, dynamic> _fromCloud(
    String id,
    Map<String, dynamic> data,
  ) {
    return {
      'id': id,
      ..._normalizeMap(data),
      'times': _asStringList(data['times']),
      'purposes': _asStringList(data['purposes']),
      'bodySymptoms': _asStringList(data['bodySymptoms']),
      'isActive': data['isActive'] != false,
    };
  }

  Map<String, dynamic> _normalizeMap(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) return MapEntry(key, value.toDate().toString());
      return MapEntry(key, value);
    });
  }

  List<String> _asStringList(dynamic value) {
    if (value is Iterable) return value.map((item) => item.toString()).toList();
    if (value is String && value.isNotEmpty) {
      return value.split(',').map((item) => item.trim()).toList();
    }
    return const [];
  }

  Timestamp? _asTimestamp(dynamic value) {
    if (value is Timestamp) return value;
    if (value is DateTime) return Timestamp.fromDate(value);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return Timestamp.fromDate(parsed);
    }
    return null;
  }

  double _roundDose(double value) => (value * 10).round() / 10;
}
